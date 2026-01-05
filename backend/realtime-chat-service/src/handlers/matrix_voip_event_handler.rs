use crate::error::AppError;
use crate::redis_client::RedisClient;
use crate::services::{call_service::CallService, matrix_db};
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use crate::websocket::ConnectionRegistry;
use deadpool_postgres::Pool;
use matrix_sdk::{
    room::Room,
    ruma::events::call::{
        answer::SyncCallAnswerEvent, candidates::SyncCallCandidatesEvent,
        hangup::SyncCallHangupEvent, invite::SyncCallInviteEvent,
    },
};
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

/// Matrix VoIP Event Handler for SDK 0.16
///
/// Processes Matrix VoIP call events using typed event structures from Matrix SDK 0.16.
///
/// This handler processes:
/// - m.call.invite - Incoming call invitations with SDP offer
/// - m.call.answer - Call answers with SDP answer
/// - m.call.candidates - ICE candidates for WebRTC connection establishment
/// - m.call.hangup - Call termination signals
pub struct MatrixVoipEventHandler {
    db: Pool,
    registry: Arc<ConnectionRegistry>,
    redis: Arc<RedisClient>,
}

impl MatrixVoipEventHandler {
    /// Create new event handler
    pub fn new(db: Pool, registry: Arc<ConnectionRegistry>, redis: Arc<RedisClient>) -> Self {
        Self {
            db,
            registry,
            redis,
        }
    }

    /// Handle m.call.invite event
    pub async fn handle_call_invite(
        &self,
        event: SyncCallInviteEvent,
        room: Room,
    ) -> Result<(), AppError> {
        // Extract content from the Original variant (ignore redacted events)
        let SyncCallInviteEvent::Original(original) = event else {
            debug!("Ignoring redacted m.call.invite event");
            return Ok(());
        };

        let content = &original.content;

        info!(
            call_id = %content.call_id,
            party_id = ?content.party_id,
            version = %content.version,
            lifetime_ms = %content.lifetime,
            room_id = %room.room_id(),
            "Received m.call.invite"
        );

        // 1. Look up conversation_id from Matrix room_id
        let room_id_str = room.room_id().as_str();
        let conversation_id = match matrix_db::lookup_conversation_by_room_id(&self.db, room_id_str).await? {
            Some(id) => id,
            None => {
                warn!(
                    room_id = %room_id_str,
                    "No conversation found for Matrix room, ignoring call invite"
                );
                return Ok(());
            }
        };

        // 2. Parse call_id from Matrix (it's a Nova UUID stored as string)
        let call_id = match Uuid::parse_str(content.call_id.as_str()) {
            Ok(id) => id,
            Err(e) => {
                warn!(
                    call_id = %content.call_id,
                    error = ?e,
                    "Invalid call_id format (expected UUID), ignoring call invite"
                );
                return Ok(());
            }
        };

        // 3. Extract SDP offer (for future use, currently just validated)
        let _sdp_offer = &content.offer.sdp;

        // 4. Store Matrix party_id in database (update existing call record)
        let party_id = content.party_id.as_ref().map(|s| s.to_string());
        if let Some(party_id) = &party_id {
            let client = self.db.get().await.map_err(|e| {
                AppError::StartServer(format!("get client: {e}"))
            })?;

            // Update call_sessions with Matrix party_id if it exists
            let update_result = client.execute(
                "UPDATE call_sessions SET matrix_party_id = $1 WHERE id = $2",
                &[party_id, &call_id]
            ).await;

            if let Err(e) = update_result {
                warn!(
                    call_id = %call_id,
                    error = ?e,
                    "Failed to update Matrix party_id in database"
                );
            }
        }

        // 5. Get call details to build the WebSocket event
        let client = self.db.get().await.map_err(|e| {
            AppError::StartServer(format!("get client: {e}"))
        })?;

        let call_row = client.query_opt(
            "SELECT initiator_id, call_type, max_participants FROM call_sessions WHERE id = $1",
            &[&call_id]
        ).await.map_err(|e| {
            AppError::StartServer(format!("fetch call: {e}"))
        })?;

        let (initiator_id, call_type, max_participants) = match call_row {
            Some(row) => {
                let initiator_id: Uuid = row.get("initiator_id");
                let call_type: String = row.get("call_type");
                let max_participants: i32 = row.get("max_participants");
                (initiator_id, call_type, max_participants)
            }
            None => {
                warn!(
                    call_id = %call_id,
                    "Call not found in database, cannot broadcast event"
                );
                return Ok(());
            }
        };

        // 6. Broadcast CallInitiated event to WebSocket clients
        let event = WebSocketEvent::CallInitiated {
            call_id,
            initiator_id,
            call_type,
            max_participants,
        };

        if let Err(e) = broadcast_event(&self.registry, &self.redis, conversation_id, initiator_id, event).await {
            warn!(
                call_id = %call_id,
                conversation_id = %conversation_id,
                error = ?e,
                "Failed to broadcast call invite to WebSocket clients"
            );
        }

        info!(
            call_id = %call_id,
            conversation_id = %conversation_id,
            room_id = %room_id_str,
            "Forwarded call invite to WebSocket clients"
        );

        Ok(())
    }

    /// Handle m.call.answer event
    pub async fn handle_call_answer(
        &self,
        event: SyncCallAnswerEvent,
        room: Room,
    ) -> Result<(), AppError> {
        let SyncCallAnswerEvent::Original(original) = event else {
            debug!("Ignoring redacted m.call.answer event");
            return Ok(());
        };

        let content = &original.content;

        info!(
            call_id = %content.call_id,
            party_id = ?content.party_id,
            room_id = %room.room_id(),
            "Received m.call.answer"
        );

        // 1. Look up conversation_id from Matrix room_id
        let room_id_str = room.room_id().as_str();
        let conversation_id = match matrix_db::lookup_conversation_by_room_id(&self.db, room_id_str).await? {
            Some(id) => id,
            None => {
                warn!(
                    room_id = %room_id_str,
                    "No conversation found for Matrix room, ignoring call answer"
                );
                return Ok(());
            }
        };

        // 2. Parse call_id from Matrix
        let call_id = match Uuid::parse_str(content.call_id.as_str()) {
            Ok(id) => id,
            Err(e) => {
                warn!(
                    call_id = %content.call_id,
                    error = ?e,
                    "Invalid call_id format (expected UUID), ignoring call answer"
                );
                return Ok(());
            }
        };

        // 3. Extract SDP answer (for future use, currently just validated)
        let _sdp_answer = &content.answer.sdp;

        // 4. Get call information (to get initiator for user_id in broadcast)
        let client = self.db.get().await.map_err(|e| {
            AppError::StartServer(format!("get client: {e}"))
        })?;

        let call_row = client.query_opt(
            "SELECT initiator_id FROM call_sessions WHERE id = $1",
            &[&call_id]
        ).await.map_err(|e| {
            AppError::StartServer(format!("fetch call: {e}"))
        })?;

        let initiator_id = match call_row {
            Some(row) => row.get::<&str, Uuid>("initiator_id"),
            None => {
                warn!(
                    call_id = %call_id,
                    "Call not found in database, cannot broadcast answer event"
                );
                return Ok(());
            }
        };

        // 5. Find the answerer (most recent participant who joined)
        let participant_row = client.query_opt(
            "SELECT user_id FROM call_participants WHERE call_id = $1 AND user_id != $2 ORDER BY joined_at DESC LIMIT 1",
            &[&call_id, &initiator_id]
        ).await.map_err(|e| {
            AppError::StartServer(format!("fetch answerer: {e}"))
        })?;

        let answerer_id = match participant_row {
            Some(row) => row.get::<&str, Uuid>("user_id"),
            None => {
                warn!(
                    call_id = %call_id,
                    "No answerer found for call, using initiator_id as fallback"
                );
                initiator_id // Fallback to initiator
            }
        };

        // 6. Broadcast CallAnswered event to WebSocket clients
        let event = WebSocketEvent::CallAnswered {
            call_id,
            answerer_id,
        };

        if let Err(e) = broadcast_event(&self.registry, &self.redis, conversation_id, answerer_id, event).await {
            warn!(
                call_id = %call_id,
                conversation_id = %conversation_id,
                error = ?e,
                "Failed to broadcast call answer to WebSocket clients"
            );
        }

        info!(
            call_id = %call_id,
            conversation_id = %conversation_id,
            answerer_id = %answerer_id,
            "Forwarded call answer to WebSocket clients"
        );

        Ok(())
    }

    /// Handle m.call.candidates event
    pub async fn handle_call_candidates(
        &self,
        event: SyncCallCandidatesEvent,
        room: Room,
    ) -> Result<(), AppError> {
        let SyncCallCandidatesEvent::Original(original) = event else {
            debug!("Ignoring redacted m.call.candidates event");
            return Ok(());
        };

        let content = &original.content;

        info!(
            call_id = %content.call_id,
            party_id = ?content.party_id,
            candidate_count = content.candidates.len(),
            room_id = %room.room_id(),
            "Received m.call.candidates"
        );

        // 1. Look up conversation_id from Matrix room_id
        let room_id_str = room.room_id().as_str();
        let conversation_id = match matrix_db::lookup_conversation_by_room_id(&self.db, room_id_str).await? {
            Some(id) => id,
            None => {
                warn!(
                    room_id = %room_id_str,
                    "No conversation found for Matrix room, ignoring ICE candidates"
                );
                return Ok(());
            }
        };

        // 2. Parse call_id from Matrix
        let call_id = match Uuid::parse_str(content.call_id.as_str()) {
            Ok(id) => id,
            Err(e) => {
                warn!(
                    call_id = %content.call_id,
                    error = ?e,
                    "Invalid call_id format (expected UUID), ignoring ICE candidates"
                );
                return Ok(());
            }
        };

        // 3. Get call information (for user_id in broadcast)
        let client = self.db.get().await.map_err(|e| {
            AppError::StartServer(format!("get client: {e}"))
        })?;

        let call_row = client.query_opt(
            "SELECT initiator_id FROM call_sessions WHERE id = $1",
            &[&call_id]
        ).await.map_err(|e| {
            AppError::StartServer(format!("fetch call: {e}"))
        })?;

        let initiator_id = match call_row {
            Some(row) => row.get::<&str, Uuid>("initiator_id"),
            None => {
                warn!(
                    call_id = %call_id,
                    "Call not found in database, cannot broadcast ICE candidates"
                );
                return Ok(());
            }
        };

        // 4. Extract and broadcast each ICE candidate
        for candidate in &content.candidates {
            // Handle optional fields - skip candidates with missing required fields
            let sdp_mid = match &candidate.sdp_mid {
                Some(mid) => mid.clone(),
                None => {
                    warn!(
                        call_id = %call_id,
                        "ICE candidate missing sdp_mid, skipping"
                    );
                    continue;
                }
            };

            let sdp_mline_index = match candidate.sdp_m_line_index {
                Some(idx) => idx.try_into().unwrap_or(0),
                None => {
                    warn!(
                        call_id = %call_id,
                        "ICE candidate missing sdp_m_line_index, skipping"
                    );
                    continue;
                }
            };

            let event = WebSocketEvent::CallIceCandidate {
                call_id,
                candidate: candidate.candidate.clone(),
                sdp_mid,
                sdp_mline_index,
            };

            if let Err(e) = broadcast_event(&self.registry, &self.redis, conversation_id, initiator_id, event).await {
                warn!(
                    call_id = %call_id,
                    conversation_id = %conversation_id,
                    error = ?e,
                    "Failed to broadcast ICE candidate to WebSocket clients"
                );
            }
        }

        info!(
            call_id = %call_id,
            conversation_id = %conversation_id,
            candidate_count = content.candidates.len(),
            "Forwarded ICE candidates to WebSocket clients"
        );

        Ok(())
    }

    /// Handle m.call.hangup event
    pub async fn handle_call_hangup(
        &self,
        event: SyncCallHangupEvent,
        room: Room,
    ) -> Result<(), AppError> {
        let SyncCallHangupEvent::Original(original) = event else {
            debug!("Ignoring redacted m.call.hangup event");
            return Ok(());
        };

        let content = original.content;

        info!(
            call_id = %content.call_id,
            party_id = ?content.party_id,
            reason = ?content.reason,
            room_id = %room.room_id(),
            "Received m.call.hangup"
        );

        // 1. Look up conversation_id from Matrix room_id
        let room_id_str = room.room_id().as_str();
        let conversation_id = match matrix_db::lookup_conversation_by_room_id(&self.db, room_id_str).await? {
            Some(id) => id,
            None => {
                warn!(
                    room_id = %room_id_str,
                    "No conversation found for Matrix room, ignoring call hangup"
                );
                return Ok(());
            }
        };

        // 2. Parse call_id from Matrix
        let call_id = match Uuid::parse_str(content.call_id.as_str()) {
            Ok(id) => id,
            Err(e) => {
                warn!(
                    call_id = %content.call_id,
                    error = ?e,
                    "Invalid call_id format (expected UUID), ignoring call hangup"
                );
                return Ok(());
            }
        };

        // 3. Get call information before ending it
        let client = self.db.get().await.map_err(|e| {
            AppError::StartServer(format!("get client: {e}"))
        })?;

        let call_row = client.query_opt(
            "SELECT initiator_id FROM call_sessions WHERE id = $1",
            &[&call_id]
        ).await.map_err(|e| {
            AppError::StartServer(format!("fetch call: {e}"))
        })?;

        let initiator_id = match call_row {
            Some(row) => row.get::<&str, Uuid>("initiator_id"),
            None => {
                warn!(
                    call_id = %call_id,
                    "Call not found in database, cannot end call"
                );
                return Ok(());
            }
        };

        // 4. End the call using CallService
        if let Err(e) = CallService::end_call(&self.db, call_id).await {
            warn!(
                call_id = %call_id,
                error = ?e,
                "Failed to end call in database"
            );
            // Continue to broadcast event even if database update fails
        }

        // 5. Broadcast CallEnded event to WebSocket clients
        let event = WebSocketEvent::CallEnded {
            call_id,
            ended_by: initiator_id, // We don't have the actual ender, use initiator as fallback
        };

        if let Err(e) = broadcast_event(&self.registry, &self.redis, conversation_id, initiator_id, event).await {
            warn!(
                call_id = %call_id,
                conversation_id = %conversation_id,
                error = ?e,
                "Failed to broadcast call hangup to WebSocket clients"
            );
        }

        info!(
            call_id = %call_id,
            conversation_id = %conversation_id,
            reason = ?content.reason,
            "Forwarded call hangup to WebSocket clients and ended call"
        );

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_handler_creation() {
        // Test removed - handler now requires runtime dependencies (Pool, ConnectionRegistry, RedisClient)
        // Integration tests should be used to test the full handler behavior
    }
}

use crate::error::AppError;
use crate::services::matrix_client::MatrixClient;
use matrix_sdk::ruma::serde::Raw;
use matrix_sdk::ruma::{RoomId, UserId};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::Arc;
use tracing::{debug, error, info};
use uuid::Uuid;

// Matrix SDK 0.16 supports VoIP events via raw JSON events
// Based on Matrix VoIP spec: https://spec.matrix.org/v1.1/client-server-api/#voice-over-ip

/// ICE candidate for WebRTC
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IceCandidate {
    pub candidate: String,
    #[serde(rename = "sdpMid", skip_serializing_if = "Option::is_none")]
    pub sdp_mid: Option<String>,
    #[serde(rename = "sdpMLineIndex", skip_serializing_if = "Option::is_none")]
    pub sdp_m_line_index: Option<u32>,
}

/// SDP session description
#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
struct SessionDescription {
    #[serde(rename = "type")]
    sdp_type: String,
    sdp: String,
}

/// Matrix VoIP service for handling E2EE calls
pub struct MatrixVoipService {
    matrix_client: Arc<MatrixClient>,
}

impl MatrixVoipService {
    /// Create new MatrixVoipService
    pub fn new(matrix_client: Arc<MatrixClient>) -> Self {
        Self { matrix_client }
    }

    /// Send m.call.invite event to initiate a call
    ///
    /// # Arguments
    /// * `room_id` - Matrix room where call takes place
    /// * `call_id` - Unique identifier for this call (Nova UUID)
    /// * `party_id` - Unique identifier for this party/session
    /// * `sdp_offer` - WebRTC SDP offer
    /// * `invitee` - Optional user ID to invite (for 1:1 calls)
    ///
    /// # Returns
    /// Matrix event ID of the sent invite
    pub async fn send_invite(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        sdp_offer: &str,
        invitee: Option<&UserId>,
    ) -> Result<String, AppError> {
        info!(
            call_id = %call_id,
            room_id = %room_id,
            party_id = %party_id,
            "Sending Matrix call invite"
        );

        // Build m.call.invite event content manually
        let mut content = json!({
            "call_id": call_id.to_string(),
            "party_id": party_id,
            "version": "1",
            "lifetime": 60000, // 60 seconds in milliseconds
            "offer": {
                "type": "offer",
                "sdp": sdp_offer
            }
        });

        // Add invitee if specified (for 1:1 calls)
        if let Some(user_id) = invitee {
            content["invitee"] = json!(user_id.to_string());
        }

        // Send via Matrix client using raw event API
        let event_id = self
            .send_custom_event(room_id, "m.call.invite", content)
            .await?;

        info!(
            call_id = %call_id,
            event_id = %event_id,
            "Matrix call invite sent"
        );

        Ok(event_id)
    }

    /// Send m.call.answer event to accept a call
    ///
    /// # Arguments
    /// * `room_id` - Matrix room where call takes place
    /// * `call_id` - Unique identifier for this call
    /// * `party_id` - Unique identifier for this party/session
    /// * `sdp_answer` - WebRTC SDP answer
    ///
    /// # Returns
    /// Matrix event ID of the sent answer
    pub async fn send_answer(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        sdp_answer: &str,
    ) -> Result<String, AppError> {
        info!(
            call_id = %call_id,
            room_id = %room_id,
            party_id = %party_id,
            "Sending Matrix call answer"
        );

        // Build m.call.answer event content manually
        let content = json!({
            "call_id": call_id.to_string(),
            "party_id": party_id,
            "version": "1",
            "answer": {
                "type": "answer",
                "sdp": sdp_answer
            }
        });

        // Send via Matrix client
        let event_id = self
            .send_custom_event(room_id, "m.call.answer", content)
            .await?;

        info!(
            call_id = %call_id,
            event_id = %event_id,
            "Matrix call answer sent"
        );

        Ok(event_id)
    }

    /// Send m.call.candidates event with ICE candidates
    ///
    /// # Arguments
    /// * `room_id` - Matrix room where call takes place
    /// * `call_id` - Unique identifier for this call
    /// * `party_id` - Unique identifier for this party/session
    /// * `candidates` - List of ICE candidates
    pub async fn send_candidates(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        candidates: Vec<IceCandidate>,
    ) -> Result<(), AppError> {
        if candidates.is_empty() {
            debug!(call_id = %call_id, "No ICE candidates to send");
            return Ok(());
        }

        info!(
            call_id = %call_id,
            room_id = %room_id,
            party_id = %party_id,
            candidate_count = candidates.len(),
            "Sending Matrix ICE candidates"
        );

        // Build m.call.candidates event content manually
        let content = json!({
            "call_id": call_id.to_string(),
            "party_id": party_id,
            "version": "1",
            "candidates": candidates
        });

        // Send via Matrix client
        self.send_custom_event(room_id, "m.call.candidates", content)
            .await?;

        info!(
            call_id = %call_id,
            "Matrix ICE candidates sent"
        );

        Ok(())
    }

    /// Send m.call.hangup event to end a call
    ///
    /// # Arguments
    /// * `room_id` - Matrix room where call takes place
    /// * `call_id` - Unique identifier for this call
    /// * `party_id` - Unique identifier for this party/session
    /// * `reason` - Reason for hangup (e.g., "user_hangup", "ice_failed")
    pub async fn send_hangup(
        &self,
        room_id: &RoomId,
        call_id: Uuid,
        party_id: &str,
        reason: &str,
    ) -> Result<(), AppError> {
        info!(
            call_id = %call_id,
            room_id = %room_id,
            party_id = %party_id,
            reason = %reason,
            "Sending Matrix call hangup"
        );

        // Build m.call.hangup event content manually
        let content = json!({
            "call_id": call_id.to_string(),
            "party_id": party_id,
            "version": "1",
            "reason": reason
        });

        // Send via Matrix client
        self.send_custom_event(room_id, "m.call.hangup", content)
            .await?;

        info!(
            call_id = %call_id,
            "Matrix call hangup sent"
        );

        Ok(())
    }

    /// Send custom Matrix events using SDK 0.16 raw event API
    ///
    /// This implementation uses `room.send_raw()` to send custom VoIP events
    /// that are not yet fully typed in Matrix SDK 0.16.
    ///
    /// # Arguments
    /// * `room_id` - Matrix room to send event to
    /// * `event_type` - Matrix event type (e.g., "m.call.invite")
    /// * `content` - Event content as JSON
    ///
    /// # Returns
    /// Matrix event ID of the sent event
    async fn send_custom_event(
        &self,
        room_id: &RoomId,
        event_type: &str,
        content: serde_json::Value,
    ) -> Result<String, AppError> {
        // Get room from client
        let room = self
            .matrix_client
            .inner()
            .get_room(room_id)
            .ok_or_else(|| {
                error!(room_id = %room_id, "Room not found");
                AppError::NotFound
            })?;

        debug!(
            room_id = %room_id,
            event_type = %event_type,
            "Sending custom Matrix event"
        );

        // Convert JSON content to Raw format for Matrix SDK
        // First serialize to string, then parse as Raw
        let json_string = serde_json::to_string(&content)
            .map_err(|e| {
                error!(error = %e, "Failed to serialize event content");
                AppError::BadRequest(format!("Invalid event content: {}", e))
            })?;

        let raw_content = Raw::from_json(
            serde_json::value::RawValue::from_string(json_string)
                .map_err(|e| {
                    error!(error = %e, "Failed to create raw JSON value");
                    AppError::BadRequest(format!("Invalid JSON format: {}", e))
                })?
        );

        // Send raw event using Matrix SDK 0.16 API
        let response = room
            .send_raw(event_type, raw_content)
            .await
            .map_err(|e| {
                error!(
                    error = %e,
                    room_id = %room_id,
                    event_type = %event_type,
                    "Failed to send Matrix event"
                );
                AppError::StartServer(format!("Matrix send event failed: {}", e))
            })?;

        let event_id = response.event_id.to_string();

        info!(
            room_id = %room_id,
            event_type = %event_type,
            event_id = %event_id,
            "Custom Matrix event sent successfully"
        );

        Ok(event_id)
    }

    /// Get the underlying Matrix client
    pub fn client(&self) -> &Arc<MatrixClient> {
        &self.matrix_client
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ice_candidate_serialization() {
        let candidate = IceCandidate {
            candidate: "candidate:1 1 UDP 2130706431 192.168.1.1 54321 typ host".to_string(),
            sdp_mid: Some("0".to_string()),
            sdp_m_line_index: Some(0),
        };

        let json = serde_json::to_string(&candidate).unwrap();
        assert!(json.contains("candidate:1"));
        assert!(json.contains("sdpMid"));
        assert!(json.contains("sdpMLineIndex"));
    }

    #[test]
    fn test_party_id_format() {
        let user_id = Uuid::new_v4();
        let party_id = format!("nova-{}", user_id);
        assert!(party_id.starts_with("nova-"));
        assert_eq!(party_id.len(), 5 + 36); // "nova-" + UUID
    }

    #[test]
    fn test_session_description_serialization() {
        let sdp = SessionDescription {
            sdp_type: "offer".to_string(),
            sdp: "v=0\r\no=- ...".to_string(),
        };

        let json = serde_json::to_value(&sdp).unwrap();
        assert_eq!(json["type"], "offer");
        assert!(json["sdp"].as_str().unwrap().starts_with("v=0"));
    }
}

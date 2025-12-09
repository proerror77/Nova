use crate::error::AppError;
use matrix_sdk::ruma::serde::Raw;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tracing::{debug, info};

/// Matrix VoIP Event Handler for SDK 0.7
///
/// Since Matrix SDK 0.7 doesn't have typed VoIP event structures,
/// we manually parse raw JSON events from the sync loop.
///
/// This handler processes:
/// - m.call.invite - Incoming call invitations
/// - m.call.answer - Call answers from peer
/// - m.call.candidates - ICE candidates for WebRTC connection
/// - m.call.hangup - Call termination signals
pub struct MatrixVoipEventHandler;

impl MatrixVoipEventHandler {
    /// Create new event handler
    pub fn new() -> Self {
        Self
    }

    /// Handle a Matrix sync event
    ///
    /// Inspects the event type and routes to appropriate handler
    pub async fn handle_event(
        &self,
        event_type: &str,
        event_content: Raw<Value>,
    ) -> Result<(), AppError> {
        match event_type {
            "m.call.invite" => self.handle_call_invite(event_content).await,
            "m.call.answer" => self.handle_call_answer(event_content).await,
            "m.call.candidates" => self.handle_call_candidates(event_content).await,
            "m.call.hangup" => self.handle_call_hangup(event_content).await,
            _ => {
                debug!(event_type = %event_type, "Ignoring non-VoIP event");
                Ok(())
            }
        }
    }

    /// Handle m.call.invite event
    async fn handle_call_invite(&self, event: Raw<Value>) -> Result<(), AppError> {
        // First deserialize Raw<Value> to Value, then convert to our struct
        let value: Value = event
            .deserialize()
            .map_err(|e| AppError::StartServer(format!("Failed to deserialize raw event: {e}")))?;

        let content: CallInviteContent = serde_json::from_value(value)
            .map_err(|e| AppError::StartServer(format!("Failed to parse call.invite: {e}")))?;

        info!(
            call_id = %content.call_id,
            party_id = %content.party_id,
            version = %content.version,
            lifetime_ms = content.lifetime,
            "Received m.call.invite"
        );

        // TODO: Forward to CallService for processing
        // This will:
        // 1. Look up conversation_id from call_id (or create new conversation)
        // 2. Notify recipient via WebSocket
        // 3. Store Matrix event_id and party_id in database
        // 4. Return OK to Matrix (event acknowledged)

        debug!(
            call_id = %content.call_id,
            "[TODO] Forward call invite to CallService"
        );

        Ok(())
    }

    /// Handle m.call.answer event
    async fn handle_call_answer(&self, event: Raw<Value>) -> Result<(), AppError> {
        let value: Value = event
            .deserialize()
            .map_err(|e| AppError::StartServer(format!("Failed to deserialize raw event: {e}")))?;

        let content: CallAnswerContent = serde_json::from_value(value)
            .map_err(|e| AppError::StartServer(format!("Failed to parse call.answer: {e}")))?;

        info!(
            call_id = %content.call_id,
            party_id = %content.party_id,
            "Received m.call.answer"
        );

        // TODO: Forward to CallService
        // This will:
        // 1. Find active call by call_id
        // 2. Extract SDP answer
        // 3. Notify caller via WebSocket with SDP answer
        // 4. Update call state to "connected"

        debug!(
            call_id = %content.call_id,
            "[TODO] Forward call answer to CallService"
        );

        Ok(())
    }

    /// Handle m.call.candidates event
    async fn handle_call_candidates(&self, event: Raw<Value>) -> Result<(), AppError> {
        let value: Value = event
            .deserialize()
            .map_err(|e| AppError::StartServer(format!("Failed to deserialize raw event: {e}")))?;

        let content: CallCandidatesContent = serde_json::from_value(value)
            .map_err(|e| AppError::StartServer(format!("Failed to parse call.candidates: {e}")))?;

        info!(
            call_id = %content.call_id,
            party_id = %content.party_id,
            candidate_count = content.candidates.len(),
            "Received m.call.candidates"
        );

        // TODO: Forward to CallService
        // This will:
        // 1. Find active call by call_id
        // 2. Extract ICE candidates
        // 3. Forward candidates to peer via WebSocket
        // 4. Peer will add candidates to PeerConnection

        debug!(
            call_id = %content.call_id,
            "[TODO] Forward ICE candidates to CallService"
        );

        Ok(())
    }

    /// Handle m.call.hangup event
    async fn handle_call_hangup(&self, event: Raw<Value>) -> Result<(), AppError> {
        let value: Value = event
            .deserialize()
            .map_err(|e| AppError::StartServer(format!("Failed to deserialize raw event: {e}")))?;

        let content: CallHangupContent = serde_json::from_value(value)
            .map_err(|e| AppError::StartServer(format!("Failed to parse call.hangup: {e}")))?;

        info!(
            call_id = %content.call_id,
            party_id = %content.party_id,
            reason = %content.reason,
            "Received m.call.hangup"
        );

        // TODO: Forward to CallService
        // This will:
        // 1. Find active call by call_id
        // 2. Notify both parties via WebSocket
        // 3. Update call state to "ended"
        // 4. Clean up resources

        debug!(
            call_id = %content.call_id,
            reason = %content.reason,
            "[TODO] Forward call hangup to CallService"
        );

        Ok(())
    }
}

// --- Manual VoIP Event Content Structs (Matrix SDK 0.7) ---

/// m.call.invite event content
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallInviteContent {
    call_id: String,
    party_id: String,
    version: String,
    lifetime: u64, // milliseconds
    offer: SdpOffer,
    #[serde(skip_serializing_if = "Option::is_none")]
    invitee: Option<String>, // Matrix user ID for 1:1 calls
}

/// SDP offer structure
#[derive(Debug, Clone, Serialize, Deserialize)]
struct SdpOffer {
    #[serde(rename = "type")]
    sdp_type: String, // Always "offer"
    sdp: String,      // WebRTC SDP
}

/// m.call.answer event content
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallAnswerContent {
    call_id: String,
    party_id: String,
    version: String,
    answer: SdpAnswer,
}

/// SDP answer structure
#[derive(Debug, Clone, Serialize, Deserialize)]
struct SdpAnswer {
    #[serde(rename = "type")]
    sdp_type: String, // Always "answer"
    sdp: String,      // WebRTC SDP
}

/// m.call.candidates event content
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallCandidatesContent {
    call_id: String,
    party_id: String,
    version: String,
    candidates: Vec<IceCandidate>,
}

/// ICE candidate for WebRTC
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IceCandidate {
    pub candidate: String,
    #[serde(rename = "sdpMid", skip_serializing_if = "Option::is_none")]
    pub sdp_mid: Option<String>,
    #[serde(rename = "sdpMLineIndex", skip_serializing_if = "Option::is_none")]
    pub sdp_m_line_index: Option<u32>,
}

/// m.call.hangup event content
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CallHangupContent {
    call_id: String,
    party_id: String,
    version: String,
    reason: String, // e.g., "user_hangup", "ice_failed", "invite_timeout"
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_parse_call_invite() {
        let json = json!({
            "call_id": "12345-67890",
            "party_id": "nova-abc123",
            "version": "1",
            "lifetime": 60000,
            "offer": {
                "type": "offer",
                "sdp": "v=0\r\no=- 123 456 IN IP4 192.168.1.1\r\n..."
            }
        });

        let content: CallInviteContent = serde_json::from_value(json).unwrap();
        assert_eq!(content.call_id, "12345-67890");
        assert_eq!(content.party_id, "nova-abc123");
        assert_eq!(content.lifetime, 60000);
        assert_eq!(content.offer.sdp_type, "offer");
    }

    #[test]
    fn test_parse_ice_candidates() {
        let json = json!({
            "call_id": "12345-67890",
            "party_id": "nova-abc123",
            "version": "1",
            "candidates": [
                {
                    "candidate": "candidate:1 1 UDP 2130706431 192.168.1.1 54321 typ host",
                    "sdpMid": "0",
                    "sdpMLineIndex": 0
                }
            ]
        });

        let content: CallCandidatesContent = serde_json::from_value(json).unwrap();
        assert_eq!(content.candidates.len(), 1);
        assert!(content.candidates[0].candidate.starts_with("candidate:1"));
    }

    #[test]
    fn test_parse_call_hangup() {
        let json = json!({
            "call_id": "12345-67890",
            "party_id": "nova-abc123",
            "version": "1",
            "reason": "user_hangup"
        });

        let content: CallHangupContent = serde_json::from_value(json).unwrap();
        assert_eq!(content.reason, "user_hangup");
    }
}

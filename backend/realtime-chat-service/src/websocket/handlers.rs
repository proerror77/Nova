// This file previously supported the REST-layer WebSocket route implementation.
// Nova is now Matrix-first; the realtime-chat-service no longer exposes chat WebSocket endpoints.

use uuid::Uuid;

#[derive(Debug, serde::Deserialize)]
pub struct WsParams {
    pub conversation_id: Uuid,
    pub user_id: Uuid,
    pub token: Option<String>,
}

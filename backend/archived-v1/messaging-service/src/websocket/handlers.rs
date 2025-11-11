// This file is part of the wsroute.rs Actor-based WebSocket implementation
// It's kept for compatibility but the main WebSocket logic is now in wsroute.rs

// WebSocket handling is now done via the WsSession Actor in wsroute.rs
// Please refer to that file for the actual WebSocket implementation

use uuid::Uuid;

#[derive(Debug, serde::Deserialize)]
pub struct WsParams {
    pub conversation_id: Uuid,
    pub user_id: Uuid,
    pub token: Option<String>,
}

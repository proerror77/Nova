use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsInboundEvent {
    #[serde(rename = "typing")]
    Typing { conversation_id: Uuid, user_id: Uuid },
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsOutboundEvent {
    #[serde(rename = "typing")]
    Typing { conversation_id: Uuid, user_id: Uuid },
}


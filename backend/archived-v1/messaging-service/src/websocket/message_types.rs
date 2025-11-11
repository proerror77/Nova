use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsInboundEvent {
    #[serde(rename = "typing")]
    Typing {
        conversation_id: Uuid,
        user_id: Uuid,
    },
    #[serde(rename = "ack")]
    Ack {
        msg_id: String,
        conversation_id: Uuid,
    },
    #[serde(rename = "get_unacked")]
    GetUnacked,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum WsOutboundEvent {
    #[serde(rename = "typing")]
    Typing {
        conversation_id: Uuid,
        user_id: Uuid,
    },
}

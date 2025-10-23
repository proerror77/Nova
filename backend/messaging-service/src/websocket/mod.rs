use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc::{UnboundedSender, UnboundedReceiver, unbounded_channel}};
use uuid::Uuid;
use axum::extract::ws::Message;

pub mod handlers;
pub mod subscription;
pub mod broadcast;
pub mod pubsub;
pub mod message_types;

#[derive(Default, Clone)]
pub struct ConnectionRegistry {
    // conversation_id -> list of channel senders
    inner: Arc<RwLock<HashMap<Uuid, Vec<UnboundedSender<Message>>>>>,
}

impl ConnectionRegistry {
    pub fn new() -> Self { Self::default() }

    pub async fn add_subscriber(&self, conversation_id: Uuid) -> UnboundedReceiver<Message> {
        let (tx, rx) = unbounded_channel();
        let mut guard = self.inner.write().await;
        guard.entry(conversation_id).or_default().push(tx);
        rx
    }

    pub async fn broadcast(&self, conversation_id: Uuid, msg: Message) {
        let mut guard = self.inner.write().await;
        if let Some(list) = guard.get_mut(&conversation_id) {
            list.retain(|sender| sender.send(msg.clone()).is_ok());
        }
    }
}

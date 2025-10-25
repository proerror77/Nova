use crate::models::video::ProgressEvent;
use actix::prelude::*;
use actix_web_actors::ws;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

/// WebSocket actor for transcoding progress streaming
pub struct ProgressStreamActor {
    video_id: Uuid,
    registry: Arc<ProgressStreamRegistry>,
}

impl ProgressStreamActor {
    pub fn new(video_id: Uuid, registry: Arc<ProgressStreamRegistry>) -> Self {
        Self { video_id, registry }
    }
}

impl Actor for ProgressStreamActor {
    type Context = ws::WebsocketContext<Self>;

    fn started(&mut self, ctx: &mut Self::Context) {
        tracing::info!("Progress stream started for video {}", self.video_id);

        // Register this actor with the registry
        let addr = ctx.address();
        let video_id = self.video_id;
        let registry = self.registry.clone();

        actix::spawn(async move {
            registry.subscribe(video_id, addr).await;
        });
    }

    fn stopped(&mut self, ctx: &mut Self::Context) {
        tracing::info!("Progress stream stopped for video {}", self.video_id);

        // Unregister from registry
        let video_id = self.video_id;
        let addr = ctx.address();
        let registry = self.registry.clone();

        actix::spawn(async move {
            registry.unsubscribe(video_id, &addr).await;
        });
    }
}

impl StreamHandler<Result<ws::Message, ws::ProtocolError>> for ProgressStreamActor {
    fn handle(&mut self, msg: Result<ws::Message, ws::ProtocolError>, ctx: &mut Self::Context) {
        match msg {
            Ok(ws::Message::Ping(msg)) => ctx.pong(&msg),
            Ok(ws::Message::Pong(_)) => {}
            Ok(ws::Message::Close(reason)) => {
                ctx.close(reason);
                ctx.stop();
            }
            Ok(ws::Message::Text(_)) => {
                // Clients shouldn't send messages, this is a one-way stream
                tracing::warn!("Unexpected text message from client");
            }
            _ => {}
        }
    }
}

/// Message sent to actor to broadcast progress update
#[derive(Message, Clone)]
#[rtype(result = "()")]
pub struct BroadcastProgress(pub ProgressEvent);

impl Handler<BroadcastProgress> for ProgressStreamActor {
    type Result = ();

    fn handle(&mut self, msg: BroadcastProgress, ctx: &mut Self::Context) {
        let event = msg.0;

        if event.video_id != self.video_id {
            return; // Only handle events for this video
        }

        match serde_json::to_string(&event) {
            Ok(json) => {
                ctx.text(json);
            }
            Err(e) => {
                tracing::error!("Failed to serialize progress event: {}", e);
            }
        }
    }
}

/// Registry of active WebSocket connections for progress streaming
pub struct ProgressStreamRegistry {
    /// Map of video_id -> list of WebSocket actors
    subscribers: RwLock<HashMap<Uuid, Vec<Addr<ProgressStreamActor>>>>,
}

impl ProgressStreamRegistry {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            subscribers: RwLock::new(HashMap::new()),
        })
    }

    /// Subscribe a WebSocket actor to progress updates for a video
    pub async fn subscribe(&self, video_id: Uuid, addr: Addr<ProgressStreamActor>) {
        let mut subs = self.subscribers.write().await;
        subs.entry(video_id).or_insert_with(Vec::new).push(addr);
        tracing::info!("Subscribed to progress updates for video {}", video_id);
    }

    /// Unsubscribe a WebSocket actor
    pub async fn unsubscribe(&self, video_id: Uuid, addr: &Addr<ProgressStreamActor>) {
        let mut subs = self.subscribers.write().await;
        if let Some(actors) = subs.get_mut(&video_id) {
            actors.retain(|a| a != addr);
            if actors.is_empty() {
                subs.remove(&video_id);
            }
        }
        tracing::info!("Unsubscribed from progress updates for video {}", video_id);
    }

    /// Broadcast progress event to all subscribers of a video
    pub async fn broadcast(&self, event: ProgressEvent) {
        let subs = self.subscribers.read().await;
        if let Some(actors) = subs.get(&event.video_id) {
            tracing::debug!(
                "Broadcasting progress to {} subscribers for video {}",
                actors.len(),
                event.video_id
            );

            for actor in actors {
                actor.do_send(BroadcastProgress(event.clone()));
            }
        }
    }

    /// Get count of active subscribers for a video
    pub async fn subscriber_count(&self, video_id: Uuid) -> usize {
        let subs = self.subscribers.read().await;
        subs.get(&video_id).map(|v| v.len()).unwrap_or(0)
    }

    /// Get total subscriber count across all videos
    pub async fn total_subscribers(&self) -> usize {
        let subs = self.subscribers.read().await;
        subs.values().map(|v| v.len()).sum()
    }
}

impl Default for ProgressStreamRegistry {
    fn default() -> Self {
        Self {
            subscribers: RwLock::new(HashMap::new()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_rt::test]
    async fn test_registry_subscribe_unsubscribe() {
        let registry = ProgressStreamRegistry::new();
        let video_id = Uuid::new_v4();

        // Initially no subscribers
        assert_eq!(registry.subscriber_count(video_id).await, 0);

        // Note: Cannot easily test actual actor subscriptions without full actix system
        // This would require integration tests
    }

    #[actix_rt::test]
    async fn test_registry_broadcast() {
        let registry = ProgressStreamRegistry::new();
        let video_id = Uuid::new_v4();

        let event = ProgressEvent::new_progress(video_id, 50, Some("test".to_string()), None);

        // Broadcasting to no subscribers should not panic
        registry.broadcast(event).await;
    }
}

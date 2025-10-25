//! WebSocket chat for live streams
//!
//! Simple, stateless design:
//! - ConnectionRegistry: in-memory store of active stream chat connections
//! - StreamChatMessage: unified message type (send/receive)
//! - No special cases: all messages go through the same code path

use super::chat_store::{StreamChatStore, StreamComment};
use crate::services::kafka_producer::EventProducer;
use actix::prelude::*;
use actix_web_actors::ws;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

// ============================================================================
// Message Types
// ============================================================================

/// Unified WebSocket message type (client sends this)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum StreamChatMessage {
    #[serde(rename = "message")]
    Message { text: String },
    #[serde(rename = "ping")]
    Ping,
}

/// Server broadcasts this to all clients in a stream
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamChatBroadcast {
    pub comment: StreamComment,
}

// ============================================================================
// Connection Registry (in-memory, per-stream)
// ============================================================================

pub type ChatSender = Addr<StreamChatActor>;

/// Tracks active WebSocket connections for a stream
#[derive(Clone)]
pub struct StreamConnectionRegistry {
    // stream_id -> list of active connections
    inner: Arc<RwLock<HashMap<Uuid, Vec<ChatSender>>>>,
}

impl StreamConnectionRegistry {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Register a new connection for a stream
    pub async fn register(&self, stream_id: Uuid, actor: ChatSender) {
        let mut registry = self.inner.write().await;
        registry.entry(stream_id).or_default().push(actor);
    }

    /// Broadcast a comment to all connections in a stream
    pub async fn broadcast(&self, stream_id: Uuid, comment: StreamComment) {
        let registry = self.inner.read().await;
        if let Some(connections) = registry.get(&stream_id) {
            let msg = StreamChatBroadcast { comment };
            for conn in connections {
                let _ = conn.try_send(BroadcastMessage(msg.clone()));
            }
        }
    }

    /// Remove dead connections (cleanup is called on actor stop)
    pub async fn cleanup(&self, stream_id: Uuid) {
        let mut registry = self.inner.write().await;
        // Simply remove the stream entry when cleanup is called
        // (this is called when the last connection disconnects)
        registry.remove(&stream_id);
    }
}

impl Default for StreamConnectionRegistry {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Actix Actor for individual WebSocket session
// ============================================================================

/// Message to broadcast to this actor
#[derive(Clone, Message)]
#[rtype(result = "()")]
pub struct BroadcastMessage(pub StreamChatBroadcast);

/// Actor for a single WebSocket connection
pub struct StreamChatActor {
    stream_id: Uuid,
    user_id: Uuid,
    username: String,
    registry: StreamConnectionRegistry,
    chat_store: StreamChatStore,
    kafka_producer: Arc<EventProducer>,
}

impl Actor for StreamChatActor {
    type Context = ws::WebsocketContext<Self>;

    fn started(&mut self, ctx: &mut Self::Context) {
        tracing::debug!(
            "WebSocket chat session started for stream {} by user {}",
            self.stream_id,
            self.user_id
        );

        // Register this actor in the connection registry
        let registry = self.registry.clone();
        let stream_id = self.stream_id;
        let actor_addr = ctx.address();

        // Spawn async task to register the connection
        actix_rt::spawn(async move {
            registry.register(stream_id, actor_addr).await;
        });
    }

    fn stopped(&mut self, _ctx: &mut Self::Context) {
        tracing::debug!(
            "WebSocket chat session stopped for stream {} by user {}",
            self.stream_id,
            self.user_id
        );

        // Cleanup dead connections
        let registry = self.registry.clone();
        let stream_id = self.stream_id;

        actix_rt::spawn(async move {
            registry.cleanup(stream_id).await;
        });
    }
}

impl Handler<BroadcastMessage> for StreamChatActor {
    type Result = ();

    fn handle(&mut self, msg: BroadcastMessage, ctx: &mut Self::Context) {
        match serde_json::to_string(&msg.0) {
            Ok(json) => ctx.text(json),
            Err(e) => tracing::warn!("Failed to serialize broadcast message: {}", e),
        }
    }
}

impl StreamHandler<Result<ws::Message, ws::ProtocolError>> for StreamChatActor {
    fn handle(&mut self, msg: Result<ws::Message, ws::ProtocolError>, ctx: &mut Self::Context) {
        match msg {
            Ok(ws::Message::Text(text)) => {
                tracing::debug!("Received text from user {}: {} bytes", self.user_id, text.len());

                // Parse JSON message
                if let Ok(payload) = serde_json::from_str::<StreamChatMessage>(&text) {
                    match payload {
                        StreamChatMessage::Message { text: msg_text } => {
                            // Validate message length
                            if msg_text.trim().is_empty() {
                                tracing::debug!("Ignoring empty message from user {}", self.user_id);
                                return;
                            }
                            if msg_text.len() > 500 {
                                tracing::warn!("Message too long from user {}", self.user_id);
                                let _ = ctx.text(
                                    serde_json::json!({
                                        "type": "error",
                                        "message": "Message too long (max 500 chars)"
                                    })
                                    .to_string(),
                                );
                                return;
                            }

                            // Create comment object with username
                            let comment = StreamComment::new(
                                self.stream_id,
                                self.user_id,
                                Some(self.username.clone()),
                                msg_text.trim().to_string(),
                            );

                            // Clone for async operations
                            let registry = self.registry.clone();
                            let mut chat_store = self.chat_store.clone();
                            let kafka_producer = self.kafka_producer.clone();
                            let comment_to_broadcast = comment.clone();
                            let comment_to_persist = comment.clone();
                            let stream_id = self.stream_id;

                            // Spawn async task to: (1) broadcast (2) persist to Redis (3) send to Kafka
                            actix_rt::spawn(async move {
                                // Broadcast to all connections in this stream
                                registry.broadcast(stream_id, comment_to_broadcast).await;

                                // Persist to Redis chat history
                                if let Err(e) = chat_store.append_comment(&comment_to_persist).await {
                                    tracing::warn!("Failed to persist comment to Redis: {}", e);
                                }

                                // Publish to Kafka topic: streams.chat
                                let kafka_payload = serde_json::json!({
                                    "event_type": "stream_chat_message",
                                    "stream_id": comment_to_persist.stream_id,
                                    "user_id": comment_to_persist.user_id,
                                    "username": comment_to_persist.username,
                                    "message": comment_to_persist.message,
                                    "created_at": comment_to_persist.created_at,
                                    "comment_id": comment_to_persist.id,
                                });

                                if let Err(e) = kafka_producer
                                    .send_json(&comment_to_persist.id.to_string(), &kafka_payload.to_string())
                                    .await
                                {
                                    tracing::warn!("Failed to publish chat message to Kafka: {}", e);
                                }
                            });
                        }
                        StreamChatMessage::Ping => {
                            ctx.pong(&[]);
                        }
                    }
                } else {
                    tracing::warn!("Received invalid JSON from user {}", self.user_id);
                }
            }
            Ok(ws::Message::Ping(msg)) => {
                ctx.pong(&msg);
            }
            Ok(ws::Message::Pong(_)) => {
                // ignore pong messages
            }
            Ok(ws::Message::Close(reason)) => {
                ctx.close(reason);
                ctx.stop();
            }
            Ok(ws::Message::Continuation(_)) => {
                tracing::warn!("Received continuation frame (closing connection)");
                ctx.stop();
            }
            Ok(ws::Message::Binary(_)) => {
                tracing::warn!("Received binary message (unsupported)");
                ctx.stop();
            }
            Ok(ws::Message::Nop) => {
                // ignore no-op
            }
            Err(e) => {
                tracing::error!("WebSocket protocol error: {}", e);
                ctx.stop();
            }
        }
    }
}

impl StreamChatActor {
    pub fn new(
        stream_id: Uuid,
        user_id: Uuid,
        username: String,
        registry: StreamConnectionRegistry,
        chat_store: StreamChatStore,
        kafka_producer: Arc<EventProducer>,
    ) -> Self {
        Self {
            stream_id,
            user_id,
            username,
            registry,
            chat_store,
            kafka_producer,
        }
    }

    pub fn stream_id(&self) -> Uuid {
        self.stream_id
    }

    pub fn user_id(&self) -> Uuid {
        self.user_id
    }
}

// ============================================================================
// Handler Registration
// ============================================================================

/// Context for WebSocket handler (shared state)
#[derive(Clone)]
pub struct StreamChatHandlerState {
    pub registry: StreamConnectionRegistry,
    pub chat_store: StreamChatStore,
    pub kafka_producer: Arc<EventProducer>,
    pub db_pool: PgPool,
}

impl StreamChatHandlerState {
    pub fn new(
        chat_store: StreamChatStore,
        kafka_producer: Arc<EventProducer>,
        db_pool: PgPool,
    ) -> Self {
        Self {
            registry: StreamConnectionRegistry::new(),
            chat_store,
            kafka_producer,
            db_pool,
        }
    }

    /// Fetch username from database
    pub async fn get_username(&self, user_id: Uuid) -> Option<String> {
        sqlx::query_scalar::<_, String>("SELECT username FROM users WHERE id = $1")
            .bind(user_id)
            .fetch_optional(&self.db_pool)
            .await
            .ok()
            .flatten()
    }
}

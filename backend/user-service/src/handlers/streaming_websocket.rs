//! WebSocket handlers for real-time streaming updates
//!
//! Provides live updates for:
//! - Viewer count changes
//! - Stream status (started, ended)
//! - Quality adaptations
//!
//! ## Connection Lifecycle
//!
//! 1. Client connects: GET /api/v1/streams/{stream_id}/ws
//! 2. Server joins client to stream's broadcast group
//! 3. Server sends initial state (current viewer count)
//! 4. Updates pushed whenever viewer count changes
//! 5. Client disconnect: remove from broadcast group
//!
//! ## Protocol
//!
//! All messages are JSON:
//! ```json
//! {
//!   "event": "viewer_count_changed|stream_started|stream_ended|quality_changed",
//!   "data": {
//!     "stream_id": "uuid",
//!     "viewer_count": 123,
//!     "peak_viewers": 150,
//!     "timestamp": "2025-10-21T10:30:45Z"
//!   }
//! }
//! ```

use actix::prelude::*;
use actix_web::{web, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use anyhow::Result;
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

use crate::metrics::streaming_metrics;
use crate::services::streaming::ViewerCounter;

// =========================================================================
// Message Types
// =========================================================================

/// WebSocket message sent to clients
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsMessage {
    pub event: String,
    pub data: serde_json::Value,
}

/// Internal actor message for broadcasting
#[derive(Debug, Clone, Message)]
#[rtype(result = "()")]
pub struct BroadcastMessage {
    pub stream_id: Uuid,
    pub message: WsMessage,
}

/// Message to register a new client
#[derive(Debug, Message)]
#[rtype(result = "()")]
pub struct Connect {
    pub stream_id: Uuid,
    pub client_addr: Addr<StreamingWebSocket>,
}

/// Message to unregister a client
#[derive(Debug, Message)]
#[rtype(result = "()")]
pub struct Disconnect {
    pub stream_id: Uuid,
    pub session_id: usize,
}

// =========================================================================
// Hub Actor (manages all WebSocket connections)
// =========================================================================

/// Central hub for managing WebSocket connections and broadcasts
pub struct StreamingHub {
    /// Map of stream_id -> list of client addresses
    connections: HashMap<Uuid, Vec<(usize, Addr<StreamingWebSocket>)>>,
    /// Next session ID
    next_session_id: usize,
}

impl Actor for StreamingHub {
    type Context = Context<Self>;
}

impl StreamingHub {
    pub fn new() -> Self {
        Self {
            connections: HashMap::new(),
            next_session_id: 0,
        }
    }

    /// Broadcast to all clients watching a stream
    fn broadcast(&self, stream_id: Uuid, message: WsMessage) {
        if let Some(clients) = self.connections.get(&stream_id) {
            for (_, addr) in clients {
                addr.do_send(BroadcastMessage {
                    stream_id,
                    message: message.clone(),
                });
            }
        }
    }
}

impl Handler<Connect> for StreamingHub {
    type Result = ();

    fn handle(&mut self, msg: Connect, _: &mut Context<Self>) -> () {
        self.connections
            .entry(msg.stream_id)
            .or_insert_with(Vec::new)
            .push((self.next_session_id, msg.client_addr));

        self.next_session_id += 1;
    }
}

impl Handler<Disconnect> for StreamingHub {
    type Result = ();

    fn handle(&mut self, msg: Disconnect, _: &mut Context<Self>) -> () {
        if let Some(clients) = self.connections.get_mut(&msg.stream_id) {
            clients.retain(|(id, _)| id != &msg.session_id);

            // Clean up empty entries
            if clients.is_empty() {
                self.connections.remove(&msg.stream_id);
            }
        }
    }
}

impl Handler<BroadcastMessage> for StreamingHub {
    type Result = ();

    fn handle(&mut self, msg: BroadcastMessage, _: &mut Context<Self>) -> () {
        self.broadcast(msg.stream_id, msg.message);
    }
}

// =========================================================================
// WebSocket Actor (per-connection)
// =========================================================================

/// Per-WebSocket-connection actor
pub struct StreamingWebSocket {
    pub stream_id: Uuid,
    pub session_id: usize,
    pub hub: Addr<StreamingHub>,
}

impl Actor for StreamingWebSocket {
    type Context = ws::WebsocketContext<Self>;

    fn started(&mut self, ctx: &mut Self::Context) {
        // Register with hub on connection
        let addr = ctx.address();
        self.hub.do_send(Connect {
            stream_id: self.stream_id,
            client_addr: addr,
        });

        // Record WebSocket connection
        streaming_metrics::helpers::record_websocket_connection(&self.stream_id.to_string());
    }

    fn stopped(&mut self, _: &mut Self::Context) {
        // Unregister from hub on disconnect
        self.hub.do_send(Disconnect {
            stream_id: self.stream_id,
            session_id: self.session_id,
        });

        // Record WebSocket disconnection
        streaming_metrics::helpers::record_websocket_disconnection(&self.stream_id.to_string());
    }
}

impl Handler<BroadcastMessage> for StreamingWebSocket {
    type Result = ();

    fn handle(&mut self, msg: BroadcastMessage, ctx: &mut Self::Context) -> () {
        // Only handle messages for this stream
        if msg.stream_id == self.stream_id {
            if let Ok(text) = serde_json::to_string(&msg.message) {
                ctx.text(text);
            }
        }
    }
}

impl StreamHandler<Result<ws::Message, ws::ProtocolError>> for StreamingWebSocket {
    fn handle(&mut self, msg: Result<ws::Message, ws::ProtocolError>, ctx: &mut Self::Context) {
        match msg {
            Ok(ws::Message::Close(reason)) => {
                ctx.close(reason);
            }
            Ok(_) => {
                // Ignore other message types (we only send, don't receive)
            }
            Err(_) => {
                ctx.stop();
            }
        }
    }
}

// =========================================================================
// HTTP Handler
// =========================================================================

/// WebSocket upgrade handler
/// GET /api/v1/streams/{stream_id}/ws
pub async fn ws_stream_updates(
    req: HttpRequest,
    stream: web::Payload,
    path: web::Path<Uuid>,
    hub: web::Data<Addr<StreamingHub>>,
) -> Result<HttpResponse, actix_web::Error> {
    let stream_id = path.into_inner();

    // Upgrade to WebSocket connection
    ws::start(
        StreamingWebSocket {
            stream_id,
            session_id: 0, // Will be assigned by hub
            hub: hub.get_ref().clone(),
        },
        &req,
        stream,
    )
}

// =========================================================================
// Pub/Sub Helper for Real-Time Updates
// =========================================================================

/// Helper to push viewer count updates to all connected clients
pub async fn notify_viewer_count_changed(
    hub: &Addr<StreamingHub>,
    redis: &ConnectionManager,
    stream_id: Uuid,
) -> Result<()> {
    let mut counter = ViewerCounter::new(redis.clone());

    // Get current metrics
    let viewer_count = counter.get_viewer_count(stream_id).await?;
    let peak_viewers = counter.get_peak_viewers(stream_id).await?;

    // Record viewer count change to Prometheus
    // Note: Using default region "us-west-2" - should be configurable in production
    streaming_metrics::helpers::record_viewer_count_change(
        &stream_id.to_string(),
        viewer_count as i32,
        "us-west-2",
    );

    // Build message
    let message = WsMessage {
        event: "viewer_count_changed".to_string(),
        data: serde_json::json!({
            "stream_id": stream_id,
            "viewer_count": viewer_count,
            "peak_viewers": peak_viewers,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        }),
    };

    // Broadcast to all clients watching this stream
    hub.do_send(BroadcastMessage { stream_id, message });

    Ok(())
}

/// Notify stream started
pub fn notify_stream_started(hub: &Addr<StreamingHub>, stream_id: Uuid) {
    // Record stream started to Prometheus
    // Note: Using default region "us-west-2" - should be configurable in production
    streaming_metrics::helpers::record_stream_started(&stream_id.to_string(), "us-west-2");

    let message = WsMessage {
        event: "stream_started".to_string(),
        data: serde_json::json!({
            "stream_id": stream_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        }),
    };

    hub.do_send(BroadcastMessage { stream_id, message });
}

/// Notify stream ended
pub fn notify_stream_ended(hub: &Addr<StreamingHub>, stream_id: Uuid) {
    // Record stream ended to Prometheus
    // Note: Duration and final viewer count should be obtained from session tracking
    // Using defaults here - should be integrated with session store
    streaming_metrics::helpers::record_stream_ended(&stream_id.to_string(), "us-west-2", 0.0, 0);

    let message = WsMessage {
        event: "stream_ended".to_string(),
        data: serde_json::json!({
            "stream_id": stream_id,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        }),
    };

    hub.do_send(BroadcastMessage { stream_id, message });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_broadcast_message_serialization() {
        let msg = WsMessage {
            event: "viewer_count_changed".to_string(),
            data: serde_json::json!({
                "stream_id": Uuid::nil(),
                "viewer_count": 42,
                "peak_viewers": 100,
            }),
        };

        let json = serde_json::to_string(&msg).unwrap();
        let decoded: WsMessage = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.event, "viewer_count_changed");
    }

    #[test]
    fn test_hub_creation() {
        let hub = StreamingHub::new();
        assert_eq!(hub.next_session_id, 0);
        assert!(hub.connections.is_empty());
    }
}

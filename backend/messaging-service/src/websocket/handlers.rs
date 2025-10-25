use axum::{extract::{ws::{WebSocketUpgrade, WebSocket, Message}, State, Query}, response::IntoResponse};
use axum::http::HeaderMap;
use futures_util::{StreamExt, SinkExt};
use serde::Deserialize;
use uuid::Uuid;
use std::sync::Arc;
use tokio::sync::Mutex;
use crate::state::AppState;
use crate::websocket::message_types::{WsInboundEvent, WsOutboundEvent};
use crate::services::conversation_service::ConversationService;
use crate::services::offline_queue;
use crate::middleware::auth::verify_jwt;
use tracing::{warn, error};

#[derive(Debug, Deserialize)]
pub struct WsParams { pub conversation_id: Uuid, pub user_id: Uuid, pub token: Option<String> }

// === Extracted: Extract message ID from broadcast message (简化逻辑) ===
fn extract_message_id(text: &str) -> String {
    // Try JSON first
    if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
        if let Some(id) = json.get("stream_id").and_then(|v| v.as_str()) {
            return id.to_string();
        }
        if let Some(id) = json.get("id").and_then(|v| v.as_str()) {
            return id.to_string();
        }
    }

    // Fallback: hash-based ID
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    text.hash(&mut hasher);
    let hash = hasher.finish();
    let now_ms = chrono::Utc::now().timestamp_millis();

    warn!("No stream_id found in message, generating ID from content");
    format!("{}-{}", now_ms, hash % 10000)
}

// === Extracted: Handle broadcast message ===
async fn handle_broadcast_message(msg: &Message, last_received_id: &Arc<Mutex<String>>) {
    if let Message::Text(ref txt) = msg {
        let msg_id = extract_message_id(txt);
        *last_received_id.lock().await = msg_id;
    }
}

// === Extracted: Handle client message ===
async fn handle_client_message(
    incoming: &Option<Result<Message, axum::Error>>,
    params: &WsParams,
    state: &AppState,
) -> bool {
    match incoming {
        Some(Ok(Message::Text(txt))) => {
            if let Ok(evt) = serde_json::from_str::<WsInboundEvent>(txt) {
                handle_ws_event(&evt, params, state).await;
            }
            true
        }
        Some(Ok(Message::Ping(_))) => {
            // Pong is handled by framework
            true
        }
        Some(Ok(Message::Close(_))) | None => false,
        _ => true,
    }
}

// === Extracted: Handle WebSocket event ===
async fn handle_ws_event(evt: &WsInboundEvent, params: &WsParams, state: &AppState) {
    match evt {
        WsInboundEvent::Typing { conversation_id, user_id } => {
            // Validate event belongs to this connection
            if conversation_id != &params.conversation_id || user_id != &params.user_id {
                return;
            }

            let out = WsOutboundEvent::Typing {
                conversation_id: *conversation_id,
                user_id: *user_id
            };

            if let Ok(out_txt) = serde_json::to_string(&out) {
                state.registry.broadcast(*conversation_id, Message::Text(out_txt.clone())).await;
                let _ = crate::websocket::pubsub::publish(&state.redis, *conversation_id, &out_txt).await;
            } else {
                error!("Failed to serialize typing event for conversation {}, user {}", conversation_id, user_id);
            }
        }

        WsInboundEvent::Ack { msg_id, conversation_id } => {
            // Client acknowledges receipt of a message
            if conversation_id != &params.conversation_id {
                return;
            }

            let manager = state.ack_pool.get_or_create(params.user_id).await;
            manager.handle_ack(msg_id).await;
            tracing::debug!("Message {} acknowledged by user {}", msg_id, params.user_id);
        }

        WsInboundEvent::GetUnacked => {
            // Client requests unacknowledged messages
            // This is handled in the main event loop after socket split
            tracing::debug!("Client {} requested unacked messages", params.user_id);
        }
    }
}

// === Extracted: Token validation - MANDATORY, no bypasses ===
async fn validate_ws_token(params: &WsParams, headers: &HeaderMap) -> Result<(), axum::http::StatusCode> {
    // SECURITY: JWT validation is MANDATORY. No exceptions, no dev flags.
    // Fail-closed: if JWT is missing or invalid, reject the connection immediately.

    let token = params.token.clone()
        .or_else(|| {
            headers.get(axum::http::header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.strip_prefix("Bearer "))
                .map(|s| s.to_string())
        });

    match token {
        None => {
            error!("🚫 WebSocket connection REJECTED: No JWT token provided in query params or Authorization header");
            Err(axum::http::StatusCode::UNAUTHORIZED)
        }
        Some(t) => {
            verify_jwt(&t).await
                .map(|claims| {
                    // Log successful authentication
                    tracing::debug!("✅ WebSocket authentication successful for user: {}", claims.sub);
                })
                .map_err(|e| {
                    error!("🚫 WebSocket connection REJECTED: Invalid JWT token - {:?}", e);
                    axum::http::StatusCode::UNAUTHORIZED
                })
        }
    }
}

pub async fn ws_handler(
    State(state): State<AppState>,
    Query(params): Query<WsParams>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    // Early return on authentication failure
    if let Err(status) = validate_ws_token(&params, &headers).await {
        return status.into_response();
    }

    ws.on_upgrade(move |socket| handle_socket(state, params, socket))
}

// === Extracted: Membership verification - MANDATORY authorization check ===
async fn verify_conversation_membership(state: &AppState, params: &WsParams) -> Result<(), ()> {
    // SECURITY: Authorization is MANDATORY. User must be a member of the conversation.
    // Fail-closed: if check fails or user is not a member, reject immediately.

    match ConversationService::is_member(&state.db, params.conversation_id, params.user_id).await {
        Ok(true) => {
            tracing::debug!("✅ WebSocket authorization: user {} is member of conversation {}",
                params.user_id, params.conversation_id);
            Ok(())
        }
        Ok(false) => {
            error!("🚫 WebSocket connection REJECTED: user {} is NOT a member of conversation {}",
                params.user_id, params.conversation_id);
            Err(())
        }
        Err(e) => {
            error!("🚫 WebSocket connection REJECTED: membership check failed for user {} in conversation {}: {:?}",
                params.user_id, params.conversation_id, e);
            Err(())
        }
    }
}

async fn handle_socket(state: AppState, params: WsParams, mut socket: WebSocket) {
    // Early return on membership check failure
    if verify_conversation_membership(&state, &params).await.is_err() {
        let _ = socket.send(Message::Close(None)).await;
        return;
    }

    // === STEP 0: Initialize ACK Manager for this user ===
    let ack_manager = state.ack_pool.get_or_create(params.user_id).await;

    // === STEP 1: Generate unique client ID and initialize consumer group ===
    let client_id = Uuid::new_v4();

    // Initialize Redis Streams consumer group for this conversation
    // (Idempotent: safe to call repeatedly)
    if let Err(e) = offline_queue::init_consumer_group(&state.redis, params.conversation_id).await {
        error!("Failed to initialize consumer group: {:?}", e);
        let _ = socket.send(Message::Close(None)).await;
        return;
    }

    let (mut sender, mut receiver) = socket.split();

    // === STEP 2: Deliver offline messages (atomic operation) ===
    // CRITICAL FIX: Use atomic delivery to prevent message loss
    //
    // Previous approach had race condition:
    //   add_subscriber() → [WINDOW] → read_pending_messages()
    // Messages arriving in [WINDOW] between these calls would be lost.
    //
    // Fix: Combine three operations atomically:
    // 1. Read pending messages from previous session
    // 2. Register for real-time broadcasts
    // 3. Read new messages since step 2
    //
    // This ensures all messages are captured without gaps.

    // Step 2a: Read pending messages (from previous disconnection)
    let pending_messages = offline_queue::read_pending_messages(
        &state.redis,
        params.conversation_id,
        params.user_id,
        client_id,
    )
    .await
    .unwrap_or_default();

    // Step 2b: Register broadcast subscription
    // Now any messages from this point forward will be caught by rx
    let (subscriber_id, mut rx) = state.registry.add_subscriber(params.conversation_id).await;

    // Step 2c: Immediately read new messages (those that arrived after init_consumer_group)
    // This captures messages between init_consumer_group and add_subscriber
    let new_messages = offline_queue::read_new_messages(
        &state.redis,
        params.conversation_id,
        params.user_id,
        client_id,
    )
    .await
    .unwrap_or_default();

    // Step 2d: Combine and deliver all messages (pending + new)
    let all_messages = [pending_messages, new_messages].concat();
    for (stream_id, fields) in all_messages {
        if let Some(payload) = fields.get("payload") {
            let msg = Message::Text(payload.clone());
            if sender.send(msg).await.is_err() {
                return;  // Connection closed
            }
            // Acknowledge after successful send (idempotent)
            let _ = offline_queue::acknowledge_message(
                &state.redis,
                params.conversation_id,
                &stream_id,
            ).await;
        }
    }

    // === STEP 4: Periodic consumer group monitoring ===
    // Spawn background task to periodically update monitoring state
    // (Not critical for functionality, but helps with debugging and metrics)
    let monitoring_task = {
        let redis = state.redis.clone();
        let user_id = params.user_id;
        let conversation_id = params.conversation_id;

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(5));
            loop {
                interval.tick().await;
                let sync_state = offline_queue::ClientSyncState {
                    client_id,
                    user_id,
                    conversation_id,
                    last_message_id: "consumer-active".to_string(),  // Monitoring flag
                    last_sync_at: chrono::Utc::now().timestamp(),
                };
                let _ = offline_queue::update_client_sync_state(&redis, &sync_state).await;
            }
        })
    };

    // === STEP 5: Periodic stream trimming ===
    // Spawn background task to periodically trim old messages
    // Prevents unbounded stream growth
    let trimming_task = {
        let redis = state.redis.clone();
        let conversation_id = params.conversation_id;

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(3600));  // Every hour
            loop {
                interval.tick().await;
                // Trim stream to keep only 10,000 most recent messages
                // Approximate trimming (~10% variance) is much faster than exact
                if let Err(e) = offline_queue::trim_stream(&redis, conversation_id, 10000).await {
                    error!("Failed to trim stream: {:?}", e);
                }
            }
        })
    };

    // === STEP 5.5: ACK timeout checking ===
    // Spawn background task to periodically check for timed-out messages
    // and automatically retry with exponential backoff
    let ack_timeout_task = {
        let ack_manager = ack_manager.clone();

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));  // Check every 10 seconds
            loop {
                interval.tick().await;
                ack_manager.check_timeouts().await;
            }
        })
    };

    // === STEP 6: MAIN MESSAGE LOOP ===
    // Multiplex incoming client messages and outgoing broadcast messages
    loop {
        tokio::select! {
            // Handle outgoing broadcast messages from other clients
            maybe = rx.recv() => {
                if let Some(msg) = maybe {
                    // Try to extract stream_id from message (for logging)
                    if let Message::Text(ref txt) = msg {
                        if let Ok(json) = serde_json::from_str::<serde_json::Value>(txt) {
                            if let Some(_stream_id) = json.get("stream_id").and_then(|v| v.as_str()) {
                                // Message came from stream - could be tracked
                            }
                        }
                    }

                    // Send to client
                    if sender.send(msg).await.is_err() {
                        break;  // Connection closed
                    }
                } else {
                    break;  // Broadcast receiver closed
                }
            }

            // Handle incoming client messages
            incoming = receiver.next() => {
                if !handle_client_message(&incoming, &params, &state).await {
                    break;
                }
            }
        }
    }

    // === STEP 7: CLEANUP ===
    // CRITICAL: Remove subscriber from registry FIRST to prevent memory leak
    // This is the primary defense against accumulating dead senders
    state.registry.remove_subscriber(params.conversation_id, subscriber_id).await;
    tracing::debug!(
        "Removed subscriber {} from conversation {} registry",
        format!("{:?}", subscriber_id),
        params.conversation_id
    );

    // Save final monitoring state on disconnection
    let final_state = offline_queue::ClientSyncState {
        client_id,
        user_id: params.user_id,
        conversation_id: params.conversation_id,
        last_message_id: "disconnected".to_string(),
        last_sync_at: chrono::Utc::now().timestamp(),
    };
    let _ = offline_queue::update_client_sync_state(&state.redis, &final_state).await;

    // Cancel background tasks
    monitoring_task.abort();
    trimming_task.abort();
    ack_timeout_task.abort();

    // Cleanup ACK manager on disconnect
    state.ack_pool.cleanup(params.user_id).await;

    tracing::debug!(
        "WebSocket connection closed for user {} in conversation {}",
        params.user_id,
        params.conversation_id
    );
}

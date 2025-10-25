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
use crate::services::offline_queue::{self, ClientSyncState};
use crate::middleware::auth::verify_jwt;
use tracing::{warn, error};

#[derive(Debug, Deserialize)]
pub struct WsParams { pub conversation_id: Uuid, pub user_id: Uuid, pub token: Option<String> }

pub async fn ws_handler(
    State(state): State<AppState>,
    Query(params): Query<WsParams>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    // Check for development mode bypass (DANGEROUS - only for testing)
    let dev_allow = std::env::var("WS_DEV_ALLOW_ALL").unwrap_or_else(|_| "false".into()) == "true";

    if dev_allow {
        warn!(
            "⚠️  JWT validation BYPASSED (WS_DEV_ALLOW_ALL=true) - DO NOT USE IN PRODUCTION ⚠️"
        );
    } else {
        // PRODUCTION MODE: Enforce JWT validation
        // Accept JWT from query ?token= or Authorization: Bearer <token>
        let token_from_query = params.token.clone();
        let token_from_header = headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "))
            .map(|s| s.to_string());

        let token = token_from_query.or(token_from_header);

        match token {
            None => {
                error!("WebSocket connection rejected: No JWT token provided");
                return axum::http::StatusCode::UNAUTHORIZED.into_response();
            }
            Some(t) => {
                if let Err(e) = verify_jwt(&t).await {
                    error!("WebSocket connection rejected: Invalid JWT token: {:?}", e);
                    return axum::http::StatusCode::UNAUTHORIZED.into_response();
                }
            }
        }
    }

    ws.on_upgrade(move |socket| handle_socket(state, params, socket))
}

async fn handle_socket(state: AppState, params: WsParams, mut socket: WebSocket) {
    // In development, allow skipping membership check (WS_DEV_ALLOW_ALL=true)
    let dev_allow = std::env::var("WS_DEV_ALLOW_ALL").unwrap_or_else(|_| "false".into()) == "true";
    if !dev_allow {
        // Explicit membership check with proper error handling
        match ConversationService::is_member(&state.db, params.conversation_id, params.user_id).await {
            Ok(true) => {
                // User is member, proceed
            }
            Ok(false) => {
                // User is not a member - reject access
                warn!(
                    "WebSocket rejected: user {} is not a member of conversation {}",
                    params.user_id, params.conversation_id
                );
                let _ = socket.send(Message::Close(None)).await;
                return;
            }
            Err(e) => {
                // Database or other error - fail secure (reject access)
                error!(
                    "WebSocket rejected: membership check failed for user {} in conversation {}: {:?}",
                    params.user_id, params.conversation_id, e
                );
                let _ = socket.send(Message::Close(None)).await;
                return;
            }
        }
    }

    // === OFFLINE MESSAGE QUEUE RECOVERY - STEP 1 ===
    // Generate unique client ID for this connection
    let client_id = Uuid::new_v4();

    // Retrieve previous client sync state (if exists)
    let last_message_id = if let Ok(Some(sync_state)) = offline_queue::get_client_sync_state(
        &state.redis,
        params.user_id,
        client_id,
    ).await {
        sync_state.last_message_id.clone()
    } else {
        // No previous state, start from beginning (last 24 hours)
        "0".to_string()
    };

    let (mut sender, mut receiver) = socket.split();

    // === OFFLINE MESSAGE QUEUE RECOVERY - STEP 2 (REORDERED) ===
    // CRITICAL FIX: Register broadcast subscription BEFORE fetching offline messages
    // This eliminates the race condition where messages arriving between
    // get_messages_since() and add_subscriber() would be lost.
    //
    // Sequence:
    // 1. Register to receive real-time messages (rx)
    // 2. Fetch offline messages from Redis
    // 3. Send offline messages via sender
    // 4. Any new messages arriving after step 2 will be caught by rx
    let mut rx = state.registry.add_subscriber(params.conversation_id).await;

    // === OFFLINE MESSAGE QUEUE RECOVERY - STEP 3 (REORDERED) ===
    // Now fetch and deliver offline messages since last known ID
    // Safe to do this AFTER registration because rx will catch any new messages
    if let Ok(offline_messages) = offline_queue::get_messages_since(
        &state.redis,
        params.conversation_id,
        &last_message_id,
    ).await {
        for (_stream_id, fields) in offline_messages {
            if let Some(payload) = fields.get("payload") {
                let msg = Message::Text(payload.clone());
                if sender.send(msg).await.is_err() {
                    return; // Connection closed
                }
            }
        }
    }

    // === OFFLINE MESSAGE QUEUE RECOVERY - STEP 4 ===
    // Track last received message ID for this connection
    let last_received_id = Arc::new(Mutex::new(last_message_id.clone()));

    // === OFFLINE MESSAGE QUEUE RECOVERY - STEP 5 ===
    // Spawn periodic sync task to update client state (every 5 seconds)
    let sync_task = {
        let redis = state.redis.clone();
        let user_id = params.user_id;
        let conversation_id = params.conversation_id;
        let last_id = Arc::clone(&last_received_id);

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(5));
            loop {
                interval.tick().await;
                let current_id = last_id.lock().await.clone();
                let sync_state = ClientSyncState {
                    client_id,
                    user_id,
                    conversation_id,
                    last_message_id: current_id,
                    last_sync_at: chrono::Utc::now().timestamp(),
                };
                let _ = offline_queue::update_client_sync_state(&redis, &sync_state).await;
            }
        })
    };

    // === MAIN MESSAGE LOOP - STEP 6 ===
    // Multiplex incoming and outgoing messages
    loop {
        tokio::select! {
            // Handle outgoing broadcast messages
            maybe = rx.recv() => {
                match maybe {
                    Some(msg) => {
                        // === CRITICAL FIX: Extract stream ID robustly ===
                        // Handle both JSON and non-JSON messages
                        // Fallback: use message hash as pseudo-ID if stream_id not provided
                        if let Message::Text(ref txt) = msg {
                            let mut extracted_id = None;

                            // Strategy 1: Try to parse as JSON and extract stream_id
                            if let Ok(json) = serde_json::from_str::<serde_json::Value>(txt) {
                                if let Some(id) = json.get("stream_id").and_then(|v| v.as_str()) {
                                    extracted_id = Some(id.to_string());
                                } else if let Some(id) = json.get("id").and_then(|v| v.as_str()) {
                                    // Fallback: use "id" field if available
                                    extracted_id = Some(id.to_string());
                                }
                            }

                            // Strategy 2: If no ID found in JSON, generate one from message content
                            // This ensures we track all messages, even non-standard ones
                            if extracted_id.is_none() {
                                // Use SHA256 hash of message content as fallback ID
                                // This is a pseudo-ID for tracking purposes
                                use std::collections::hash_map::DefaultHasher;
                                use std::hash::{Hash, Hasher};

                                let mut hasher = DefaultHasher::new();
                                txt.hash(&mut hasher);
                                let hash = hasher.finish();

                                // Create a pseudo stream ID based on hash
                                // Format: timestamp-hash (mimics Redis stream ID format)
                                let now_ms = chrono::Utc::now().timestamp_millis();
                                extracted_id = Some(format!("{}-{}", now_ms, hash % 10000));

                                warn!(
                                    "No stream_id found in message, using generated ID: {:?}",
                                    extracted_id
                                );
                            }

                            // Update last_received_id if we have one
                            if let Some(id) = extracted_id {
                                *last_received_id.lock().await = id;
                            }
                        }

                        if sender.send(msg).await.is_err() { break; }
                    }
                    None => break,
                }
            }

            // Handle incoming client messages
            incoming = receiver.next() => {
                match incoming {
                    Some(Ok(Message::Text(txt))) => {
                        if let Ok(evt) = serde_json::from_str::<WsInboundEvent>(&txt) {
                            match evt {
                                WsInboundEvent::Typing { conversation_id, user_id } => {
                                    if conversation_id == params.conversation_id && user_id == params.user_id {
                                        let out = WsOutboundEvent::Typing { conversation_id, user_id };
                                        match serde_json::to_string(&out) {
                                            Ok(out_txt) => {
                                                state.registry.broadcast(params.conversation_id, Message::Text(out_txt.clone())).await;
                                                let _ = crate::websocket::pubsub::publish(&state.redis, params.conversation_id, &out_txt).await;
                                            }
                                            Err(e) => {
                                                error!(
                                                    "Failed to serialize typing event for conversation {}, user {}: {:?}",
                                                    conversation_id, user_id, e
                                                );
                                                // Continue processing - don't kill the WebSocket connection
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Some(Ok(Message::Ping(data))) => { let _ = sender.send(Message::Pong(data)).await; }
                    Some(Ok(Message::Close(_))) | None => break,
                    _ => {}
                }
            }
        }
    }

    // === CLEANUP - STEP 7 ===
    // Save final sync state on disconnection
    let final_id = last_received_id.lock().await.clone();
    let final_state = ClientSyncState {
        client_id,
        user_id: params.user_id,
        conversation_id: params.conversation_id,
        last_message_id: final_id,
        last_sync_at: chrono::Utc::now().timestamp(),
    };
    let _ = offline_queue::update_client_sync_state(&state.redis, &final_state).await;

    // Cancel the sync task
    sync_task.abort();
}

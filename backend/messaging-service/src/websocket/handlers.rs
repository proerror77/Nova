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
    }
}

// === Extracted: Token validation (消除嵌套) ===
async fn validate_ws_token(params: &WsParams, headers: &HeaderMap) -> Result<(), axum::http::StatusCode> {
    let dev_allow = std::env::var("WS_DEV_ALLOW_ALL").unwrap_or_else(|_| "false".into()) == "true";

    if dev_allow {
        warn!("⚠️  JWT validation BYPASSED (WS_DEV_ALLOW_ALL=true) - DO NOT USE IN PRODUCTION ⚠️");
        return Ok(());
    }

    let token = params.token.clone()
        .or_else(|| {
            headers.get(axum::http::header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.strip_prefix("Bearer "))
                .map(|s| s.to_string())
        });

    match token {
        None => {
            error!("WebSocket connection rejected: No JWT token provided");
            Err(axum::http::StatusCode::UNAUTHORIZED)
        }
        Some(t) => {
            verify_jwt(&t).await
                .map(|_| ()) // Extract the Claims, return ()
                .map_err(|e| {
                    error!("WebSocket connection rejected: Invalid JWT token: {:?}", e);
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

// === Extracted: Membership verification (消除嵌套) ===
async fn verify_conversation_membership(state: &AppState, params: &WsParams) -> Result<(), ()> {
    let dev_allow = std::env::var("WS_DEV_ALLOW_ALL").unwrap_or_else(|_| "false".into()) == "true";
    if dev_allow {
        return Ok(());
    }

    match ConversationService::is_member(&state.db, params.conversation_id, params.user_id).await {
        Ok(true) => Ok(()),
        Ok(false) => {
            warn!("WebSocket rejected: user {} is not a member of conversation {}",
                params.user_id, params.conversation_id);
            Err(())
        }
        Err(e) => {
            error!("WebSocket rejected: membership check failed for user {} in conversation {}: {:?}",
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
                if let Some(msg) = maybe {
                    handle_broadcast_message(&msg, &last_received_id).await;
                    if sender.send(msg).await.is_err() { break; }
                } else {
                    break;
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

use crate::middleware::auth::verify_jwt;
use crate::services::conversation_service::ConversationService;
use crate::services::offline_queue;
use crate::state::AppState;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use crate::websocket::message_types::WsInboundEvent;
use axum::http::HeaderMap;
use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    response::IntoResponse,
};
use futures_util::{stream::SplitSink, SinkExt, StreamExt};
use serde::Deserialize;
use tracing::error;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct WsParams {
    pub conversation_id: Uuid,
    pub user_id: Uuid,
    pub token: Option<String>,
}

async fn handle_client_message(
    incoming: &Option<Result<Message, axum::Error>>,
    params: &WsParams,
    state: &AppState,
    client_id: Uuid,
    sender: &mut SplitSink<WebSocket, Message>,
) -> bool {
    match incoming {
        Some(Ok(Message::Text(txt))) => match serde_json::from_str::<WsInboundEvent>(txt) {
            Ok(WsInboundEvent::Ack { msg_id, conversation_id }) => {
                if conversation_id == params.conversation_id {
                    if let Err(e) = offline_queue::acknowledge_message(
                        &state.redis,
                        params.conversation_id,
                        msg_id.as_str(),
                    )
                    .await
                    {
                        tracing::error!(
                            error = %e,
                            "Failed to ACK stream {} for user {}",
                            msg_id,
                            params.user_id
                        );
                    }
                } else {
                    tracing::warn!(
                        "Ignoring ACK for conversation {} (connection bound to {})",
                        conversation_id,
                        params.conversation_id
                    );
                }
                true
            }
            Ok(WsInboundEvent::GetUnacked) => {
                let pending = offline_queue::read_pending_messages(
                    &state.redis,
                    params.conversation_id,
                    params.user_id,
                    client_id,
                )
                .await
                .unwrap_or_default();

                for (_, fields) in pending {
                    if let Some(payload) = fields.get("payload") {
                        if sender
                            .send(Message::Text(payload.clone().into()))
                            .await
                            .is_err()
                        {
                            return false;
                        }
                    }
                }
                true
            }
            Ok(evt) => {
                handle_ws_event(&evt, params, state).await;
                true
            }
            Err(e) => {
                tracing::warn!("Failed to parse inbound WS message: {:?}", e);
                true
            }
        },
        Some(Ok(Message::Ping(_))) => true,
        Some(Ok(Message::Close(_))) | None => false,
        _ => true,
    }
}

// === Extracted: Handle WebSocket event ===
async fn handle_ws_event(evt: &WsInboundEvent, params: &WsParams, state: &AppState) {
    match evt {
        WsInboundEvent::Typing {
            conversation_id,
            user_id,
        } => {
            // Validate event belongs to this connection
            if *conversation_id != params.conversation_id || *user_id != params.user_id {
                return;
            }

            // Broadcast typing.started event using unified event system
            let event = WebSocketEvent::TypingStarted {
                conversation_id: *conversation_id,
            };

            let _ = broadcast_event(
                &state.registry,
                &state.redis,
                *conversation_id,
                *user_id,
                event,
            )
            .await;
        }

        WsInboundEvent::Ack {
            msg_id,
            conversation_id,
        } => {
            if *conversation_id != params.conversation_id {
                return;
            }
            tracing::debug!(
                "Received duplicate ACK handler invocation for msg {} from user {}",
                msg_id,
                params.user_id
            );
        }

        WsInboundEvent::GetUnacked => {
            // Client requests unacknowledged messages
            // This is handled in the main event loop after socket split
            tracing::debug!("Client {} requested unacked messages", params.user_id);
        }
    }
}

// === Extracted: Token validation - MANDATORY, no bypasses ===
async fn validate_ws_token(
    params: &WsParams,
    headers: &HeaderMap,
) -> Result<(), axum::http::StatusCode> {
    // SECURITY: JWT validation is MANDATORY. No exceptions, no dev flags.
    // Fail-closed: if JWT is missing or invalid, reject the connection immediately.

    let token = params.token.clone().or_else(|| {
        headers
            .get(axum::http::header::AUTHORIZATION)
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
            verify_jwt(&t)
                .await
                .map(|claims| {
                    // Log successful authentication
                    tracing::debug!(
                        "✅ WebSocket authentication successful for user: {}",
                        claims.sub
                    );
                })
                .map_err(|e| {
                    error!(
                        "🚫 WebSocket connection REJECTED: Invalid JWT token - {:?}",
                        e
                    );
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
            tracing::debug!(
                "✅ WebSocket authorization: user {} is member of conversation {}",
                params.user_id,
                params.conversation_id
            );
            Ok(())
        }
        Ok(false) => {
            error!(
                "🚫 WebSocket connection REJECTED: user {} is NOT a member of conversation {}",
                params.user_id, params.conversation_id
            );
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
    if verify_conversation_membership(&state, &params)
        .await
        .is_err()
    {
        let _ = socket.send(Message::Close(None)).await;
        return;
    }

    let client_id = Uuid::new_v4();

    if let Err(e) = offline_queue::init_consumer_group(&state.redis, params.conversation_id).await {
        error!("Failed to initialize consumer group: {:?}", e);
        let _ = socket.send(Message::Close(None)).await;
        return;
    }

    let (mut sender, mut receiver) = socket.split();

    let pending_messages = offline_queue::read_pending_messages(
        &state.redis,
        params.conversation_id,
        params.user_id,
        client_id,
    )
    .await
    .unwrap_or_default();

    let (subscriber_id, mut rx) = state.registry.add_subscriber(params.conversation_id).await;

    let new_messages = offline_queue::read_new_messages(
        &state.redis,
        params.conversation_id,
        params.user_id,
        client_id,
    )
    .await
    .unwrap_or_default();

    for (_, fields) in pending_messages.into_iter().chain(new_messages.into_iter()) {
        if let Some(payload) = fields.get("payload") {
            if sender
                .send(Message::Text(payload.clone().into()))
                .await
                .is_err()
            {
                return;
            }
        }
    }

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
                    last_message_id: "consumer-active".to_string(),
                    last_sync_at: chrono::Utc::now().timestamp(),
                };
                let _ = offline_queue::update_client_sync_state(&redis, &sync_state).await;
            }
        })
    };

    let trimming_task = {
        let redis = state.redis.clone();
        let conversation_id = params.conversation_id;

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(3600));
            loop {
                interval.tick().await;
                if let Err(e) = offline_queue::trim_stream(&redis, conversation_id, 10000).await {
                    error!("Failed to trim stream: {:?}", e);
                }
            }
        })
    };

    let mut resend_interval = tokio::time::interval(std::time::Duration::from_secs(10));

    loop {
        tokio::select! {
            maybe = rx.recv() => {
                if let Some(msg) = maybe {
                    if sender.send(msg).await.is_err() {
                        break;
                    }
                } else {
                    break;
                }
            }
            incoming = receiver.next() => {
                if !handle_client_message(&incoming, &params, &state, client_id, &mut sender).await {
                    break;
                }
            }
            _ = resend_interval.tick() => {
                let pending = offline_queue::read_pending_messages(
                    &state.redis,
                    params.conversation_id,
                    params.user_id,
                    client_id,
                )
                .await
                .unwrap_or_default();

                for (_, fields) in pending {
                    if let Some(payload) = fields.get("payload") {
                        if sender
                            .send(Message::Text(payload.clone().into()))
                            .await
                            .is_err()
                        {
                            break;
                        }
                    }
                }
            }
        }
    }

    state
        .registry
        .remove_subscriber(params.conversation_id, subscriber_id)
        .await;

    tracing::debug!(
        "Removed subscriber {:?} from conversation {} registry",
        subscriber_id,
        params.conversation_id
    );

    let final_state = offline_queue::ClientSyncState {
        client_id,
        user_id: params.user_id,
        conversation_id: params.conversation_id,
        last_message_id: "disconnected".to_string(),
        last_sync_at: chrono::Utc::now().timestamp(),
    };
    let _ = offline_queue::update_client_sync_state(&state.redis, &final_state).await;

    monitoring_task.abort();
    trimming_task.abort();

    tracing::debug!(
        "WebSocket connection closed for user {} in conversation {}",
        params.user_id,
        params.conversation_id
    );
}


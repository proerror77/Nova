use crate::middleware::auth::verify_jwt;
use crate::redis_client::RedisClient;
use crate::services::conversation_service::ConversationService;
use crate::services::offline_queue;
use crate::state::AppState;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use crate::websocket::message_types::WsInboundEvent;
use crate::websocket::ConnectionRegistry;
use actix::{Actor, ActorContext, AsyncContext, Handler, Message as ActixMessage, StreamHandler};
use actix_web::{get, web, Error, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use serde::Deserialize;
use sqlx::{Pool, Postgres};
use std::time::{Duration, Instant};
use tracing::error;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct WsParams {
    pub conversation_id: Uuid,
    pub user_id: Uuid,
    pub token: Option<String>,
}

// Message type for broadcasting to WebSocket actor
#[derive(ActixMessage)]
#[rtype(result = "()")]
struct BroadcastMessage(String);

// Message type for sending text to WebSocket
#[derive(ActixMessage)]
#[rtype(result = "()")]
struct TextMessage(String);

// WebSocket Actor
struct WsSession {
    conversation_id: Uuid,
    user_id: Uuid,
    client_id: Uuid,
    subscriber_id: crate::websocket::SubscriberId,
    registry: ConnectionRegistry,
    redis: RedisClient,
    db: Pool<Postgres>,
    hb: Instant,
    // Store full AppState for event handling
    app_state: AppState,
}

// Standalone async function for handling WebSocket events (avoids borrow checker issues)
async fn handle_ws_event_async(
    user_id: Uuid,
    conversation_id: Uuid,
    evt: &WsInboundEvent,
    _db: &sqlx::Pool<sqlx::Postgres>,
    registry: &ConnectionRegistry,
    redis: &RedisClient,
) -> Result<(), Box<dyn std::error::Error>> {
    match evt {
        WsInboundEvent::Typing {
            conversation_id: evt_conv_id,
            user_id: evt_user_id,
        } => {
            // Validate event belongs to this connection
            if *evt_conv_id != conversation_id || *evt_user_id != user_id {
                return Ok(());
            }

            // Broadcast typing.started event using unified event system
            let event = WebSocketEvent::TypingStarted {
                conversation_id: *evt_conv_id,
            };

            broadcast_event(registry, redis, *evt_conv_id, *evt_user_id, event).await?;
        }

        WsInboundEvent::Ack {
            msg_id,
            conversation_id: evt_conv_id,
        } => {
            if *evt_conv_id != conversation_id {
                return Ok(());
            }
            offline_queue::acknowledge_message(redis, conversation_id, msg_id.as_str()).await?;
        }

        WsInboundEvent::GetUnacked => {
            tracing::debug!("Client {} requested unacked messages", user_id);
        }
    }
    Ok(())
}

impl WsSession {
    fn new(
        conversation_id: Uuid,
        user_id: Uuid,
        client_id: Uuid,
        subscriber_id: crate::websocket::SubscriberId,
        registry: ConnectionRegistry,
        redis: RedisClient,
        db: Pool<Postgres>,
        app_state: AppState,
    ) -> Self {
        Self {
            conversation_id,
            user_id,
            client_id,
            subscriber_id,
            registry,
            redis,
            db,
            hb: Instant::now(),
            app_state,
        }
    }

    fn hb(&self, ctx: &mut ws::WebsocketContext<Self>) {
        ctx.run_interval(Duration::from_secs(5), |act, ctx| {
            if Instant::now().duration_since(act.hb) > Duration::from_secs(30) {
                tracing::warn!("WebSocket heartbeat failed, disconnecting");
                ctx.stop();
                return;
            }
            ctx.ping(b"");
        });
    }

    fn start_periodic_tasks(&self, ctx: &mut ws::WebsocketContext<Self>) {
        // Monitoring task - update sync state every 5s
        let redis = self.redis.clone();
        let user_id = self.user_id;
        let conversation_id = self.conversation_id;
        let client_id = self.client_id;

        ctx.run_interval(Duration::from_secs(5), move |_act, _ctx| {
            let redis = redis.clone();
            let sync_state = offline_queue::ClientSyncState {
                client_id,
                user_id,
                conversation_id,
                last_message_id: "consumer-active".to_string(),
                last_sync_at: chrono::Utc::now().timestamp(),
            };
            actix::spawn(async move {
                let _ = offline_queue::update_client_sync_state(&redis, &sync_state).await;
            });
        });

        // Trimming task - trim stream every hour
        let redis = self.redis.clone();
        let conversation_id = self.conversation_id;

        ctx.run_interval(Duration::from_secs(3600), move |_act, _ctx| {
            let redis = redis.clone();
            actix::spawn(async move {
                if let Err(e) = offline_queue::trim_stream(&redis, conversation_id, 10000).await {
                    error!("Failed to trim stream: {:?}", e);
                }
            });
        });

        // Resend pending messages every 10s
        let redis = self.redis.clone();
        let user_id = self.user_id;
        let conversation_id = self.conversation_id;
        let client_id = self.client_id;

        ctx.run_interval(Duration::from_secs(10), move |act, ctx| {
            let redis = redis.clone();
            let addr = ctx.address();
            actix::spawn(async move {
                let pending = offline_queue::read_pending_messages(
                    &redis,
                    conversation_id,
                    user_id,
                    client_id,
                )
                .await
                .unwrap_or_default();

                for (_, fields) in pending {
                    if let Some(payload) = fields.get("payload") {
                        addr.do_send(TextMessage(payload.clone()));
                    }
                }
            });
        });
    }

    async fn handle_ws_event(&self, evt: &WsInboundEvent, state: &AppState) {
        match evt {
            WsInboundEvent::Typing {
                conversation_id,
                user_id,
            } => {
                // Validate event belongs to this connection
                if *conversation_id != self.conversation_id || *user_id != self.user_id {
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
                if *conversation_id != self.conversation_id {
                    return;
                }
                if let Err(e) = offline_queue::acknowledge_message(
                    &self.redis,
                    self.conversation_id,
                    msg_id.as_str(),
                )
                .await
                {
                    tracing::error!(
                        error = %e,
                        "Failed to ACK stream {} for user {}",
                        msg_id,
                        self.user_id
                    );
                }
            }

            WsInboundEvent::GetUnacked => {
                // Handled in separate context via ctx.text()
                tracing::debug!("Client {} requested unacked messages", self.user_id);
            }
        }
    }
}

impl Actor for WsSession {
    type Context = ws::WebsocketContext<Self>;

    fn started(&mut self, ctx: &mut Self::Context) {
        tracing::info!(
            "WebSocket session started for user {} in conversation {}",
            self.user_id,
            self.conversation_id
        );

        // Start heartbeat
        self.hb(ctx);

        // Start periodic tasks
        self.start_periodic_tasks(ctx);

        // Send pending and new messages
        let redis = self.redis.clone();
        let conversation_id = self.conversation_id;
        let user_id = self.user_id;
        let client_id = self.client_id;

        let addr = ctx.address();
        actix::spawn(async move {
            let pending =
                offline_queue::read_pending_messages(&redis, conversation_id, user_id, client_id)
                    .await
                    .unwrap_or_default();

            let new = offline_queue::read_new_messages(&redis, conversation_id, user_id, client_id)
                .await
                .unwrap_or_default();

            for (_, fields) in pending.into_iter().chain(new.into_iter()) {
                if let Some(payload) = fields.get("payload") {
                    addr.do_send(BroadcastMessage(payload.clone()));
                }
            }
        });
    }

    fn stopped(&mut self, _ctx: &mut Self::Context) {
        tracing::info!(
            "WebSocket session stopped for user {} in conversation {}",
            self.user_id,
            self.conversation_id
        );

        // Cleanup: remove subscriber from registry
        let registry = self.registry.clone();
        let conversation_id = self.conversation_id;
        let subscriber_id = self.subscriber_id;

        actix::spawn(async move {
            registry
                .remove_subscriber(conversation_id, subscriber_id)
                .await;
        });

        // Update final sync state
        let redis = self.redis.clone();
        let final_state = offline_queue::ClientSyncState {
            client_id: self.client_id,
            user_id: self.user_id,
            conversation_id: self.conversation_id,
            last_message_id: "disconnected".to_string(),
            last_sync_at: chrono::Utc::now().timestamp(),
        };

        actix::spawn(async move {
            let _ = offline_queue::update_client_sync_state(&redis, &final_state).await;
        });
    }
}

// Handle broadcast messages
impl Handler<BroadcastMessage> for WsSession {
    type Result = ();

    fn handle(&mut self, msg: BroadcastMessage, ctx: &mut Self::Context) {
        ctx.text(msg.0);
    }
}

// Handle text messages
impl Handler<TextMessage> for WsSession {
    type Result = ();

    fn handle(&mut self, msg: TextMessage, ctx: &mut Self::Context) {
        ctx.text(msg.0);
    }
}

// Handle WebSocket protocol messages
impl StreamHandler<Result<ws::Message, ws::ProtocolError>> for WsSession {
    fn handle(&mut self, msg: Result<ws::Message, ws::ProtocolError>, ctx: &mut Self::Context) {
        match msg {
            Ok(ws::Message::Ping(msg)) => {
                self.hb = Instant::now();
                ctx.pong(&msg);
            }
            Ok(ws::Message::Pong(_)) => {
                self.hb = Instant::now();
            }
            Ok(ws::Message::Text(text)) => {
                match serde_json::from_str::<WsInboundEvent>(&text) {
                    Ok(WsInboundEvent::GetUnacked) => {
                        // Send unacked messages
                        let redis = self.redis.clone();
                        let conversation_id = self.conversation_id;
                        let user_id = self.user_id;
                        let client_id = self.client_id;
                        let addr = ctx.address();

                        actix::spawn(async move {
                            let pending = offline_queue::read_pending_messages(
                                &redis,
                                conversation_id,
                                user_id,
                                client_id,
                            )
                            .await
                            .unwrap_or_default();

                            for (_, fields) in pending {
                                if let Some(payload) = fields.get("payload") {
                                    addr.do_send(TextMessage(payload.clone()));
                                }
                            }
                        });
                    }
                    Ok(evt) => {
                        // Handle other events - use the stored app_state
                        let state = self.app_state.clone();
                        let user_id = self.user_id;
                        let conversation_id = self.conversation_id;
                        let db = state.db.clone();
                        let registry = state.registry.clone();
                        let redis = state.redis.clone();

                        actix::spawn(async move {
                            // Handle WebSocket event asynchronously
                            if let Err(e) = handle_ws_event_async(
                                user_id,
                                conversation_id,
                                &evt,
                                &db,
                                &registry,
                                &redis,
                            )
                            .await
                            {
                                tracing::error!("Failed to handle WebSocket event: {:?}", e);
                            }
                        });
                    }
                    Err(e) => {
                        tracing::warn!("Failed to parse WS message: {:?}", e);
                    }
                }
            }
            Ok(ws::Message::Binary(_)) => {
                tracing::warn!("Binary WebSocket messages not supported");
            }
            Ok(ws::Message::Close(reason)) => {
                tracing::info!("WebSocket close message received: {:?}", reason);
                ctx.stop();
            }
            _ => {}
        }
    }
}

// Token validation
async fn validate_ws_token(
    params: &WsParams,
    req: &HttpRequest,
) -> Result<(), actix_web::http::StatusCode> {
    let token = params.token.clone().or_else(|| {
        req.headers()
            .get(actix_web::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.strip_prefix("Bearer "))
            .map(|s| s.to_string())
    });

    match token {
        None => {
            error!("🚫 WebSocket connection REJECTED: No JWT token provided");
            Err(actix_web::http::StatusCode::UNAUTHORIZED)
        }
        Some(t) => verify_jwt(&t)
            .await
            .map(|claims| {
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
                actix_web::http::StatusCode::UNAUTHORIZED
            }),
    }
}

// Membership verification
async fn verify_conversation_membership(db: &Pool<Postgres>, params: &WsParams) -> Result<(), ()> {
    match ConversationService::is_member(db, params.conversation_id, params.user_id).await {
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
            error!(
                "🚫 WebSocket connection REJECTED: membership check failed: {:?}",
                e
            );
            Err(())
        }
    }
}

// HTTP handler
#[get("/ws")]
pub async fn ws_handler(
    req: HttpRequest,
    stream: web::Payload,
    state: web::Data<AppState>,
    query: web::Query<WsParams>,
) -> Result<HttpResponse, Error> {
    let params = query.into_inner();

    // Authentication
    if let Err(status) = validate_ws_token(&params, &req).await {
        return Ok(HttpResponse::build(status).finish());
    }

    // Authorization
    if verify_conversation_membership(&state.db, &params)
        .await
        .is_err()
    {
        return Ok(HttpResponse::Forbidden().finish());
    }

    // Initialize consumer group
    if let Err(e) = offline_queue::init_consumer_group(&state.redis, params.conversation_id).await {
        error!("Failed to initialize consumer group: {:?}", e);
        return Ok(HttpResponse::InternalServerError().finish());
    }

    let client_id = Uuid::new_v4();

    // Register subscriber
    let (subscriber_id, mut rx) = state.registry.add_subscriber(params.conversation_id).await;

    // Create WebSocket session with full AppState
    let session = WsSession::new(
        params.conversation_id,
        params.user_id,
        client_id,
        subscriber_id,
        state.registry.clone(),
        state.redis.clone(),
        state.db.clone(),
        state.as_ref().clone(), // Pass the full AppState
    );

    let resp = ws::start(session, &req, stream)?;

    // Spawn task to forward broadcast messages to WebSocket
    // This bridges the registry's unbounded receiver to the WebSocket actor
    // Note: This is a simplified version - production should handle backpressure
    tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            // Convert axum::extract::ws::Message to String
            // This is a placeholder - actual implementation depends on message format
            tracing::debug!("Received broadcast message (forwarding not implemented yet)");
        }
    });

    Ok(resp)
}

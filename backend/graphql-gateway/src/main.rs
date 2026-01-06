use crate::rest_api::devices::{get_current_device, list_devices, logout_device};
use crate::rest_api::graph::{
    check_is_following, follow_user, get_my_followers, get_my_following, get_user_followers,
    get_user_following, unfollow_user,
};
use crate::rest_api::notifications::{
    batch_create_notifications, create_notification, delete_notification, get_notification,
    get_notification_preferences, get_notification_stats, get_notifications, get_unread_count,
    mark_all_notifications_read, mark_notification_read, register_push_token,
    unregister_push_token, update_notification_preferences,
};
use crate::rest_api::poll::{
    add_candidate, check_voted, close_poll, create_poll, delete_poll, get_active_polls, get_poll,
    get_rankings, get_trending_polls, remove_candidate, unvote, vote_on_poll,
};
use crate::rest_api::search::{
    get_suggestions, get_trending_topics, search_all, search_content, search_hashtags,
    search_users_full,
};
use crate::rest_api::settings::{get_settings, update_settings};
use crate::rest_api::social_likes::{
    batch_check_bookmarked, batch_check_comment_liked, batch_check_liked, check_bookmarked, check_comment_liked,
    check_liked, create_bookmark, create_comment, create_comment_like, create_like, create_share,
    delete_bookmark, delete_comment, delete_comment_like, delete_comment_v2, delete_like,
    delete_like_legacy, get_bookmarks, get_comment_like_count, get_comments, get_likes,
    get_share_count, get_share_count_legacy, get_user_liked_posts,
};
use actix_web::{middleware::Logger, web, App, HttpServer};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse, GraphQLSubscription};
use opentelemetry_config::{init_tracing, TracingConfig};
use std::env;
use tracing::info;
use tracing_subscriber::prelude::*;

mod cache;
mod clients;
mod config;
mod kafka; // ✅ P0-5: Kafka integration for subscriptions
mod middleware;
mod rest_api; // HTTP REST API v2 for mobile clients
mod schema;
mod security; // ✅ P0-2: GraphQL security extensions

use clients::ServiceClients;
use grpc_clients::config::GrpcConfig;
use middleware::{JwtMiddleware, RateLimitConfig, RateLimitMiddleware};
use schema::build_schema;

async fn graphql_handler(
    schema: web::Data<schema::AppSchema>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    schema.execute(req.into_inner()).await.into()
}

async fn graphql_subscription_handler(
    schema: web::Data<schema::AppSchema>,
    req: actix_web::HttpRequest,
    payload: web::Payload,
) -> actix_web::Result<actix_web::HttpResponse> {
    GraphQLSubscription::new(schema.as_ref().clone()).start(&req, payload)
}

async fn health_handler() -> &'static str {
    "ok"
}

/// Circuit breaker health endpoint for monitoring
/// Returns the current state of all circuit breakers
/// ✅ P0: Circuit breaker observability for operations team
async fn circuit_breaker_health_handler(
    clients: web::Data<ServiceClients>,
) -> actix_web::Result<actix_web::HttpResponse> {
    use resilience::circuit_breaker::CircuitState;

    // Get ServiceClients from app data
    let clients = clients.get_ref();

    let health_status = clients.health_status();

    // Convert to JSON response
    let status_json: Vec<serde_json::Value> = health_status
        .into_iter()
        .map(|(service, state)| {
            let state_str = match state {
                CircuitState::Closed => "closed",
                CircuitState::Open => "open",
                CircuitState::HalfOpen => "half_open",
            };
            serde_json::json!({
                "service": service,
                "state": state_str,
                "healthy": state == CircuitState::Closed || state == CircuitState::HalfOpen,
            })
        })
        .collect();

    let all_healthy = status_json
        .iter()
        .all(|s| s["healthy"].as_bool().unwrap_or(false));

    let response = serde_json::json!({
        "status": if all_healthy { "healthy" } else { "degraded" },
        "circuit_breakers": status_json,
    });

    Ok(actix_web::HttpResponse::Ok()
        .content_type("application/json")
        .json(response))
}

/// SDL (Schema Definition Language) endpoint for schema introspection
/// Enables automatic client code generation and documentation
async fn schema_handler(schema: web::Data<schema::AppSchema>) -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok()
        .content_type("text/plain")
        .body(schema.sdl())
}

async fn playground_handler() -> actix_web::HttpResponse {
    actix_web::HttpResponse::Ok()
        .content_type("text/html")
        .body(r#"
<!DOCTYPE html>
<html>
<head>
    <title>Apollo Sandbox</title>
    <style>
        body {
            margin: 0;
            overflow: hidden;
            font-family: ui-monospace, Menlo, Consolas, "Roboto Mono", "Ubuntu Monospace", monospace;
        }
        sandbox-ui {
            height: 100vh;
            width: 100vw;
            display: block;
        }
    </style>
</head>
<body>
    <script src="https://embeddable-sandbox.cdn.apollographql.com/_latest/embeddable-sandbox.umd.production.min.js"></script>
    <sandbox-ui initial-state='{"document":"{ __typename }","variables":{},"headers":{},"url":"http://localhost:8080/graphql"}'></sandbox-ui>
</body>
</html>
        "#)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize rustls crypto provider (required for rustls 0.23+)
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");

    // Initialize OpenTelemetry tracing (if enabled)
    let tracing_config = TracingConfig::from_env();
    if tracing_config.enabled {
        match init_tracing("graphql-gateway", tracing_config) {
            Ok(_tracer) => {
                info!("OpenTelemetry distributed tracing initialized for graphql-gateway");
            }
            Err(e) => {
                eprintln!("Failed to initialize OpenTelemetry tracing: {}", e);
                // Initialize fallback structured logging with JSON format for production-grade observability
                tracing_subscriber::registry()
                    .with(
                        tracing_subscriber::EnvFilter::try_from_default_env()
                            .unwrap_or_else(|_| "info,graphql_gateway=debug".into()),
                    )
                    .with(
                        tracing_subscriber::fmt::layer()
                            .json()
                            .with_current_span(true)
                            .with_span_list(true)
                            .with_thread_ids(true)
                            .with_thread_names(true)
                            .with_line_number(true)
                            .with_file(true)
                            .with_target(true),
                    )
                    .init();
            }
        }
    } else {
        // Initialize fallback structured logging without OpenTelemetry
        tracing_subscriber::registry()
            .with(
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| "info,graphql_gateway=debug".into()),
            )
            .with(
                tracing_subscriber::fmt::layer()
                    .json()
                    .with_current_span(true)
                    .with_span_list(true)
                    .with_thread_ids(true)
                    .with_thread_names(true)
                    .with_line_number(true)
                    .with_file(true)
                    .with_target(true),
            )
            .init();
    }

    info!("Starting GraphQL Gateway...");

    // Load configuration (includes JWT config from AWS Secrets Manager or env)
    let config = config::Config::from_env().await.map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("Failed to load configuration: {}", e),
        )
    })?;

    info!(
        algorithm = %config.jwt.algorithm,
        issuer = %config.jwt.issuer,
        "JWT configuration loaded successfully"
    );

    // Initialize gRPC client config (TLS/mTLS + timeouts)
    let grpc_cfg = GrpcConfig::from_env().map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("Failed to load gRPC config: {}", e),
        )
    })?;

    // Initialize service clients from shared gRPC config (honors TLS + tier)
    let clients = ServiceClients::from_grpc_config(&grpc_cfg).map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("Failed to initialize service clients: {}", e),
        )
    })?;

    info!("Service clients initialized from gRPC config (TLS/tier aware)");

    // Initialize JWT keys for crypto-core (RS256 only)
    // SECURITY: Must use RS256 asymmetric encryption, never HS256
    // Note: For RS256, signing_key is the private key, validation_key is the public key
    let jwt_private_key = if config.jwt.algorithm == "RS256" || config.jwt.algorithm == "ES256" {
        config.jwt.signing_key.clone()
    } else {
        env::var("JWT_PRIVATE_KEY_PEM").map_err(|_| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "JWT_PRIVATE_KEY_PEM required for RS256 tokens",
            )
        })?
    };

    let jwt_public_key = config
        .jwt
        .validation_key
        .clone()
        .or_else(|| env::var("JWT_PUBLIC_KEY_PEM").ok())
        .ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "JWT public key (validation_key or JWT_PUBLIC_KEY_PEM) required for RS256",
            )
        })?;

    crypto_core::jwt::initialize_jwt_keys(&jwt_private_key, &jwt_public_key).map_err(|e| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("Failed to initialize JWT keys - check PEM format: {}", e),
        )
    })?;

    info!("JWT authentication enabled with RS256 algorithm");

    // Build GraphQL schema with service clients
    let schema = build_schema(clients.clone());

    let bind_addr = format!("{}:{}", config.server.host, config.server.port);
    info!("GraphQL Gateway starting on http://{}", bind_addr);

    // ✅ P0-3: Initialize rate limiting (100 req/sec per IP, burst of 10)
    let rate_limit_config = RateLimitConfig {
        req_per_second: 100,
        burst_size: 10,
    };
    let rate_limiter = RateLimitMiddleware::new(rate_limit_config);
    info!("Rate limiting enabled: 100 req/sec per IP with burst capacity of 10");

    // Start HTTP server with GraphQL, WebSocket subscriptions, and SDL
    HttpServer::new(move || {
        App::new()
            .wrap(Logger::default())
            .wrap(rate_limiter.clone()) // ✅ P0-3: Apply rate limiting before JWT auth
            .wrap(JwtMiddleware::new()) // ✅ P0-1: Fixed - Now uses RS256 from crypto-core
            .app_data(web::Data::new(schema.clone()))
            .app_data(web::Data::new(clients.clone()))
            // ✅ P0-4: GraphQL endpoints
            .route("/graphql", web::post().to(graphql_handler))
            // ✅ P0-4: WebSocket subscriptions (real-time updates)
            .route("/graphql", web::get().to(graphql_subscription_handler))
            .route("/ws", web::get().to(graphql_subscription_handler))
            // ✅ P0-4: Schema SDL endpoint for autodoc and code generation
            .route("/graphql/schema", web::get().to(schema_handler))
            .route("/schema", web::get().to(schema_handler))
            // Developer tools
            .route("/playground", web::get().to(playground_handler))
            .route("/health", web::get().to(health_handler))
            // ✅ P0: Circuit breaker monitoring endpoint
            .route(
                "/health/circuit-breakers",
                web::get().to(circuit_breaker_health_handler),
            )
            // ✅ REST API v2 endpoints for mobile clients
            // Authentication
            .route("/api/v2/auth/register", web::post().to(rest_api::register))
            .route("/api/v2/auth/login", web::post().to(rest_api::login))
            .route(
                "/api/v2/auth/refresh",
                web::post().to(rest_api::refresh_token),
            )
            .route("/api/v2/auth/logout", web::post().to(rest_api::logout))
            .route(
                "/api/v2/auth/users/profiles/batch",
                web::post().to(rest_api::batch_get_profiles),
            )
            // Invite code validation (public endpoint - no auth required)
            .route(
                "/api/v2/auth/invites/validate",
                web::get().to(rest_api::validate_invite_code),
            )
            // ✅ Phone Authentication API (public endpoints - no auth required)
            .route(
                "/api/v2/auth/phone/send-code",
                web::post().to(rest_api::phone_auth::send_phone_code),
            )
            .route(
                "/api/v2/auth/phone/verify",
                web::post().to(rest_api::phone_auth::verify_phone_code),
            )
            .route(
                "/api/v2/auth/phone/register",
                web::post().to(rest_api::phone_auth::phone_register),
            )
            .route(
                "/api/v2/auth/phone/login",
                web::post().to(rest_api::phone_auth::phone_login),
            )
            // ✅ OAuth Authentication API (Google, Apple)
            .route(
                "/api/v2/auth/oauth/google/start",
                web::post().to(rest_api::oauth::start_google_oauth),
            )
            .route(
                "/api/v2/auth/oauth/google/callback",
                web::get().to(rest_api::oauth::google_oauth_callback_get),
            )
            .route(
                "/api/v2/auth/oauth/google/callback",
                web::post().to(rest_api::oauth::complete_google_oauth),
            )
            .route(
                "/api/v2/auth/oauth/apple/start",
                web::post().to(rest_api::oauth::start_apple_oauth),
            )
            .route(
                "/api/v2/auth/oauth/apple/callback",
                web::post().to(rest_api::oauth::complete_apple_oauth),
            )
            .route(
                "/api/v2/auth/oauth/apple/native",
                web::post().to(rest_api::oauth::apple_native_sign_in),
            )
            // ✅ Passkey (WebAuthn/FIDO2) Authentication API
            .route(
                "/api/v2/auth/passkey/register/start",
                web::post().to(rest_api::passkey::start_registration),
            )
            .route(
                "/api/v2/auth/passkey/register/complete",
                web::post().to(rest_api::passkey::complete_registration),
            )
            .route(
                "/api/v2/auth/passkey/authenticate/start",
                web::post().to(rest_api::passkey::start_authentication),
            )
            .route(
                "/api/v2/auth/passkey/authenticate/complete",
                web::post().to(rest_api::passkey::complete_authentication),
            )
            .route(
                "/api/v2/auth/passkey/list",
                web::get().to(rest_api::passkey::list_passkeys),
            )
            .route(
                "/api/v2/auth/passkey/{credential_id}",
                web::delete().to(rest_api::passkey::revoke_passkey),
            )
            .route(
                "/api/v2/auth/passkey/{credential_id}/rename",
                web::put().to(rest_api::passkey::rename_passkey),
            )
            // ✅ Identity/Password Management API
            .route(
                "/api/v2/identity/password/change",
                web::post().to(rest_api::identity::change_password),
            )
            .route(
                "/api/v2/identity/password/reset/request",
                web::post().to(rest_api::identity::request_password_reset),
            )
            .route(
                "/api/v2/identity/password/reset",
                web::post().to(rest_api::identity::reset_password),
            )
            .service(rest_api::get_conversations)
            .service(rest_api::get_messages)
            .service(rest_api::create_conversation)
            .service(rest_api::send_chat_message)
            // Feed API
            .route("/api/v2/feed", web::get().to(rest_api::get_feed))
            .route(
                "/api/v2/feed/user/{user_id}",
                web::get().to(rest_api::get_feed_by_user),
            )
            .route(
                "/api/v2/feed/explore",
                web::get().to(rest_api::get_explore_feed),
            )
            .route(
                "/api/v2/feed/trending",
                web::get().to(rest_api::get_trending_feed),
            )
            .route(
                "/api/v2/feed/recommended-creators",
                web::get().to(rest_api::get_recommended_creators),
            )
            // Guest Feed API (unauthenticated trending feed)
            .route(
                "/api/v2/guest/feed/trending",
                web::get().to(rest_api::get_guest_trending_feed),
            )
            // ✅ Content API (Posts)
            // NOTE: Specific routes MUST be before generic {id} routes to prevent {id} from matching "user"
            .route(
                "/api/v2/content",
                web::post().to(rest_api::content::create_post),
            )
            .route(
                "/api/v2/content/user/{user_id}",
                web::get().to(rest_api::content::get_user_posts),
            )
            .route(
                "/api/v2/content/{id}",
                web::get().to(rest_api::content::get_post),
            )
            .route(
                "/api/v2/content/{id}",
                web::put().to(rest_api::content::update_post),
            )
            .route(
                "/api/v2/content/{id}",
                web::delete().to(rest_api::content::delete_post),
            )
            // SQL JOIN optimized endpoints for user's liked/saved posts
            // Note: v2 routes use /api/v2/content/user/{user_id}/liked format for ingress compatibility
            .route(
                "/api/v2/content/user/{user_id}/liked",
                web::get().to(rest_api::content::get_user_liked_posts),
            )
            .route(
                "/api/v2/content/user/{user_id}/saved",
                web::get().to(rest_api::content::get_user_saved_posts),
            )
            // Legacy v1 routes (kept for backwards compatibility)
            .route(
                "/api/v1/posts/user/{user_id}/liked",
                web::get().to(rest_api::content::get_user_liked_posts),
            )
            .route(
                "/api/v1/posts/user/{user_id}/saved",
                web::get().to(rest_api::content::get_user_saved_posts),
            )
            // ✅ User Profile API
            // NOTE: username route MUST be before {id} route to prevent {id} from matching "username"
            .route(
                "/api/v2/users/username/{username}",
                web::get().to(rest_api::get_profile_by_username),
            )
            .route("/api/v2/users/{id}", web::get().to(rest_api::get_profile))
            .route(
                "/api/v2/users/{id}",
                web::put().to(rest_api::update_profile),
            )
            .route(
                "/api/v2/users/avatar",
                web::post().to(rest_api::upload_avatar),
            )
            .service(rest_api::upload_media)
            .service(rest_api::media::initiate_upload)
            .service(rest_api::media::get_media)
            .service(rest_api::media::complete_upload)
            .service(rest_api::media::get_user_media)
            .service(rest_api::media::get_streaming_url)
            .service(rest_api::media::get_download_url)
            .service(rest_api::media::delete_media)
            // ✅ Chat API (conversations, messages)
            .service(rest_api::chat::get_conversations)
            .service(rest_api::chat::send_chat_message)
            .service(rest_api::chat::get_messages)
            .service(rest_api::chat::create_conversation)
            .route(
                "/api/v2/chat/conversations/{id}",
                web::get().to(rest_api::chat::get_conversation_by_id),
            )
            // ✅ Video/Voice Call API (proxy to realtime-chat-service)
            .service(rest_api::calls::initiate_call)
            .service(rest_api::calls::answer_call)
            .service(rest_api::calls::reject_call)
            .service(rest_api::calls::end_call)
            .service(rest_api::calls::send_ice_candidate)
            .service(rest_api::calls::get_ice_servers)
            // ✅ Alice AI Assistant API
            .route("/api/v2/alice/status", web::get().to(rest_api::get_status))
            .route("/api/v2/alice/chat", web::post().to(rest_api::send_message))
            .route("/api/v2/alice/voice", web::post().to(rest_api::voice_mode))
            .route(
                "/api/v2/alice/enhance",
                web::post().to(rest_api::enhance_post),
            )
            // ✅ X.AI (Grok) API Proxy
            .route(
                "/api/v2/xai/status",
                web::get().to(rest_api::xai::get_status),
            )
            .route("/api/v2/xai/chat", web::post().to(rest_api::xai::chat))
            .route(
                "/api/v2/xai/chat/stream",
                web::post().to(rest_api::xai::chat_stream),
            )
            .route(
                "/api/v2/xai/voice/token",
                web::post().to(rest_api::xai::get_voice_token),
            )
            // ✅ LiveKit Voice Agent API
            .route(
                "/api/v2/livekit/token",
                web::post().to(rest_api::livekit::generate_token),
            )
            // ✅ Photo Analysis API (iOS Vision → ranking-service)
            .route(
                "/api/v2/photo-analysis/upload",
                web::post().to(rest_api::photo_analysis::upload_photo_analysis),
            )
            .route(
                "/api/v2/photo-analysis/onboarding",
                web::post().to(rest_api::photo_analysis::upload_onboarding_interests),
            )
            // VLM API (Vision Language Model - Image Analysis & Tagging)
            .route(
                "/api/v2/vlm/analyze",
                web::post().to(rest_api::vlm::analyze_image),
            )
            .route(
                "/api/v2/posts/{id}/tags",
                web::get().to(rest_api::vlm::get_post_tags),
            )
            .route(
                "/api/v2/posts/{id}/tags",
                web::put().to(rest_api::vlm::update_post_tags),
            )
            // ✅ Channels API
            .route(
                "/api/v2/channels",
                web::get().to(rest_api::get_all_channels),
            )
            .route(
                "/api/v2/channels/{id}",
                web::get().to(rest_api::get_channel_details),
            )
            .route(
                "/api/v2/users/{id}/channels",
                web::get().to(rest_api::get_user_channels),
            )
            .route(
                "/api/v2/channels/subscribe",
                web::post().to(rest_api::subscribe_channel),
            )
            .route(
                "/api/v2/channels/unsubscribe",
                web::delete().to(rest_api::unsubscribe_channel),
            )
            .route(
                "/api/v2/channels/suggest",
                web::post().to(rest_api::channels::suggest_channels),
            )
            // ✅ Social Graph API (Friends, Search, Devices, etc.)
            .route(
                "/api/v2/search/users",
                web::get().to(rest_api::search_users),
            )
            .route(
                "/api/v2/friends/recommendations",
                web::get().to(rest_api::get_recommendations),
            )
            .route("/api/v2/friends/add", web::post().to(rest_api::add_friend))
            .route(
                "/api/v2/friends/remove",
                web::delete().to(rest_api::remove_friend),
            )
            .route(
                "/api/v2/friends/list",
                web::get().to(rest_api::get_friends_list),
            )
            // ✅ Social interactions
            .service(create_like)
            .service(delete_like)
            .service(delete_like_legacy)
            .service(get_likes)
            .service(check_liked)
            .service(batch_check_liked)
            .service(create_comment)
            .service(delete_comment)
            .service(delete_comment_v2)
            .service(get_comments)
            .service(create_share)
            .service(get_share_count)
            .service(get_share_count_legacy)
            // ✅ Bookmark API
            .service(create_bookmark)
            .service(delete_bookmark)
            .service(get_bookmarks)
            .service(check_bookmarked)
            .service(batch_check_bookmarked)
            // ✅ User Liked Posts API
            .service(get_user_liked_posts)
            // ✅ Comment Likes API (IG/小红书风格评论点赞)
            .service(create_comment_like)
            .service(delete_comment_like)
            .service(get_comment_like_count)
            .service(check_comment_liked)
            .service(batch_check_comment_liked)
            // ✅ Device Management API
            .route("/api/v2/devices", web::get().to(rest_api::get_devices))
            .route(
                "/api/v2/devices/logout",
                web::post().to(rest_api::logout_device),
            )
            .route(
                "/api/v2/devices/current",
                web::get().to(rest_api::get_current_device),
            )
            // ✅ Invitations API
            .route(
                "/api/v2/invitations/generate",
                web::post().to(rest_api::generate_invite_code),
            )
            .route(
                "/api/v2/invitations",
                web::get().to(rest_api::list_invitations),
            )
            .route(
                "/api/v2/invitations/stats",
                web::get().to(rest_api::get_invitation_stats),
            )
            // ✅ Chat & Group API
            .route(
                "/api/v2/chat/groups/create",
                web::post().to(rest_api::create_group_chat),
            )
            .route(
                "/api/v2/chat/conversations/{id}",
                web::get().to(rest_api::get_conversation_by_id),
            )
            // ✅ Video/Voice Call API (proxy to realtime-chat-service)
            .service(rest_api::calls::initiate_call)
            .service(rest_api::calls::answer_call)
            .service(rest_api::calls::reject_call)
            .service(rest_api::calls::end_call)
            .service(rest_api::calls::send_ice_candidate)
            .service(rest_api::calls::get_ice_servers)
            // ✅ Poll API (投票榜单)
            .service(get_trending_polls)
            .service(get_active_polls)
            .service(create_poll)
            .service(get_poll)
            .service(vote_on_poll)
            .service(unvote)
            .service(check_voted)
            .service(get_rankings)
            .service(add_candidate)
            .service(remove_candidate)
            .service(close_poll)
            .service(delete_poll)
            // ✅ Graph API (Follow/Unfollow)
            .route("/api/v2/graph/following", web::get().to(get_my_following))
            .route(
                "/api/v2/graph/following/{user_id}",
                web::get().to(get_user_following),
            )
            .route("/api/v2/graph/followers", web::get().to(get_my_followers))
            .route(
                "/api/v2/graph/followers/{user_id}",
                web::get().to(get_user_followers),
            )
            .route("/api/v2/graph/follow", web::post().to(follow_user))
            .route(
                "/api/v2/graph/follow/{user_id}",
                web::delete().to(unfollow_user),
            )
            .route(
                "/api/v2/graph/is-following/{user_id}",
                web::get().to(check_is_following),
            )
            // ✅ Notifications API
            .route("/api/v2/notifications", web::get().to(get_notifications))
            .route("/api/v2/notifications", web::post().to(create_notification))
            // Specific routes must come before parameterized routes
            .route(
                "/api/v2/notifications/read-all",
                web::post().to(mark_all_notifications_read),
            )
            .route(
                "/api/v2/notifications/unread-count",
                web::get().to(get_unread_count),
            )
            .route(
                "/api/v2/notifications/stats",
                web::get().to(get_notification_stats),
            )
            .route(
                "/api/v2/notifications/preferences",
                web::get().to(get_notification_preferences),
            )
            .route(
                "/api/v2/notifications/preferences",
                web::put().to(update_notification_preferences),
            )
            .route(
                "/api/v2/notifications/push-token",
                web::post().to(register_push_token),
            )
            .route(
                "/api/v2/notifications/push-token/{token}",
                web::delete().to(unregister_push_token),
            )
            .route(
                "/api/v2/notifications/batch",
                web::post().to(batch_create_notifications),
            )
            // Parameterized routes last
            .route(
                "/api/v2/notifications/{id}",
                web::get().to(get_notification),
            )
            .route(
                "/api/v2/notifications/{id}",
                web::delete().to(delete_notification),
            )
            .route(
                "/api/v2/notifications/{id}/read",
                web::post().to(mark_notification_read),
            )
            // ✅ Search API (content, users, hashtags, trending)
            .route("/api/v2/search", web::get().to(search_all))
            .route("/api/v2/search/content", web::get().to(search_content))
            .route(
                "/api/v2/search/users-full",
                web::get().to(search_users_full),
            )
            .route("/api/v2/search/hashtags", web::get().to(search_hashtags))
            .route("/api/v2/search/suggestions", web::get().to(get_suggestions))
            .route(
                "/api/v2/search/trending",
                web::get().to(get_trending_topics),
            )
            // ✅ User Settings API
            .route("/api/v2/settings", web::get().to(get_settings))
            .route("/api/v2/settings", web::put().to(update_settings))
            // ✅ Device Management API
            .route("/api/v2/devices", web::get().to(list_devices))
            .route("/api/v2/devices/current", web::get().to(get_current_device))
            .route("/api/v2/devices/logout", web::post().to(logout_device))
            // ✅ Account Management API (Multi-account & Alias)
            .route(
                "/api/v2/accounts",
                web::get().to(rest_api::accounts::list_accounts),
            )
            .route(
                "/api/v2/accounts/switch",
                web::post().to(rest_api::accounts::switch_account),
            )
            .route(
                "/api/v2/accounts/alias",
                web::post().to(rest_api::accounts::create_alias_account),
            )
            .route(
                "/api/v2/accounts/alias/{id}",
                web::get().to(rest_api::accounts::get_alias_account),
            )
            .route(
                "/api/v2/accounts/alias/{id}",
                web::put().to(rest_api::accounts::update_alias_account),
            )
            .route(
                "/api/v2/accounts/alias/{id}",
                web::delete().to(rest_api::accounts::delete_alias_account),
            )
            // ✅ Matrix E2EE Integration API (proxied to realtime-chat-service)
            .service(rest_api::matrix::get_matrix_token)
            .service(rest_api::matrix::get_matrix_config)
            .service(rest_api::matrix::get_all_room_mappings)
            .service(rest_api::matrix::save_room_mapping)
            .service(rest_api::matrix::get_room_mapping)
            .service(rest_api::matrix::get_conversation_mapping)
            .service(rest_api::matrix::get_encryption_status)
            .service(rest_api::matrix::get_room_status)
    })
    .bind(&bind_addr)?
    .run()
    .await
}

#[cfg(test)]
mod tests {
    #[allow(unused_imports)]
    use super::*;

    #[tokio::test]
    async fn test_health_query() {
        let clients = crate::clients::ServiceClients::default();
        let schema = crate::schema::build_schema(clients);

        let query = "{ health }";
        let result = schema.execute(query).await;

        assert!(result.errors.is_empty());
        assert_eq!(result.data.to_string(), r#"{health: "ok"}"#);
    }
}

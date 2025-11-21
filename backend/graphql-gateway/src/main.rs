use actix_web::{middleware::Logger, web, App, HttpServer};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse, GraphQLSubscription};
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
    // Initialize structured logging with JSON format for production-grade observability
    // Includes: timestamp, level, target, thread IDs, line numbers, and structured fields
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,graphql_gateway=debug".into()),
        )
        .with(
            tracing_subscriber::fmt::layer()
                .json() // ✅ JSON format for log aggregation (CloudWatch, Datadog, ELK)
                .with_current_span(true) // Include span context for distributed tracing
                .with_span_list(true) // Include all parent spans
                .with_thread_ids(true) // Include thread IDs for debugging
                .with_thread_names(true) // Include thread names
                .with_line_number(true) // Include source line numbers
                .with_file(true) // Include source file paths
                .with_target(true), // Include target module path
        )
        .init();

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

    // Initialize service clients from configuration
    let clients = ServiceClients::new(
        &config.services.auth_service,
        // user_service removed - service is deprecated
        &config.services.content_service,
        &config.services.feed_service,
    );

    info!("Service clients initialized");

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
            // Feed API
            .route("/api/v2/feed", web::get().to(rest_api::get_feed))
            // ✅ User Profile API
            .route("/api/v2/users/{id}", web::get().to(rest_api::get_profile))
            .route("/api/v2/users/{id}", web::put().to(rest_api::update_profile))
            .route("/api/v2/users/avatar", web::post().to(rest_api::upload_avatar))
            // ✅ Alice AI Assistant API
            .route("/api/v2/alice/status", web::get().to(rest_api::get_status))
            .route("/api/v2/alice/chat", web::post().to(rest_api::send_message))
            .route("/api/v2/alice/voice", web::post().to(rest_api::voice_mode))
            // ✅ Channels API
            .route("/api/v2/channels", web::get().to(rest_api::get_all_channels))
            .route("/api/v2/channels/{id}", web::get().to(rest_api::get_channel_details))
            .route("/api/v2/users/{id}/channels", web::get().to(rest_api::get_user_channels))
            .route("/api/v2/channels/subscribe", web::post().to(rest_api::subscribe_channel))
            .route("/api/v2/channels/unsubscribe", web::delete().to(rest_api::unsubscribe_channel))
            // ✅ Social Graph API (Friends, Search, Devices, etc.)
            .route("/api/v2/search/users", web::get().to(rest_api::search_users))
            .route("/api/v2/friends/recommendations", web::get().to(rest_api::get_recommendations))
            .route("/api/v2/friends/add", web::post().to(rest_api::add_friend))
            .route("/api/v2/friends/remove", web::delete().to(rest_api::remove_friend))
            .route("/api/v2/friends/list", web::get().to(rest_api::get_friends_list))
            // ✅ Device Management API
            .route("/api/v2/devices", web::get().to(rest_api::get_devices))
            .route("/api/v2/devices/logout", web::post().to(rest_api::logout_device))
            .route("/api/v2/devices/current", web::get().to(rest_api::get_current_device))
            // ✅ Invitations API
            .route("/api/v2/invitations/generate", web::post().to(rest_api::generate_invite_code))
            // ✅ Chat & Group API
            .route("/api/v2/chat/groups/create", web::post().to(rest_api::create_group_chat))
    })
    .bind(&bind_addr)?
    .run()
    .await
}

#[cfg(test)]
mod tests {
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

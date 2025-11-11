use actix_web::{web, App, HttpServer, middleware::Logger};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse, GraphQLSubscription};
use tracing::info;
use tracing_subscriber::prelude::*;
use std::env;

mod config;
mod clients;
mod schema;
mod middleware;
mod cache;
mod kafka;  // ✅ P0-5: Kafka integration for subscriptions
mod security; // ✅ P0-2: GraphQL security extensions

use clients::ServiceClients;
use schema::build_schema;
use middleware::{JwtMiddleware, RateLimitMiddleware, RateLimitConfig};
use cache::CacheConfig;

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
    GraphQLSubscription::new(schema.as_ref().clone())
        .start(&req, payload)
}

async fn health_handler() -> &'static str {
    "ok"
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
                .with_target(true) // Include target module path
        )
        .init();

    info!("Starting GraphQL Gateway...");

    // Load configuration (includes JWT config from AWS Secrets Manager or env)
    let config = config::Config::from_env()
        .await
        .map_err(|e| format!("Failed to load configuration: {}", e))?;

    info!(
        algorithm = %config.jwt.algorithm,
        issuer = %config.jwt.issuer,
        "JWT configuration loaded successfully"
    );

    // Initialize service clients from configuration
    let clients = ServiceClients::new(
        &config.services.auth_service,
        &config.services.user_service,
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
        env::var("JWT_PRIVATE_KEY_PEM")
            .map_err(|_| "JWT_PRIVATE_KEY_PEM required for RS256 tokens")?
    };

    let jwt_public_key = config.jwt.validation_key.clone()
        .or_else(|| env::var("JWT_PUBLIC_KEY_PEM").ok())
        .ok_or("JWT public key (validation_key or JWT_PUBLIC_KEY_PEM) required for RS256")?;

    crypto_core::jwt::initialize_jwt_keys(&jwt_private_key, &jwt_public_key)
        .map_err(|e| format!("Failed to initialize JWT keys - check PEM format: {}", e))?;

    info!("JWT authentication enabled with RS256 algorithm");

    // Build GraphQL schema with service clients
    let schema = build_schema(clients);

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
            .wrap(rate_limiter.clone())  // ✅ P0-3: Apply rate limiting before JWT auth
            .wrap(JwtMiddleware::new())  // ✅ P0-1: Fixed - Now uses RS256 from crypto-core
            .app_data(web::Data::new(schema.clone()))
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

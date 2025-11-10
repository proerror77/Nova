use actix_web::{web, App, HttpServer, middleware::Logger};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse, GraphQLSubscription};
use tracing::info;
use std::env;

mod config;
mod clients;
mod schema;
mod middleware;
mod cache;

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
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            env::var("RUST_LOG")
                .unwrap_or_else(|_| "info,graphql_gateway=debug".to_string())
        )
        .init();

    info!("Starting GraphQL Gateway...");

    // Initialize service clients from environment variables
    let auth_endpoint = env::var("AUTH_SERVICE_URL")
        .unwrap_or_else(|_| "http://auth-service.nova-backend.svc.cluster.local:9083".to_string());
    let user_endpoint = env::var("USER_SERVICE_URL")
        .unwrap_or_else(|_| "http://user-service.nova-backend.svc.cluster.local:9080".to_string());
    let content_endpoint = env::var("CONTENT_SERVICE_URL")
        .unwrap_or_else(|_| "http://content-service.nova-backend.svc.cluster.local:9081".to_string());
    let feed_endpoint = env::var("FEED_SERVICE_URL")
        .unwrap_or_else(|_| "http://feed-service.nova-backend.svc.cluster.local:9084".to_string());

    let clients = ServiceClients::new(
        &auth_endpoint,
        &user_endpoint,
        &content_endpoint,
        &feed_endpoint,
    );

    info!("Service clients initialized");

    // Build GraphQL schema with service clients
    let schema = build_schema(clients);

    // JWT configuration
    let jwt_secret = env::var("JWT_SECRET")
        .expect("JWT_SECRET environment variable must be set");
    info!("JWT authentication enabled");

    let server_host = env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let server_port = env::var("SERVER_PORT")
        .unwrap_or_else(|_| "8080".to_string())
        .parse::<u16>()
        .expect("SERVER_PORT must be a valid u16");

    let bind_addr = format!("{}:{}", server_host, server_port);
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
            .wrap(JwtMiddleware::new(jwt_secret.clone()))
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

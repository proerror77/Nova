//! Nova User Service
//!
//! Refactored for simplicity:
//! - Single point of initialization (AppState)
//! - Modular route configuration
//! - Centralized background task management
//! - Clear separation of concerns

use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpServer};
use std::io;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use user_service::{
    app_state::AppState, background, cli, config::Config, metrics, routes,
    middleware::{GlobalRateLimitMiddleware, MetricsMiddleware},
    security,
};

#[actix_web::main]
async fn main() -> io::Result<()> {
    // 1. Handle CLI commands (healthcheck, etc.)
    if cli::handle_cli_commands().await? {
        return Ok(());
    }

    // 2. Initialize tracing
    init_tracing();

    // 3. Load configuration
    let config = Config::from_env().expect("Failed to load configuration");
    tracing::info!("Starting user-service v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("Environment: {}", config.app.env);

    // 4. Initialize JWT keys
    let private_key_pem = std::fs::read_to_string(
        std::env::var("JWT_PRIVATE_KEY_FILE").ok().map(|_| "").unwrap_or(""),
    )
    .unwrap_or_else(|_| config.jwt.private_key_pem.clone());

    let public_key_pem = std::fs::read_to_string(
        std::env::var("JWT_PUBLIC_KEY_FILE").ok().map(|_| "").unwrap_or(""),
    )
    .unwrap_or_else(|_| config.jwt.public_key_pem.clone());

    security::jwt::initialize_keys(&private_key_pem, &public_key_pem)
        .expect("Failed to initialize JWT keys");

    // 5. Initialize metrics
    metrics::init_metrics();

    // 6. Initialize all application state (databases, services, etc.)
    let state = AppState::initialize(config.clone())
        .await
        .expect("Failed to initialize application state");

    // 7. Spawn background tasks
    let background_tasks = background::spawn_background_tasks(state.clone())
        .await
        .expect("Failed to spawn background tasks");

    // 8. Start HTTP server
    let bind_address = format!("{}:{}", config.app.host, config.app.port);
    tracing::info!("Starting HTTP server at {}", bind_address);

    let server = HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            .app_data(web::Data::new(state.clone()))
            .wrap(cors)
            .wrap(Logger::default())
            .wrap(tracing_actix_web::TracingLogger::default())
            .wrap(MetricsMiddleware)
            .wrap(GlobalRateLimitMiddleware::new(state.rate_limiter.clone()))
            .configure(routes::configure_routes)
    })
    .bind(&bind_address)?
    .workers(4)
    .run();

    // 9. Run server and handle graceful shutdown
    let result = server.await;

    // 10. Cleanup: Gracefully shutdown background tasks
    tracing::info!("Server shutting down. Stopping background services...");
    background::shutdown_background_tasks(background_tasks).await;

    result
}

/// Initialize tracing subscriber
fn init_tracing() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=debug,sqlx=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();
}

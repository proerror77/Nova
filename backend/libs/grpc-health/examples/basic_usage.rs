//! Basic usage example of grpc-health library
//!
//! This example demonstrates how to:
//! 1. Create a health manager with PostgreSQL and Redis checks
//! 2. Start background health monitoring
//! 3. Integrate with a gRPC server
//!
//! To run this example:
//! ```bash
//! # Ensure PostgreSQL and Redis are running
//! docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=password postgres:16
//! docker run -d -p 6379:6379 redis:7
//!
//! # Run the example
//! cargo run --example basic_usage
//!
//! # In another terminal, test the health endpoint
//! grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check
//! ```

use grpc_health::HealthManagerBuilder;
use std::sync::Arc;
use std::time::Duration;
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    // Configuration
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:password@localhost:5432/postgres".to_string());
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());
    let grpc_port = std::env::var("GRPC_PORT")
        .unwrap_or_else(|_| "50051".to_string())
        .parse::<u16>()?;

    tracing::info!("Starting gRPC Health Check example");
    tracing::info!("Database URL: {}", mask_password(&database_url));
    tracing::info!("Redis URL: {}", redis_url);
    tracing::info!("gRPC Port: {}", grpc_port);

    // Initialize database connection
    tracing::info!("Connecting to PostgreSQL...");
    let pg_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;
    tracing::info!("✅ Connected to PostgreSQL");

    // Initialize Redis connection
    tracing::info!("Connecting to Redis...");
    let redis_client = redis::Client::open(redis_url)?;
    let redis_manager = redis_client.get_connection_manager().await?;
    tracing::info!("✅ Connected to Redis");

    // Create health manager with all dependency checks
    tracing::info!("Setting up health checks...");
    let (health_manager, health_service) = HealthManagerBuilder::new()
        .with_postgres(pg_pool.clone())
        .with_redis(redis_manager.clone())
        .build()
        .await;
    tracing::info!("✅ Health manager created");

    // Start background health checks (every 10 seconds)
    let health_manager = Arc::new(tokio::sync::Mutex::new(health_manager));
    let _handle = grpc_health::HealthManager::start_background_check(
        health_manager.clone(),
        Duration::from_secs(10),
    );
    tracing::info!("✅ Background health checks started (interval: 10s)");

    // Create gRPC server address
    let addr = format!("0.0.0.0:{}", grpc_port).parse()?;

    tracing::info!("Starting gRPC server on {}", addr);
    tracing::info!("Health check endpoint: grpc.health.v1.Health");
    tracing::info!("");
    tracing::info!("Test the health endpoint:");
    tracing::info!(
        "  grpcurl -plaintext localhost:{} grpc.health.v1.Health/Check",
        grpc_port
    );
    tracing::info!("");

    // Start gRPC server with health service
    // Note: health_service is already a HealthServer<impl Health>
    Server::builder()
        .add_service(health_service)
        .serve(addr)
        .await?;

    Ok(())
}

/// Mask password in connection string for logging
fn mask_password(url: &str) -> String {
    url.split('@')
        .enumerate()
        .map(|(i, part)| {
            if i == 0 && part.contains("://") {
                // This is the credentials part
                if let Some(proto_end) = part.find("://") {
                    let proto = &part[..=proto_end + 2]; // Include "://"
                    let rest = &part[proto_end + 3..];
                    if let Some(colon_pos) = rest.find(':') {
                        format!("{}{}:****", proto, &rest[..colon_pos])
                    } else {
                        part.to_string()
                    }
                } else {
                    part.to_string()
                }
            } else {
                part.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("@")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mask_password() {
        assert_eq!(
            mask_password("postgres://user:password@localhost:5432/db"),
            "postgres://user:****@localhost:5432/db"
        );
        assert_eq!(
            mask_password("postgres://user@localhost:5432/db"),
            "postgres://user@localhost:5432/db"
        );
    }
}

//! # gRPC Health Check Library
//!
//! Production-ready health check implementation for Kubernetes liveness and readiness probes.
//! Implements the standard grpc.health.v1 protocol using tonic-health.
//!
//! ## Features
//!
//! - Standard grpc.health.v1 protocol support
//! - Liveness vs Readiness probe distinction
//! - External dependency checking (PostgreSQL, Redis, Kafka)
//! - Background health monitoring
//! - Builder pattern for easy integration
//!
//! ## Example
//!
//! ```ignore
//! use grpc_health::{HealthManagerBuilder, HealthManager};
//! use sqlx::PgPool;
//! use std::time::Duration;
//! use std::sync::Arc;
//!
//! # async fn example() -> Result<(), Box<dyn std::error::Error>> {
//! # let database_url = "postgres://user:pass@localhost/db";
//! # let redis_url = "redis://localhost";
//! let pg_pool = sqlx::PgPool::connect(database_url).await?;
//! let redis_client = redis::Client::open(redis_url)?
//!     .get_connection_manager()
//!     .await?;
//!
//! let (health_manager, health_service) = HealthManagerBuilder::new()
//!     .with_postgres(pg_pool.clone())
//!     .with_redis(redis_client.clone())
//!     .build()
//!     .await;
//!
//! // Start background health checks
//! let health_manager = Arc::new(tokio::sync::Mutex::new(health_manager));
//! HealthManager::start_background_check(
//!     health_manager.clone(),
//!     Duration::from_secs(10),
//! );
//!
//! // Add health_service to your gRPC server
//! # Ok(())
//! # }
//! ```

mod builder;
mod checks;
mod error;
mod health;
mod manager;

pub use builder::HealthManagerBuilder;
pub use checks::{HealthCheck, KafkaHealthCheck, PostgresHealthCheck, RedisHealthCheck};
pub use error::{HealthCheckError, Result};
pub use health::HealthStatus;
pub use manager::HealthManager;

// Re-export tonic-health types for convenience
pub use tonic_health::pb::health_server::HealthServer;
pub use tonic_health::server::HealthReporter;

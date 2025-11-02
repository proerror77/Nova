/// Nova Auth Service
///
/// This service handles all authentication and authorization for the Nova platform.
/// It provides:
/// - User registration and login
/// - OAuth2 integration (Google, Apple, Facebook, WeChat)
/// - JWT token management
/// - Password reset and change
/// - Session management
/// - Two-factor authentication
///
/// Architecture:
/// - gRPC interface for inter-service communication
/// - REST API for client applications
/// - PostgreSQL for persistent data
/// - Redis for sessions and caching
/// - Argon2id for password hashing
/// - RS256 for JWT signing with key rotation
pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
pub mod handlers;
pub mod models;
pub mod security;
pub mod services;
pub mod utils;
pub mod validators;

pub use error::{AuthError, AuthResult};
use redis::aio::ConnectionManager;
use services::KafkaEventProducer;
use sqlx::PgPool;

/// Application state shared across all handlers
#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub redis: ConnectionManager,
    pub kafka_producer: Option<KafkaEventProducer>,
}

// gRPC generated code
pub mod nova {
    pub mod auth {
        pub mod v1 {
            tonic::include_proto!("nova.auth.v1");
        }
    }
}

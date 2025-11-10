pub mod cache;

pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
pub mod handlers;
pub mod jobs;
pub mod metrics;
pub mod middleware;
pub mod models;
pub mod openapi;
pub mod security;
pub mod services;
pub mod utils;
pub mod validators;

pub use config::Config;
pub use error::{AppError, Result};

use redis_utils::SharedConnectionManager;
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub redis: SharedConnectionManager,
}

// image_processing re-export removed - moved to media-service (port 8082)

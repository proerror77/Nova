/// Content Service Library
///
/// Handles posts, comments, and stories endpoints for the Nova social platform.
/// This service is extracted from the monolithic user-service to enable independent scaling
/// and deployment.
///
/// # Modules
///
/// - `handlers`: Content-related HTTP request handlers
/// - `models`: Data structures for posts, comments, stories
/// - `services`: Business logic layer
/// - `db`: Database access layer and repositories
/// - `cache`: Content caching and invalidation
/// - `middleware`: HTTP middleware for authentication and rate limiting
/// - `error`: Error types and handling
/// - `config`: Configuration management
/// - `metrics`: Observability and metrics collection
pub mod cache;
pub mod config;
pub mod consumers;
pub mod db;
pub mod error;
pub mod grpc;
pub mod handlers;
pub mod jobs;
pub mod kafka;
pub mod metrics;
pub mod middleware;
pub mod models;
pub mod openapi;
pub mod services;

pub use config::Config;
pub use error::{AppError, Result};

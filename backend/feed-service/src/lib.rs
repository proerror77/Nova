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
pub mod security;
pub mod services;
pub mod utils;

pub use cache::{CacheConfig, CachedFeedPost, FeedCache};
pub use config::Config;
pub use error::{AppError, Result};

// Re-export trending service components (ML recommendation moved to ranking-service)
// Keeping only services needed for feed assembly and caching

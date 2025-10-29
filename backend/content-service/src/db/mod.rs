/// Database access layer
///
/// This module provides:
/// - Database connection pooling
/// - Repository implementations for posts, comments, stories
/// - Database migrations
///
/// Extracted from user-service as part of P1.2 service splitting.
use sqlx::postgres::PgPool;

pub mod comment_repo;
pub mod ch_client;
pub mod feed_schema;
pub mod post_repo;
pub mod post_share_repo;

// Re-export repositories
pub use comment_repo::*;
pub use post_repo::*;
pub use post_share_repo::*;
pub use feed_schema::ensure_feed_tables;

/// Create database connection pool
pub async fn create_pool(database_url: &str, max_connections: u32) -> Result<PgPool, sqlx::Error> {
    use sqlx::postgres::PgPoolOptions;
    use std::time::Duration;

    PgPoolOptions::new()
        .max_connections(max_connections)
        .acquire_timeout(Duration::from_secs(10))
        .idle_timeout(Duration::from_secs(300))
        .max_lifetime(Duration::from_secs(1800))
        .connect(database_url)
        .await
}

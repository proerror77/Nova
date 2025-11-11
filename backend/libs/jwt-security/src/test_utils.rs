//! Test utilities for JWT security testing
//!
//! Provides safe Redis connections for testing with proper error handling

use anyhow::Result;
use redis::aio::ConnectionManager;
use redis::Client;
use std::env;

/// Get Redis connection for testing
///
/// Uses REDIS_TEST_URL environment variable or defaults to localhost
/// Tests should handle connection failures gracefully
pub async fn get_test_redis_connection() -> Result<ConnectionManager> {
    let redis_url = env::var("REDIS_TEST_URL")
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let client = Client::open(redis_url)
        .map_err(|e| anyhow::anyhow!("Failed to create Redis client: {}", e))?;

    let manager = ConnectionManager::new(client).await
        .map_err(|e| anyhow::anyhow!("Failed to connect to Redis: {}", e))?;

    Ok(manager)
}

/// Check if Redis is available for testing
pub async fn is_redis_available() -> bool {
    get_test_redis_connection().await.is_ok()
}
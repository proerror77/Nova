/// Unified Redis operations
/// Eliminates duplication of Redis SET_EX, GET, DELETE patterns across services
use anyhow::{anyhow, Result};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;

/// Set a key with expiration (SET_EX operation)
///
/// # Arguments
/// * `redis` - Redis connection manager
/// * `key` - Cache key
/// * `value` - Value to store (must be serializable to string)
/// * `ttl_seconds` - Time to live in seconds
///
/// # Example
/// ```ignore
/// redis_set_ex(&redis, "verify_email:user@example.com", "token123", 3600).await?;
/// ```
pub async fn redis_set_ex(
    redis: &ConnectionManager,
    key: &str,
    value: &str,
    ttl_seconds: u64,
) -> Result<()> {
    let mut conn = redis.clone();
    let _: () = conn
        .set_ex(key, value, ttl_seconds)
        .await
        .map_err(|e| anyhow!("Failed to set Redis key '{}': {}", key, e))?;
    Ok(())
}

/// Get a value from Redis
///
/// # Arguments
/// * `redis` - Redis connection manager
/// * `key` - Cache key
///
/// # Returns
/// `Ok(Some(value))` if key exists, `Ok(None)` if key doesn't exist
///
/// # Example
/// ```ignore
/// let token = redis_get(&redis, "verify_email:user@example.com").await?;
/// ```
pub async fn redis_get(
    redis: &ConnectionManager,
    key: &str,
) -> Result<Option<String>> {
    let mut conn = redis.clone();
    let value: Option<String> = conn
        .get(key)
        .await
        .map_err(|e| anyhow!("Failed to get Redis key '{}': {}", key, e))?;
    Ok(value)
}

/// Delete a key from Redis
///
/// # Arguments
/// * `redis` - Redis connection manager
/// * `key` - Cache key
///
/// # Returns
/// Number of keys deleted (0 or 1)
///
/// # Example
/// ```ignore
/// redis_delete(&redis, "verify_email:user@example.com").await?;
/// ```
pub async fn redis_delete(
    redis: &ConnectionManager,
    key: &str,
) -> Result<u32> {
    let mut conn = redis.clone();
    let deleted: u32 = conn
        .del(key)
        .await
        .map_err(|e| anyhow!("Failed to delete Redis key '{}': {}", key, e))?;
    Ok(deleted)
}

/// Check if a key exists in Redis
///
/// # Arguments
/// * `redis` - Redis connection manager
/// * `key` - Cache key
///
/// # Example
/// ```ignore
/// let exists = redis_exists(&redis, "verify_email:user@example.com").await?;
/// ```
pub async fn redis_exists(
    redis: &ConnectionManager,
    key: &str,
) -> Result<bool> {
    let mut conn = redis.clone();
    let exists: bool = conn
        .exists(key)
        .await
        .map_err(|e| anyhow!("Failed to check Redis key '{}': {}", key, e))?;
    Ok(exists)
}

/// Increment a Redis integer value
///
/// # Arguments
/// * `redis` - Redis connection manager
/// * `key` - Cache key
/// * `increment` - Amount to increment by
///
/// # Example
/// ```ignore
/// let new_count = redis_incr(&redis, "rate_limit:user123", 1).await?;
/// ```
pub async fn redis_incr(
    redis: &ConnectionManager,
    key: &str,
    increment: i32,
) -> Result<i32> {
    let mut conn = redis.clone();
    let value: i32 = conn
        .incr(key, increment)
        .await
        .map_err(|e| anyhow!("Failed to increment Redis key '{}': {}", key, e))?;
    Ok(value)
}

/// Set expiration on an existing key
///
/// # Arguments
/// * `redis` - Redis connection manager
/// * `key` - Cache key
/// * `ttl_seconds` - New time to live in seconds
///
/// # Returns
/// `true` if timeout was set, `false` if key doesn't exist
///
/// # Example
/// ```ignore
/// redis_expire(&redis, "verify_email:user@example.com", 7200).await?;
/// ```
pub async fn redis_expire(
    redis: &ConnectionManager,
    key: &str,
    ttl_seconds: u64,
) -> Result<bool> {
    let mut conn = redis.clone();
    let expired: bool = conn
        .expire(key, ttl_seconds as i64)
        .await
        .map_err(|e| anyhow!("Failed to set expiration on Redis key '{}': {}", key, e))?;
    Ok(expired)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_redis_operations_module_compiles() {
        // Ensures all exports are accessible
        assert!(true);
    }
}

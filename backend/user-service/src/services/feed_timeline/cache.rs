//! Redis caching layer for feed timeline
//!
//! Provides efficient caching of user feeds with TTL-based expiration

use redis::aio::Connection;
use sqlx::PgPool;
use serde_json;
use crate::error::AppError;

use super::TimelinePost;

const FEED_CACHE_KEY_PREFIX: &str = "feed:timeline";
const FEED_CACHE_TTL: usize = 300;  // 5 minutes

/// Get feed with Redis cache support
/// 
/// # Arguments
/// * `user_id` - User ID to fetch feed for
/// * `limit` - Maximum posts to return
/// * `redis` - Redis connection
/// * `db` - PostgreSQL connection pool
/// 
/// # Returns
/// Vector of TimelinePost sorted by creation time
pub async fn get_feed_cached(
    user_id: i32,
    limit: i32,
    redis: &mut Connection,
    db: &PgPool,
) -> Result<Vec<TimelinePost>, AppError> {
    let cache_key = format!("{}:user:{}:limit:{}", FEED_CACHE_KEY_PREFIX, user_id, limit);

    // Try to get from cache
    if let Ok(cached) = redis.get::<_, String>(&cache_key).await {
        if let Ok(posts) = serde_json::from_str(&cached) {
            return Ok(posts);
        }
    }

    // Cache miss - fetch from database
    let posts = fetch_feed_from_db(user_id, limit, db).await?;

    // Write back to cache
    let json = serde_json::to_string(&posts)
        .map_err(|e| AppError::InternalServerError(format!("JSON serialization failed: {}", e)))?;
    
    let _: Result<(), _> = redis
        .set_ex(&cache_key, json, FEED_CACHE_TTL)
        .await;

    Ok(posts)
}

/// Fetch feed directly from PostgreSQL database
async fn fetch_feed_from_db(
    user_id: i32,
    limit: i32,
    db: &PgPool,
) -> Result<Vec<TimelinePost>, AppError> {
    let limit = limit.min(100);  // Cap at 100 posts
    
    sqlx::query_as::<_, TimelinePost>(
        "SELECT id, user_id, content, created_at, like_count
         FROM posts
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT $2"
    )
    .bind(user_id)
    .bind(limit)
    .fetch_all(db)
    .await
    .map_err(|e| AppError::DatabaseError(format!("Failed to fetch feed: {}", e)))
}

/// Invalidate feed cache for a user
/// 
/// # Arguments
/// * `user_id` - User ID whose cache to invalidate
/// * `redis` - Redis connection
/// 
/// # Returns
/// Result indicating success or failure
pub async fn invalidate_feed_cache(
    user_id: i32,
    redis: &mut Connection,
) -> Result<(), AppError> {
    let pattern = format!("{}:user:{}:*", FEED_CACHE_KEY_PREFIX, user_id);
    
    let keys: Vec<String> = redis
        .keys(pattern)
        .await
        .map_err(|e| AppError::CacheError(format!("Failed to scan keys: {}", e)))?;

    for key in keys {
        let _: Result<i32, _> = redis.del(&key).await;
    }

    Ok(())
}

/// Clear all feed cache (use with caution)
pub async fn clear_all_feed_cache(
    redis: &mut Connection,
) -> Result<(), AppError> {
    let pattern = format!("{}:*", FEED_CACHE_KEY_PREFIX);
    
    let keys: Vec<String> = redis
        .keys(pattern)
        .await
        .map_err(|e| AppError::CacheError(format!("Failed to scan keys: {}", e)))?;

    for key in keys {
        let _: Result<i32, _> = redis.del(&key).await;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_cache_key_format() {
        let key = format!("{}:user:{}:limit:{}", FEED_CACHE_KEY_PREFIX, 123, 20);
        assert_eq!(key, "feed:timeline:user:123:limit:20");
    }

    #[tokio::test]
    async fn test_limit_capping() {
        let capped = 150i32.min(100);
        assert_eq!(capped, 100);
    }
}

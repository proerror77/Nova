/// User profile caching utilities
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::models::User;

const USER_CACHE_TTL: usize = 3600; // 1 hour

#[derive(Serialize, Deserialize, Clone)]
pub struct CachedUser {
    pub id: Uuid,
    pub username: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub email_verified: bool,
    pub private_account: bool,
}

impl From<User> for CachedUser {
    fn from(user: User) -> Self {
        CachedUser {
            id: user.id,
            username: user.username,
            display_name: user.display_name,
            bio: user.bio,
            avatar_url: user.avatar_url,
            email_verified: user.email_verified,
            private_account: user.private_account,
        }
    }
}

/// Get user from cache by ID
pub async fn get_cached_user(
    redis: &ConnectionManager,
    user_id: Uuid,
) -> Result<Option<CachedUser>, redis::RedisError> {
    let key = format!("nova:cache:user:{}", user_id);
    let mut redis = redis.clone();
    let cached: Option<String> = redis::cmd("GET")
        .arg(&key)
        .query_async(&mut redis)
        .await?;

    if let Some(json_str) = cached {
        if let Ok(user) = serde_json::from_str::<CachedUser>(&json_str) {
            return Ok(Some(user));
        }
    }

    Ok(None)
}

/// Set user in cache
pub async fn set_cached_user(
    redis: &ConnectionManager,
    user: &CachedUser,
) -> Result<(), redis::RedisError> {
    let key = format!("nova:cache:user:{}", user.id);
    let json = serde_json::to_string(user).unwrap_or_default();

    let mut redis = redis.clone();
    redis::cmd("SET")
        .arg(&key)
        .arg(&json)
        .arg("EX")
        .arg(USER_CACHE_TTL)
        .query_async(&mut redis)
        .await?;

    Ok(())
}

/// Invalidate user cache
pub async fn invalidate_user_cache(
    redis: &ConnectionManager,
    user_id: Uuid,
) -> Result<(), redis::RedisError> {
    let key = format!("nova:cache:user:{}", user_id);
    let mut redis = redis.clone();
    redis::cmd("DEL")
        .arg(&key)
        .query_async(&mut redis)
        .await?;

    Ok(())
}

/// Cache search results
pub async fn cache_search_results(
    redis: &ConnectionManager,
    query: &str,
    limit: i64,
    offset: i64,
    results: &str,
) -> Result<(), redis::RedisError> {
    let key = format!("nova:cache:search:users:{}:{}:{}", query, limit, offset);

    let mut redis = redis.clone();
    redis::cmd("SET")
        .arg(&key)
        .arg(results)
        .arg("EX")
        .arg(1800) // 30 minutes TTL for search results
        .query_async(&mut redis)
        .await?;

    Ok(())
}

/// Get cached search results
pub async fn get_cached_search_results(
    redis: &ConnectionManager,
    query: &str,
    limit: i64,
    offset: i64,
) -> Result<Option<String>, redis::RedisError> {
    let key = format!("nova:cache:search:users:{}:{}:{}", query, limit, offset);
    let mut redis = redis.clone();
    let cached: Option<String> = redis::cmd("GET")
        .arg(&key)
        .query_async(&mut redis)
        .await?;

    Ok(cached)
}

/// Invalidate search cache for a query pattern
pub async fn invalidate_search_cache(
    redis: &ConnectionManager,
    query_pattern: &str,
) -> Result<(), redis::RedisError> {
    let pattern = format!("nova:cache:search:users:{}:*", query_pattern);
    let mut redis = redis.clone();
    let keys: Vec<String> = redis::cmd("KEYS")
        .arg(&pattern)
        .query_async(&mut redis)
        .await?;

    if !keys.is_empty() {
        let mut redis = redis.clone();
        redis::cmd("DEL")
            .arg(&keys)
            .query_async(&mut redis)
            .await?;
    }

    Ok(())
}

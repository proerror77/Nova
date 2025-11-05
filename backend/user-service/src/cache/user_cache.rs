use super::versioning::{
    get_invalidation_timestamp, get_or_compute, is_version_valid, VersionedCacheEntry,
};
use crate::models::User;
/// User profile caching utilities
use redis_utils::SharedConnectionManager;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::utils::redis_timeout::run_with_timeout;
use chrono::{DateTime, Utc};
use rand::Rng;
use tokio::time::Duration as TokioDuration;

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
    pub created_at: DateTime<Utc>,
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
            created_at: user.created_at,
        }
    }
}

const USER_CACHE_MISS_SENTINEL: &str = "__nova_cache_miss__";
const NEGATIVE_CACHE_TTL_SECONDS: usize = 300;

/// Get user from cache by ID
pub async fn get_cached_user(
    redis: &SharedConnectionManager,
    user_id: Uuid,
) -> Result<Option<CachedUser>, redis::RedisError> {
    let key = format!("nova:cache:user:{}", user_id);
    let mut redis = redis.lock().await;
    let cached: Option<String> = run_with_timeout(
        redis::cmd("GET")
            .arg(&key)
            .query_async::<_, Option<String>>(&mut *redis),
    )
    .await?;

    if let Some(json_str) = cached {
        if json_str == USER_CACHE_MISS_SENTINEL {
            return Ok(None);
        }

        if let Ok(user) = serde_json::from_str::<CachedUser>(&json_str) {
            return Ok(Some(user));
        }
    }

    Ok(None)
}

/// Set user in cache
pub async fn set_cached_user(
    redis: &SharedConnectionManager,
    user: &CachedUser,
) -> Result<(), redis::RedisError> {
    let key = format!("nova:cache:user:{}", user.id);
    // CRITICAL FIX: Properly handle serialization errors instead of silently failing
    let json = serde_json::to_string(user).map_err(|e| {
        tracing::error!("Failed to serialize user {} for cache: {}", user.id, e);
        redis::RedisError::from((redis::ErrorKind::TypeError, "user serialization failed"))
    })?;

    let mut redis = redis.lock().await;
    run_with_timeout(
        redis::cmd("SET")
            .arg(&key)
            .arg(&json)
            .arg("EX")
            .arg(USER_CACHE_TTL)
            .query_async::<_, ()>(&mut *redis),
    )
    .await?;

    Ok(())
}

/// Cache a negative lookup for a user (prevents cache penetration)
pub async fn cache_user_miss(
    redis: &SharedConnectionManager,
    user_id: Uuid,
) -> Result<(), redis::RedisError> {
    let key = format!("nova:cache:user:{}", user_id);
    let mut redis = redis.lock().await;
    run_with_timeout(
        redis::cmd("SET")
            .arg(&key)
            .arg(USER_CACHE_MISS_SENTINEL)
            .arg("EX")
            .arg(NEGATIVE_CACHE_TTL_SECONDS)
            .query_async::<_, ()>(&mut *redis),
    )
    .await?;
    Ok(())
}

/// Invalidate user cache
pub async fn invalidate_user_cache(
    redis: &SharedConnectionManager,
    user_id: Uuid,
) -> Result<(), redis::RedisError> {
    let key = format!("nova:cache:user:{}", user_id);
    let mut redis = redis.lock().await;
    run_with_timeout(
        redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut *redis),
    )
    .await?;

    Ok(())
}

/// Cache search results
pub async fn cache_search_results(
    redis: &SharedConnectionManager,
    query: &str,
    limit: i64,
    offset: i64,
    results: &str,
) -> Result<(), redis::RedisError> {
    let key = format!("nova:cache:search:users:{}:{}:{}", query, limit, offset);

    let mut redis = redis.lock().await;
    run_with_timeout(
        redis::cmd("SET")
            .arg(&key)
            .arg(results)
            .arg("EX")
            .arg(1800) // 30 minutes TTL for search results
            .query_async::<_, ()>(&mut *redis),
    )
    .await?;

    Ok(())
}

/// Get cached search results
pub async fn get_cached_search_results(
    redis: &SharedConnectionManager,
    query: &str,
    limit: i64,
    offset: i64,
) -> Result<Option<String>, redis::RedisError> {
    let key = format!("nova:cache:search:users:{}:{}:{}", query, limit, offset);
    let mut redis = redis.lock().await;
    let cached: Option<String> = run_with_timeout(
        redis::cmd("GET")
            .arg(&key)
            .query_async::<_, Option<String>>(&mut *redis),
    )
    .await?;

    Ok(cached)
}

/// Invalidate search cache for a query pattern using SCAN (non-blocking)
///
/// CRITICAL FIX: Replace blocking KEYS command with non-blocking SCAN
/// KEYS command blocks entire Redis instance and causes system failures under load.
/// SCAN is O(1) average case and never blocks Redis.
pub async fn invalidate_search_cache(
    redis: &SharedConnectionManager,
    query_pattern: &str,
) -> Result<(), redis::RedisError> {
    let pattern = format!("nova:cache:search:users:{}:*", query_pattern);
    let mut redis = redis.lock().await;

    // Use SCAN instead of KEYS to avoid blocking Redis
    const MAX_ITERATIONS: usize = 1000;
    const MAX_KEYS: usize = 50_000;
    let mut cursor: u64 = 0;
    let mut all_keys: Vec<String> = Vec::new();
    let mut iterations: usize = 0;

    loop {
        iterations += 1;
        if iterations > MAX_ITERATIONS || all_keys.len() >= MAX_KEYS {
            tracing::warn!(
                "SCAN aborted early: iterations={}, collected_keys={}, pattern={}",
                iterations,
                all_keys.len(),
                pattern
            );
            break;
        }

        let mut rng = rand::thread_rng();
        let count: u32 = rng.gen_range(100..=500);

        // SCAN with MATCH pattern and COUNT for batch size
        let (next_cursor, batch_keys): (u64, Vec<String>) = run_with_timeout(
            redis::cmd("SCAN")
                .arg(cursor)
                .arg("MATCH")
                .arg(&pattern)
                .arg("COUNT")
                .arg(count) // Jittered batch size to avoid sync thundering
                .query_async::<_, (u64, Vec<String>)>(&mut *redis),
        )
        .await?;

        if !batch_keys.is_empty() {
            let room_left = MAX_KEYS.saturating_sub(all_keys.len());
            if batch_keys.len() > room_left {
                all_keys.extend(batch_keys.into_iter().take(room_left));
            } else {
                all_keys.extend(batch_keys);
            }
        }

        // Break when cursor returns to 0 (scan complete)
        if next_cursor == 0 {
            break;
        }
        cursor = next_cursor;

        // Light backoff every ~10k keys to avoid starving the reactor
        if all_keys.len() % 10_000 == 0 {
            tokio::time::sleep(TokioDuration::from_millis(2)).await;
        }
    }

    // Delete all collected keys in batches to avoid command size limits
    if !all_keys.is_empty() {
        for chunk in all_keys.chunks(1000) {
            run_with_timeout(
                redis::cmd("DEL")
                    .arg(chunk)
                    .query_async::<_, ()>(&mut *redis),
            )
            .await?;
        }

        tracing::info!(
            "Invalidated {} search cache entries for pattern: {}",
            all_keys.len(),
            pattern
        );
    }

    Ok(())
}

/// Get cached user with version control (prevents race conditions)
///
/// CRITICAL FIX: Atomic get-or-compute pattern to prevent:
/// 1. Cache stampede (multiple requests computing same value)
/// 2. TOCTOU race conditions
/// 3. Stale data reads
///
/// Uses Redis WATCH/MULTI/EXEC for atomic operation
pub async fn get_cached_user_versioned(
    redis: &SharedConnectionManager,
    user_id: Uuid,
    compute_fn: impl Fn() -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<CachedUser, Box<dyn std::error::Error>>> + Send,
        >,
    >,
) -> Result<CachedUser, Box<dyn std::error::Error>> {
    let key = format!("nova:cache:user:{}:v2", user_id); // v2 indicates version-controlled cache

    // Get or compute with atomic operation
    let result = get_or_compute(redis, &key, &compute_fn, USER_CACHE_TTL).await?;

    // Verify version hasn't been invalidated
    let invalidated_at = get_invalidation_timestamp(redis, &key)
        .await
        .unwrap_or(None);
    if !is_version_valid::<CachedUser>(
        &VersionedCacheEntry::new(result.data.clone()),
        invalidated_at,
    ) {
        // Cache was invalidated, compute fresh value
        let fresh_data = compute_fn().await?;
        return Ok(fresh_data);
    }

    Ok(result.data)
}

/// Invalidate user cache with version control
///
/// Atomically invalidates cache and increments version
pub async fn invalidate_user_cache_versioned(
    redis: &SharedConnectionManager,
    user_id: Uuid,
) -> Result<(), Box<dyn std::error::Error>> {
    let key = format!("nova:cache:user:{}:v2", user_id);
    super::versioning::invalidate_with_version(redis, &key).await
}

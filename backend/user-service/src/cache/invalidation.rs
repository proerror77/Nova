/// Cache invalidation with exponential backoff retry
///
/// CRITICAL FIX: Ensures cache invalidation completes with automatic retries
/// instead of silently failing, which would lead to stale cache data.
use redis::aio::ConnectionManager;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{error, warn};
use uuid::Uuid;

/// Maximum number of retry attempts
const MAX_RETRIES: u32 = 3;
/// Initial backoff duration (500ms)
const INITIAL_BACKOFF_MS: u64 = 500;

/// Invalidate user cache with automatic retry
///
/// This ensures that cache invalidation completes even if Redis
/// experiences temporary connectivity issues.
pub async fn invalidate_user_cache_with_retry(
    redis: &ConnectionManager,
    user_id: Uuid,
) -> Result<(), String> {
    let key = format!("nova:cache:user:{}", user_id);

    for attempt in 1..=MAX_RETRIES {
        match redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut redis.clone())
            .await
        {
            Ok(_) => {
                if attempt > 1 {
                    tracing::info!(
                        "User cache invalidation succeeded after {} attempts (user: {})",
                        attempt,
                        user_id
                    );
                }
                return Ok(());
            }
            Err(e) => {
                if attempt == MAX_RETRIES {
                    error!(
                        "Failed to invalidate user cache after {} attempts (user: {}): {}",
                        MAX_RETRIES, user_id, e
                    );
                    return Err(format!("Cache invalidation failed: {}", e));
                }

                // Exponential backoff: 500ms, 1s, 2s
                let backoff_ms = INITIAL_BACKOFF_MS * 2_u64.pow(attempt - 1);
                warn!(
                    "Cache invalidation attempt {} failed (user: {}), retrying in {}ms: {}",
                    attempt, user_id, backoff_ms, e
                );
                sleep(Duration::from_millis(backoff_ms)).await;
            }
        }
    }

    unreachable!()
}

/// Invalidate search cache with automatic retry
pub async fn invalidate_search_cache_with_retry(
    redis: &ConnectionManager,
    query_pattern: &str,
) -> Result<(), String> {
    let pattern = format!("nova:cache:search:users:{}:*", query_pattern);

    for attempt in 1..=MAX_RETRIES {
        match invalidate_search_cache_internal(redis, &pattern).await {
            Ok(count) => {
                if attempt > 1 {
                    tracing::info!(
                        "Search cache invalidation succeeded after {} attempts (pattern: {}, {} keys)",
                        attempt,
                        pattern,
                        count
                    );
                } else if count > 0 {
                    tracing::debug!(
                        "Search cache invalidation cleared {} keys (pattern: {})",
                        count,
                        pattern
                    );
                }
                return Ok(());
            }
            Err(e) => {
                if attempt == MAX_RETRIES {
                    error!(
                        "Failed to invalidate search cache after {} attempts (pattern: {}): {}",
                        MAX_RETRIES, pattern, e
                    );
                    return Err(format!("Search cache invalidation failed: {}", e));
                }

                let backoff_ms = INITIAL_BACKOFF_MS * 2_u64.pow(attempt - 1);
                warn!(
                    "Search cache invalidation attempt {} failed (pattern: {}), retrying in {}ms: {}",
                    attempt, pattern, backoff_ms, e
                );
                sleep(Duration::from_millis(backoff_ms)).await;
            }
        }
    }

    unreachable!()
}

/// Internal function to scan and delete search cache keys
async fn invalidate_search_cache_internal(
    redis: &ConnectionManager,
    pattern: &str,
) -> Result<usize, String> {
    let mut redis = redis.clone();
    let mut cursor: u64 = 0;
    let mut all_keys: Vec<String> = Vec::new();

    // SCAN loop using SCAN instead of blocking KEYS
    loop {
        let (next_cursor, batch_keys): (u64, Vec<String>) = redis::cmd("SCAN")
            .arg(cursor)
            .arg("MATCH")
            .arg(pattern)
            .arg("COUNT")
            .arg(100)
            .query_async::<_, (u64, Vec<String>)>(&mut redis)
            .await
            .map_err(|e| e.to_string())?;

        all_keys.extend(batch_keys);

        if next_cursor == 0 {
            break;
        }
        cursor = next_cursor;
    }

    // Delete collected keys in batches
    if !all_keys.is_empty() {
        let mut redis = redis.clone();
        let count = all_keys.len();

        for chunk in all_keys.chunks(1000) {
            redis::cmd("DEL")
                .arg(chunk)
                .query_async::<_, ()>(&mut redis)
                .await
                .map_err(|e| e.to_string())?;
        }

        Ok(count)
    } else {
        Ok(0)
    }
}

/// Feed cache invalidation with retry
pub async fn invalidate_feed_cache_with_retry(
    redis: &ConnectionManager,
    user_id: Uuid,
) -> Result<(), String> {
    // Feed cache key format: nova:cache:feed:{user_id}
    let key = format!("nova:cache:feed:{}", user_id);

    for attempt in 1..=MAX_RETRIES {
        match redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut redis.clone())
            .await
        {
            Ok(_) => {
                if attempt > 1 {
                    tracing::info!(
                        "Feed cache invalidation succeeded after {} attempts (user: {})",
                        attempt,
                        user_id
                    );
                }
                return Ok(());
            }
            Err(e) => {
                if attempt == MAX_RETRIES {
                    error!(
                        "Failed to invalidate feed cache after {} attempts (user: {}): {}",
                        MAX_RETRIES, user_id, e
                    );
                    return Err(format!("Feed cache invalidation failed: {}", e));
                }

                let backoff_ms = INITIAL_BACKOFF_MS * 2_u64.pow(attempt - 1);
                warn!(
                    "Feed cache invalidation attempt {} failed (user: {}), retrying in {}ms: {}",
                    attempt, user_id, backoff_ms, e
                );
                sleep(Duration::from_millis(backoff_ms)).await;
            }
        }
    }

    unreachable!()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_backoff_calculation() {
        // Verify exponential backoff: 500ms, 1s, 2s
        assert_eq!(INITIAL_BACKOFF_MS * 2_u64.pow(0), 500);
        assert_eq!(INITIAL_BACKOFF_MS * 2_u64.pow(1), 1000);
        assert_eq!(INITIAL_BACKOFF_MS * 2_u64.pow(2), 2000);
    }

    #[test]
    fn test_max_retries() {
        assert_eq!(MAX_RETRIES, 3);
    }
}

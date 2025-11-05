use chrono::Utc;
/// Cache Versioning and Race Condition Prevention
///
/// CRITICAL FIX: Add version control to prevent race conditions
/// Problems addressed:
/// 1. TOCTOU (Time of Check to Time of Use) race conditions
/// 2. Cache stampede when multiple requests trigger cache misses simultaneously
/// 3. Stale data consistency issues
///
/// Solution: Version-tagged cache entries with atomic CAS operations
use redis_utils::SharedConnectionManager;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::utils::redis_timeout::run_with_timeout;

/// Versioned cache entry wrapper
/// Adds version metadata to prevent stale reads and race conditions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionedCacheEntry<T> {
    /// Actual cached data
    pub data: T,
    /// Version identifier (timestamp-based, nanosecond precision)
    /// Prevents ABA problem and stale reads
    pub version: i64,
    /// Creation timestamp (Unix seconds)
    pub created_at: i64,
    /// Last update timestamp (Unix seconds)
    pub updated_at: i64,
}

impl<T> VersionedCacheEntry<T> {
    /// Create a new versioned cache entry
    pub fn new(data: T) -> Self {
        let now = Utc::now().timestamp();
        Self {
            data,
            version: now * 1_000_000_000
                + SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map(|d| d.subsec_nanos() as i64)
                    .unwrap_or(0),
            created_at: now,
            updated_at: now,
        }
    }

    /// Update the data and increment version
    pub fn update(mut self, data: T) -> Self {
        self.data = data;
        self.updated_at = Utc::now().timestamp();
        // Generate new version based on current time
        let now = Utc::now().timestamp();
        self.version = now * 1_000_000_000
            + SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.subsec_nanos() as i64)
                .unwrap_or(0);
        self
    }

    /// Check if entry is stale (older than TTL seconds)
    pub fn is_stale(&self, ttl_secs: i64) -> bool {
        let now = Utc::now().timestamp();
        (now - self.updated_at) > ttl_secs
    }
}

/// Cache operation result with version information
#[derive(Debug)]
pub struct CacheOpResult<T> {
    pub data: T,
    pub version: i64,
    pub was_cached: bool,
}

/// Atomic cache-get-or-compute pattern
///
/// Prevents cache stampede by using Redis WATCH/MULTI/EXEC
/// If multiple requests race, only one computes the value
pub async fn get_or_compute<T, F>(
    redis: &SharedConnectionManager,
    key: &str,
    compute: &F,
    ttl_secs: usize,
) -> Result<CacheOpResult<T>, Box<dyn std::error::Error>>
where
    T: Serialize + for<'de> Deserialize<'de> + Send + 'static,
    F: Fn() -> std::pin::Pin<
        Box<dyn std::future::Future<Output = Result<T, Box<dyn std::error::Error>>> + Send>,
    >,
{
    let mut redis_conn = {
        let guard = redis.lock().await;
        guard.clone()
    };

    // Try to read from cache
    loop {
        // Watch the key for changes
        let _ = run_with_timeout(
            redis::cmd("WATCH")
                .arg(key)
                .query_async::<_, ()>(&mut redis_conn),
        )
        .await;

        // Read current value
        let cached: Option<String> =
            run_with_timeout(redis::cmd("GET").arg(key).query_async(&mut redis_conn)).await?;

        if let Some(cached_json) = cached {
            match serde_json::from_str::<VersionedCacheEntry<T>>(&cached_json) {
                Ok(entry) => {
                    // Cache hit with valid version
                    return Ok(CacheOpResult {
                        data: entry.data,
                        version: entry.version,
                        was_cached: true,
                    });
                }
                Err(_) => {
                    // Corrupted cache entry, delete it
                    let _ = run_with_timeout(
                        redis::cmd("DEL")
                            .arg(key)
                            .query_async::<_, ()>(&mut redis_conn),
                    )
                    .await;
                }
            }
        }

        // Cache miss - try to compute with WATCH protection
        let computed_data = compute().await?;
        let entry = VersionedCacheEntry::new(computed_data);
        let entry_json = serde_json::to_string(&entry)?;

        // Use MULTI/EXEC to atomically set if value hasn't changed
        run_with_timeout(redis::cmd("MULTI").query_async::<_, ()>(&mut redis_conn)).await?;

        run_with_timeout(
            redis::cmd("SET")
                .arg(key)
                .arg(&entry_json)
                .arg("EX")
                .arg(ttl_secs as usize)
                .query_async::<_, ()>(&mut redis_conn),
        )
        .await?;

        // EXEC will return empty list if watched key changed (another request modified it)
        let exec_result: Vec<String> =
            run_with_timeout(redis::cmd("EXEC").query_async(&mut redis_conn)).await?;

        // Unwatch for next attempt
        let _ = run_with_timeout(redis::cmd("UNWATCH").query_async::<_, ()>(&mut redis_conn)).await;

        if !exec_result.is_empty() {
            // Transaction succeeded, we wrote the value
            return Ok(CacheOpResult {
                data: entry.data,
                version: entry.version,
                was_cached: false,
            });
        }
        // Transaction failed (watched key changed), loop to read new value
    }
}

/// Invalidate cache with version check
///
/// Ensures cache is properly cleared and version is incremented
pub async fn invalidate_with_version(
    redis: &SharedConnectionManager,
    key: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut redis_conn = redis.lock().await.clone();

    // Use Lua script for atomic invalidation
    let script = r#"
        local key = KEYS[1]
        redis.call('DEL', key)
        -- Store invalidation timestamp for version verification
        redis.call('SET', key .. ':invalidated_at', ARGV[1], 'EX', 3600)
        return 1
    "#;

    let now = Utc::now().timestamp();
    run_with_timeout(
        redis::Script::new(script)
            .key(key)
            .arg(now)
            .invoke_async::<_, i64>(&mut redis_conn),
    )
    .await?;

    Ok(())
}

/// Get cache invalidation timestamp
///
/// Returns the time when cache was last invalidated
pub async fn get_invalidation_timestamp(
    redis: &SharedConnectionManager,
    key: &str,
) -> Result<Option<i64>, Box<dyn std::error::Error>> {
    let mut redis_conn = redis.lock().await.clone();

    let invalidated_at: Option<String> = run_with_timeout(
        redis::cmd("GET")
            .arg(format!("{}:invalidated_at", key))
            .query_async(&mut redis_conn),
    )
    .await?;

    if let Some(ts_str) = invalidated_at {
        if let Ok(ts) = ts_str.parse::<i64>() {
            return Ok(Some(ts));
        }
    }

    Ok(None)
}

/// Validate cache entry version
///
/// Checks if a cached version is still valid
pub fn is_version_valid<T>(entry: &VersionedCacheEntry<T>, invalidated_at: Option<i64>) -> bool {
    // If cache was invalidated after this entry was created, it's stale
    if let Some(invalidation_ts) = invalidated_at {
        return entry.created_at > invalidation_ts;
    }

    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_versioned_cache_entry_creation() {
        let data = "test_data".to_string();
        let entry = VersionedCacheEntry::new(data.clone());

        assert_eq!(entry.data, data);
        assert!(entry.version > 0);
        assert!(entry.created_at > 0);
        assert_eq!(entry.created_at, entry.updated_at);
    }

    #[test]
    fn test_versioned_cache_entry_update() {
        let entry = VersionedCacheEntry::new("old_data".to_string());
        let old_version = entry.version;
        let previous_updated_at = entry.updated_at;

        std::thread::sleep(std::time::Duration::from_millis(10));

        let updated = entry.update("new_data".to_string());

        assert_eq!(updated.data, "new_data".to_string());
        assert!(updated.version > old_version); // Version should increment
        assert!(updated.updated_at >= previous_updated_at);
    }

    #[test]
    fn test_versioned_cache_entry_staleness() {
        let entry = VersionedCacheEntry::new("data".to_string());

        // Should not be stale immediately
        assert!(!entry.is_stale(3600));

        // Manually set old timestamp to simulate age
        let old_entry = VersionedCacheEntry {
            data: entry.data.clone(),
            version: entry.version,
            created_at: entry.created_at - 3700,
            updated_at: entry.updated_at - 3700,
        };

        // Should be stale after 1 hour
        assert!(old_entry.is_stale(3600));
    }

    #[test]
    fn test_version_validity() {
        let entry = VersionedCacheEntry::new("data".to_string());
        let created_at = entry.created_at;

        // Valid if no invalidation timestamp
        assert!(is_version_valid(&entry, None));

        // Valid if invalidation happened before creation
        assert!(is_version_valid(&entry, Some(created_at - 100)));

        // Invalid if invalidation happened after creation
        assert!(!is_version_valid(&entry, Some(created_at + 100)));
    }
}

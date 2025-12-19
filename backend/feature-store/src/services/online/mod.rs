use crate::error::{AppError, Result};
use redis::AsyncCommands;
use redis_utils::SharedConnectionManager;
use std::collections::HashMap;
use tracing::{error, info, warn};
use uuid::Uuid;

pub mod cache_warmer;

const FEATURE_KEY_PREFIX: &str = "feature";
const FEATURE_TTL_SECONDS: i64 = 7 * 24 * 60 * 60; // 7 days

/// OnlineFeatureStore provides hot feature cache with p99 < 5ms latency
///
/// **Architecture**:
/// - Redis ConnectionManager with connection pooling
/// - Feature key format: `feature:{user_id}:{feature_name}`
/// - TTL: 7 days for user features
/// - Batch operations optimized for feed rendering
///
/// **Usage**:
/// ```ignore
/// let store = OnlineFeatureStore::new(redis_manager);
///
/// // Get single user features
/// let features = store.get_features(user_id, &["engagement_score", "avg_session_time"]).await?;
///
/// // Batch get for multiple users (feed rendering)
/// let batch_features = store.batch_get_features(&user_ids, &["engagement_score"]).await?;
/// ```
pub struct OnlineFeatureStore {
    redis_manager: SharedConnectionManager,
}

impl OnlineFeatureStore {
    /// Create a new OnlineFeatureStore instance
    ///
    /// # Arguments
    /// * `redis_manager` - Shared Redis ConnectionManager from redis-utils
    pub fn new(redis_manager: SharedConnectionManager) -> Self {
        info!("Initializing OnlineFeatureStore with 7-day TTL");
        Self { redis_manager }
    }

    /// Get features for a single user
    ///
    /// # Arguments
    /// * `user_id` - Target user UUID
    /// * `feature_names` - Array of feature names to retrieve
    ///
    /// # Returns
    /// HashMap of feature_name -> value. Returns empty HashMap for cache misses (no error).
    ///
    /// # Errors
    /// Returns AppError::Redis on connection failures or timeout
    pub async fn get_features(
        &self,
        user_id: Uuid,
        feature_names: &[String],
    ) -> Result<HashMap<String, f64>> {
        if feature_names.is_empty() {
            return Ok(HashMap::new());
        }

        let mut conn = self.redis_manager.lock().await;
        let mut result = HashMap::new();

        for feature_name in feature_names {
            let key = format_feature_key(user_id, feature_name);

            match redis_utils::with_timeout(async { conn.get::<_, Option<String>>(&key).await })
                .await
            {
                Ok(Some(value)) => match value.parse::<f64>() {
                    Ok(val) => {
                        result.insert(feature_name.clone(), val);
                    }
                    Err(e) => {
                        warn!(
                            user_id = %user_id,
                            feature_name = %feature_name,
                            value = %value,
                            error = %e,
                            "Failed to parse feature value as f64"
                        );
                    }
                },
                Ok(None) => {
                    // Cache miss - normal behavior, don't log
                }
                Err(e) => {
                    error!(
                        user_id = %user_id,
                        feature_name = %feature_name,
                        error = %e,
                        "Redis error getting feature"
                    );
                    return Err(AppError::Redis(format!(
                        "Failed to get feature {}: {}",
                        feature_name, e
                    )));
                }
            }
        }

        Ok(result)
    }

    /// Batch get features for multiple users (optimized for feed rendering)
    ///
    /// # Arguments
    /// * `user_ids` - Array of user UUIDs
    /// * `feature_names` - Array of feature names to retrieve for each user
    ///
    /// # Returns
    /// HashMap of user_id -> (feature_name -> value). Cache misses return empty HashMap per user.
    ///
    /// # Errors
    /// Returns AppError::Redis on connection failures or timeout
    ///
    /// # Performance
    /// Uses Redis MGET for batch operations to minimize round trips.
    /// For 100 users × 5 features, this is ~20x faster than individual GET calls.
    pub async fn batch_get_features(
        &self,
        user_ids: &[Uuid],
        feature_names: &[String],
    ) -> Result<HashMap<Uuid, HashMap<String, f64>>> {
        if user_ids.is_empty() || feature_names.is_empty() {
            return Ok(HashMap::new());
        }

        let mut conn = self.redis_manager.lock().await;
        let mut result: HashMap<Uuid, HashMap<String, f64>> = HashMap::new();

        // Build all keys for MGET
        let mut keys = Vec::new();
        let mut key_mapping = Vec::new(); // (user_id, feature_name) tuples

        for user_id in user_ids {
            for feature_name in feature_names {
                keys.push(format_feature_key(*user_id, feature_name));
                key_mapping.push((*user_id, feature_name.clone()));
            }
        }

        // Execute MGET for all keys at once
        match redis_utils::with_timeout(async { conn.get::<_, Vec<Option<String>>>(&keys).await })
            .await
        {
            Ok(values) => {
                for (idx, value_opt) in values.into_iter().enumerate() {
                    if let Some(value) = value_opt {
                        let (user_id, feature_name) = &key_mapping[idx];

                        match value.parse::<f64>() {
                            Ok(val) => {
                                result
                                    .entry(*user_id)
                                    .or_default()
                                    .insert(feature_name.clone(), val);
                            }
                            Err(e) => {
                                warn!(
                                    user_id = %user_id,
                                    feature_name = %feature_name,
                                    value = %value,
                                    error = %e,
                                    "Failed to parse feature value in batch operation"
                                );
                            }
                        }
                    }
                }
            }
            Err(e) => {
                error!(
                    user_count = user_ids.len(),
                    feature_count = feature_names.len(),
                    error = %e,
                    "Redis error in batch_get_features"
                );
                return Err(AppError::Redis(format!(
                    "Failed to batch get features: {}",
                    e
                )));
            }
        }

        Ok(result)
    }

    /// Set a single feature value for a user
    ///
    /// # Arguments
    /// * `user_id` - Target user UUID
    /// * `feature_name` - Name of the feature
    /// * `value` - Feature value (f64)
    ///
    /// # TTL
    /// All features expire after 7 days
    ///
    /// # Errors
    /// Returns AppError::Redis on connection failures or timeout
    pub async fn set_feature(&self, user_id: Uuid, feature_name: String, value: f64) -> Result<()> {
        let key = format_feature_key(user_id, &feature_name);
        let value_str = value.to_string();
        let mut conn = self.redis_manager.lock().await;

        match redis_utils::with_timeout(async {
            conn.set_ex::<_, _, ()>(&key, &value_str, FEATURE_TTL_SECONDS as u64)
                .await
        })
        .await
        {
            Ok(_) => Ok(()),
            Err(e) => {
                error!(
                    user_id = %user_id,
                    feature_name = %feature_name,
                    error = %e,
                    "Redis error setting feature"
                );
                Err(AppError::Redis(format!(
                    "Failed to set feature {}: {}",
                    feature_name, e
                )))
            }
        }
    }

    /// Warm cache with multiple features for a user (background operation)
    ///
    /// # Arguments
    /// * `user_id` - Target user UUID
    /// * `features` - HashMap of feature_name -> value
    ///
    /// # Usage
    /// Typically called by cache_warmer background job to pre-populate hot features
    ///
    /// # TTL
    /// All features expire after 7 days
    ///
    /// # Errors
    /// Returns AppError::Redis on connection failures. Individual feature failures are logged but don't fail the entire operation.
    pub async fn warm_features(&self, user_id: Uuid, features: HashMap<String, f64>) -> Result<()> {
        if features.is_empty() {
            return Ok(());
        }

        let mut conn = self.redis_manager.lock().await;

        // Use pipeline for batch SET operations
        let mut pipe = redis::pipe();

        for (feature_name, value) in &features {
            let key = format_feature_key(user_id, feature_name);
            let value_str = value.to_string();
            pipe.set_ex(&key, &value_str, FEATURE_TTL_SECONDS as u64);
        }

        match redis_utils::with_timeout(async { pipe.query_async::<_, Vec<()>>(&mut *conn).await })
            .await
        {
            Ok(_) => {
                info!(
                    user_id = %user_id,
                    feature_count = features.len(),
                    "Successfully warmed features"
                );
                Ok(())
            }
            Err(e) => {
                error!(
                    user_id = %user_id,
                    feature_count = features.len(),
                    error = %e,
                    "Failed to warm features"
                );
                Err(AppError::Redis(format!("Failed to warm features: {}", e)))
            }
        }
    }

    /// Delete features for a user (used when user is deleted)
    ///
    /// # Arguments
    /// * `user_id` - Target user UUID
    /// * `feature_names` - Optional array of specific features to delete. If None, deletes all features for user.
    ///
    /// # Errors
    /// Returns AppError::Redis on connection failures or timeout
    pub async fn delete_features(
        &self,
        user_id: Uuid,
        feature_names: Option<&[String]>,
    ) -> Result<()> {
        let mut conn = self.redis_manager.lock().await;

        match feature_names {
            Some(names) => {
                // Delete specific features
                let keys: Vec<String> = names
                    .iter()
                    .map(|name| format_feature_key(user_id, name))
                    .collect();

                match redis_utils::with_timeout(async { conn.del::<_, ()>(&keys).await }).await {
                    Ok(_) => {
                        info!(
                            user_id = %user_id,
                            feature_count = names.len(),
                            "Deleted specific features"
                        );
                        Ok(())
                    }
                    Err(e) => {
                        error!(
                            user_id = %user_id,
                            error = %e,
                            "Failed to delete features"
                        );
                        Err(AppError::Redis(format!("Failed to delete features: {}", e)))
                    }
                }
            }
            None => {
                // Delete all features for user using SCAN + DEL pattern
                let pattern = format!("{}:{}:*", FEATURE_KEY_PREFIX, user_id);

                // Use SCAN to find keys (safer than KEYS *)
                match redis_utils::with_timeout(async {
                    let mut keys_to_delete = Vec::new();
                    let mut cursor = 0;

                    loop {
                        let (new_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                            .arg(cursor)
                            .arg("MATCH")
                            .arg(&pattern)
                            .arg("COUNT")
                            .arg(100)
                            .query_async(&mut *conn)
                            .await?;

                        keys_to_delete.extend(keys);
                        cursor = new_cursor;

                        if cursor == 0 {
                            break;
                        }
                    }

                    if !keys_to_delete.is_empty() {
                        conn.del::<_, ()>(&keys_to_delete).await?;
                    }

                    Ok::<usize, redis::RedisError>(keys_to_delete.len())
                })
                .await
                {
                    Ok(count) => {
                        info!(
                            user_id = %user_id,
                            deleted_count = count,
                            "Deleted all features for user"
                        );
                        Ok(())
                    }
                    Err(e) => {
                        error!(
                            user_id = %user_id,
                            error = %e,
                            "Failed to delete all features"
                        );
                        Err(AppError::Redis(format!(
                            "Failed to delete all features: {}",
                            e
                        )))
                    }
                }
            }
        }
    }

    /// Get cache statistics for monitoring
    ///
    /// # Returns
    /// HashMap with:
    /// - "total_keys": Total feature keys in Redis
    /// - "memory_used": Approximate memory used by features
    pub async fn get_stats(&self) -> Result<HashMap<String, i64>> {
        let mut conn = self.redis_manager.lock().await;
        let mut stats = HashMap::new();

        // Get approximate key count
        match redis_utils::with_timeout(async {
            let pattern = format!("{}:*", FEATURE_KEY_PREFIX);
            let mut cursor = 0;
            let mut total_keys = 0;

            loop {
                let (new_cursor, keys): (u64, Vec<String>) = redis::cmd("SCAN")
                    .arg(cursor)
                    .arg("MATCH")
                    .arg(&pattern)
                    .arg("COUNT")
                    .arg(1000)
                    .query_async(&mut *conn)
                    .await?;

                total_keys += keys.len();
                cursor = new_cursor;

                if cursor == 0 {
                    break;
                }
            }

            Ok::<i64, redis::RedisError>(total_keys as i64)
        })
        .await
        {
            Ok(count) => {
                stats.insert("total_keys".to_string(), count);
            }
            Err(e) => {
                warn!(error = %e, "Failed to get key count for stats");
                stats.insert("total_keys".to_string(), -1);
            }
        }

        // Get memory info
        match redis_utils::with_timeout(async {
            let info: String = redis::cmd("INFO")
                .arg("memory")
                .query_async(&mut *conn)
                .await?;
            Ok::<String, redis::RedisError>(info)
        })
        .await
        {
            Ok(info) => {
                // Parse used_memory from INFO output
                for line in info.lines() {
                    if line.starts_with("used_memory:") {
                        if let Some(value) = line.split(':').nth(1) {
                            if let Ok(memory) = value.trim().parse::<i64>() {
                                stats.insert("memory_used".to_string(), memory);
                            }
                        }
                    }
                }
            }
            Err(e) => {
                warn!(error = %e, "Failed to get memory info");
            }
        }

        Ok(stats)
    }
}

/// Format Redis key for a feature
///
/// Format: `feature:{user_id}:{feature_name}`
fn format_feature_key(user_id: Uuid, feature_name: &str) -> String {
    format!("{}:{}:{}", FEATURE_KEY_PREFIX, user_id, feature_name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_feature_key() {
        let user_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let key = format_feature_key(user_id, "engagement_score");
        assert_eq!(
            key,
            "feature:550e8400-e29b-41d4-a716-446655440000:engagement_score"
        );
    }

    #[test]
    fn test_format_feature_key_special_chars() {
        let user_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let key = format_feature_key(user_id, "avg_session:time");
        assert_eq!(
            key,
            "feature:550e8400-e29b-41d4-a716-446655440000:avg_session:time"
        );
    }
}

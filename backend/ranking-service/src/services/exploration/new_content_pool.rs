// ============================================
// New Content Pool Manager
// ============================================
//
// Manages the exploration pool for new/untested content
// Backed by Redis for real-time updates
//
// Data Flow:
// 1. New content uploaded → Added to exploration pool
// 2. UCB algorithm selects content for display
// 3. Engagement events update pool statistics
// 4. Content graduates to main pool after sufficient data

use super::{ucb::UCBExplorer, ExplorationError, Result};
use chrono::{DateTime, Utc};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use tracing::{debug, info};
use uuid::Uuid;

/// Entry in the new content exploration pool
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewContentEntry {
    pub content_id: Uuid,
    pub author_id: Uuid,
    pub upload_time: DateTime<Utc>,
    pub impressions: u32,
    pub engagements: u32,
    /// UCB score (updated periodically)
    pub ucb_score: f64,
    /// Whether content is still active in exploration
    pub is_active: bool,
}

impl NewContentEntry {
    pub fn new(content_id: Uuid, author_id: Uuid) -> Self {
        Self {
            content_id,
            author_id,
            upload_time: Utc::now(),
            impressions: 0,
            engagements: 0,
            ucb_score: f64::MAX, // New content gets maximum exploration priority
            is_active: true,
        }
    }

    pub fn engagement_rate(&self) -> f64 {
        if self.impressions > 0 {
            self.engagements as f64 / self.impressions as f64
        } else {
            0.0
        }
    }
}

/// Redis-backed new content pool manager
pub struct NewContentPool {
    redis: redis::Client,
    ucb_explorer: UCBExplorer,
    /// Maximum age for content in exploration pool (hours)
    max_content_age_hours: i64,
    /// Redis key prefix
    key_prefix: String,
}

impl NewContentPool {
    /// Redis keys:
    /// - {prefix}:pool - Sorted set of content_id by UCB score
    /// - {prefix}:entry:{content_id} - Hash with entry details
    /// - {prefix}:total_impressions - Total impressions counter
    const POOL_KEY_SUFFIX: &'static str = ":pool";
    const ENTRY_KEY_PREFIX: &'static str = ":entry:";
    const TOTAL_IMPRESSIONS_KEY: &'static str = ":total_impressions";

    pub fn new(redis: redis::Client) -> Self {
        Self {
            redis,
            ucb_explorer: UCBExplorer::default(),
            max_content_age_hours: 168, // 7 days
            key_prefix: "exploration".to_string(),
        }
    }

    /// Create with custom UCB explorer
    pub fn with_ucb_explorer(mut self, explorer: UCBExplorer) -> Self {
        self.ucb_explorer = explorer;
        self
    }

    /// Create with custom key prefix
    pub fn with_key_prefix(mut self, prefix: &str) -> Self {
        self.key_prefix = prefix.to_string();
        self
    }

    fn pool_key(&self) -> String {
        format!("{}{}", self.key_prefix, Self::POOL_KEY_SUFFIX)
    }

    fn entry_key(&self, content_id: &Uuid) -> String {
        format!(
            "{}{}{}",
            self.key_prefix,
            Self::ENTRY_KEY_PREFIX,
            content_id
        )
    }

    fn total_impressions_key(&self) -> String {
        format!("{}{}", self.key_prefix, Self::TOTAL_IMPRESSIONS_KEY)
    }

    /// Add new content to exploration pool
    pub async fn add_content(&self, content_id: Uuid, author_id: Uuid) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        let entry = NewContentEntry::new(content_id, author_id);
        let entry_json = serde_json::to_string(&entry)
            .map_err(|e| ExplorationError::PoolError(e.to_string()))?;

        // Add to sorted set with UCB score
        let _: () = conn
            .zadd(self.pool_key(), &content_id.to_string(), entry.ucb_score)
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Store entry details
        let _: () = conn
            .set_ex(
                self.entry_key(&content_id),
                entry_json,
                self.max_content_age_hours as u64 * 3600,
            )
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        info!(
            content_id = %content_id,
            author_id = %author_id,
            "Added content to exploration pool"
        );

        Ok(())
    }

    /// Record an impression for content
    pub async fn record_impression(&self, content_id: Uuid) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Get current entry
        let entry_json: Option<String> = conn
            .get(self.entry_key(&content_id))
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        if let Some(json) = entry_json {
            let mut entry: NewContentEntry = serde_json::from_str(&json)
                .map_err(|e| ExplorationError::PoolError(e.to_string()))?;

            entry.impressions += 1;

            // Update entry
            let updated_json = serde_json::to_string(&entry)
                .map_err(|e| ExplorationError::PoolError(e.to_string()))?;
            let _: () = conn
                .set_ex(
                    self.entry_key(&content_id),
                    updated_json,
                    self.max_content_age_hours as u64 * 3600,
                )
                .await
                .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

            // Increment total impressions
            let _: () = conn
                .incr(self.total_impressions_key(), 1i64)
                .await
                .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

            debug!(
                content_id = %content_id,
                impressions = entry.impressions,
                "Recorded impression"
            );
        }

        Ok(())
    }

    /// Record an engagement (like, comment, share, completion)
    pub async fn record_engagement(&self, content_id: Uuid) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Get current entry
        let entry_json: Option<String> = conn
            .get(self.entry_key(&content_id))
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        if let Some(json) = entry_json {
            let mut entry: NewContentEntry = serde_json::from_str(&json)
                .map_err(|e| ExplorationError::PoolError(e.to_string()))?;

            entry.engagements += 1;

            // Update entry
            let updated_json = serde_json::to_string(&entry)
                .map_err(|e| ExplorationError::PoolError(e.to_string()))?;
            let _: () = conn
                .set_ex(
                    self.entry_key(&content_id),
                    updated_json,
                    self.max_content_age_hours as u64 * 3600,
                )
                .await
                .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

            debug!(
                content_id = %content_id,
                engagements = entry.engagements,
                "Recorded engagement"
            );
        }

        Ok(())
    }

    /// Sample content using UCB algorithm
    pub async fn sample_by_ucb(&self, count: usize) -> Result<Vec<Uuid>> {
        if count == 0 {
            return Ok(Vec::new());
        }

        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Get top content by UCB score (stored in sorted set)
        let content_ids: Vec<String> = conn
            .zrevrange(self.pool_key(), 0, (count * 2) as isize)
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Parse UUIDs
        let result: Vec<Uuid> = content_ids
            .iter()
            .filter_map(|s| Uuid::parse_str(s).ok())
            .take(count)
            .collect();

        info!(
            requested = count,
            returned = result.len(),
            "Sampled content from exploration pool"
        );

        Ok(result)
    }

    /// Update UCB scores for all content in pool
    /// Should be called periodically (e.g., every minute)
    pub async fn refresh_ucb_scores(&self) -> Result<usize> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Get total impressions
        let total_impressions: u32 = conn.get(self.total_impressions_key()).await.unwrap_or(0);

        // Get all content in pool
        let content_ids: Vec<String> = conn
            .zrange(self.pool_key(), 0, -1)
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        let mut updated_count = 0;

        for content_id_str in &content_ids {
            let content_id = match Uuid::parse_str(content_id_str) {
                Ok(id) => id,
                Err(_) => continue,
            };

            // Get entry
            let entry_json: Option<String> = conn
                .get(self.entry_key(&content_id))
                .await
                .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

            if let Some(json) = entry_json {
                let mut entry: NewContentEntry = match serde_json::from_str(&json) {
                    Ok(e) => e,
                    Err(_) => continue,
                };

                // Compute new UCB score
                entry.ucb_score = self.ucb_explorer.ucb_score(
                    entry.impressions,
                    entry.engagements,
                    total_impressions,
                );

                // Update score in sorted set
                let _: () = conn
                    .zadd(self.pool_key(), content_id_str, entry.ucb_score)
                    .await
                    .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

                // Update entry
                if let Ok(updated_json) = serde_json::to_string(&entry) {
                    let _: () = conn
                        .set_ex(
                            self.entry_key(&content_id),
                            updated_json,
                            self.max_content_age_hours as u64 * 3600,
                        )
                        .await
                        .unwrap_or(());
                }

                updated_count += 1;
            }
        }

        info!(
            updated = updated_count,
            total_pool_size = content_ids.len(),
            total_impressions = total_impressions,
            "Refreshed UCB scores"
        );

        Ok(updated_count)
    }

    /// Get entry details for content
    pub async fn get_entry(&self, content_id: Uuid) -> Result<Option<NewContentEntry>> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        let entry_json: Option<String> = conn
            .get(self.entry_key(&content_id))
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        match entry_json {
            Some(json) => {
                let entry: NewContentEntry = serde_json::from_str(&json)
                    .map_err(|e| ExplorationError::PoolError(e.to_string()))?;
                Ok(Some(entry))
            }
            None => Ok(None),
        }
    }

    /// Remove content from exploration pool (graduation or removal)
    pub async fn remove_content(&self, content_id: Uuid) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Remove from sorted set
        let _: () = conn
            .zrem(self.pool_key(), &content_id.to_string())
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        // Remove entry (optional, will expire anyway)
        let _: () = conn
            .del(self.entry_key(&content_id))
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        info!(content_id = %content_id, "Removed content from exploration pool");

        Ok(())
    }

    /// Get pool size
    pub async fn pool_size(&self) -> Result<usize> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        let size: usize = conn
            .zcard(self.pool_key())
            .await
            .map_err(|e| ExplorationError::RedisError(e.to_string()))?;

        Ok(size)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_content_entry() {
        let content_id = Uuid::new_v4();
        let author_id = Uuid::new_v4();

        let entry = NewContentEntry::new(content_id, author_id);

        assert_eq!(entry.content_id, content_id);
        assert_eq!(entry.author_id, author_id);
        assert_eq!(entry.impressions, 0);
        assert_eq!(entry.engagements, 0);
        assert!(entry.is_active);
        assert_eq!(entry.ucb_score, f64::MAX);
    }

    #[test]
    fn test_engagement_rate() {
        let mut entry = NewContentEntry::new(Uuid::new_v4(), Uuid::new_v4());

        // No impressions
        assert_eq!(entry.engagement_rate(), 0.0);

        // With data
        entry.impressions = 100;
        entry.engagements = 10;
        assert!((entry.engagement_rate() - 0.1).abs() < 0.01);
    }
}

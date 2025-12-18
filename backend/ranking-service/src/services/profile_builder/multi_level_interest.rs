// ============================================
// Multi-Level Interest Model (多层次兴趣模型)
// ============================================
//
// P2-1: Three-tiered interest architecture
//
// Layer Structure:
// ┌──────────────────┐  Weight: 0.40  Decay: 30 minutes
// │  Realtime (RT)   │  Redis ZSET, TTL 2h
// ├──────────────────┤
// │  Short-Term (ST) │  Weight: 0.35  Decay: 24 hours
// │                  │  Redis Hash, TTL 7d
// ├──────────────────┤
// │  Long-Term (LT)  │  Weight: 0.25  Decay: 30 days
// │                  │  ClickHouse + Redis
// └──────────────────┘
//
// Combined Score = 0.40*RT + 0.35*ST + 0.25*LT

use chrono::{DateTime, Utc};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::{debug, info};
use uuid::Uuid;

use super::{ProfileBuilderError, Result};

/// Configuration for multi-level interest model
#[derive(Debug, Clone)]
pub struct MultiLevelConfig {
    /// Realtime layer weight (default: 0.40)
    pub realtime_weight: f32,
    /// Short-term layer weight (default: 0.35)
    pub short_term_weight: f32,
    /// Long-term layer weight (default: 0.25)
    pub long_term_weight: f32,

    /// Realtime decay half-life in minutes (default: 30)
    pub realtime_decay_minutes: f32,
    /// Short-term decay half-life in hours (default: 24)
    pub short_term_decay_hours: f32,
    /// Long-term decay half-life in days (default: 30)
    pub long_term_decay_days: f32,

    /// Realtime TTL in seconds (default: 7200 = 2h)
    pub realtime_ttl_secs: u64,
    /// Short-term TTL in seconds (default: 604800 = 7d)
    pub short_term_ttl_secs: u64,
    /// Long-term TTL in seconds (default: 7776000 = 90d)
    pub long_term_ttl_secs: u64,

    /// Maximum interests per layer
    pub max_interests_per_layer: usize,
    /// Minimum weight threshold to keep
    pub min_weight_threshold: f32,
}

impl Default for MultiLevelConfig {
    fn default() -> Self {
        Self {
            realtime_weight: 0.40,
            short_term_weight: 0.35,
            long_term_weight: 0.25,

            realtime_decay_minutes: 30.0,
            short_term_decay_hours: 24.0,
            long_term_decay_days: 30.0,

            realtime_ttl_secs: 7200,        // 2 hours
            short_term_ttl_secs: 604800,    // 7 days
            long_term_ttl_secs: 7776000,    // 90 days

            max_interests_per_layer: 50,
            min_weight_threshold: 0.01,
        }
    }
}

/// Interest level enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum InterestLevel {
    Realtime,
    ShortTerm,
    LongTerm,
}

impl InterestLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            InterestLevel::Realtime => "rt",
            InterestLevel::ShortTerm => "st",
            InterestLevel::LongTerm => "lt",
        }
    }
}

/// Interest entry with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InterestEntry {
    pub tag: String,
    pub weight: f32,
    pub raw_score: f32,
    pub level: InterestLevel,
    pub interaction_count: u32,
    pub last_updated: DateTime<Utc>,
}

/// Combined interest with scores from all levels
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CombinedInterest {
    pub tag: String,
    pub combined_score: f32,
    pub realtime_score: f32,
    pub short_term_score: f32,
    pub long_term_score: f32,
    pub trend: InterestTrend,
}

/// Interest trend indicator
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum InterestTrend {
    /// Interest is growing (RT > ST > LT)
    Rising,
    /// Interest is stable (scores similar)
    Stable,
    /// Interest is declining (RT < ST < LT)
    Declining,
    /// Interest is new (no LT data)
    New,
}

/// Multi-level interest model manager
pub struct MultiLevelInterestModel {
    redis: redis::Client,
    config: MultiLevelConfig,
}

impl MultiLevelInterestModel {
    pub fn new(redis: redis::Client, config: MultiLevelConfig) -> Self {
        Self { redis, config }
    }

    pub fn with_default_config(redis: redis::Client) -> Self {
        Self::new(redis, MultiLevelConfig::default())
    }

    // ============================================
    // Redis Key Generation
    // ============================================

    fn realtime_key(&self, user_id: Uuid) -> String {
        format!("interest:rt:{}", user_id)
    }

    fn short_term_key(&self, user_id: Uuid) -> String {
        format!("interest:st:{}", user_id)
    }

    fn long_term_key(&self, user_id: Uuid) -> String {
        format!("interest:lt:{}", user_id)
    }

    fn interest_meta_key(&self, user_id: Uuid, level: InterestLevel, tag: &str) -> String {
        format!("interest:meta:{}:{}:{}", level.as_str(), user_id, tag)
    }

    // ============================================
    // Interest Updates
    // ============================================

    /// Record an interest signal at all levels
    ///
    /// The signal propagates to all three layers with different decay rates
    pub async fn record_interest(
        &self,
        user_id: Uuid,
        tags: &[String],
        engagement_weight: f32,
    ) -> Result<()> {
        if tags.is_empty() {
            return Ok(());
        }

        let mut conn = self.redis.get_multiplexed_async_connection().await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        let now = Utc::now();

        for tag in tags {
            // Update realtime layer (ZSET with score increment)
            let rt_key = self.realtime_key(user_id);
            let _: () = conn.zincr(&rt_key, tag, engagement_weight as f64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
            let _: () = conn.expire(&rt_key, self.config.realtime_ttl_secs as i64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

            // Update short-term layer (ZSET with time-decayed score)
            let st_key = self.short_term_key(user_id);
            let _: () = conn.zincr(&st_key, tag, engagement_weight as f64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
            let _: () = conn.expire(&st_key, self.config.short_term_ttl_secs as i64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

            // Update long-term layer (ZSET with slower accumulation)
            let lt_key = self.long_term_key(user_id);
            // Long-term uses smaller increments for stability
            let lt_weight = engagement_weight * 0.3;
            let _: () = conn.zincr(&lt_key, tag, lt_weight as f64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
            let _: () = conn.expire(&lt_key, self.config.long_term_ttl_secs as i64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

            // Update metadata
            let meta_key = self.interest_meta_key(user_id, InterestLevel::Realtime, tag);
            let _: () = conn.hset(&meta_key, "last_updated", now.timestamp()).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
            let _: () = conn.hincr(&meta_key, "interaction_count", 1).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
            let _: () = conn.expire(&meta_key, self.config.long_term_ttl_secs as i64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
        }

        // Trim each layer to max size
        self.trim_layer(user_id, InterestLevel::Realtime).await?;
        self.trim_layer(user_id, InterestLevel::ShortTerm).await?;
        self.trim_layer(user_id, InterestLevel::LongTerm).await?;

        debug!(
            user_id = %user_id,
            tags_count = tags.len(),
            weight = engagement_weight,
            "Recorded multi-level interest"
        );

        Ok(())
    }

    /// Record a negative signal (skip, not interested)
    pub async fn record_negative_signal(
        &self,
        user_id: Uuid,
        tags: &[String],
        negative_weight: f32,
    ) -> Result<()> {
        // Negative signals primarily affect realtime and short-term
        // Long-term should be more stable
        if tags.is_empty() {
            return Ok(());
        }

        let mut conn = self.redis.get_multiplexed_async_connection().await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        for tag in tags {
            // Strong negative on realtime
            let rt_key = self.realtime_key(user_id);
            let _: () = conn.zincr(&rt_key, tag, negative_weight as f64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

            // Moderate negative on short-term
            let st_key = self.short_term_key(user_id);
            let _: () = conn.zincr(&st_key, tag, (negative_weight * 0.5) as f64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

            // Weak negative on long-term (for stability)
            let lt_key = self.long_term_key(user_id);
            let _: () = conn.zincr(&lt_key, tag, (negative_weight * 0.1) as f64).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
        }

        debug!(
            user_id = %user_id,
            tags_count = tags.len(),
            weight = negative_weight,
            "Recorded negative signal"
        );

        Ok(())
    }

    /// Trim a layer to max size
    async fn trim_layer(&self, user_id: Uuid, level: InterestLevel) -> Result<()> {
        let mut conn = self.redis.get_multiplexed_async_connection().await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        let key = match level {
            InterestLevel::Realtime => self.realtime_key(user_id),
            InterestLevel::ShortTerm => self.short_term_key(user_id),
            InterestLevel::LongTerm => self.long_term_key(user_id),
        };

        let size: usize = conn.zcard(&key).await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        if size > self.config.max_interests_per_layer {
            let remove_count = size - self.config.max_interests_per_layer;
            let _: () = conn.zremrangebyrank(&key, 0, (remove_count - 1) as isize).await
                .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
        }

        Ok(())
    }

    // ============================================
    // Interest Retrieval
    // ============================================

    /// Get interests from a specific layer
    pub async fn get_layer_interests(
        &self,
        user_id: Uuid,
        level: InterestLevel,
        limit: usize,
    ) -> Result<Vec<(String, f32)>> {
        let mut conn = self.redis.get_multiplexed_async_connection().await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        let key = match level {
            InterestLevel::Realtime => self.realtime_key(user_id),
            InterestLevel::ShortTerm => self.short_term_key(user_id),
            InterestLevel::LongTerm => self.long_term_key(user_id),
        };

        let interests: Vec<(String, f64)> = conn
            .zrevrange_withscores(&key, 0, (limit - 1) as isize)
            .await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        Ok(interests.into_iter().map(|(tag, score)| (tag, score as f32)).collect())
    }

    /// Get combined interests with weighted scores from all layers
    ///
    /// This is the main method for ranking/recall to use
    pub async fn get_combined_interests(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<CombinedInterest>> {
        // Fetch from all layers
        let rt_interests = self.get_layer_interests(user_id, InterestLevel::Realtime, 50).await?;
        let st_interests = self.get_layer_interests(user_id, InterestLevel::ShortTerm, 50).await?;
        let lt_interests = self.get_layer_interests(user_id, InterestLevel::LongTerm, 50).await?;

        // Normalize each layer
        let rt_normalized = self.normalize_scores(&rt_interests);
        let st_normalized = self.normalize_scores(&st_interests);
        let lt_normalized = self.normalize_scores(&lt_interests);

        // Combine all tags
        let mut combined: HashMap<String, CombinedInterest> = HashMap::new();

        // Add realtime interests
        for (tag, score) in &rt_normalized {
            combined.insert(tag.clone(), CombinedInterest {
                tag: tag.clone(),
                combined_score: 0.0,
                realtime_score: *score,
                short_term_score: 0.0,
                long_term_score: 0.0,
                trend: InterestTrend::New,
            });
        }

        // Add short-term interests
        for (tag, score) in &st_normalized {
            combined.entry(tag.clone())
                .and_modify(|e| e.short_term_score = *score)
                .or_insert(CombinedInterest {
                    tag: tag.clone(),
                    combined_score: 0.0,
                    realtime_score: 0.0,
                    short_term_score: *score,
                    long_term_score: 0.0,
                    trend: InterestTrend::Stable,
                });
        }

        // Add long-term interests
        for (tag, score) in &lt_normalized {
            combined.entry(tag.clone())
                .and_modify(|e| e.long_term_score = *score)
                .or_insert(CombinedInterest {
                    tag: tag.clone(),
                    combined_score: 0.0,
                    realtime_score: 0.0,
                    short_term_score: 0.0,
                    long_term_score: *score,
                    trend: InterestTrend::Stable,
                });
        }

        // Calculate combined scores and trends
        let mut result: Vec<CombinedInterest> = combined.into_values()
            .map(|mut interest| {
                // Weighted combination
                interest.combined_score =
                    self.config.realtime_weight * interest.realtime_score +
                    self.config.short_term_weight * interest.short_term_score +
                    self.config.long_term_weight * interest.long_term_score;

                // Determine trend
                interest.trend = self.compute_trend(
                    interest.realtime_score,
                    interest.short_term_score,
                    interest.long_term_score,
                );

                interest
            })
            .filter(|i| i.combined_score >= self.config.min_weight_threshold)
            .collect();

        // Sort by combined score
        result.sort_by(|a, b| b.combined_score.partial_cmp(&a.combined_score)
            .unwrap_or(std::cmp::Ordering::Equal));

        result.truncate(limit);

        Ok(result)
    }

    /// Normalize scores to 0-1 range
    fn normalize_scores(&self, scores: &[(String, f32)]) -> Vec<(String, f32)> {
        if scores.is_empty() {
            return Vec::new();
        }

        let max_score = scores.iter()
            .map(|(_, s)| s.abs())
            .fold(0.0f32, f32::max);

        if max_score == 0.0 {
            return scores.iter()
                .map(|(tag, _)| (tag.clone(), 0.0))
                .collect();
        }

        scores.iter()
            .map(|(tag, score)| (tag.clone(), *score / max_score))
            .collect()
    }

    /// Compute interest trend from layer scores
    fn compute_trend(&self, rt: f32, st: f32, lt: f32) -> InterestTrend {
        // If no long-term data, it's new
        if lt < 0.01 {
            return InterestTrend::New;
        }

        let rt_ratio = if st > 0.01 { rt / st } else { 1.0 };
        let st_ratio = if lt > 0.01 { st / lt } else { 1.0 };

        // Rising: RT significantly > ST, or ST significantly > LT
        if rt_ratio > 1.3 || st_ratio > 1.3 {
            return InterestTrend::Rising;
        }

        // Declining: RT significantly < ST, or ST significantly < LT
        if rt_ratio < 0.7 || st_ratio < 0.7 {
            return InterestTrend::Declining;
        }

        InterestTrend::Stable
    }

    // ============================================
    // Utility Methods
    // ============================================

    /// Get interest score for a specific tag
    pub async fn get_interest_score(
        &self,
        user_id: Uuid,
        tag: &str,
    ) -> Result<CombinedInterest> {
        let mut conn = self.redis.get_multiplexed_async_connection().await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        let rt_score: Option<f64> = conn.zscore(self.realtime_key(user_id), tag).await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
        let st_score: Option<f64> = conn.zscore(self.short_term_key(user_id), tag).await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
        let lt_score: Option<f64> = conn.zscore(self.long_term_key(user_id), tag).await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        let rt = rt_score.unwrap_or(0.0) as f32;
        let st = st_score.unwrap_or(0.0) as f32;
        let lt = lt_score.unwrap_or(0.0) as f32;

        let combined = self.config.realtime_weight * rt +
            self.config.short_term_weight * st +
            self.config.long_term_weight * lt;

        Ok(CombinedInterest {
            tag: tag.to_string(),
            combined_score: combined,
            realtime_score: rt,
            short_term_score: st,
            long_term_score: lt,
            trend: self.compute_trend(rt, st, lt),
        })
    }

    /// Compute interest match score for content
    ///
    /// Returns 0.0 - 1.0, where higher means better match
    pub async fn compute_interest_match(
        &self,
        user_id: Uuid,
        content_tags: &[String],
    ) -> Result<f32> {
        if content_tags.is_empty() {
            return Ok(0.5); // Neutral
        }

        let interests = self.get_combined_interests(user_id, 30).await?;
        if interests.is_empty() {
            return Ok(0.5); // No interests, neutral
        }

        let mut matched_score = 0.0f32;
        let mut total_score = 0.0f32;

        for interest in &interests {
            total_score += interest.combined_score;
            if content_tags.iter().any(|t| t == &interest.tag) {
                matched_score += interest.combined_score;

                // Bonus for rising trends
                if interest.trend == InterestTrend::Rising {
                    matched_score += interest.combined_score * 0.2;
                }
            }
        }

        if total_score == 0.0 {
            return Ok(0.5);
        }

        // Normalize to 0.0 - 1.0
        let score = (matched_score / total_score).min(1.0).max(0.0);

        Ok(score)
    }

    /// Apply time decay to all layers (run periodically)
    pub async fn apply_decay(&self, user_id: Uuid) -> Result<()> {
        let mut conn = self.redis.get_multiplexed_async_connection().await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        let _now = Utc::now();

        // Realtime decay (aggressive)
        let rt_decay = 0.9; // 10% decay
        self.apply_layer_decay(&mut conn, user_id, InterestLevel::Realtime, rt_decay).await?;

        // Short-term decay (moderate)
        let st_decay = 0.95; // 5% decay
        self.apply_layer_decay(&mut conn, user_id, InterestLevel::ShortTerm, st_decay).await?;

        // Long-term decay (gentle)
        let lt_decay = 0.99; // 1% decay
        self.apply_layer_decay(&mut conn, user_id, InterestLevel::LongTerm, lt_decay).await?;

        debug!(user_id = %user_id, "Applied time decay to interests");

        Ok(())
    }

    async fn apply_layer_decay(
        &self,
        conn: &mut redis::aio::MultiplexedConnection,
        user_id: Uuid,
        level: InterestLevel,
        decay_factor: f32,
    ) -> Result<()> {
        let key = match level {
            InterestLevel::Realtime => self.realtime_key(user_id),
            InterestLevel::ShortTerm => self.short_term_key(user_id),
            InterestLevel::LongTerm => self.long_term_key(user_id),
        };

        // Get all members
        let members: Vec<(String, f64)> = conn.zrange_withscores(&key, 0, -1).await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        // Apply decay
        for (tag, score) in members {
            let new_score = score * decay_factor as f64;
            if new_score.abs() < self.config.min_weight_threshold as f64 {
                // Remove if below threshold
                let _: () = conn.zrem(&key, &tag).await
                    .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
            } else {
                let _: () = conn.zadd(&key, &tag, new_score).await
                    .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;
            }
        }

        Ok(())
    }

    /// Clear all interests for a user (for testing or reset)
    pub async fn clear_all(&self, user_id: Uuid) -> Result<()> {
        let mut conn = self.redis.get_multiplexed_async_connection().await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        let _: () = conn.del(&[
            self.realtime_key(user_id),
            self.short_term_key(user_id),
            self.long_term_key(user_id),
        ]).await
            .map_err(|e| ProfileBuilderError::StorageError(e.to_string()))?;

        info!(user_id = %user_id, "Cleared all interests");

        Ok(())
    }

    /// Get statistics about user's interest distribution
    pub async fn get_interest_stats(&self, user_id: Uuid) -> Result<InterestStats> {
        let rt = self.get_layer_interests(user_id, InterestLevel::Realtime, 100).await?;
        let st = self.get_layer_interests(user_id, InterestLevel::ShortTerm, 100).await?;
        let lt = self.get_layer_interests(user_id, InterestLevel::LongTerm, 100).await?;

        let combined = self.get_combined_interests(user_id, 100).await?;

        let rising_count = combined.iter()
            .filter(|i| i.trend == InterestTrend::Rising)
            .count();
        let declining_count = combined.iter()
            .filter(|i| i.trend == InterestTrend::Declining)
            .count();

        Ok(InterestStats {
            realtime_count: rt.len(),
            short_term_count: st.len(),
            long_term_count: lt.len(),
            combined_count: combined.len(),
            rising_interests: rising_count,
            declining_interests: declining_count,
            top_interests: combined.into_iter()
                .take(10)
                .map(|i| (i.tag, i.combined_score))
                .collect(),
        })
    }
}

/// Interest statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InterestStats {
    pub realtime_count: usize,
    pub short_term_count: usize,
    pub long_term_count: usize,
    pub combined_count: usize,
    pub rising_interests: usize,
    pub declining_interests: usize,
    pub top_interests: Vec<(String, f32)>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_weights_sum_to_one() {
        let config = MultiLevelConfig::default();
        let sum = config.realtime_weight + config.short_term_weight + config.long_term_weight;
        assert!((sum - 1.0).abs() < 0.001, "Weights should sum to 1.0");
    }

    #[test]
    fn test_interest_level_as_str() {
        assert_eq!(InterestLevel::Realtime.as_str(), "rt");
        assert_eq!(InterestLevel::ShortTerm.as_str(), "st");
        assert_eq!(InterestLevel::LongTerm.as_str(), "lt");
    }

    #[test]
    fn test_trend_computation() {
        let model = MultiLevelInterestModel {
            redis: redis::Client::open("redis://127.0.0.1/").unwrap(),
            config: MultiLevelConfig::default(),
        };

        // Rising trend: RT >> ST
        assert_eq!(model.compute_trend(1.0, 0.5, 0.3), InterestTrend::Rising);

        // Declining trend: RT << ST
        assert_eq!(model.compute_trend(0.3, 0.6, 0.8), InterestTrend::Declining);

        // Stable trend
        assert_eq!(model.compute_trend(0.5, 0.5, 0.5), InterestTrend::Stable);

        // New interest (no LT)
        assert_eq!(model.compute_trend(1.0, 0.5, 0.0), InterestTrend::New);
    }

    #[test]
    fn test_normalize_scores() {
        let model = MultiLevelInterestModel {
            redis: redis::Client::open("redis://127.0.0.1/").unwrap(),
            config: MultiLevelConfig::default(),
        };

        let scores = vec![
            ("music".to_string(), 10.0),
            ("sports".to_string(), 5.0),
            ("tech".to_string(), 2.5),
        ];

        let normalized = model.normalize_scores(&scores);

        assert_eq!(normalized[0].1, 1.0);  // Max -> 1.0
        assert_eq!(normalized[1].1, 0.5);  // Half of max
        assert_eq!(normalized[2].1, 0.25); // Quarter of max
    }
}

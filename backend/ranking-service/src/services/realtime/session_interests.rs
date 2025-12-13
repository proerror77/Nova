// ============================================
// Session Interest Manager (会话兴趣管理)
// ============================================
//
// Manages real-time interest signals during a session
// for within-session personalization
//
// Interest calculation:
// - Positive signals: likes, comments, shares, high completion rate
// - Negative signals: skip, not interested, low completion
// - Time decay: recent interactions weighted more
//
// Redis keys:
// - session:{session_id}:interests - Sorted set of tags by weight

use super::{RealtimeError, Result};
use chrono::{DateTime, Utc};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

/// Session interest entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInterest {
    pub tag: String,
    pub weight: f64,
    pub last_updated: DateTime<Utc>,
    pub interaction_count: u32,
}

/// Session interest manager
pub struct SessionInterestManager {
    redis: redis::Client,
    /// Session TTL in seconds
    session_ttl: u64,
    /// Time decay half-life in seconds (default: 30 minutes)
    decay_half_life_seconds: f64,
    /// Maximum interests to track per session
    max_interests: usize,
    /// Key prefix
    key_prefix: String,
}

impl SessionInterestManager {
    pub fn new(redis: redis::Client) -> Self {
        Self {
            redis,
            session_ttl: 7200, // 2 hours
            decay_half_life_seconds: 1800.0, // 30 minutes
            max_interests: 50,
            key_prefix: "session".to_string(),
        }
    }

    fn interests_key(&self, session_id: &str) -> String {
        format!("{}:{}:interests", self.key_prefix, session_id)
    }

    fn interest_detail_key(&self, session_id: &str, tag: &str) -> String {
        format!("{}:{}:interest:{}", self.key_prefix, session_id, tag)
    }

    /// Update session interest based on content interaction
    ///
    /// # Arguments
    /// * `session_id` - Session identifier
    /// * `content_tags` - Tags from the content
    /// * `engagement_weight` - Weight of engagement (1.0 for like, 2.0 for comment, etc.)
    pub async fn update_interest(
        &self,
        session_id: &str,
        content_tags: &[String],
        engagement_weight: f64,
    ) -> Result<()> {
        if content_tags.is_empty() {
            return Ok(());
        }

        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let interests_key = self.interests_key(session_id);

        for tag in content_tags {
            // Increment score in sorted set
            let _: () = conn
                .zincr(&interests_key, tag, engagement_weight)
                .await
                .map_err(|e| RealtimeError::RedisError(e.to_string()))?;
        }

        // Set TTL on sorted set
        let _: () = conn
            .expire(&interests_key, self.session_ttl as i64)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        // Trim to max size (keep top N)
        let size: usize = conn
            .zcard(&interests_key)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        if size > self.max_interests {
            let _: () = conn
                .zremrangebyrank(&interests_key, 0, (size - self.max_interests - 1) as isize)
                .await
                .map_err(|e| RealtimeError::RedisError(e.to_string()))?;
        }

        debug!(
            session_id = session_id,
            tags_count = content_tags.len(),
            engagement_weight = engagement_weight,
            "Session interests updated"
        );

        Ok(())
    }

    /// Record negative interest signal (skip, not interested)
    pub async fn record_negative_signal(
        &self,
        session_id: &str,
        content_tags: &[String],
        negative_weight: f64, // Should be negative, e.g., -1.0
    ) -> Result<()> {
        self.update_interest(session_id, content_tags, negative_weight)
            .await
    }

    /// Get top session interests
    pub async fn get_session_interests(
        &self,
        session_id: &str,
        limit: usize,
    ) -> Result<Vec<(String, f64)>> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let interests: Vec<(String, f64)> = conn
            .zrevrange_withscores(self.interests_key(session_id), 0, (limit - 1) as isize)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        Ok(interests)
    }

    /// Get interest score for a specific tag
    pub async fn get_interest_score(&self, session_id: &str, tag: &str) -> Result<f64> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let score: Option<f64> = conn
            .zscore(self.interests_key(session_id), tag)
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        Ok(score.unwrap_or(0.0))
    }

    /// Compute personalization boost for content based on session interests
    ///
    /// Returns a score between 0.0 and 1.0
    /// Higher = content matches session interests
    pub async fn compute_personalization_boost(
        &self,
        session_id: &str,
        content_tags: &[String],
    ) -> Result<f64> {
        if content_tags.is_empty() {
            return Ok(0.5); // Default neutral score
        }

        let interests = self.get_session_interests(session_id, 20).await?;
        if interests.is_empty() {
            return Ok(0.5); // No interests yet, neutral score
        }

        // Calculate total interest weight for matching tags
        let mut matched_weight = 0.0;
        let mut total_weight = 0.0;

        for (tag, score) in &interests {
            total_weight += score.abs();
            if content_tags.iter().any(|t| t == tag) {
                matched_weight += *score;
            }
        }

        if total_weight == 0.0 {
            return Ok(0.5);
        }

        // Normalize to 0.0 - 1.0 range
        // Positive match = boost (0.5 - 1.0)
        // Negative match = penalty (0.0 - 0.5)
        let normalized = (matched_weight / total_weight + 1.0) / 2.0;

        Ok(normalized.max(0.0).min(1.0))
    }

    /// Merge session interests with long-term user profile
    ///
    /// Returns combined interest weights with session weighted more heavily
    /// for real-time personalization
    pub async fn merge_with_profile(
        &self,
        session_id: &str,
        profile_interests: &[(String, f64)],
        session_weight: f64, // How much to weight session vs profile (0.0 - 1.0)
    ) -> Result<Vec<(String, f64)>> {
        let session_interests = self.get_session_interests(session_id, 30).await?;

        // Merge interests
        let mut merged: std::collections::HashMap<String, f64> = std::collections::HashMap::new();

        // Add profile interests
        for (tag, score) in profile_interests {
            merged.insert(
                tag.clone(),
                score * (1.0 - session_weight),
            );
        }

        // Add session interests (weighted more heavily)
        for (tag, score) in session_interests {
            let entry = merged.entry(tag).or_insert(0.0);
            *entry += score * session_weight;
        }

        // Sort by combined score
        let mut result: Vec<(String, f64)> = merged.into_iter().collect();
        result.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        Ok(result)
    }

    /// Clear session interests (on session end or reset)
    pub async fn clear_session(&self, session_id: &str) -> Result<()> {
        let mut conn = self
            .redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        let _: () = conn
            .del(self.interests_key(session_id))
            .await
            .map_err(|e| RealtimeError::RedisError(e.to_string()))?;

        info!(session_id = session_id, "Session interests cleared");

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_interest() {
        let interest = SessionInterest {
            tag: "music".to_string(),
            weight: 5.0,
            last_updated: Utc::now(),
            interaction_count: 3,
        };

        assert_eq!(interest.tag, "music");
        assert_eq!(interest.weight, 5.0);
    }
}

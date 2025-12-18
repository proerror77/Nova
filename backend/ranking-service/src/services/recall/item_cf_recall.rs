use super::{Candidate, RecallSource, RecallStrategy};
use anyhow::{Context, Result};
use async_trait::async_trait;
use redis::AsyncCommands;
use tracing::info;

/// Item-based Collaborative Filtering Recall Strategy (P1-1)
///
/// Algorithm:
/// 1. Get user's recently interacted items (liked, viewed, completed)
/// 2. For each item, find similar items from pre-computed similarity matrix
/// 3. Aggregate and rank by similarity score
///
/// Data Sources:
/// - `user:{user_id}:recent_items` -> Sorted Set of recent item interactions (score = timestamp)
/// - `item:{post_id}:similar` -> Sorted Set of similar items (score = similarity)
///
/// Similarity is pre-computed by batch job based on:
/// - Co-interaction patterns (users who liked X also liked Y)
/// - Content similarity (tags, hashtags, media type)
/// - Engagement correlation
pub struct ItemCFRecallStrategy {
    redis_client: redis::Client,
}

/// Redis key prefixes
const USER_RECENT_ITEMS_KEY: &str = "user:recent_items:";
const ITEM_SIMILAR_KEY: &str = "item:similar:";

/// Configuration
const MAX_RECENT_ITEMS: isize = 20;      // Max recent items to consider
const SIMILAR_PER_ITEM: isize = 10;       // Similar items per seed item
const MIN_SIMILARITY_SCORE: f64 = 0.1;    // Minimum similarity threshold

impl ItemCFRecallStrategy {
    pub fn new(redis_client: redis::Client) -> Self {
        Self { redis_client }
    }

    /// Get user's recently interacted items
    async fn get_recent_items(&self, user_id: &str) -> Result<Vec<String>> {
        let mut conn = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .context("Failed to get Redis connection")?;

        let key = format!("{}{}", USER_RECENT_ITEMS_KEY, user_id);

        // Get most recent items (highest timestamp = most recent)
        let items: Vec<String> = conn
            .zrevrange(&key, 0, MAX_RECENT_ITEMS - 1)
            .await
            .unwrap_or_default();

        Ok(items)
    }

    /// Get similar items for a given item
    async fn get_similar_items(
        &self,
        post_id: &str,
        limit: isize,
    ) -> Result<Vec<(String, f64)>> {
        let mut conn = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .context("Failed to get Redis connection")?;

        let key = format!("{}{}", ITEM_SIMILAR_KEY, post_id);

        // Get top similar items with their scores
        let similar: Vec<(String, f64)> = conn
            .zrevrangebyscore_withscores(&key, "+inf", MIN_SIMILARITY_SCORE)
            .await
            .unwrap_or_default();

        // Limit results
        let limited: Vec<(String, f64)> = similar.into_iter().take(limit as usize).collect();

        Ok(limited)
    }
}

#[async_trait]
impl RecallStrategy for ItemCFRecallStrategy {
    async fn recall(&self, user_id: &str, limit: i32) -> Result<Vec<Candidate>> {
        // Step 1: Get user's recent items
        let recent_items = self.get_recent_items(user_id).await?;

        if recent_items.is_empty() {
            info!(
                "Item-CF recall: user {} has no recent items, returning empty",
                user_id
            );
            return Ok(Vec::new());
        }

        info!(
            "Item-CF recall: user {} has {} recent items",
            user_id,
            recent_items.len()
        );

        // Step 2: For each recent item, get similar items
        let mut candidate_scores: std::collections::HashMap<String, f64> =
            std::collections::HashMap::new();
        let mut seen_sources: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();

        for (item_idx, seed_item) in recent_items.iter().enumerate() {
            let similar_items = self.get_similar_items(seed_item, SIMILAR_PER_ITEM).await?;

            for (similar_post_id, similarity_score) in similar_items {
                // Skip if this is one of the user's recent items (already seen)
                if recent_items.contains(&similar_post_id) {
                    continue;
                }

                // Decay weight based on recency of seed item
                let recency_decay = 1.0 - (item_idx as f64 * 0.05);
                let weighted_score = similarity_score * recency_decay.max(0.5);

                // Aggregate scores (take max if seen from multiple seeds)
                candidate_scores
                    .entry(similar_post_id.clone())
                    .and_modify(|existing| {
                        if weighted_score > *existing {
                            *existing = weighted_score;
                        }
                    })
                    .or_insert(weighted_score);

                seen_sources
                    .entry(similar_post_id)
                    .or_insert_with(|| seed_item.clone());
            }
        }

        // Step 3: Sort by score and take top candidates
        let mut scored_candidates: Vec<(String, f64)> = candidate_scores.into_iter().collect();
        scored_candidates.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        let candidates: Vec<Candidate> = scored_candidates
            .into_iter()
            .take(limit as usize)
            .map(|(post_id, score)| Candidate {
                post_id,
                recall_source: RecallSource::ItemCF,
                recall_weight: (score as f32).clamp(0.1, 1.0),
                timestamp: chrono::Utc::now().timestamp(), // Will be enriched later
            })
            .collect();

        info!(
            "Item-CF recall: user {} retrieved {} candidates from {} seed items",
            user_id,
            candidates.len(),
            recent_items.len()
        );

        Ok(candidates)
    }

    fn source(&self) -> RecallSource {
        RecallSource::ItemCF
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_format() {
        let user_id = "user123";
        let post_id = "post456";

        let user_key = format!("{}{}", USER_RECENT_ITEMS_KEY, user_id);
        let item_key = format!("{}{}", ITEM_SIMILAR_KEY, post_id);

        assert_eq!(user_key, "user:recent_items:user123");
        assert_eq!(item_key, "item:similar:post456");
    }

    #[test]
    fn test_recall_source() {
        let redis_client =
            redis::Client::open("redis://localhost:6379").expect("Redis client failed");
        let strategy = ItemCFRecallStrategy::new(redis_client);

        assert_eq!(strategy.source(), RecallSource::ItemCF);
    }
}

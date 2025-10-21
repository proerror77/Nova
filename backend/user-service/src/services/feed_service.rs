//! DEPRECATED: This module is a legacy placeholder. Use `feed_ranking_service` instead.
//!
//! The real implementation has moved to feed_ranking_service.rs which provides
//! a complete, tested implementation with actual Redis and ClickHouse integration.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};

/// Feed ranking algorithm configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedConfig {
    /// Weight for freshness score (0.0-1.0)
    pub freshness_weight: f32,
    /// Weight for engagement score (0.0-1.0)
    pub engagement_weight: f32,
    /// Weight for affinity score (0.0-1.0)
    pub affinity_weight: f32,
    /// Freshness decay rate (λ) - higher = faster decay
    pub freshness_lambda: f32,
    /// Maximum items per candidate source
    pub max_follow_candidates: u32,
    pub max_trending_candidates: u32,
    pub max_affinity_candidates: u32,
    /// Feed page size
    pub page_size: u32,
    /// ClickHouse query timeout (ms)
    pub ch_query_timeout_ms: u32,
}

impl Default for FeedConfig {
    fn default() -> Self {
        Self {
            freshness_weight: 0.30,
            engagement_weight: 0.40,
            affinity_weight: 0.30,
            freshness_lambda: 0.10,
            max_follow_candidates: 500,
            max_trending_candidates: 200,
            max_affinity_candidates: 200,
            page_size: 20,
            ch_query_timeout_ms: 5000,
        }
    }
}

/// Raw post from ClickHouse ranking query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankedPost {
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub likes: u32,
    pub comments: u32,
    pub shares: u32,
    pub impressions: u32,
    pub freshness_score: f32,
    pub engagement_score: f32,
    pub affinity_score: f32,
    pub combined_score: f32,
    pub created_at: DateTime<Utc>,
}

/// Feed response item with enriched data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedItem {
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub score: f32,
    pub reason: String, // "follow", "trending", "affinity"
    pub engagement: EngagementMetrics,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngagementMetrics {
    pub likes: u32,
    pub comments: u32,
    pub shares: u32,
    pub impressions: u32,
    pub avg_dwell_ms: u32,
}

/// Feed service with ClickHouse integration
pub struct FeedService {
    config: FeedConfig,
    clickhouse_client: Arc<ClickHouseClient>,
    redis_client: Arc<RedisClient>,
}

// Mock clients for now (will be replaced with real implementations)
pub struct ClickHouseClient;
pub struct RedisClient;

impl FeedService {
    pub fn new(
        config: FeedConfig,
        clickhouse_client: Arc<ClickHouseClient>,
        redis_client: Arc<RedisClient>,
    ) -> Self {
        Self {
            config,
            clickhouse_client,
            redis_client,
        }
    }

    /// Generate personalized feed for user
    /// Algorithm: Candidate sources (Follow + Trending + Affinity) → Merge → Rank → Return
    pub async fn get_personalized_feed(
        &self,
        user_id: Uuid,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<FeedItem>> {
        let limit = limit.min(self.config.page_size);

        debug!(
            "Fetching personalized feed for user {} offset={} limit={}",
            user_id, offset, limit
        );

        // Step 1: Try Redis cache first
        if let Ok(cached_feed) = self.get_cached_feed(user_id, offset, limit).await {
            debug!("Cache hit for user {}", user_id);
            return Ok(cached_feed);
        }

        debug!("Cache miss for user {}, querying ClickHouse", user_id);

        // Step 2: Get candidate sources from ClickHouse
        let (follow_candidates, trending_candidates, affinity_candidates) = tokio::join!(
            self.get_follow_candidates(user_id),
            self.get_trending_candidates(),
            self.get_affinity_candidates(user_id)
        );

        let follow_posts = follow_candidates.unwrap_or_default();
        let trending_posts = trending_candidates.unwrap_or_default();
        let affinity_posts = affinity_candidates.unwrap_or_default();

        // Step 3: Merge candidates with deduplication
        let merged = self.merge_candidates(follow_posts, trending_posts, affinity_posts);

        // Step 4: Sort by combined score and slice
        let feed: Vec<FeedItem> = merged
            .into_iter()
            .take((offset + limit) as usize)
            .skip(offset as usize)
            .map(|(post, reason)| FeedItem {
                post_id: post.post_id,
                author_id: post.author_id,
                score: post.combined_score,
                reason,
                engagement: EngagementMetrics {
                    likes: post.likes,
                    comments: post.comments,
                    shares: post.shares,
                    impressions: post.impressions,
                    avg_dwell_ms: 0, // Placeholder - would come from CH query
                },
            })
            .collect();

        // Step 5: Cache the result
        if let Err(e) = self.cache_feed(user_id, offset, limit, &feed).await {
            warn!("Failed to cache feed for user {}: {}", user_id, e);
        }

        Ok(feed)
    }

    /// Get posts from users that the target user follows (Last 72 hours)
    /// Query: SELECT top 500 recent posts from followed users
    async fn get_follow_candidates(&self, user_id: Uuid) -> Result<Vec<(RankedPost, String)>> {
        let query = format!(
            r#"
            SELECT
                fp.id as post_id,
                fp.user_id as author_id,
                sum(pm.likes_count) as likes,
                sum(pm.comments_count) as comments,
                sum(pm.shares_count) as shares,
                sum(pm.impressions_count) as impressions,
                round(exp(-{} * dateDiff('hour', toStartOfHour(fp.created_at), now())), 4) as freshness_score,
                round(log1p((sum(pm.likes_count) + 2.0*sum(pm.comments_count) + 3.0*sum(pm.shares_count)) /
                    greatest(sum(pm.impressions_count), 1)), 4) as engagement_score,
                0.0 as affinity_score,
                round({} * exp(-{} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                       {} * log1p((sum(pm.likes_count) + 2.0*sum(pm.comments_count) + 3.0*sum(pm.shares_count)) /
                       greatest(sum(pm.impressions_count), 1)), 4) as combined_score,
                fp.created_at
            FROM posts_cdc fp
            INNER JOIN follows_cdc f ON fp.user_id = f.following_id
            LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id AND pm.metric_hour >= toStartOfHour(now()) - INTERVAL 3 HOUR
            WHERE f.follower_id = '{}'
              AND f.created_at > now() - INTERVAL 90 DAY
              AND fp.created_at > now() - INTERVAL 72 HOUR
            GROUP BY fp.id, fp.user_id, fp.created_at
            ORDER BY fp.created_at DESC
            LIMIT {}
            "#,
            self.config.freshness_lambda,
            self.config.freshness_weight,
            self.config.freshness_lambda,
            self.config.engagement_weight,
            user_id,
            self.config.max_follow_candidates
        );

        debug!("Executing follow candidates query for user {}", user_id);
        self.clickhouse_query::<RankedPost>(&query)
            .await
            .map(|posts| {
                posts
                    .into_iter()
                    .map(|p| (p, "follow".to_string()))
                    .collect()
            })
            .map_err(|e| {
                error!("Failed to query follow candidates: {}", e);
                AppError::Internal(format!("ClickHouse query failed: {}", e))
            })
    }

    /// Get trending posts (top by 24h engagement)
    /// Query: SELECT top 200 posts with highest engagement in last 24h
    async fn get_trending_candidates(&self) -> Result<Vec<(RankedPost, String)>> {
        let query = format!(
            r#"
            SELECT
                post_id,
                author_id,
                likes_count as likes,
                comments_count as comments,
                shares_count as shares,
                impressions_count as impressions,
                round(exp(-{} * dateDiff('hour', metric_hour, now())), 4) as freshness_score,
                round(log1p((likes_count + 2.0*comments_count + 3.0*shares_count) /
                    greatest(impressions_count, 1)), 4) as engagement_score,
                0.0 as affinity_score,
                round({} * exp(-{} * dateDiff('hour', metric_hour, now())) +
                       {} * log1p((likes_count + 2.0*comments_count + 3.0*shares_count) /
                       greatest(impressions_count, 1)), 4) as combined_score,
                metric_hour as created_at
            FROM post_metrics_1h
            WHERE metric_hour >= now() - INTERVAL 24 HOUR
            ORDER BY combined_score DESC
            LIMIT {}
            "#,
            self.config.freshness_lambda,
            self.config.freshness_weight,
            self.config.freshness_lambda,
            self.config.engagement_weight,
            self.config.max_trending_candidates
        );

        debug!("Executing trending candidates query");
        self.clickhouse_query::<RankedPost>(&query)
            .await
            .map(|posts| {
                posts
                    .into_iter()
                    .map(|p| (p, "trending".to_string()))
                    .collect()
            })
            .map_err(|e| {
                error!("Failed to query trending candidates: {}", e);
                AppError::Internal(format!("ClickHouse query failed: {}", e))
            })
    }

    /// Get posts from authors user has interacted with (affinity-based recommendations)
    /// Query: SELECT top 200 posts from high-affinity authors (90-day interaction history)
    async fn get_affinity_candidates(&self, user_id: Uuid) -> Result<Vec<(RankedPost, String)>> {
        let query = format!(
            r#"
            SELECT
                fp.id as post_id,
                fp.user_id as author_id,
                sum(pm.likes_count) as likes,
                sum(pm.comments_count) as comments,
                sum(pm.shares_count) as shares,
                sum(pm.impressions_count) as impressions,
                round(exp(-{} * dateDiff('hour', toStartOfHour(fp.created_at), now())), 4) as freshness_score,
                round(log1p((sum(pm.likes_count) + 2.0*sum(pm.comments_count) + 3.0*sum(pm.shares_count)) /
                    greatest(sum(pm.impressions_count), 1)), 4) as engagement_score,
                round(log1p(aa.interaction_count), 4) as affinity_score,
                round({} * exp(-{} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                       {} * log1p((sum(pm.likes_count) + 2.0*sum(pm.comments_count) + 3.0*sum(pm.shares_count)) /
                       greatest(sum(pm.impressions_count), 1)) +
                       {} * log1p(aa.interaction_count), 4) as combined_score,
                fp.created_at
            FROM posts_cdc fp
            INNER JOIN user_author_90d aa ON fp.user_id = aa.author_id
            LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id AND pm.metric_hour >= toStartOfHour(now()) - INTERVAL 3 HOUR
            WHERE aa.user_id = '{}'
              AND fp.created_at > now() - INTERVAL 14 DAY
            GROUP BY fp.id, fp.user_id, fp.created_at, aa.interaction_count
            ORDER BY combined_score DESC
            LIMIT {}
            "#,
            self.config.freshness_lambda,
            self.config.freshness_weight,
            self.config.freshness_lambda,
            self.config.engagement_weight,
            self.config.affinity_weight,
            user_id,
            self.config.max_affinity_candidates
        );

        debug!("Executing affinity candidates query for user {}", user_id);
        self.clickhouse_query::<RankedPost>(&query)
            .await
            .map(|posts| {
                posts
                    .into_iter()
                    .map(|p| (p, "affinity".to_string()))
                    .collect()
            })
            .map_err(|e| {
                error!("Failed to query affinity candidates: {}", e);
                AppError::Internal(format!("ClickHouse query failed: {}", e))
            })
    }

    /// Merge three candidate sources with deduplication
    /// Priority: Follow (most relevant) → Trending → Affinity
    fn merge_candidates(
        &self,
        follow_posts: Vec<(RankedPost, String)>,
        trending_posts: Vec<(RankedPost, String)>,
        affinity_posts: Vec<(RankedPost, String)>,
    ) -> Vec<(RankedPost, String)> {
        use std::collections::HashMap;

        let mut merged: HashMap<Uuid, (RankedPost, String)> = HashMap::new();

        // Add posts in priority order
        // Follow posts have highest priority
        for (post, reason) in follow_posts {
            merged.insert(post.post_id, (post, reason));
        }

        // Add trending (if not already seen)
        for (post, reason) in trending_posts {
            merged.entry(post.post_id).or_insert((post, reason));
        }

        // Add affinity (if not already seen)
        for (post, reason) in affinity_posts {
            merged.entry(post.post_id).or_insert((post, reason));
        }

        // Sort by combined_score descending
        let mut result: Vec<_> = merged.into_values().collect();
        result.sort_by(|a, b| {
            b.0.combined_score
                .partial_cmp(&a.0.combined_score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        result
    }

    /// Get cached feed from Redis (MOCK IMPLEMENTATION)
    ///
    /// Real implementation: see feed_ranking_service.rs
    /// Cache key: feed:v1:{user_id}:{offset}:{limit}
    /// TTL: 60 seconds
    async fn get_cached_feed(
        &self,
        user_id: Uuid,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<FeedItem>> {
        let _cache_key = format!("feed:v1:{}:{}:{}", user_id, offset, limit);
        // This module is deprecated. Always return cache miss for backward compatibility.
        debug!("get_cached_feed called (deprecated module) - returning cache miss for user {} offset={} limit={}", user_id, offset, limit);
        Err(AppError::NotFound("Cache miss".to_string()))
    }

    /// Cache feed to Redis (MOCK IMPLEMENTATION)
    ///
    /// Real implementation: see feed_ranking_service.rs
    /// TTL: 60 seconds
    async fn cache_feed(
        &self,
        user_id: Uuid,
        offset: u32,
        limit: u32,
        _feed: &[FeedItem],
    ) -> Result<()> {
        let _cache_key = format!("feed:v1:{}:{}:{}", user_id, offset, limit);
        // This module is deprecated. No-op for backward compatibility.
        debug!(
            "cache_feed called (deprecated module) - no-op for user {} offset={} limit={}",
            user_id, offset, limit
        );
        Ok(())
    }

    /// Execute ClickHouse query (MOCK IMPLEMENTATION)
    ///
    /// Real implementation: see feed_ranking_service.rs
    /// This is a placeholder - would use real clickhouse-rs client
    async fn clickhouse_query<T: for<'de> Deserialize<'de>>(&self, query: &str) -> Result<Vec<T>> {
        // This module is deprecated. Always return empty results for backward compatibility.
        debug!(
            "clickhouse_query called (deprecated module) - returning empty results for: {}",
            query
        );
        Ok(Vec::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feed_config_defaults() {
        let config = FeedConfig::default();
        assert_eq!(config.freshness_weight, 0.30);
        assert_eq!(config.engagement_weight, 0.40);
        assert_eq!(config.affinity_weight, 0.30);
        assert_eq!(config.max_follow_candidates, 500);
    }

    #[test]
    fn test_merge_candidates_deduplication() {
        // Create mock posts
        let post_id = Uuid::new_v4();
        let author_id = Uuid::new_v4();

        let post1 = RankedPost {
            post_id,
            author_id,
            likes: 100,
            comments: 10,
            shares: 5,
            impressions: 1000,
            freshness_score: 0.8,
            engagement_score: 0.5,
            affinity_score: 0.0,
            combined_score: 0.6,
            created_at: Utc::now(),
        };

        let post2 = RankedPost {
            post_id,
            author_id,
            likes: 100,
            comments: 10,
            shares: 5,
            impressions: 1000,
            freshness_score: 0.8,
            engagement_score: 0.5,
            affinity_score: 0.0,
            combined_score: 0.5,
            created_at: Utc::now(),
        };

        let config = FeedConfig::default();
        let feed_service =
            FeedService::new(config, Arc::new(ClickHouseClient), Arc::new(RedisClient));

        let merged = feed_service.merge_candidates(
            vec![(post1.clone(), "follow".to_string())],
            vec![(post2, "trending".to_string())],
            vec![],
        );

        // Should have only 1 entry (follow version takes priority)
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].0.post_id, post_id);
        assert_eq!(merged[0].1, "follow");
    }

    #[test]
    fn test_merge_candidates_sorting() {
        let post_id1 = Uuid::new_v4();
        let post_id2 = Uuid::new_v4();

        let post1 = RankedPost {
            post_id: post_id1,
            author_id: Uuid::new_v4(),
            likes: 100,
            comments: 10,
            shares: 5,
            impressions: 1000,
            freshness_score: 0.8,
            engagement_score: 0.5,
            affinity_score: 0.0,
            combined_score: 0.5,
            created_at: Utc::now(),
        };

        let post2 = RankedPost {
            post_id: post_id2,
            author_id: Uuid::new_v4(),
            likes: 200,
            comments: 20,
            shares: 10,
            impressions: 2000,
            freshness_score: 0.9,
            engagement_score: 0.7,
            affinity_score: 0.0,
            combined_score: 0.8,
            created_at: Utc::now(),
        };

        let config = FeedConfig::default();
        let feed_service =
            FeedService::new(config, Arc::new(ClickHouseClient), Arc::new(RedisClient));

        let merged = feed_service.merge_candidates(
            vec![(post1, "follow".to_string())],
            vec![(post2, "trending".to_string())],
            vec![],
        );

        // Should be sorted by combined_score (post2 has 0.8 > post1's 0.5)
        assert_eq!(merged[0].0.combined_score, 0.8);
        assert_eq!(merged[1].0.combined_score, 0.5);
    }
}

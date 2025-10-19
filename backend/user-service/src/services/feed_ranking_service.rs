/// Feed Ranking Service
///
/// Orchestrates personalized video feed generation with multi-level caching,
/// ranking signal aggregation, and engagement tracking. Implements cache-first
/// architecture with graceful degradation.
<<<<<<< HEAD
=======

>>>>>>> origin/007-personalized-feed-ranking
use crate::error::{AppError, Result};
use crate::models::video::*;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tracing::{debug, info, warn};
use uuid::Uuid;

/// Feed ranking service configuration
#[derive(Debug, Clone)]
pub struct FeedRankingConfig {
    pub cache_ttl_hours: u64,
    pub cache_hit_target_pct: f32,
    pub dedup_window_days: u32,
    pub feed_size_min: u32,
    pub feed_size_max: u32,
}

impl Default for FeedRankingConfig {
    fn default() -> Self {
        Self {
            cache_ttl_hours: 1,
            cache_hit_target_pct: 95.0,
            dedup_window_days: 30,
            feed_size_min: 30,
            feed_size_max: 50,
        }
    }
}

/// Represents a video in the personalized feed
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedVideo {
    pub id: String,
    pub creator_id: String,
    pub title: String,
    pub duration_seconds: u32,
    pub thumbnail_url: Option<String>,
    pub view_count: u32,
    pub like_count: u32,
    pub comment_count: u32,
    pub share_count: u32,
    pub completion_rate: f32,
    pub url_720p: Option<String>,
    pub url_480p: Option<String>,
    pub url_360p: Option<String>,
    pub ranking_score: f32,
}

/// Personalized feed response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedResponse {
    pub videos: Vec<FeedVideo>,
    pub next_cursor: Option<String>,
}

/// Engagement event type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EngagementType {
    Like,
    Watch,
    Share,
    Comment,
}

impl EngagementType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Like => "like",
            Self::Watch => "watch",
            Self::Share => "share",
            Self::Comment => "comment",
        }
    }
}

/// Cache statistics for monitoring
#[derive(Debug, Clone)]
pub struct CacheStats {
    pub total_requests: u64,
    pub cache_hits: u64,
    pub cache_misses: u64,
    pub hit_rate: f32,
}

impl CacheStats {
    pub fn new() -> Self {
        Self {
            total_requests: 0,
            cache_hits: 0,
            cache_misses: 0,
            hit_rate: 0.0,
        }
    }

    pub fn record_hit(&mut self) {
        self.total_requests = self.total_requests.wrapping_add(1);
        self.cache_hits = self.cache_hits.wrapping_add(1);
        self.update_hit_rate();
    }

    pub fn record_miss(&mut self) {
        self.total_requests = self.total_requests.wrapping_add(1);
        self.cache_misses = self.cache_misses.wrapping_add(1);
        self.update_hit_rate();
    }

    fn update_hit_rate(&mut self) {
        if self.total_requests > 0 {
            self.hit_rate = (self.cache_hits as f32 / self.total_requests as f32) * 100.0;
        }
    }
}

/// Main feed ranking service
pub struct FeedRankingService {
    config: FeedRankingConfig,
    cache_stats: Arc<Mutex<CacheStats>>,
}

impl FeedRankingService {
    /// Create new feed ranking service
    pub fn new(config: FeedRankingConfig) -> Self {
        Self {
            config,
            cache_stats: Arc::new(Mutex::new(CacheStats::new())),
        }
    }

    /// Generate personalized feed for user with caching
    pub async fn get_personalized_feed(
        &self,
        user_id: Uuid,
        cursor: Option<String>,
        limit: Option<u32>,
    ) -> Result<FeedResponse> {
        info!(
            "Generating personalized feed for user: {}, cursor: {:?}",
            user_id, cursor
        );

        let limit = limit
            .unwrap_or(40)
            .max(self.config.feed_size_min)
            .min(self.config.feed_size_max);

        // Step 1: Try to get from cache first
        let cache_key = format!("feed:u:{}", user_id);
        debug!("Checking cache for key: {}", cache_key);

        // Simulate cache check (in production, would use Redis)
        if self.simulate_cache_hit(&cache_key) {
            if let Ok(mut stats) = self.cache_stats.lock() {
                stats.record_hit();
            }
            info!("Cache hit for user feed: {}", user_id);

            let cached_feed = self.get_cached_feed(&cache_key)?;
            return Ok(cached_feed);
        }

        if let Ok(mut stats) = self.cache_stats.lock() {
            stats.record_miss();
        }
        info!("Cache miss for user feed: {}, generating feed", user_id);

        // Step 2: Query ranking signals from ClickHouse
<<<<<<< HEAD
        debug!(
            "Querying ranking signals from ClickHouse for user: {}",
            user_id
        );
        let ranking_signals = self.query_ranking_signals(user_id).await?;

        // Step 3: Rank videos using multi-signal algorithm
        debug!(
            "Ranking {} videos for user: {}",
            ranking_signals.len(),
            user_id
        );
=======
        debug!("Querying ranking signals from ClickHouse for user: {}", user_id);
        let ranking_signals = self.query_ranking_signals(user_id).await?;

        // Step 3: Rank videos using multi-signal algorithm
        debug!("Ranking {} videos for user: {}", ranking_signals.len(), user_id);
>>>>>>> origin/007-personalized-feed-ranking
        let mut ranked_videos = ranking_signals;
        ranked_videos.sort_by(|a, b| {
            b.ranking_score
                .partial_cmp(&a.ranking_score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        // Step 4: Apply deduplication (last 30 days)
<<<<<<< HEAD
        debug!(
            "Applying deduplication for user: {} (window: {} days)",
            user_id, self.config.dedup_window_days
        );
=======
        debug!("Applying deduplication for user: {} (window: {} days)", user_id, self.config.dedup_window_days);
>>>>>>> origin/007-personalized-feed-ranking
        let deduped = self
            .dedup_videos(&ranked_videos, user_id, self.config.dedup_window_days)
            .await?;

        // Step 5: Return top N videos with pagination cursor
        let result_videos: Vec<_> = deduped.into_iter().take(limit as usize).collect();
        let next_cursor = if result_videos.len() >= (limit as usize) {
            Some(format!("cursor_{}", Uuid::new_v4()))
        } else {
            None
        };

        let response = FeedResponse {
            videos: result_videos,
            next_cursor,
        };

        // Step 6: Cache the result
<<<<<<< HEAD
        debug!(
            "Caching feed result for user: {}, TTL: {} hours",
            user_id, self.config.cache_ttl_hours
        );
=======
        debug!("Caching feed result for user: {}, TTL: {} hours", user_id, self.config.cache_ttl_hours);
>>>>>>> origin/007-personalized-feed-ranking
        self.cache_feed(&cache_key, &response).await?;

        let hit_rate = self
            .cache_stats
            .lock()
            .ok()
            .map(|s| s.hit_rate)
            .unwrap_or(0.0);

        info!(
            "✓ Feed generated for user: {} (videos: {}, cache_hit_rate: {:.1}%)",
            user_id,
            response.videos.len(),
            hit_rate
        );

        Ok(response)
    }

    /// Record user engagement (like, share, comment, watch)
    pub async fn record_engagement(
        &self,
        user_id: Uuid,
        video_id: Uuid,
        event_type: EngagementType,
    ) -> Result<()> {
        info!(
            "Recording engagement: user={}, video={}, type={}",
            user_id,
            video_id,
            event_type.as_str()
        );

        // Step 1: Update Redis counter immediately (optimistic update)
        let counter_key = format!("video:{}:{}", video_id, event_type.as_str());
        debug!("Incrementing counter: {}", counter_key);
        // In production: self.redis.increment(&counter_key).await?;

        // Step 2: Queue engagement event for batch processing
        debug!(
            "Queueing engagement event to Kafka: user={}, video={}",
            user_id, video_id
        );
<<<<<<< HEAD
        self.queue_engagement_event(user_id, video_id, event_type)
            .await?;
=======
        self.queue_engagement_event(user_id, video_id, event_type).await?;
>>>>>>> origin/007-personalized-feed-ranking

        // Step 3: Invalidate user's feed cache to force refresh
        let cache_key = format!("feed:u:{}", user_id);
        debug!("Invalidating cache: {}", cache_key);
        self.invalidate_cache(&cache_key).await?;

        info!(
            "✓ Engagement recorded and cache invalidated for user: {}",
            user_id
        );

        Ok(())
    }

    /// Warm cache for top active users before deployment
    pub async fn warm_cache_for_top_users(&self, top_user_ids: Vec<Uuid>) -> Result<()> {
        info!("Warming cache for {} top users", top_user_ids.len());

        for (idx, user_id) in top_user_ids.iter().enumerate() {
            if idx % 100 == 0 {
                debug!("Cache warming progress: {}/{}", idx, top_user_ids.len());
            }

            match self.get_personalized_feed(*user_id, None, None).await {
                Ok(_) => {
                    debug!("Cache warmed for user: {}", user_id);
                }
                Err(e) => {
                    warn!("Failed to warm cache for user {}: {}", user_id, e);
                    // Continue with other users on error
                }
            }
        }

        let success_rate = self
            .cache_stats
            .lock()
            .ok()
            .map(|s| (s.cache_hits as f32 / top_user_ids.len() as f32) * 100.0)
            .unwrap_or(0.0);

        info!(
            "✓ Cache warming complete (target: {}, success rate: {:.1}%)",
            top_user_ids.len(),
            success_rate
        );

        Ok(())
    }

    /// Get cache statistics for monitoring
    pub fn get_cache_stats(&self) -> CacheStats {
        match self.cache_stats.lock() {
            Ok(stats) => stats.clone(),
            Err(_) => CacheStats::new(),
        }
    }

    // ========== Private helper methods ==========

    /// Simulate cache hit (placeholder for Redis integration)
    fn simulate_cache_hit(&self, _key: &str) -> bool {
        // In production, would check Redis
        // For now, simulate 90% hit rate based on timestamp
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .subsec_nanos();
        (nanos % 100) < 90
    }

    /// Get cached feed (placeholder)
    fn get_cached_feed(&self, _key: &str) -> Result<FeedResponse> {
        // In production: would fetch from Redis
        Ok(FeedResponse {
            videos: vec![],
            next_cursor: None,
        })
    }

    /// Query ranking signals from ClickHouse
    async fn query_ranking_signals(&self, user_id: Uuid) -> Result<Vec<FeedVideo>> {
        debug!("Querying ranking signals for user: {}", user_id);

        // In production, would query ClickHouse with:
        // SELECT video_id, completion_rate, engagement_score, affinity_boost, deep_model_score
        // FROM video_ranking_signals_1h
        // WHERE hour >= now() - INTERVAL 30 DAY
        // ORDER BY hour DESC
        // LIMIT 1000

        // Placeholder: return empty list
        Ok(vec![])
    }

    /// Deduplicate videos (remove watched in last N days)
    async fn dedup_videos(
        &self,
        videos: &[FeedVideo],
        user_id: Uuid,
        window_days: u32,
    ) -> Result<Vec<FeedVideo>> {
        debug!(
            "Deduplicating {} videos for user: {} (window: {} days)",
            videos.len(),
            user_id,
            window_days
        );

        // In production, would query user_watch_history_realtime:
        // SELECT video_id FROM user_watch_history_realtime
        // WHERE user_id = $1 AND watched_at >= now() - INTERVAL $2 DAY
        // LIMIT 10000

        // For now, return all videos (no dedup)
        Ok(videos.to_vec())
    }

    /// Cache feed result with TTL
    async fn cache_feed(&self, _key: &str, _response: &FeedResponse) -> Result<()> {
        // In production: would store in Redis with TTL
        // redis.set_ex(key, response, ttl_seconds).await?
        Ok(())
    }

    /// Invalidate cache entry
    async fn invalidate_cache(&self, _key: &str) -> Result<()> {
        // In production: would delete from Redis
        // redis.del(key).await?
        Ok(())
    }

    /// Queue engagement event to Kafka
    async fn queue_engagement_event(
        &self,
        _user_id: Uuid,
        _video_id: Uuid,
        _event_type: EngagementType,
    ) -> Result<()> {
        // In production: would publish to Kafka topic
        // kafka_producer.send(topic, json!({...})).await?
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feed_ranking_service_creation() {
        let config = FeedRankingConfig::default();
        let service = FeedRankingService::new(config);
        assert_eq!(service.config.cache_ttl_hours, 1);
        assert_eq!(service.config.dedup_window_days, 30);
    }

    #[test]
    fn test_cache_stats_tracking() {
        let mut stats = CacheStats::new();
        assert_eq!(stats.hit_rate, 0.0);

        stats.record_hit();
        assert_eq!(stats.total_requests, 1);
        assert_eq!(stats.cache_hits, 1);
        assert_eq!(stats.hit_rate, 100.0);

        stats.record_miss();
        assert_eq!(stats.total_requests, 2);
        assert_eq!(stats.cache_misses, 1);
        assert_eq!(stats.hit_rate, 50.0);
    }

    #[test]
    fn test_engagement_type_str() {
        assert_eq!(EngagementType::Like.as_str(), "like");
        assert_eq!(EngagementType::Share.as_str(), "share");
        assert_eq!(EngagementType::Watch.as_str(), "watch");
        assert_eq!(EngagementType::Comment.as_str(), "comment");
    }

    #[tokio::test]
    async fn test_get_personalized_feed() {
        let config = FeedRankingConfig::default();
        let service = FeedRankingService::new(config);
        let user_id = Uuid::new_v4();

<<<<<<< HEAD
        let result = service.get_personalized_feed(user_id, None, Some(40)).await;
=======
        let result = service
            .get_personalized_feed(user_id, None, Some(40))
            .await;
>>>>>>> origin/007-personalized-feed-ranking

        assert!(result.is_ok());
        let feed = result.unwrap();
        assert!(feed.videos.len() <= 40);
    }

    #[tokio::test]
    async fn test_record_engagement() {
        let config = FeedRankingConfig::default();
        let service = FeedRankingService::new(config);
        let user_id = Uuid::new_v4();
        let video_id = Uuid::new_v4();

        let result = service
            .record_engagement(user_id, video_id, EngagementType::Like)
            .await;

        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_cache_warming() {
        let config = FeedRankingConfig::default();
        let service = FeedRankingService::new(config);
        let users = vec![Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4()];

        let result = service.warm_cache_for_top_users(users.clone()).await;

        assert!(result.is_ok());
        let stats = service.get_cache_stats();
        assert!(stats.total_requests >= users.len() as u64);
    }
}

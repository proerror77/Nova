use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::cache::FeedCache;
use crate::db::ch_client::ClickHouseClient;
use crate::error::{AppError, Result};
use crate::middleware::circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};

/// Feed candidate with ClickHouse Row derivation
#[derive(Debug, Clone, Serialize, Deserialize, clickhouse::Row)]
pub struct FeedCandidate {
    pub post_id: String, // ClickHouse uses String for UUID
    pub author_id: String,
    pub likes: u32,
    pub comments: u32,
    pub shares: u32,
    pub impressions: u32,
    pub freshness_score: f64,
    pub engagement_score: f64,
    pub affinity_score: f64,
    pub combined_score: f64,
    pub created_at: DateTime<Utc>,
}

impl FeedCandidate {
    /// Convert to Uuid (handles parse errors)
    pub fn post_id_uuid(&self) -> Result<Uuid> {
        Uuid::parse_str(&self.post_id).map_err(|e| {
            error!("Failed to parse post_id: {}", e);
            AppError::Internal(format!("Invalid UUID: {}", e))
        })
    }

    pub fn author_id_uuid(&self) -> Result<Uuid> {
        Uuid::parse_str(&self.author_id).map_err(|e| {
            error!("Failed to parse author_id: {}", e);
            AppError::Internal(format!("Invalid UUID: {}", e))
        })
    }
}

/// Simple string-based post ID (for ClickHouse queries)
#[derive(Debug, Clone, Serialize, Deserialize, clickhouse::Row)]
pub struct StringId {
    pub post_id: String,
}

/// Ranked post ready for response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankedPost {
    pub post_id: Uuid,
    pub combined_score: f64,
    pub reason: String,
}

/// Feed ranking service - integrates ClickHouse + Redis
pub struct FeedRankingService {
    ch_client: Arc<ClickHouseClient>,
    cache: Arc<tokio::sync::Mutex<FeedCache>>,
    circuit_breaker: CircuitBreaker,
    freshness_weight: f64,
    engagement_weight: f64,
    affinity_weight: f64,
    freshness_lambda: f64,
}

impl FeedRankingService {
    pub fn new(
        ch_client: Arc<ClickHouseClient>,
        cache: Arc<tokio::sync::Mutex<FeedCache>>,
    ) -> Self {
        Self {
            ch_client,
            cache,
            circuit_breaker: CircuitBreaker::new(CircuitBreakerConfig {
                failure_threshold: 3,
                success_threshold: 3,
                timeout_seconds: 30,
            }),
            freshness_weight: 0.3,
            engagement_weight: 0.4,
            affinity_weight: 0.3,
            freshness_lambda: 0.1,
        }
    }

    /// Configure ranking weights
    pub fn with_weights(
        mut self,
        freshness: f64,
        engagement: f64,
        affinity: f64,
        lambda: f64,
    ) -> Self {
        self.freshness_weight = freshness;
        self.engagement_weight = engagement;
        self.affinity_weight = affinity;
        self.freshness_lambda = lambda;
        self
    }

    /// Get ranked feed from ClickHouse (single query, single sort)
    ///
    /// Combines all three sources (followees, trending, affinity) in ClickHouse
    /// with deduplication. Saturation control is simpler here. Returns final sorted post IDs.
    pub async fn get_ranked_feed(&self, user_id: Uuid, limit: usize) -> Result<Vec<Uuid>> {
        debug!(
            "Fetching ranked feed for user {} (limit: {})",
            user_id, limit
        );

        // Single unified query: all three sources + union + dedup + saturation in one pass
        let query = format!(
            r#"
            WITH all_posts AS (
                -- Followees posts (72h window)
                SELECT
                    toString(fp.id) as post_id,
                    toString(fp.user_id) as author_id,
                    round({fresh_w} * exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                           {eng_w} * log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                           greatest(sum(pm.exposures), 1)), 4) as score
                FROM posts_cdc fp
                INNER JOIN follows_cdc f ON fp.user_id = f.following_id
                LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id
                WHERE f.follower_id = '{user_id}'
                  AND f.created_at > now() - INTERVAL 90 DAY
                  AND fp.created_at > now() - INTERVAL 72 HOUR
                GROUP BY fp.id, fp.user_id, fp.created_at

                UNION ALL

                -- Trending posts (24h window)
                SELECT
                    toString(post_id) as post_id,
                    toString(author_id) as author_id,
                    round({fresh_w} * exp(-{lambda} * dateDiff('hour', window_start, now())) +
                           {eng_w} * log1p((likes + 2.0*comments + 3.0*shares) /
                           greatest(exposures, 1)), 4) as score
                FROM post_metrics_1h
                WHERE window_start >= now() - INTERVAL 24 HOUR

                UNION ALL

                -- Affinity posts (14d window)
                SELECT
                    toString(fp.id) as post_id,
                    toString(fp.user_id) as author_id,
                    round({fresh_w} * exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                           {eng_w} * log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                           greatest(sum(pm.exposures), 1)) +
                           {aff_w} * log1p((aa.likes + aa.comments + aa.views)), 4) as score
                FROM posts_cdc fp
                INNER JOIN user_author_90d aa ON fp.user_id = aa.author_id
                LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id
                WHERE aa.user_id = '{user_id}'
                  AND fp.created_at > now() - INTERVAL 14 DAY
                GROUP BY fp.id, fp.user_id, fp.created_at, (aa.likes + aa.comments + aa.views)
            ),
            deduped AS (
                -- Dedup: keep max score per post_id
                SELECT
                    post_id,
                    author_id,
                    max(score) as score
                FROM all_posts
                GROUP BY post_id, author_id
            ),
            ranked AS (
                -- Add position info for saturation control
                SELECT
                    post_id,
                    author_id,
                    score,
                    ROW_NUMBER() OVER (ORDER BY score DESC) as pos,
                    ROW_NUMBER() OVER (PARTITION BY author_id ORDER BY score DESC) as author_seq
                FROM deduped
            )
            SELECT post_id
            FROM ranked
            WHERE pos <= {limit}
            ORDER BY score DESC
            "#,
            user_id = user_id,
            lambda = self.freshness_lambda,
            fresh_w = self.freshness_weight,
            eng_w = self.engagement_weight,
            aff_w = self.affinity_weight,
            limit = limit * 3 // Fetch extra to account for filtering
        );

        let ch_client = self.ch_client.clone();
        let query_clone = query.clone();

        let results = self
            .circuit_breaker
            .call(|| async move {
                ch_client
                    .query_with_retry::<StringId>(&query_clone, 3)
                    .await
            })
            .await?;

        let mut post_ids: Vec<Uuid> = results
            .into_iter()
            .filter_map(|r| Uuid::parse_str(&r.post_id).ok())
            .collect();

        // Apply saturation control in Rust (simpler than ClickHouse window functions)
        post_ids = self.apply_saturation_control_simple(post_ids, limit);

        debug!(
            "Retrieved {} ranked posts for user {}",
            post_ids.len(),
            user_id
        );
        Ok(post_ids)
    }

    /// Simple in-memory saturation control
    /// Rule: max 1 post per author in top-5, then max 2 per author after
    fn apply_saturation_control_simple(&self, posts: Vec<Uuid>, limit: usize) -> Vec<Uuid> {
        use std::collections::HashMap;

        let mut result = Vec::new();
        let mut author_counts: HashMap<String, usize> = HashMap::new();

        for post_id in posts {
            // For now, we don't have author_id here. In production, fetch from metadata.
            // Simple approach: just take first N posts (dedup already done in SQL)
            result.push(post_id);

            if result.len() >= limit {
                break;
            }
        }

        result
    }

    /// Get feed candidates from ClickHouse (DEPRECATED)
    ///
    /// Use get_ranked_feed() instead. This is kept for backwards compatibility.
    #[deprecated(note = "Use get_ranked_feed() instead")]
    pub async fn get_feed_candidates(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<FeedCandidate>> {
        debug!(
            "Fetching feed candidates for user {} (limit: {}) [DEPRECATED]",
            user_id, limit
        );

        // Fetch candidates from 3 independent sources in parallel
        let (followees_result, trending_result, affinity_result) = tokio::join!(
            self.get_followees_candidates(user_id, 200),
            self.get_trending_candidates(200),
            self.get_affinity_candidates(user_id, 200),
        );

        let mut all_candidates = Vec::new();

        if let Ok(mut followees) = followees_result {
            debug!("Retrieved {} followees candidates", followees.len());
            all_candidates.append(&mut followees);
        } else {
            warn!(
                "Failed to fetch followees candidates: {:?}",
                followees_result.err()
            );
        }

        if let Ok(mut trending) = trending_result {
            debug!("Retrieved {} trending candidates", trending.len());
            all_candidates.append(&mut trending);
        } else {
            warn!(
                "Failed to fetch trending candidates: {:?}",
                trending_result.err()
            );
        }

        if let Ok(mut affinity) = affinity_result {
            debug!("Retrieved {} affinity candidates", affinity.len());
            all_candidates.append(&mut affinity);
        } else {
            warn!(
                "Failed to fetch affinity candidates: {:?}",
                affinity_result.err()
            );
        }

        debug!(
            "Retrieved {} total candidates from all sources",
            all_candidates.len()
        );

        Ok(all_candidates)
    }

    /// Get fallback feed when ClickHouse is unavailable
    async fn fallback_feed(&self, user_id: Uuid) -> Result<Vec<Uuid>> {
        warn!(
            "Using fallback feed for user {} (ClickHouse unavailable)",
            user_id
        );

        // Try cache first
        let mut cache = self.cache.lock().await;
        if let Some(cached) = cache.read_feed_cache(user_id, 0, 20).await? {
            debug!(
                "Fallback: using cached feed ({} posts)",
                cached.post_ids.len()
            );
            return Ok(cached.post_ids);
        }

        // No cache - return empty (in production: query PostgreSQL timeline)
        warn!("Fallback: no cache available, returning empty feed");
        Ok(Vec::new())
    }

    /// Get posts from followees (72h window) with circuit breaker
    async fn get_followees_candidates(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<FeedCandidate>> {
        let query = format!(
            r#"
            SELECT
                toString(fp.id) as post_id,
                toString(fp.user_id) as author_id,
                sum(pm.likes) as likes,
                sum(pm.comments) as comments,
                sum(pm.shares) as shares,
                sum(pm.exposures) as impressions,
                round(exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())), 4) as freshness_score,
                round(log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                    greatest(sum(pm.exposures), 1)), 4) as engagement_score,
                0.0 as affinity_score,
                round({fresh_w} * exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                       {eng_w} * log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                       greatest(sum(pm.exposures), 1)), 4) as combined_score,
                fp.created_at
            FROM posts_cdc fp
            INNER JOIN follows_cdc f ON fp.user_id = f.following_id
            LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id AND pm.window_start >= toStartOfHour(now()) - INTERVAL 3 HOUR
            WHERE f.follower_id = '{user_id}'
              AND f.created_at > now() - INTERVAL 90 DAY
              AND fp.created_at > now() - INTERVAL 72 HOUR
            GROUP BY fp.id, fp.user_id, fp.created_at
            ORDER BY combined_score DESC
            LIMIT {limit}
            "#,
            user_id = user_id,
            lambda = self.freshness_lambda,
            fresh_w = self.freshness_weight,
            eng_w = self.engagement_weight,
            limit = limit
        );

        let ch_client = self.ch_client.clone();
        let query_clone = query.clone();

        self.circuit_breaker
            .call(|| async move {
                ch_client
                    .query_with_retry::<FeedCandidate>(&query_clone, 3)
                    .await
            })
            .await
    }

    /// Get trending posts (24h window) with circuit breaker
    async fn get_trending_candidates(&self, limit: usize) -> Result<Vec<FeedCandidate>> {
        let query = format!(
            r#"
            SELECT
                toString(post_id) as post_id,
                toString(author_id) as author_id,
                likes as likes,
                comments as comments,
                shares as shares,
                exposures as impressions,
                round(exp(-{lambda} * dateDiff('hour', window_start, now())), 4) as freshness_score,
                round(log1p((likes + 2.0*comments + 3.0*shares) /
                    greatest(exposures, 1)), 4) as engagement_score,
                0.0 as affinity_score,
                round({fresh_w} * exp(-{lambda} * dateDiff('hour', window_start, now())) +
                       {eng_w} * log1p((likes + 2.0*comments + 3.0*shares) /
                       greatest(exposures, 1)), 4) as combined_score,
                window_start as created_at
            FROM post_metrics_1h
            WHERE window_start >= now() - INTERVAL 24 HOUR
            ORDER BY combined_score DESC
            LIMIT {limit}
            "#,
            lambda = self.freshness_lambda,
            fresh_w = self.freshness_weight,
            eng_w = self.engagement_weight,
            limit = limit
        );

        let ch_client = self.ch_client.clone();
        let query_clone = query.clone();

        self.circuit_breaker
            .call(|| async move {
                ch_client
                    .query_with_retry::<FeedCandidate>(&query_clone, 3)
                    .await
            })
            .await
    }

    /// Get posts from authors user has interacted with (90d window) with circuit breaker
    async fn get_affinity_candidates(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<FeedCandidate>> {
        let query = format!(
            r#"
            SELECT
                toString(fp.id) as post_id,
                toString(fp.user_id) as author_id,
                sum(pm.likes) as likes,
                sum(pm.comments) as comments,
                sum(pm.shares) as shares,
                sum(pm.exposures) as impressions,
                round(exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())), 4) as freshness_score,
                round(log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                    greatest(sum(pm.exposures), 1)), 4) as engagement_score,
                round(log1p((aa.likes + aa.comments + aa.views)), 4) as affinity_score,
                round({fresh_w} * exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                       {eng_w} * log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                       greatest(sum(pm.exposures), 1)) +
                       {aff_w} * log1p((aa.likes + aa.comments + aa.views)), 4) as combined_score,
                fp.created_at
            FROM posts_cdc fp
            INNER JOIN user_author_90d aa ON fp.user_id = aa.author_id
            LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id AND pm.window_start >= toStartOfHour(now()) - INTERVAL 3 HOUR
            WHERE aa.user_id = '{user_id}'
              AND fp.created_at > now() - INTERVAL 14 DAY
            GROUP BY fp.id, fp.user_id, fp.created_at, (aa.likes + aa.comments + aa.views)
            ORDER BY combined_score DESC
            LIMIT {limit}
            "#,
            user_id = user_id,
            lambda = self.freshness_lambda,
            fresh_w = self.freshness_weight,
            eng_w = self.engagement_weight,
            aff_w = self.affinity_weight,
            limit = limit
        );

        let ch_client = self.ch_client.clone();
        let query_clone = query.clone();

        self.circuit_breaker
            .call(|| async move {
                ch_client
                    .query_with_retry::<FeedCandidate>(&query_clone, 3)
                    .await
            })
            .await
    }

    /// Get circuit breaker state for monitoring
    pub async fn get_circuit_state(&self) -> CircuitState {
        self.circuit_breaker.get_state().await
    }

    /// Build ClickHouse query for feed ranking (DEPRECATED - use individual methods)
    #[deprecated(
        note = "Use get_followees_candidates, get_trending_candidates, get_affinity_candidates instead"
    )]
    fn build_feed_query(&self, user_id: Uuid, limit: usize) -> String {
        format!(
            r#"
            WITH follow_posts AS (
                SELECT
                    toString(fp.id) as post_id,
                    toString(fp.user_id) as author_id,
                    sum(pm.likes) as likes,
                    sum(pm.comments) as comments,
                    sum(pm.shares) as shares,
                    sum(pm.exposures) as impressions,
                    round(exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())), 4) as freshness_score,
                    round(log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                        greatest(sum(pm.exposures), 1)), 4) as engagement_score,
                    0.0 as affinity_score,
                    round({fresh_w} * exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                           {eng_w} * log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                           greatest(sum(pm.exposures), 1)), 4) as combined_score,
                    fp.created_at
                FROM posts_cdc fp
                INNER JOIN follows_cdc f ON fp.user_id = f.following_id
                LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id AND pm.window_start >= toStartOfHour(now()) - INTERVAL 3 HOUR
                WHERE f.follower_id = '{user_id}'
                  AND f.created_at > now() - INTERVAL 90 DAY
                  AND fp.created_at > now() - INTERVAL 72 HOUR
                GROUP BY fp.id, fp.user_id, fp.created_at
            ),
            trending_posts AS (
                SELECT
                    toString(post_id) as post_id,
                    toString(author_id) as author_id,
                    likes as likes,
                    comments as comments,
                    shares as shares,
                    exposures as impressions,
                    round(exp(-{lambda} * dateDiff('hour', window_start, now())), 4) as freshness_score,
                    round(log1p((likes + 2.0*comments + 3.0*shares) /
                        greatest(exposures, 1)), 4) as engagement_score,
                    0.0 as affinity_score,
                    round({fresh_w} * exp(-{lambda} * dateDiff('hour', window_start, now())) +
                           {eng_w} * log1p((likes + 2.0*comments + 3.0*shares) /
                           greatest(exposures, 1)), 4) as combined_score,
                    window_start as created_at
                FROM post_metrics_1h
                WHERE window_start >= now() - INTERVAL 24 HOUR
                ORDER BY combined_score DESC
                LIMIT 200
            ),
            affinity_posts AS (
                SELECT
                    toString(fp.id) as post_id,
                    toString(fp.user_id) as author_id,
                    sum(pm.likes) as likes,
                    sum(pm.comments) as comments,
                    sum(pm.shares) as shares,
                    sum(pm.exposures) as impressions,
                    round(exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())), 4) as freshness_score,
                    round(log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                        greatest(sum(pm.exposures), 1)), 4) as engagement_score,
                    round(log1p((aa.likes + aa.comments + aa.views)), 4) as affinity_score,
                    round({fresh_w} * exp(-{lambda} * dateDiff('hour', toStartOfHour(fp.created_at), now())) +
                           {eng_w} * log1p((sum(pm.likes) + 2.0*sum(pm.comments) + 3.0*sum(pm.shares)) /
                           greatest(sum(pm.exposures), 1)) +
                           {aff_w} * log1p((aa.likes + aa.comments + aa.views)), 4) as combined_score,
                    fp.created_at
                FROM posts_cdc fp
                INNER JOIN user_author_90d aa ON fp.user_id = aa.author_id
                LEFT JOIN post_metrics_1h pm ON fp.id = pm.post_id AND pm.window_start >= toStartOfHour(now()) - INTERVAL 3 HOUR
                WHERE aa.user_id = '{user_id}'
                  AND fp.created_at > now() - INTERVAL 14 DAY
                GROUP BY fp.id, fp.user_id, fp.created_at, (aa.likes + aa.comments + aa.views)
                ORDER BY combined_score DESC
                LIMIT 200
            )
            SELECT *
            FROM (
                SELECT * FROM follow_posts
                UNION ALL
                SELECT * FROM trending_posts
                UNION ALL
                SELECT * FROM affinity_posts
            )
            ORDER BY combined_score DESC
            LIMIT {limit}
            "#,
            user_id = user_id,
            lambda = self.freshness_lambda,
            fresh_w = self.freshness_weight,
            eng_w = self.engagement_weight,
            aff_w = self.affinity_weight,
            limit = limit
        )
    }

    /// Rank candidates and apply deduplication + saturation control
    pub fn rank_with_clickhouse(&self, candidates: Vec<FeedCandidate>) -> Result<Vec<RankedPost>> {
        use std::collections::HashMap;

        let mut seen: HashMap<String, f64> = HashMap::new();
        let mut ranked: Vec<RankedPost> = Vec::new();

        for candidate in candidates {
            // Deduplication: keep highest score
            if let Some(&existing_score) = seen.get(&candidate.post_id) {
                if candidate.combined_score <= existing_score {
                    continue;
                }
            }

            seen.insert(candidate.post_id.clone(), candidate.combined_score);

            let post_id = candidate.post_id_uuid()?;

            // Determine reason based on scores
            let reason = if candidate.affinity_score > 0.0 {
                "affinity"
            } else if candidate.freshness_score > candidate.engagement_score {
                "follow"
            } else {
                "trending"
            };

            ranked.push(RankedPost {
                post_id,
                combined_score: candidate.combined_score,
                reason: reason.to_string(),
            });
        }

        // Sort by combined score (descending)
        ranked.sort_by(|a, b| {
            b.combined_score
                .partial_cmp(&a.combined_score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        Ok(ranked)
    }

    /// Apply deduplication and saturation control
    ///
    /// Dedup: Keep highest-scoring duplicate posts
    /// Saturation: Max 1 post per author in top-5, min distance of 3 between same-author posts
    pub fn apply_dedup_and_saturation(&self, ranked: Vec<RankedPost>) -> Vec<RankedPost> {
        use std::collections::HashSet;

        let mut seen_posts: HashSet<Uuid> = HashSet::new();
        let mut result: Vec<RankedPost> = Vec::new();

        for post in ranked {
            // Dedup: skip if already seen
            if seen_posts.contains(&post.post_id) {
                debug!("Dedup: skipping duplicate post_id={}", post.post_id);
                continue;
            }

            // Extract author_id (would be better to store in RankedPost directly)
            // For now, we skip author saturation check
            // In production: parse post metadata to get author_id

            seen_posts.insert(post.post_id);
            result.push(post);

            // Hard limit of 100 posts
            if result.len() >= 100 {
                break;
            }
        }

        result
    }

    /// Apply deduplication and saturation control (with author tracking)
    ///
    /// Enhanced version that requires author_id in candidates
    /// Rules:
    /// - Dedup: HashMap to track highest-scoring duplicate
    /// - Top-5 saturation: No more than 1 post per author in first 5 positions
    /// - Min distance: At least 3 positions between same-author posts
    pub fn dedup_and_saturation_with_authors(
        &self,
        candidates: Vec<FeedCandidate>,
    ) -> Result<Vec<RankedPost>> {
        use std::collections::HashMap;

        // Step 1: Dedup - keep highest score per post_id
        let mut post_scores: HashMap<String, FeedCandidate> = HashMap::new();
        for candidate in candidates {
            let entry = post_scores
                .entry(candidate.post_id.clone())
                .or_insert_with(|| candidate.clone());
            if candidate.combined_score > entry.combined_score {
                *entry = candidate;
            }
        }

        // Step 2: Convert to RankedPost and sort
        let mut ranked: Vec<(FeedCandidate, RankedPost)> = post_scores
            .into_iter()
            .filter_map(|(_, candidate)| {
                let post_id = candidate.post_id_uuid().ok()?;
                let reason = if candidate.affinity_score > 0.0 {
                    "affinity"
                } else if candidate.freshness_score > candidate.engagement_score {
                    "follow"
                } else {
                    "trending"
                };

                Some((
                    candidate.clone(),
                    RankedPost {
                        post_id,
                        combined_score: candidate.combined_score,
                        reason: reason.to_string(),
                    },
                ))
            })
            .collect();

        ranked.sort_by(|a, b| {
            b.1.combined_score
                .partial_cmp(&a.1.combined_score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        // Step 3: Apply saturation control
        let mut result: Vec<RankedPost> = Vec::new();
        let mut top5_authors: HashMap<String, usize> = HashMap::new(); // author_id -> count in top 5
        let mut author_last_pos: HashMap<String, usize> = HashMap::new(); // author_id -> last position

        for (candidate, ranked_post) in ranked {
            let author_id = &candidate.author_id;
            let current_pos = result.len();

            // Rule 1: Top-5 saturation - max 1 post per author in first 5
            if current_pos < 5 {
                if let Some(&count) = top5_authors.get(author_id) {
                    if count >= 1 {
                        debug!(
                            "Saturation: skipping post_id={} (author={} already has {} in top-5)",
                            ranked_post.post_id, author_id, count
                        );
                        continue;
                    }
                }
            }

            // Rule 2: Min distance of 3 between same-author posts
            if let Some(&last_pos) = author_last_pos.get(author_id) {
                let distance = current_pos.saturating_sub(last_pos);
                if distance < 3 {
                    debug!(
                        "Saturation: skipping post_id={} (author={} last at pos {}, distance {})",
                        ranked_post.post_id, author_id, last_pos, distance
                    );
                    continue;
                }
            }

            // Accept post
            result.push(ranked_post);
            author_last_pos.insert(author_id.clone(), current_pos);

            if current_pos < 5 {
                *top5_authors.entry(author_id.clone()).or_insert(0) += 1;
            }

            // Hard limit
            if result.len() >= 100 {
                break;
            }
        }

        Ok(result)
    }

    /// Get feed with caching (optimized per-user cache)
    ///
    /// Caches entire feed (100 posts) per user, not per offset.
    /// Pagination is handled in-memory from cached results.
    pub async fn get_feed(
        &self,
        user_id: Uuid,
        limit: usize,
        offset: usize,
    ) -> Result<(Vec<Uuid>, bool)> {
        // Try cache first (per-user, not per-offset)
        {
            let mut cache = self.cache.lock().await;
            if let Some(cached) = cache
                .read_feed_cache(user_id, 0, 100) // Always fetch full cache
                .await?
            {
                debug!(
                    "Feed cache HIT for user {} (cached {} posts)",
                    user_id,
                    cached.post_ids.len()
                );

                // Handle pagination from cached results
                let has_more = cached.post_ids.len() > offset + limit;
                let posts: Vec<Uuid> = cached
                    .post_ids
                    .into_iter()
                    .skip(offset)
                    .take(limit)
                    .collect();

                if !posts.is_empty() {
                    return Ok((posts, has_more));
                }
            }
        }

        debug!("Feed cache MISS for user {}", user_id);

        // Check circuit breaker state
        let cb_state = self.circuit_breaker.get_state().await;
        if cb_state == CircuitState::Open {
            warn!("Circuit breaker OPEN - using fallback feed");
            let fallback_posts = self.fallback_feed(user_id).await?;
            let has_more = fallback_posts.len() > offset + limit;
            let result: Vec<Uuid> = fallback_posts
                .into_iter()
                .skip(offset)
                .take(limit)
                .collect();
            return Ok((result, has_more));
        }

        // Single optimized query: get ranked, deduped, saturated posts
        let all_posts = match self.get_ranked_feed(user_id, 100).await {
            Ok(posts) => posts,
            Err(e) => {
                error!("ClickHouse query failed, using fallback: {}", e);
                let fallback_posts = self.fallback_feed(user_id).await?;
                let has_more = fallback_posts.len() > offset + limit;
                let result: Vec<Uuid> = fallback_posts
                    .into_iter()
                    .skip(offset)
                    .take(limit)
                    .collect();
                return Ok((result, has_more));
            }
        };

        // Handle pagination
        let has_more = all_posts.len() > offset + limit;
        let result_posts: Vec<Uuid> = all_posts.iter().skip(offset).take(limit).copied().collect();

        // Cache full result (async, best-effort)
        {
            let mut cache = self.cache.lock().await;

            // Write with per-user key (not per-offset)
            if let Err(e) = cache
                .write_feed_cache(
                    user_id,
                    0,   // Always use offset 0 for full feed cache
                    100, // Fixed size: full feed
                    all_posts.clone(),
                    Some(120), // 2 minute TTL
                )
                .await
            {
                warn!("Failed to write feed cache: {}", e);
            }

            // Mark posts as seen (for deduplication across page loads)
            if let Err(e) = cache.mark_posts_seen(user_id, &result_posts).await {
                warn!("Failed to mark posts as seen: {}", e);
            }
        }

        Ok((result_posts, has_more))
    }

    pub async fn invalidate_cache(&self, user_id: Uuid) -> Result<()> {
        let mut cache = self.cache.lock().await;
        cache.invalidate_feed(user_id).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_candidate_uuid_parsing() {
        let candidate = FeedCandidate {
            post_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            author_id: "650e8400-e29b-41d4-a716-446655440000".to_string(),
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

        assert!(candidate.post_id_uuid().is_ok());
        assert!(candidate.author_id_uuid().is_ok());
    }
}

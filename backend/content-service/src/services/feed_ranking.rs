use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Instant;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::cache::feed_cache::FeedCache;
use crate::config::FeedConfig;
use crate::db::{ch_client::ClickHouseClient, post_repo};
use crate::error::{AppError, Result};
use crate::metrics::feed::{
    FEED_CACHE_EVENTS, FEED_CANDIDATE_COUNT, FEED_REQUEST_DURATION_SECONDS, FEED_REQUEST_TOTAL,
};
use crate::middleware::circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};

#[derive(Debug, Clone, Serialize, Deserialize, clickhouse::Row)]
pub struct FeedCandidate {
    pub post_id: String,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankedPost {
    pub post_id: Uuid,
    pub combined_score: f64,
    pub reason: String,
}

pub struct FeedRankingService {
    ch_client: Arc<ClickHouseClient>,
    cache: Arc<tokio::sync::Mutex<FeedCache>>,
    circuit_breaker: CircuitBreaker,
    db_pool: PgPool,
    freshness_weight: f64,
    engagement_weight: f64,
    affinity_weight: f64,
    freshness_lambda: f64,
    max_feed_candidates: usize,
    candidate_prefetch_multiplier: usize,
    fallback_cache_ttl_secs: u64,
}

impl FeedRankingService {
    pub fn new(
        ch_client: Arc<ClickHouseClient>,
        cache: Arc<tokio::sync::Mutex<FeedCache>>,
        db_pool: PgPool,
        config: FeedRankingConfig,
    ) -> Self {
        Self {
            ch_client,
            cache,
            circuit_breaker: CircuitBreaker::new(CircuitBreakerConfig {
                failure_threshold: 3,
                success_threshold: 3,
                timeout_seconds: 30,
            }),
            db_pool,
            freshness_weight: config.freshness_weight,
            engagement_weight: config.engagement_weight,
            affinity_weight: config.affinity_weight,
            freshness_lambda: config.freshness_lambda,
            max_feed_candidates: config.max_candidates,
            candidate_prefetch_multiplier: config.candidate_prefetch_multiplier,
            fallback_cache_ttl_secs: config.fallback_cache_ttl_secs,
        }
    }

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

    pub async fn get_feed_candidates(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<FeedCandidate>> {
        debug!(
            "Fetching feed candidates for user {} (limit: {})",
            user_id, limit
        );

        let source_limit = limit.min(self.max_feed_candidates);
        let (followees_result, trending_result, affinity_result) = tokio::join!(
            self.get_followees_candidates(user_id, source_limit),
            self.get_trending_candidates(source_limit),
            self.get_affinity_candidates(user_id, source_limit),
        );

        let mut all_candidates = Vec::new();

        if let Ok(mut followees) = followees_result {
            debug!("Retrieved {} followees candidates", followees.len());
            all_candidates.append(&mut followees);
        }

        if let Ok(mut trending) = trending_result {
            debug!("Retrieved {} trending candidates", trending.len());
            all_candidates.append(&mut trending);
        }

        if let Ok(mut affinity) = affinity_result {
            debug!("Retrieved {} affinity candidates", affinity.len());
            all_candidates.append(&mut affinity);
        }

        debug!(
            "Retrieved {} total candidates from all sources",
            all_candidates.len()
        );

        Ok(all_candidates)
    }

    pub async fn get_feed(
        &self,
        user_id: Uuid,
        limit: usize,
        offset: usize,
    ) -> Result<(Vec<Uuid>, bool, usize)> {
        if matches!(self.circuit_breaker.get_state().await, CircuitState::Open) {
            return self.fallback_feed(user_id, limit, offset).await;
        }

        let start = Instant::now();
        let candidate_limit = ((offset + limit)
            .max(limit * self.candidate_prefetch_multiplier))
        .min(self.max_feed_candidates);

        let candidates = self
            .circuit_breaker
            .call(|| async { self.get_feed_candidates(user_id, candidate_limit).await })
            .await?;

        let ranked = self
            .rank_candidates(candidates, self.max_feed_candidates)
            .await?;

        let all_posts: Vec<Uuid> = ranked.iter().map(|p| p.post_id).collect();
        let total_count = all_posts.len();

        let start_index = offset.min(total_count);
        let end = (start_index + limit).min(total_count);
        let page_posts = all_posts[start_index..end].to_vec();
        let has_more = end < total_count;

        {
            let mut cache = self.cache.lock().await;
            if total_count > 0 {
                cache
                    .write_feed_cache(user_id, all_posts.clone(), None)
                    .await?;
            } else {
                cache.invalidate_feed(user_id).await?;
            }
        }

        let elapsed = start.elapsed().as_secs_f64();
        FEED_REQUEST_DURATION_SECONDS
            .with_label_values(&["clickhouse"])
            .observe(elapsed);
        FEED_REQUEST_TOTAL
            .with_label_values(&["clickhouse"])
            .inc();
        FEED_CANDIDATE_COUNT
            .with_label_values(&["clickhouse"])
            .observe(total_count as f64);

        Ok((page_posts, has_more, total_count))
    }

    pub async fn fallback_feed(
        &self,
        user_id: Uuid,
        limit: usize,
        offset: usize,
    ) -> Result<(Vec<Uuid>, bool, usize)> {
        warn!(
            "Using fallback feed for user {} (ClickHouse unavailable)",
            user_id
        );

        let start = Instant::now();

        {
            let mut cache = self.cache.lock().await;
            match cache.read_feed_cache(user_id).await? {
                Some(cached) => {
                    let total_count = cached.post_ids.len();
                    if offset < total_count {
                        let end = (offset + limit).min(total_count);
                        let page = cached.post_ids[offset..end].to_vec();
                        let has_more = end < total_count;

                        FEED_CACHE_EVENTS
                            .with_label_values(&["hit"])
                            .inc();

                        let elapsed = start.elapsed().as_secs_f64();
                        FEED_REQUEST_DURATION_SECONDS
                            .with_label_values(&["cache"])
                            .observe(elapsed);
                        FEED_REQUEST_TOTAL
                            .with_label_values(&["cache"])
                            .inc();
                        FEED_CANDIDATE_COUNT
                            .with_label_values(&["cache"])
                            .observe(total_count as f64);
                        return Ok((page, has_more, total_count));
                    }

                    debug!(
                        "Fallback cache present but offset out of range (user={} offset={} total={})",
                        user_id, offset, total_count
                    );
                    FEED_CACHE_EVENTS
                        .with_label_values(&["miss"])
                        .inc();
                }
                None => {
                    FEED_CACHE_EVENTS
                        .with_label_values(&["miss"])
                        .inc();
                }
            }
        }

        let fetch_limit = offset.saturating_add(limit).saturating_add(1) as i64;
        let posts = post_repo::get_recent_published_post_ids(&self.db_pool, fetch_limit, 0)
            .await
            .map_err(|e| {
                error!("Timeline fallback query failed: {}", e);
                AppError::Internal("Failed to load timeline fallback feed".into())
            })?;

        if posts.is_empty() {
            warn!(
                "Fallback: no recent published posts available (user={}, offset={}, limit={})",
                user_id, offset, limit
            );
        }

        let total_count = posts.len();
        let start_index = offset.min(total_count);
        let end = (start_index + limit).min(total_count);
        let page_posts: Vec<Uuid> = posts[start_index..end].to_vec();
        let has_more = end < total_count;

        if total_count > 0 {
            let mut cache = self.cache.lock().await;
            cache
                .write_feed_cache(user_id, posts.clone(), Some(self.fallback_cache_ttl_secs))
                .await?;
        }

        let elapsed = start.elapsed().as_secs_f64();
        FEED_REQUEST_DURATION_SECONDS
            .with_label_values(&["fallback_postgres"])
            .observe(elapsed);
        FEED_REQUEST_TOTAL
            .with_label_values(&["fallback_postgres"])
            .inc();
        FEED_CANDIDATE_COUNT
            .with_label_values(&["fallback_postgres"])
            .observe(total_count as f64);

        Ok((page_posts, has_more, total_count))
    }

    async fn rank_candidates(
        &self,
        candidates: Vec<FeedCandidate>,
        max_items: usize,
    ) -> Result<Vec<RankedPost>> {
        let mut ranked = Vec::new();
        for candidate in candidates {
            let post_id = candidate.post_id_uuid()?;
            let combined_score = self.compute_score(&candidate);
            ranked.push(RankedPost {
                post_id,
                combined_score,
                reason: "combined_score".to_string(),
            });
        }

        ranked.sort_by(|a, b| b.combined_score.partial_cmp(&a.combined_score).unwrap());
        Ok(ranked.into_iter().take(max_items).collect())
    }

    fn compute_score(&self, candidate: &FeedCandidate) -> f64 {
        let freshness = candidate.freshness_score * self.freshness_weight;
        let engagement = candidate.engagement_score * self.engagement_weight;
        let affinity = candidate.affinity_score * self.affinity_weight;

        freshness + engagement + affinity - self.freshness_lambda
    }

    async fn get_followees_candidates(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<FeedCandidate>> {
        #[derive(clickhouse::Row, serde::Deserialize)]
        struct CandidateRow {
            post_id: String,
            author_id: String,
            likes: u32,
            comments: u32,
            shares: u32,
            impressions: u32,
            freshness_score: f64,
            engagement_score: f64,
            affinity_score: f64,
            combined_score: f64,
            created_at: DateTime<Utc>,
        }

        let query = r#"
            SELECT post_id, author_id, likes, comments, shares, impressions,
                   freshness_score, engagement_score, affinity_score, combined_score, created_at
            FROM feed_candidates_followees
            WHERE user_id = ?
            ORDER BY combined_score DESC
            LIMIT ?
        "#;

        let rows = self
            .ch_client
            .query_with_params::<CandidateRow, _>(query, |stmt| {
                stmt.bind(user_id).bind(limit as u64)
            })
            .await?;
        Ok(rows
            .into_iter()
            .map(|row| FeedCandidate {
                post_id: row.post_id,
                author_id: row.author_id,
                likes: row.likes,
                comments: row.comments,
                shares: row.shares,
                impressions: row.impressions,
                freshness_score: row.freshness_score,
                engagement_score: row.engagement_score,
                affinity_score: row.affinity_score,
                combined_score: row.combined_score,
                created_at: row.created_at,
            })
            .collect())
    }

    async fn get_trending_candidates(&self, limit: usize) -> Result<Vec<FeedCandidate>> {
        #[derive(clickhouse::Row, serde::Deserialize)]
        struct CandidateRow {
            post_id: String,
            author_id: String,
            likes: u32,
            comments: u32,
            shares: u32,
            impressions: u32,
            freshness_score: f64,
            engagement_score: f64,
            affinity_score: f64,
            combined_score: f64,
            created_at: DateTime<Utc>,
        }

        let query = r#"
            SELECT post_id, author_id, likes, comments, shares, impressions,
                   freshness_score, engagement_score, affinity_score, combined_score, created_at
            FROM feed_candidates_trending
            ORDER BY combined_score DESC
            LIMIT ?
        "#;

        let rows = self
            .ch_client
            .query_with_params::<CandidateRow, _>(query, |stmt| stmt.bind(limit as u64))
            .await?;
        Ok(rows
            .into_iter()
            .map(|row| FeedCandidate {
                post_id: row.post_id,
                author_id: row.author_id,
                likes: row.likes,
                comments: row.comments,
                shares: row.shares,
                impressions: row.impressions,
                freshness_score: row.freshness_score,
                engagement_score: row.engagement_score,
                affinity_score: row.affinity_score,
                combined_score: row.combined_score,
                created_at: row.created_at,
            })
            .collect())
    }

    async fn get_affinity_candidates(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<FeedCandidate>> {
        #[derive(clickhouse::Row, serde::Deserialize)]
        struct CandidateRow {
            post_id: String,
            author_id: String,
            likes: u32,
            comments: u32,
            shares: u32,
            impressions: u32,
            freshness_score: f64,
            engagement_score: f64,
            affinity_score: f64,
            combined_score: f64,
            created_at: DateTime<Utc>,
        }

        let query = r#"
            SELECT post_id, author_id, likes, comments, shares, impressions,
                   freshness_score, engagement_score, affinity_score, combined_score, created_at
            FROM feed_candidates_affinity
            WHERE user_id = ?
            ORDER BY combined_score DESC
            LIMIT ?
        "#;

        let rows = self
            .ch_client
            .query_with_params::<CandidateRow, _>(query, |stmt| {
                stmt.bind(user_id).bind(limit as u64)
            })
            .await?;
        Ok(rows
            .into_iter()
            .map(|row| FeedCandidate {
                post_id: row.post_id,
                author_id: row.author_id,
                likes: row.likes,
                comments: row.comments,
                shares: row.shares,
                impressions: row.impressions,
                freshness_score: row.freshness_score,
                engagement_score: row.engagement_score,
                affinity_score: row.affinity_score,
                combined_score: row.combined_score,
                created_at: row.created_at,
            })
            .collect())
    }
}

#[derive(Debug, Clone)]
pub struct FeedRankingConfig {
    pub freshness_weight: f64,
    pub engagement_weight: f64,
    pub affinity_weight: f64,
    pub freshness_lambda: f64,
    pub max_candidates: usize,
    pub candidate_prefetch_multiplier: usize,
    pub fallback_cache_ttl_secs: u64,
}

impl From<FeedConfig> for FeedRankingConfig {
    fn from(config: FeedConfig) -> Self {
        FeedRankingConfig {
            freshness_weight: config.freshness_weight,
            engagement_weight: config.engagement_weight,
            affinity_weight: config.affinity_weight,
            freshness_lambda: config.freshness_lambda,
            max_candidates: config.max_candidates.max(1),
            candidate_prefetch_multiplier: config.candidate_prefetch_multiplier.max(1),
            fallback_cache_ttl_secs: config.fallback_cache_ttl_secs.max(1),
        }
    }
}

impl From<&FeedConfig> for FeedRankingConfig {
    fn from(config: &FeedConfig) -> Self {
        FeedRankingConfig {
            freshness_weight: config.freshness_weight,
            engagement_weight: config.engagement_weight,
            affinity_weight: config.affinity_weight,
            freshness_lambda: config.freshness_lambda,
            max_candidates: config.max_candidates.max(1),
            candidate_prefetch_multiplier: config.candidate_prefetch_multiplier.max(1),
            fallback_cache_ttl_secs: config.fallback_cache_ttl_secs.max(1),
        }
    }
}

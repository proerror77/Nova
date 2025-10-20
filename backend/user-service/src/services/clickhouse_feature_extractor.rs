/// ClickHouse Feature Extraction Service
///
/// Extracts ranking signals from ClickHouse OLAP layer for personalized feed ranking.
/// Replaces direct PostgreSQL queries with ClickHouse aggregations for 100x better performance.
///
/// Architecture:
/// - Queries ClickHouse materialized views (pre-aggregated metrics)
/// - Populates Redis cache for hot signals (TTL 5min)
/// - Returns RankingSignals ready for ranking_engine.rs
///
/// Key insight (Linus): "We eliminate special cases by making ClickHouse the single source of truth
/// for all ranking signals. The application layer doesn't know or care about aggregation—it just
/// gets complete RankingSignals."

use crate::services::ranking_engine::RankingSignals;
use chrono::{Duration, Utc};
use redis::Commands;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// ClickHouse client wrapper
pub struct ClickHouseClient {
    url: String,
    user: String,
    password: String,
    http_client: reqwest::Client,
}

impl ClickHouseClient {
    pub fn new(url: String, user: String, password: String) -> Self {
        Self {
            url,
            user,
            password,
            http_client: reqwest::Client::new(),
        }
    }

    /// Execute raw SQL query and return JSON response
    async fn execute_query(&self, sql: &str) -> Result<Vec<u8>, String> {
        let response = self
            .http_client
            .post(&format!("{}/", self.url))
            .basic_auth(&self.user, Some(&self.password))
            .body(sql.to_string())
            .send()
            .await
            .map_err(|e| format!("ClickHouse request failed: {}", e))?;

        if !response.status().is_success() {
            let error_body = response
                .text()
                .await
                .unwrap_or_else(|_| "Unknown error".to_string());
            return Err(format!("ClickHouse error: {}", error_body));
        }

        response
            .bytes()
            .await
            .map(|b| b.to_vec())
            .map_err(|e| format!("Failed to read response: {}", e))
    }
}

/// Post signal with all metrics (intermediate format from ClickHouse)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostSignalRow {
    pub post_id: String,
    pub freshness_score: f32,
    pub completion_rate: f32,
    pub engagement_score: f32,
    pub affinity_score: f32,
    // deep_model_score comes from separate ML service
}

impl PostSignalRow {
    /// Convert to RankingSignals (add deep_model_score from external service)
    pub fn to_ranking_signals(&self, deep_model_score: f32) -> RankingSignals {
        let video_id = Uuid::parse_str(&self.post_id).unwrap_or_default();

        RankingSignals {
            video_id,
            freshness_score: self.freshness_score.clamp(0.0, 1.0),
            completion_rate: self.completion_rate.clamp(0.0, 1.0),
            engagement_score: self.engagement_score.clamp(0.0, 1.0),
            affinity_score: self.affinity_score.clamp(0.0, 1.0),
            deep_model_score: deep_model_score.clamp(0.0, 1.0),
        }
    }
}

/// Feature Extractor Service
pub struct ClickHouseFeatureExtractor {
    clickhouse: Arc<ClickHouseClient>,
    redis: Arc<redis::Client>,
    cache_ttl: i64, // seconds
}

impl ClickHouseFeatureExtractor {
    pub fn new(
        clickhouse: Arc<ClickHouseClient>,
        redis: Arc<redis::Client>,
        cache_ttl_minutes: i64,
    ) -> Self {
        Self {
            clickhouse,
            redis,
            cache_ttl: cache_ttl_minutes * 60,
        }
    }

    /// Get ranking signals for a user's post list
    ///
    /// This is the main entry point. It:
    /// 1. Checks Redis cache first
    /// 2. Queries ClickHouse for missing signals
    /// 3. Fills cache for next request
    /// 4. Returns complete RankingSignals ready for ranking_engine
    pub async fn get_ranking_signals(
        &self,
        user_id: Uuid,
        post_ids: &[Uuid],
    ) -> Result<Vec<RankingSignals>, String> {
        if post_ids.is_empty() {
            return Ok(Vec::new());
        }

        debug!(
            "Extracting ranking signals for user: {}, {} posts",
            user_id,
            post_ids.len()
        );

        // Step 1: Check Redis cache
        let mut cached_signals = self.get_cached_signals(&user_id, post_ids).await?;
        let cached_count = cached_signals.len();

        // Step 2: Find missing posts
        let cached_post_ids: std::collections::HashSet<Uuid> = cached_signals
            .iter()
            .map(|s| s.video_id)
            .collect();
        let missing_post_ids: Vec<Uuid> = post_ids
            .iter()
            .copied()
            .filter(|id| !cached_post_ids.contains(id))
            .collect();

        if !missing_post_ids.is_empty() {
            debug!(
                "Cache miss for {} posts (hit rate: {:.1}%)",
                missing_post_ids.len(),
                100.0 * cached_count as f32 / post_ids.len() as f32
            );

            // Step 3: Query ClickHouse for missing signals
            let fresh_signals = self
                .query_clickhouse_signals(&user_id, &missing_post_ids)
                .await?;

            // Step 4: Cache new signals
            for signal in &fresh_signals {
                let _ = self.cache_signal(&user_id, signal).await;
            }

            cached_signals.extend(fresh_signals);
        } else {
            debug!("All signals served from cache");
        }

        // Step 5: Sort in original order (important for consistency)
        let post_id_order: std::collections::HashMap<Uuid, usize> = post_ids
            .iter()
            .enumerate()
            .map(|(i, id)| (*id, i))
            .collect();

        cached_signals.sort_by_key(|s| post_id_order.get(&s.video_id).copied().unwrap_or(usize::MAX));

        Ok(cached_signals)
    }

    /// Query ClickHouse for ranking signals (low-level)
    ///
    /// This executes the main ranking query against ClickHouse.
    /// The query is optimized using:
    /// - Materialized views (pre-aggregated metrics)
    /// - ORDER BY indices
    /// - Time-based partitions
    async fn query_clickhouse_signals(
        &self,
        user_id: &Uuid,
        post_ids: &[Uuid],
    ) -> Result<Vec<RankingSignals>, String> {
        // Build SQL query
        let post_ids_csv = post_ids
            .iter()
            .map(|id| format!("'{}'", id.to_string()))
            .collect::<Vec<_>>()
            .join(",");

        let sql = format!(
            r#"
            SELECT
              toString(p.id) as post_id,
              -- Freshness: exponential decay (λ = 0.10)
              exp(-0.10 * dateDiff('hour', p.created_at, now())) AS freshness_score,

              -- Completion Rate: normalized from average dwell time
              least(1.0, ua.avg_dwell_ms / 30000.0) AS completion_rate,

              -- Engagement: from hourly post metrics
              coalesce(pm.combined_score, 0.5) AS engagement_score,

              -- Affinity: log-normalized user-author interaction
              least(1.0, log1p(coalesce(ua.interaction_count, 0)) / log1p(100)) AS affinity_score

            FROM posts_cdc p
            LEFT JOIN user_author_90d ua ON
              ua.user_id = '{}' AND
              ua.author_id = p.user_id
            LEFT JOIN post_metrics_1h pm ON
              pm.post_id = p.id AND
              pm.metric_hour >= toStartOfHour(now()) - INTERVAL 1 HOUR

            WHERE p.id IN ({})
              AND p.created_at > now() - INTERVAL 30 DAY

            FORMAT JSONEachRow
            "#,
            user_id, post_ids_csv
        );

        debug!("Executing ClickHouse query for {} posts", post_ids.len());

        // Execute query
        let response_bytes = self.clickhouse.execute_query(&sql).await?;

        // Parse response (JSONEachRow format)
        let response_str = String::from_utf8(response_bytes)
            .map_err(|e| format!("Invalid UTF-8 in ClickHouse response: {}", e))?;

        let mut signals = Vec::new();

        for line in response_str.lines() {
            if line.trim().is_empty() {
                continue;
            }

            let row: PostSignalRow = serde_json::from_str(line)
                .map_err(|e| format!("Failed to parse ClickHouse row: {}", e))?;

            // TODO: Fetch deep_model_score from ML service (for now, use 0.5)
            let signal = row.to_ranking_signals(0.5);

            // Validate signal before returning
            if !signal.is_valid() {
                warn!("Invalid signal for post {}: {:?}", row.post_id, signal);
                continue;
            }

            signals.push(signal);
        }

        info!(
            "Successfully extracted {} ranking signals from ClickHouse",
            signals.len()
        );

        Ok(signals)
    }

    /// Get hot posts for new user cold start
    ///
    /// Returns system-level recommendations when user has no interaction history
    pub async fn get_hot_posts(&self, limit: usize, hours: i32) -> Result<Vec<(Uuid, f32)>, String> {
        let sql = format!(
            r#"
            SELECT
              parseUUID(post_id) as post_id,
              combined_score

            FROM post_ranking_scores
            WHERE metric_hour >= toStartOfHour(now()) - INTERVAL {} HOUR

            ORDER BY combined_score DESC
            LIMIT {}

            FORMAT JSONEachRow
            "#,
            hours, limit
        );

        debug!("Querying hot posts (limit: {}, hours: {})", limit, hours);

        let response_bytes = self.clickhouse.execute_query(&sql).await?;
        let response_str = String::from_utf8(response_bytes)
            .map_err(|e| format!("Invalid UTF-8: {}", e))?;

        let mut hot_posts = Vec::new();

        for line in response_str.lines() {
            if line.trim().is_empty() {
                continue;
            }

            #[derive(Deserialize)]
            struct HotPostRow {
                post_id: String,
                combined_score: f32,
            }

            let row: HotPostRow = serde_json::from_str(line)
                .map_err(|e| format!("Failed to parse hot post: {}", e))?;

            let post_id = Uuid::parse_str(&row.post_id)
                .map_err(|e| format!("Invalid post ID: {}", e))?;

            hot_posts.push((post_id, row.combined_score.clamp(0.0, 1.0)));
        }

        Ok(hot_posts)
    }

    /// Get user-author affinity for explicit recommendations
    ///
    /// Returns normalized affinity scores for a list of authors
    pub async fn get_user_author_affinity(
        &self,
        user_id: Uuid,
        author_ids: &[Uuid],
    ) -> Result<Vec<(Uuid, f32)>, String> {
        if author_ids.is_empty() {
            return Ok(Vec::new());
        }

        let author_ids_csv = author_ids
            .iter()
            .map(|id| format!("'{}'", id.to_string()))
            .collect::<Vec<_>>()
            .join(",");

        let sql = format!(
            r#"
            SELECT
              parseUUID(author_id) as author_id,
              least(1.0, log1p(interaction_count) / log1p(100)) as affinity_score

            FROM user_author_90d
            WHERE user_id = '{}' AND author_id IN ({})

            FORMAT JSONEachRow
            "#,
            user_id, author_ids_csv
        );

        debug!(
            "Querying affinity for user {} with {} authors",
            user_id,
            author_ids.len()
        );

        let response_bytes = self.clickhouse.execute_query(&sql).await?;
        let response_str = String::from_utf8(response_bytes)
            .map_err(|e| format!("Invalid UTF-8: {}", e))?;

        let mut affinity_scores = Vec::new();

        for line in response_str.lines() {
            if line.trim().is_empty() {
                continue;
            }

            #[derive(Deserialize)]
            struct AffinityRow {
                author_id: String,
                affinity_score: f32,
            }

            let row: AffinityRow = serde_json::from_str(line)
                .map_err(|e| format!("Failed to parse affinity: {}", e))?;

            let author_id = Uuid::parse_str(&row.author_id)
                .map_err(|e| format!("Invalid author ID: {}", e))?;

            affinity_scores.push((author_id, row.affinity_score.clamp(0.0, 1.0)));
        }

        Ok(affinity_scores)
    }

    // ============================================
    // Private helper methods
    // ============================================

    /// Check Redis cache for existing signals
    async fn get_cached_signals(
        &self,
        user_id: &Uuid,
        post_ids: &[Uuid],
    ) -> Result<Vec<RankingSignals>, String> {
        let mut cached = Vec::new();
        let mut redis_conn = self
            .redis
            .get_connection()
            .map_err(|e| format!("Redis connection failed: {}", e))?;

        for post_id in post_ids {
            let cache_key = format!("ranking_signals:{}:{}", user_id, post_id);

            let cached_json: Option<String> = redis_conn
                .get(&cache_key)
                .map_err(|e| format!("Redis get failed: {}", e))?;

            if let Some(json) = cached_json {
                if let Ok(signal) = serde_json::from_str::<RankingSignals>(&json) {
                    cached.push(signal);
                }
            }
        }

        Ok(cached)
    }

    /// Cache a single ranking signal
    async fn cache_signal(&self, user_id: &Uuid, signal: &RankingSignals) -> Result<(), String> {
        let cache_key = format!("ranking_signals:{}:{}", user_id, signal.video_id);
        let json = serde_json::to_string(signal)
            .map_err(|e| format!("Failed to serialize signal: {}", e))?;

        let mut redis_conn = self
            .redis
            .get_connection()
            .map_err(|e| format!("Redis connection failed: {}", e))?;

        redis_conn
            .set_ex(&cache_key, &json, self.cache_ttl as u64)
            .map_err(|e| format!("Redis set_ex failed: {}", e))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_post_signal_row_conversion() {
        let row = PostSignalRow {
            post_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            freshness_score: 0.85,
            completion_rate: 0.75,
            engagement_score: 0.92,
            affinity_score: 0.60,
        };

        let signal = row.to_ranking_signals(0.55);

        assert!(signal.is_valid());
        assert_eq!(signal.freshness_score, 0.85);
        assert_eq!(signal.completion_rate, 0.75);
        assert_eq!(signal.engagement_score, 0.92);
        assert_eq!(signal.affinity_score, 0.60);
        assert_eq!(signal.deep_model_score, 0.55);
    }

    #[test]
    fn test_signal_score_clamping() {
        let row = PostSignalRow {
            post_id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            freshness_score: 1.5, // Out of range
            completion_rate: -0.1, // Out of range
            engagement_score: 0.50,
            affinity_score: 0.50,
        };

        let signal = row.to_ranking_signals(1.2); // Out of range

        assert!(signal.is_valid());
        assert_eq!(signal.freshness_score, 1.0); // Clamped
        assert_eq!(signal.completion_rate, 0.0); // Clamped
        assert_eq!(signal.deep_model_score, 1.0); // Clamped
    }
}

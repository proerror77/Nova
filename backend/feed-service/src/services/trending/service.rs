/// Trending Service
///
/// Main service for querying and delivering trending content
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::db::trending_repo::{ContentType, EventType, TimeWindow, TrendingItem, TrendingRepo};
use crate::error::{AppError, Result};

const TRENDING_CACHE_TTL: u64 = 300; // 5 minutes

/// Trending response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrendingResponse {
    pub items: Vec<TrendingItemWithMetadata>,
    pub count: usize,
    pub time_window: String,
    pub category: Option<String>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// Trending item with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrendingItemWithMetadata {
    pub rank: i32,
    pub content_id: String,
    pub content_type: String,
    pub score: f64,
    pub views_count: i32,
    pub likes_count: i32,
    pub shares_count: i32,
    pub comments_count: i32,

    // Additional metadata (joined from content tables)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub creator_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub creator_username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thumbnail_url: Option<String>,
}

impl From<TrendingItem> for TrendingItemWithMetadata {
    fn from(item: TrendingItem) -> Self {
        Self {
            rank: item.rank,
            content_id: item.content_id.to_string(),
            content_type: item.content_type,
            score: item.score,
            views_count: item.views_count,
            likes_count: item.likes_count,
            shares_count: item.shares_count,
            comments_count: item.comments_count,
            title: None,
            creator_id: None,
            creator_username: None,
            thumbnail_url: None,
        }
    }
}

/// Trending service
pub struct TrendingService {
    repo: TrendingRepo,
    pool: PgPool,
    redis: Option<ConnectionManager>,
}

impl TrendingService {
    pub fn new(pool: PgPool, redis: Option<ConnectionManager>) -> Self {
        Self {
            repo: TrendingRepo::new(pool.clone()),
            pool,
            redis,
        }
    }

    /// Get trending content
    pub async fn get_trending(
        &self,
        time_window: TimeWindow,
        category: Option<&str>,
        limit: usize,
    ) -> Result<TrendingResponse> {
        let cache_key = format!(
            "nova:trending:{}:{}",
            time_window.as_str(),
            category.unwrap_or("all")
        );

        // Try Redis cache first
        if let Some(redis) = &self.redis {
            if let Ok(cached) = self.get_from_cache(redis, &cache_key).await {
                debug!("Trending cache hit: {}", cache_key);
                return Ok(cached);
            }
        }

        // Fetch from database
        let items = self
            .repo
            .get_trending(time_window, category, limit as i64)
            .await?;

        // Enrich items with metadata
        let enriched = self.enrich_trending_items(items).await?;

        let response = TrendingResponse {
            count: enriched.len(),
            items: enriched,
            time_window: time_window.to_string(),
            category: category.map(String::from),
            updated_at: chrono::Utc::now(),
        };

        // Cache the response
        if let Some(redis) = &self.redis {
            if let Err(e) = self.cache_response(redis, &cache_key, &response).await {
                warn!("Failed to cache trending response: {}", e);
            }
        }

        Ok(response)
    }

    /// Get trending by content type
    pub async fn get_trending_by_type(
        &self,
        content_type: ContentType,
        time_window: TimeWindow,
        limit: usize,
    ) -> Result<TrendingResponse> {
        let items = self
            .repo
            .get_trending_by_type(content_type, time_window, limit as i64)
            .await?;

        let enriched = self.enrich_trending_items(items).await?;

        Ok(TrendingResponse {
            count: enriched.len(),
            items: enriched,
            time_window: time_window.to_string(),
            category: None,
            updated_at: chrono::Utc::now(),
        })
    }

    /// Record engagement event
    pub async fn record_engagement(
        &self,
        content_id: Uuid,
        content_type: ContentType,
        user_id: Uuid,
        event_type: EventType,
    ) -> Result<()> {
        self.repo
            .record_engagement(
                content_id,
                content_type,
                user_id,
                event_type,
                None, // session_id
                None, // ip_address
                None, // user_agent
            )
            .await?;

        // Invalidate cache for affected time windows
        if let Some(redis) = &self.redis {
            let _ = self.invalidate_cache_for_content(redis, content_id).await;
        }

        Ok(())
    }

    /// Enrich trending items with content metadata
    async fn enrich_trending_items(
        &self,
        items: Vec<TrendingItem>,
    ) -> Result<Vec<TrendingItemWithMetadata>> {
        let mut enriched = Vec::new();

        for item in items {
            let mut meta = TrendingItemWithMetadata::from(item.clone());

            // Enrich based on content type
            match item.content_type.as_str() {
                "video" => {
                    if let Ok(Some((title, creator_id, username, thumbnail))) =
                        self.get_video_metadata(item.content_id).await
                    {
                        meta.title = Some(title);
                        meta.creator_id = Some(creator_id);
                        meta.creator_username = Some(username);
                        meta.thumbnail_url = Some(thumbnail);
                    }
                }
                "post" => {
                    if let Ok(Some((content, creator_id, username))) =
                        self.get_post_metadata(item.content_id).await
                    {
                        meta.title = Some(content);
                        meta.creator_id = Some(creator_id);
                        meta.creator_username = Some(username);
                    }
                }
                "stream" => {
                    if let Ok(Some((title, creator_id, username, thumbnail))) =
                        self.get_stream_metadata(item.content_id).await
                    {
                        meta.title = Some(title);
                        meta.creator_id = Some(creator_id);
                        meta.creator_username = Some(username);
                        meta.thumbnail_url = Some(thumbnail);
                    }
                }
                _ => {}
            }

            enriched.push(meta);
        }

        Ok(enriched)
    }

    /// Get video metadata
    async fn get_video_metadata(
        &self,
        video_id: Uuid,
    ) -> Result<Option<(String, String, String, String)>> {
        let result = sqlx::query_as::<_, (String, Uuid, String, String)>(
            r#"
            SELECT v.title, v.user_id, u.username, v.thumbnail_url
            FROM videos v
            JOIN users u ON v.user_id = u.id
            WHERE v.id = $1 AND v.deleted_at IS NULL
            "#,
        )
        .bind(video_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to fetch video metadata: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(result.map(|(title, user_id, username, thumbnail)| {
            (title, user_id.to_string(), username, thumbnail)
        }))
    }

    /// Get post metadata
    async fn get_post_metadata(&self, post_id: Uuid) -> Result<Option<(String, String, String)>> {
        let result = sqlx::query_as::<_, (String, Uuid, String)>(
            r#"
            SELECT p.content, p.user_id, u.username
            FROM posts p
            JOIN users u ON p.user_id = u.id
            WHERE p.id = $1 AND p.deleted_at IS NULL
            "#,
        )
        .bind(post_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to fetch post metadata: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(result.map(|(content, user_id, username)| (content, user_id.to_string(), username)))
    }

    /// Get stream metadata
    async fn get_stream_metadata(
        &self,
        stream_id: Uuid,
    ) -> Result<Option<(String, String, String, String)>> {
        let result = sqlx::query_as::<_, (String, Uuid, String, Option<String>)>(
            r#"
            SELECT s.title, s.user_id, u.username, s.thumbnail_url
            FROM streams s
            JOIN users u ON s.user_id = u.id
            WHERE s.id = $1
            "#,
        )
        .bind(stream_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to fetch stream metadata: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(result.map(|(title, user_id, username, thumbnail)| {
            (
                title,
                user_id.to_string(),
                username,
                thumbnail.unwrap_or_default(),
            )
        }))
    }

    /// Get from cache
    async fn get_from_cache(
        &self,
        redis: &ConnectionManager,
        key: &str,
    ) -> Result<TrendingResponse> {
        let mut conn = redis.clone();
        let cached: Option<String> = conn.get(key).await.map_err(|e| {
            error!("Redis GET failed: {}", e);
            AppError::Internal("Cache read failed".to_string())
        })?;

        if let Some(json) = cached {
            serde_json::from_str(&json).map_err(|e| {
                error!("Failed to deserialize cached trending: {}", e);
                AppError::Internal("Cache deserialization failed".to_string())
            })
        } else {
            Err(AppError::NotFound("Cache miss".to_string()))
        }
    }

    /// Cache response
    async fn cache_response(
        &self,
        redis: &ConnectionManager,
        key: &str,
        response: &TrendingResponse,
    ) -> Result<()> {
        let mut conn = redis.clone();
        let json = serde_json::to_string(response).map_err(|e| {
            error!("Failed to serialize trending response: {}", e);
            AppError::Internal("Serialization failed".to_string())
        })?;

        conn.set_ex(key, json, TRENDING_CACHE_TTL)
            .await
            .map_err(|e| {
                error!("Redis SET failed: {}", e);
                AppError::Internal("Cache write failed".to_string())
            })?;

        Ok(())
    }

    /// Invalidate cache for content
    async fn invalidate_cache_for_content(
        &self,
        redis: &ConnectionManager,
        _content_id: Uuid,
    ) -> Result<()> {
        let mut conn = redis.clone();

        // Invalidate all trending caches (simple approach)
        // In production, use more granular invalidation
        let patterns = vec![
            "nova:trending:1h:*",
            "nova:trending:24h:*",
            "nova:trending:7d:*",
        ];

        for pattern in patterns {
            // Note: DEL with pattern requires SCAN in production
            // For now, we just invalidate specific known keys
            let keys = vec![
                format!("{}all", pattern.trim_end_matches('*')),
                // Add more categories as needed
            ];

            for key in keys {
                // Ignore errors during cache invalidation
                let _ = async {
                    let _: redis::RedisResult<()> = conn.del(&key).await;
                }
                .await;
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_trending_item_conversion() {
        let item = TrendingItem {
            rank: 1,
            content_id: Uuid::new_v4(),
            content_type: "video".to_string(),
            score: 450.23,
            views_count: 1000,
            likes_count: 100,
            shares_count: 50,
            comments_count: 30,
            computed_at: chrono::Utc::now(),
        };

        let meta: TrendingItemWithMetadata = item.into();
        assert_eq!(meta.rank, 1);
        assert_eq!(meta.content_type, "video");
    }

    #[test]
    fn test_cache_key_format() {
        let key = format!("nova:trending:{}:{}", "1h", "entertainment");
        assert_eq!(key, "nova:trending:1h:entertainment");
    }
}

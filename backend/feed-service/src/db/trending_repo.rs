use serde::{Deserialize, Serialize};
/// Trending Repository
///
/// Database operations for the trending/discovery system
use sqlx::PgPool;
use tracing::error;
use uuid::Uuid;

use crate::error::{AppError, Result};

/// Engagement event type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EventType {
    View,
    Like,
    Share,
    Comment,
}

impl EventType {
    /// Get weight for this event type
    pub fn weight(&self) -> f64 {
        match self {
            Self::View => 1.0,
            Self::Like => 5.0,
            Self::Share => 10.0,
            Self::Comment => 3.0,
        }
    }

    pub fn as_str(&self) -> &str {
        match self {
            Self::View => "view",
            Self::Like => "like",
            Self::Share => "share",
            Self::Comment => "comment",
        }
    }
}

impl std::fmt::Display for EventType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Content type for trending
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContentType {
    Video,
    Post,
    Stream,
}

impl ContentType {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Video => "video",
            Self::Post => "post",
            Self::Stream => "stream",
        }
    }
}

impl std::fmt::Display for ContentType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Time window for trending calculation
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TimeWindow {
    #[serde(rename = "1h")]
    OneHour,
    #[serde(rename = "24h")]
    TwentyFourHours,
    #[serde(rename = "7d")]
    SevenDays,
    #[serde(rename = "all")]
    All,
}

impl TimeWindow {
    pub fn as_str(&self) -> &str {
        match self {
            Self::OneHour => "1h",
            Self::TwentyFourHours => "24h",
            Self::SevenDays => "7d",
            Self::All => "all",
        }
    }

    pub fn hours(&self) -> i64 {
        match self {
            Self::OneHour => 1,
            Self::TwentyFourHours => 24,
            Self::SevenDays => 168,
            Self::All => 999999,
        }
    }
}

impl std::fmt::Display for TimeWindow {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Trending item
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrendingItem {
    pub rank: i32,
    pub content_id: Uuid,
    pub content_type: String,
    pub score: f64,
    pub views_count: i32,
    pub likes_count: i32,
    pub shares_count: i32,
    pub comments_count: i32,
    pub computed_at: chrono::DateTime<chrono::Utc>,
}

/// Trending metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrendingMetadata {
    pub content_type: String,
    pub category: Option<String>,
    pub time_window: String,
    pub last_computed_at: chrono::DateTime<chrono::Utc>,
    pub item_count: i32,
    pub computation_duration_ms: Option<i32>,
}

/// Trending Repository
pub struct TrendingRepo {
    pool: PgPool,
}

impl TrendingRepo {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Record an engagement event
    pub async fn record_engagement(
        &self,
        content_id: Uuid,
        content_type: ContentType,
        user_id: Uuid,
        event_type: EventType,
        session_id: Option<String>,
        ip_address: Option<String>,
        user_agent: Option<String>,
    ) -> Result<Option<Uuid>> {
        // Validate IP address if provided (but bind as string - SQLx doesn't support IpAddr directly)
        if let Some(ref ip) = ip_address {
            let _: Option<std::net::IpAddr> = ip.parse().ok();
        }

        let result = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT record_engagement($1, $2, $3, $4, $5, $6, $7)
            "#,
        )
        .bind(content_id)
        .bind(content_type.as_str())
        .bind(user_id)
        .bind(event_type.as_str())
        .bind(session_id)
        .bind(ip_address)
        .bind(user_agent)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to record engagement: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(result)
    }

    /// Get trending items for a time window and optional category
    pub async fn get_trending(
        &self,
        time_window: TimeWindow,
        category: Option<&str>,
        limit: i64,
    ) -> Result<Vec<TrendingItem>> {
        let items = sqlx::query_as::<
            _,
            (
                i32,                           // rank
                Uuid,                          // content_id
                String,                        // content_type
                f64,                           // score (NUMERIC -> f64)
                i32,                           // views_count
                i32,                           // likes_count
                i32,                           // shares_count
                i32,                           // comments_count
                chrono::DateTime<chrono::Utc>, // computed_at
            ),
        >(
            r#"
            SELECT
                rank,
                content_id,
                content_type,
                score::FLOAT8 as score,
                views_count,
                likes_count,
                shares_count,
                comments_count,
                computed_at
            FROM trending_scores
            WHERE time_window = $1
                AND ($2::VARCHAR IS NULL OR category = $2)
            ORDER BY score DESC
            LIMIT $3
            "#,
        )
        .bind(time_window.as_str())
        .bind(category)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to get trending items: {}", e);
            AppError::Database(e.to_string())
        })?
        .into_iter()
        .map(
            |(
                rank,
                content_id,
                content_type,
                score,
                views,
                likes,
                shares,
                comments,
                computed_at,
            )| {
                TrendingItem {
                    rank,
                    content_id,
                    content_type,
                    score,
                    views_count: views,
                    likes_count: likes,
                    shares_count: shares,
                    comments_count: comments,
                    computed_at,
                }
            },
        )
        .collect();

        Ok(items)
    }

    /// Refresh trending scores for a time window
    pub async fn refresh_trending_scores(
        &self,
        time_window: TimeWindow,
        category: Option<&str>,
        limit: i32,
    ) -> Result<i32> {
        let updated = sqlx::query_scalar::<_, i32>(
            r#"
            SELECT refresh_trending_scores($1, $2, $3)
            "#,
        )
        .bind(time_window.as_str())
        .bind(category)
        .bind(limit)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to refresh trending scores: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(updated)
    }

    /// Get trending metadata
    pub async fn get_trending_metadata(
        &self,
        time_window: TimeWindow,
        category: Option<&str>,
    ) -> Result<Option<TrendingMetadata>> {
        let metadata = sqlx::query_as::<
            _,
            (
                String,                        // content_type
                Option<String>,                // category
                String,                        // time_window
                chrono::DateTime<chrono::Utc>, // last_computed_at
                i32,                           // item_count
                Option<i32>,                   // computation_duration_ms
            ),
        >(
            r#"
            SELECT
                content_type,
                category,
                time_window,
                last_computed_at,
                item_count,
                computation_duration_ms
            FROM trending_metadata
            WHERE time_window = $1
                AND ($2::VARCHAR IS NULL OR category = $2)
            LIMIT 1
            "#,
        )
        .bind(time_window.as_str())
        .bind(category)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to get trending metadata: {}", e);
            AppError::Database(e.to_string())
        })?
        .map(
            |(content_type, category, time_window, last_computed_at, item_count, duration)| {
                TrendingMetadata {
                    content_type,
                    category,
                    time_window,
                    last_computed_at,
                    item_count,
                    computation_duration_ms: duration,
                }
            },
        );

        Ok(metadata)
    }

    /// Get engagement count for content
    pub async fn get_engagement_count(
        &self,
        content_id: Uuid,
        time_window: TimeWindow,
    ) -> Result<i64> {
        let count = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COUNT(*)
            FROM engagement_events
            WHERE content_id = $1
                AND created_at >= NOW() - INTERVAL '1 hour' * $2
            "#,
        )
        .bind(content_id)
        .bind(time_window.hours())
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to get engagement count: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(count)
    }

    /// Compute trending score for a specific content item
    pub async fn compute_score(
        &self,
        content_id: Uuid,
        time_window: TimeWindow,
        decay_rate: f64,
    ) -> Result<f64> {
        let score = sqlx::query_scalar::<_, f64>(
            r#"
            SELECT compute_trending_score($1, $2, $3)::FLOAT8
            "#,
        )
        .bind(content_id)
        .bind(time_window.as_str())
        .bind(decay_rate)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to compute trending score: {}", e);
            AppError::Database(e.to_string())
        })?;

        Ok(score)
    }

    /// Get trending by content type
    pub async fn get_trending_by_type(
        &self,
        content_type: ContentType,
        time_window: TimeWindow,
        limit: i64,
    ) -> Result<Vec<TrendingItem>> {
        let items = sqlx::query_as::<
            _,
            (
                i32,                           // rank
                Uuid,                          // content_id
                String,                        // content_type
                f64,                           // score
                i32,                           // views_count
                i32,                           // likes_count
                i32,                           // shares_count
                i32,                           // comments_count
                chrono::DateTime<chrono::Utc>, // computed_at
            ),
        >(
            r#"
            SELECT
                rank,
                content_id,
                content_type,
                score::FLOAT8 as score,
                views_count,
                likes_count,
                shares_count,
                comments_count,
                computed_at
            FROM trending_scores
            WHERE time_window = $1
                AND content_type = $2
            ORDER BY score DESC
            LIMIT $3
            "#,
        )
        .bind(time_window.as_str())
        .bind(content_type.as_str())
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to get trending by type: {}", e);
            AppError::Database(e.to_string())
        })?
        .into_iter()
        .map(
            |(
                rank,
                content_id,
                content_type,
                score,
                views,
                likes,
                shares,
                comments,
                computed_at,
            )| {
                TrendingItem {
                    rank,
                    content_id,
                    content_type,
                    score,
                    views_count: views,
                    likes_count: likes,
                    shares_count: shares,
                    comments_count: comments,
                    computed_at,
                }
            },
        )
        .collect();

        Ok(items)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_type_weight() {
        assert_eq!(EventType::View.weight(), 1.0);
        assert_eq!(EventType::Like.weight(), 5.0);
        assert_eq!(EventType::Share.weight(), 10.0);
        assert_eq!(EventType::Comment.weight(), 3.0);
    }

    #[test]
    fn test_time_window_hours() {
        assert_eq!(TimeWindow::OneHour.hours(), 1);
        assert_eq!(TimeWindow::TwentyFourHours.hours(), 24);
        assert_eq!(TimeWindow::SevenDays.hours(), 168);
    }

    #[test]
    fn test_content_type_str() {
        assert_eq!(ContentType::Video.as_str(), "video");
        assert_eq!(ContentType::Post.as_str(), "post");
        assert_eq!(ContentType::Stream.as_str(), "stream");
    }
}

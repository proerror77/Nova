use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::types::Json;
use sqlx::FromRow;
use uuid::Uuid;

// ============================================
// Post Models
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Post {
    pub id: Uuid,
    pub user_id: Uuid,
    pub content: Option<String>,
    pub caption: Option<String>,
    pub media_key: String,
    pub media_type: String, // 'image', 'video', 'live_photo', 'mixed', or 'none'
    pub media_urls: Json<Vec<String>>, // CDN URLs for attached media (JSONB in DB)
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
    /// Legacy soft-delete column which may be either a boolean or timestamp
    /// depending on the deployed schema version. We map it as text for maximum
    /// compatibility but do not rely on it for filtering – `deleted_at` is the
    /// canonical flag for soft-deletion.
    pub soft_delete: Option<String>,
    /// Account type used when post was created: "primary" or "alias" (Issue #259)
    #[sqlx(default)]
    pub author_account_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PostImage {
    pub id: Uuid,
    pub post_id: Uuid,
    pub s3_key: String,
    pub status: String,
    pub size_variant: String,
    pub file_size: Option<i32>,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub url: Option<String>,
    pub error_message: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PostMetadata {
    pub post_id: Uuid,
    pub like_count: i32,
    pub comment_count: i32,
    pub view_count: i32,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct UploadSession {
    pub id: Uuid,
    pub post_id: Uuid,
    pub upload_token: String,
    pub file_hash: Option<String>,
    pub expires_at: DateTime<Utc>,
    pub is_completed: bool,
    pub created_at: DateTime<Utc>,
}

// ============================================
// Post Response Models
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoMetadata {
    pub id: String,
    pub cdn_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub duration_seconds: Option<i32>,
    pub position: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostResponse {
    pub id: String,
    pub user_id: String,
    pub caption: Option<String>,
    pub thumbnail_url: Option<String>,
    pub medium_url: Option<String>,
    pub original_url: Option<String>,
    pub videos: Option<Vec<VideoMetadata>>,
    pub content_type: String, // 'image', 'video', 'live_photo', 'mixed', or 'none'
    pub like_count: i32,
    pub comment_count: i32,
    pub view_count: i32,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImageSizes {
    pub thumbnail_url: Option<String>,
    pub medium_url: Option<String>,
    pub original_url: Option<String>,
}

// ============================================
// Feed Models (for ClickHouse integration)
// ============================================

/// Feed ranking request parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedRankingRequest {
    pub user_id: Uuid,
    pub limit: u32,
    pub offset: u32,
    pub algo: String, // "ch" (ClickHouse), "time" (timeline)
    pub cursor: Option<String>,
}

/// Post candidate from ClickHouse with raw metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostCandidate {
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub likes: u32,
    pub comments: u32,
    pub shares: u32,
    pub impressions: u32,
}

/// Ranked post with computed scores
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankedPost {
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub freshness_score: f32,
    pub engagement_score: f32,
    pub affinity_score: f32,
    pub combined_score: f32,
    pub reason: String, // "follow", "trending", "affinity"
}

/// Feed response with pagination
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedResponse {
    pub posts: Vec<Uuid>,
    pub cursor: Option<String>,
    pub has_more: bool,
    pub total_count: usize,
}

/// Feed metrics for observability
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedMetrics {
    pub cache_hit: bool,
    pub source: String, // "redis", "clickhouse", "fallback"
    pub query_time_ms: u64,
    pub candidate_count: usize,
    pub final_count: usize,
}

// Note: Comment, Like, and Share models are defined in social-service.
// PostMetadata still contains like_count/comment_count for display purposes,
// but these values are fetched from social-service via gRPC.

// ============================================
// Bookmark Models
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Bookmark {
    pub id: Uuid,
    pub user_id: Uuid,
    pub post_id: Uuid,
    pub bookmarked_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookmarkResponse {
    pub id: String,
    pub user_id: String,
    pub post_id: String,
    pub bookmarked_at: String,
}

// ============================================
// Channels
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Channel {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub category: Option<String>,
    pub subscriber_count: i64,
    pub slug: Option<String>,
    pub icon_url: Option<String>,
    pub display_order: Option<i32>,
    pub is_enabled: Option<bool>,
    pub topic_keywords: Option<serde_json::Value>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

// ============================================
// Post-Channel Association
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PostChannel {
    pub post_id: Uuid,
    pub channel_id: Uuid,
    pub confidence: f32,
    pub tagged_by: String,
    pub created_at: DateTime<Utc>,
}

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

// ============================================
// Post Models
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Post {
    pub id: Uuid,
    pub user_id: Uuid,
    pub caption: Option<String>,
    pub image_key: String,
    pub image_sizes: Option<serde_json::Value>,
    pub status: String,
    pub content_type: String, // 'image', 'video', or 'mixed'
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub soft_delete: Option<DateTime<Utc>>,
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
    pub content_type: String, // 'image', 'video', or 'mixed'
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

// ============================================
// Comment Models
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Comment {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub parent_comment_id: Option<Uuid>, // For nested comments/replies
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub soft_delete: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentResponse {
    pub id: String,
    pub post_id: String,
    pub user_id: String,
    pub username: Option<String>,
    pub avatar_url: Option<String>,
    pub content: String,
    pub parent_comment_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub is_edited: bool,
}

// ============================================
// Like Models
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Like {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LikeResponse {
    pub id: String,
    pub post_id: String,
    pub user_id: String,
    pub created_at: String,
}

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
// Post Share Models
// ============================================

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PostShare {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub share_via: Option<String>,
    pub shared_with_user_id: Option<Uuid>,
    pub shared_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostShareResponse {
    pub id: String,
    pub post_id: String,
    pub user_id: String,
    pub share_via: Option<String>,
    pub shared_with_user_id: Option<String>,
    pub shared_at: String,
}

pub mod video;

// Re-export commonly used types from video module
pub use video::{UploadStatus, ResumableUpload, UploadChunk, VideoEntity, VideoStatus};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub username: String,
    pub password_hash: String,
    pub email_verified: bool,
    pub is_active: bool,
    pub totp_secret: Option<String>,
    pub totp_enabled: bool,
    pub two_fa_enabled_at: Option<DateTime<Utc>>,
    pub failed_login_attempts: i32,
    pub locked_until: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_login_at: Option<DateTime<Utc>>,
    // Profile fields
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_photo_url: Option<String>,
    pub location: Option<String>,
    pub private_account: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserProfile {
    pub id: String,
    pub username: String,
    pub email: Option<String>, // Only shown to self
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_photo_url: Option<String>,
    pub location: Option<String>,
    pub private_account: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UpdateUserProfileRequest {
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_photo_url: Option<String>,
    pub location: Option<String>,
    pub private_account: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Session {
    pub id: Uuid,
    pub user_id: Uuid,
    pub access_token_hash: String,
    pub expires_at: DateTime<Utc>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct RefreshToken {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token_hash: String,
    pub expires_at: DateTime<Utc>,
    pub is_revoked: bool,
    pub revoked_at: Option<DateTime<Utc>>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct EmailVerification {
    pub id: Uuid,
    pub user_id: Uuid,
    pub email: String,
    pub token_hash: String,
    pub expires_at: DateTime<Utc>,
    pub is_used: bool,
    pub used_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PasswordReset {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token_hash: String,
    pub expires_at: DateTime<Utc>,
    pub is_used: bool,
    pub used_at: Option<DateTime<Utc>>,
    pub ip_address: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct AuthLog {
    pub id: i64,
    pub user_id: Option<Uuid>,
    pub event_type: String,
    pub status: String,
    pub email: Option<String>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub metadata: Option<serde_json::Value>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct OAuthConnection {
    pub id: Uuid,
    pub user_id: Uuid,
    pub provider: String, // "apple", "google", "facebook"
    pub provider_user_id: String,
    pub provider_email: Option<String>,
    pub display_name: Option<String>,
    pub access_token_hash: String,
    pub refresh_token_hash: Option<String>,
    pub token_expires_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

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

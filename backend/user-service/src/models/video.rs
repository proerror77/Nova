/// Video models and data structures for Phase 4
///
/// Defines DTOs, domain models, and database entities for video functionality.
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ========================================
// Video Domain Models
// ========================================

/// Video status in the system lifecycle
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VideoStatus {
    /// File is being uploaded
    Uploading,
    /// Processing (transcoding, thumbnail extraction)
    Processing,
    /// Published and visible in feed
    Published,
    /// Archived but not deleted
    Archived,
    /// Soft-deleted
    Deleted,
}

impl VideoStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Uploading => "uploading",
            Self::Processing => "processing",
            Self::Published => "published",
            Self::Archived => "archived",
            Self::Deleted => "deleted",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "uploading" => Some(Self::Uploading),
            "processing" => Some(Self::Processing),
            "published" => Some(Self::Published),
            "archived" => Some(Self::Archived),
            "deleted" => Some(Self::Deleted),
            _ => None,
        }
    }
}

/// Video content type (original content vs. derived formats)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VideoContentType {
    /// Original user-created content
    Original,
    /// Response to a challenge
    Challenge,
    /// Duet with another video
    Duet,
    /// Reaction to another video
    Reaction,
    /// Remix of existing audio/content
    Remix,
}

impl VideoContentType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Original => "original",
            Self::Challenge => "challenge",
            Self::Duet => "duet",
            Self::Reaction => "reaction",
            Self::Remix => "remix",
        }
    }
}

/// Video visibility level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VideoVisibility {
    /// Anyone can view
    Public,
    /// Only followers can view
    Friends,
    /// Only creator can view
    Private,
}

impl VideoVisibility {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Public => "public",
            Self::Friends => "friends",
            Self::Private => "private",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "public" => Some(Self::Public),
            "friends" => Some(Self::Friends),
            "private" => Some(Self::Private),
            _ => None,
        }
    }
}

// ========================================
// Video Entity (Database)
// ========================================

/// Video database entity
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct VideoEntity {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub duration_seconds: i32,
    pub upload_url: Option<String>,
    pub cdn_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub status: String, // Stored as string, use VideoStatus for conversion
    pub content_type: String,
    pub hashtags: serde_json::Value, // JSONB
    pub visibility: String,
    pub allow_comments: bool,
    pub allow_duet: bool,
    pub allow_react: bool,
    pub created_at: DateTime<Utc>,
    pub published_at: Option<DateTime<Utc>>,
    pub archived_at: Option<DateTime<Utc>>,
    pub deleted_at: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
}

impl VideoEntity {
    /// Get parsed status
    pub fn get_status(&self) -> VideoStatus {
        VideoStatus::from_str(&self.status).unwrap_or(VideoStatus::Uploading)
    }

    /// Get parsed content type
    pub fn get_content_type(&self) -> VideoContentType {
        match self.content_type.as_str() {
            "challenge" => VideoContentType::Challenge,
            "duet" => VideoContentType::Duet,
            "reaction" => VideoContentType::Reaction,
            "remix" => VideoContentType::Remix,
            _ => VideoContentType::Original,
        }
    }

    /// Get parsed visibility
    pub fn get_visibility(&self) -> VideoVisibility {
        match self.visibility.as_str() {
            "friends" => VideoVisibility::Friends,
            "private" => VideoVisibility::Private,
            _ => VideoVisibility::Public,
        }
    }

    /// Get hashtags as Vec<String>
    pub fn get_hashtags(&self) -> Vec<String> {
        self.hashtags
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default()
    }
}

// ========================================
// Video Engagement Entity (Database)
// ========================================

/// Video engagement statistics (denormalized)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct VideoEngagementEntity {
    pub video_id: Uuid,
    pub view_count: i64,
    pub like_count: i64,
    pub share_count: i64,
    pub comment_count: i64,
    pub completion_rate: Option<f64>, // NUMERIC(3,2)
    pub avg_watch_seconds: Option<i32>,
    pub last_updated: DateTime<Utc>,
}

// ========================================
// API DTOs
// ========================================

/// Create video request DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateVideoRequest {
    pub title: String,
    pub description: Option<String>,
    pub hashtags: Option<Vec<String>>,
    pub visibility: Option<String>,   // default: "public"
    pub allow_comments: Option<bool>, // default: true
    pub allow_duet: Option<bool>,     // default: true
    pub allow_react: Option<bool>,    // default: true
}

/// Update video metadata request DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateVideoRequest {
    pub title: Option<String>,
    pub description: Option<String>,
    pub hashtags: Option<Vec<String>>,
    pub visibility: Option<String>,
    pub allow_comments: Option<bool>,
    pub allow_duet: Option<bool>,
    pub allow_react: Option<bool>,
}

/// Video response DTO (for API responses)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoResponse {
    pub id: String, // UUID as string
    pub creator_id: String,
    pub title: String,
    pub description: Option<String>,
    pub duration_seconds: u32,
    pub cdn_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub status: String,
    pub content_type: String,
    pub hashtags: Vec<String>,
    pub visibility: String,
    pub created_at: i64, // Unix timestamp
    pub published_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub engagement: Option<EngagementResponse>,
}

/// Video engagement response DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngagementResponse {
    pub view_count: u64,
    pub like_count: u64,
    pub share_count: u64,
    pub comment_count: u64,
    pub completion_rate: Option<f32>,
    pub avg_watch_seconds: Option<u32>,
}

/// Presigned upload URL response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PresignedUploadResponse {
    pub video_id: String,
    pub upload_url: String,
    pub expiry_seconds: u32,
}

/// Video processing progress DTO (for Kafka events)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoProcessingProgress {
    pub video_id: String,
    pub stage: String, // "uploading", "validating", "transcoding", "extracting_thumbnails", "generating_embeddings", "completed", "failed"
    pub progress_percent: u32,
    pub error: Option<String>,
}

// ========================================
// ClickHouse Models
// ========================================

/// Video metrics for ClickHouse (1-hour aggregation)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoMetrics1h {
    pub post_id: i64,
    pub author_id: i64,
    pub metric_hour: DateTime<Utc>,
    pub likes_count: u32,
    pub comments_count: u32,
    pub shares_count: u32,
    pub impressions_count: u32,
    pub watch_time_seconds: u32,
}

/// User-author affinity (90-day rolling)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserAuthorAffinity {
    pub user_id: i64,
    pub author_id: i64,
    pub interaction_count: u32,
    pub last_interaction: DateTime<Utc>,
    pub interaction_score: f32,
}

// ========================================
// Streaming Models
// ========================================

/// HLS playlist segment
#[derive(Debug, Clone, Serialize)]
pub struct HlsSegment {
    pub duration: f32,
    pub uri: String,
}

/// DASH representation (quality tier)
#[derive(Debug, Clone, Serialize)]
pub struct DashRepresentation {
    pub bitrate: u32,
    pub resolution: String, // "1920x1080", "1280x720", etc.
    pub codec: String,
    pub initialization_segment: String,
    pub media_segments: Vec<String>,
}

// ========================================
// Deep Learning Models
// ========================================

/// Video embedding (from TensorFlow Serving)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoEmbedding {
    pub video_id: String,
    pub embedding: Vec<f32>, // 256-dimensional vector
    pub model_version: String,
    pub generated_at: DateTime<Utc>,
}

/// Similarity search result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimilarVideo {
    pub video_id: String,
    pub similarity_score: f32, // [0.0, 1.0]
    pub title: String,
    pub creator_id: String,
    pub thumbnail_url: Option<String>,
}

// ========================================
// Batch Processing Models
// ========================================

/// Transcoding job for batch processing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodingJob {
    pub job_id: String,
    pub video_id: String,
    pub source_url: String,
    pub target_bitrates: Vec<String>, // ["720p", "480p", "360p"]
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub status: String, // "pending", "processing", "completed", "failed"
    pub error: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_status_conversion() {
        assert_eq!(VideoStatus::Uploading.as_str(), "uploading");
        assert_eq!(
            VideoStatus::from_str("published"),
            Some(VideoStatus::Published)
        );
        assert_eq!(VideoStatus::from_str("invalid"), None);
    }

    #[test]
    fn test_video_visibility_conversion() {
        assert_eq!(VideoVisibility::Public.as_str(), "public");
        assert_eq!(
            VideoVisibility::from_str("private"),
            Some(VideoVisibility::Private)
        );
    }
}

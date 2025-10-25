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
    // Transcoding fields (Task 2.4)
    #[sqlx(default)]
    pub transcoding_status: Option<String>,
    #[sqlx(default)]
    pub transcoding_retry_count: Option<i32>,
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
// Video Upload Session Entity (Database)
// ========================================

/// Video upload session for tracking two-phase uploads
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct VideoUploadSession {
    pub id: i32,
    pub video_id: Uuid,
    pub upload_token: String,
    pub file_hash: Option<String>,
    pub file_size: Option<i64>,
    pub expires_at: DateTime<Utc>,
    pub is_completed: bool,
    pub created_at: DateTime<Utc>,
}

// ========================================
// Resumable Upload Models
// ========================================

/// Upload status enum for resumable uploads
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum UploadStatus {
    /// Upload in progress
    Uploading,
    /// All chunks uploaded successfully
    Completed,
    /// Upload failed or expired
    Failed,
    /// User cancelled the upload
    Cancelled,
}

impl UploadStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Uploading => "uploading",
            Self::Completed => "completed",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "uploading" => Some(Self::Uploading),
            "completed" => Some(Self::Completed),
            "failed" => Some(Self::Failed),
            "cancelled" => Some(Self::Cancelled),
            _ => None,
        }
    }
}

/// Resumable upload session
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ResumableUpload {
    pub id: Uuid,
    pub user_id: Uuid,
    pub video_id: Option<Uuid>,
    pub file_name: String,
    pub file_size: i64,
    pub uploaded_size: i64,
    pub chunk_size: i32,
    pub chunks_total: i32,
    pub chunks_completed: i32,
    pub status: String, // Stored as string, use UploadStatus for conversion
    pub s3_upload_id: Option<String>,
    pub s3_bucket: Option<String>,
    pub s3_key: Option<String>,
    pub content_hash: Option<String>,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[sqlx(default)]
    pub completed_at: Option<DateTime<Utc>>,
}

impl ResumableUpload {
    /// Get parsed status
    pub fn get_status(&self) -> UploadStatus {
        UploadStatus::from_str(&self.status).unwrap_or(UploadStatus::Uploading)
    }

    /// Check if all chunks have been uploaded
    pub fn is_complete(&self) -> bool {
        self.chunks_completed >= self.chunks_total
    }

    /// Calculate progress percentage
    pub fn progress_percent(&self) -> f64 {
        if self.chunks_total == 0 {
            0.0
        } else {
            (self.chunks_completed as f64 / self.chunks_total as f64) * 100.0
        }
    }
}

/// Individual upload chunk
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UploadChunk {
    pub id: Uuid,
    pub upload_id: Uuid,
    pub chunk_number: i32,
    pub chunk_size: i64,
    pub etag: String,
    pub chunk_hash: String,
    pub status: String,
    pub upload_attempts: i32,
    pub last_error: Option<String>,
    pub created_at: DateTime<Utc>,
    #[sqlx(default)]
    pub completed_at: Option<DateTime<Utc>>,
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

/// Video upload init request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoUploadInitRequest {
    pub filename: String,
    pub content_type: String,
    pub file_size: i64,
    pub title: String,
    pub description: Option<String>,
    pub hashtags: Option<Vec<String>>,
    pub visibility: Option<String>,
}

/// Video upload init response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoUploadInitResponse {
    pub presigned_url: String,
    pub video_id: String,
    pub upload_token: String,
    pub expires_in: i64,
    pub instructions: String,
}

/// Video upload complete request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoUploadCompleteRequest {
    pub video_id: String,
    pub upload_token: String,
    pub file_hash: String,
    pub file_size: i64,
}

/// Video upload complete response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoUploadCompleteResponse {
    pub video_id: String,
    pub status: String,
    pub message: String,
    pub video_key: String,
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

// ========================================
// Transcoding Progress Events
// ========================================

/// Transcoding status for real-time progress tracking
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TranscodingStatus {
    /// Job is queued and waiting for worker
    Pending,
    /// Currently transcoding
    Processing,
    /// Successfully completed and published
    Published,
    /// Transcoding failed (retryable or fatal)
    Failed,
}

impl TranscodingStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Processing => "processing",
            Self::Published => "published",
            Self::Failed => "failed",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "pending" => Some(Self::Pending),
            "processing" => Some(Self::Processing),
            "published" => Some(Self::Published),
            "failed" => Some(Self::Failed),
            _ => None,
        }
    }
}

/// Real-time progress event for transcoding jobs
/// Sent to WebSocket subscribers and webhook endpoints
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressEvent {
    pub video_id: Uuid,
    pub status: TranscodingStatus,
    pub progress_percent: u8,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_stage: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub estimated_remaining_seconds: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manifest_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retrying: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_at: Option<DateTime<Utc>>,
    pub timestamp: DateTime<Utc>,
}

impl ProgressEvent {
    /// Create a progress event
    pub fn new_progress(
        video_id: Uuid,
        progress_percent: u8,
        current_stage: Option<String>,
        estimated_remaining_seconds: Option<i32>,
    ) -> Self {
        Self {
            video_id,
            status: TranscodingStatus::Processing,
            progress_percent,
            current_stage,
            estimated_remaining_seconds,
            manifest_url: None,
            error_message: None,
            error_code: None,
            retrying: None,
            retry_at: None,
            timestamp: Utc::now(),
        }
    }

    /// Create a completion event
    pub fn new_completed(video_id: Uuid, manifest_url: String) -> Self {
        Self {
            video_id,
            status: TranscodingStatus::Published,
            progress_percent: 100,
            current_stage: Some("completed".to_string()),
            estimated_remaining_seconds: Some(0),
            manifest_url: Some(manifest_url),
            error_message: None,
            error_code: None,
            retrying: None,
            retry_at: None,
            timestamp: Utc::now(),
        }
    }

    /// Create an error event
    pub fn new_error(
        video_id: Uuid,
        error_message: String,
        error_code: String,
        retrying: bool,
        retry_at: Option<DateTime<Utc>>,
    ) -> Self {
        Self {
            video_id,
            status: TranscodingStatus::Failed,
            progress_percent: 0,
            current_stage: None,
            estimated_remaining_seconds: None,
            manifest_url: None,
            error_message: Some(error_message),
            error_code: Some(error_code),
            retrying: Some(retrying),
            retry_at,
            timestamp: Utc::now(),
        }
    }

    /// Get webhook event type
    pub fn event_type(&self) -> &'static str {
        match self.status {
            TranscodingStatus::Processing => "transcoding.progress",
            TranscodingStatus::Published => "transcoding.completed",
            TranscodingStatus::Failed => "transcoding.failed",
            TranscodingStatus::Pending => "transcoding.queued",
        }
    }
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

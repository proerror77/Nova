/// Data models for media-service
///
/// This module defines structures for:
/// - Video: Video metadata and status
/// - Upload: Upload session and chunk information
/// - Reel: Short-form video content
///
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ========================================
// Video Models
// ========================================

/// Video status in the system lifecycle
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VideoStatus {
    Uploading,
    Processing,
    Published,
    Archived,
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

/// Video visibility level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum VideoVisibility {
    Public,
    Friends,
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

/// Video database entity
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Video {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub duration_seconds: i32,
    pub cdn_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub status: String,
    pub visibility: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Video {
    pub fn get_status(&self) -> VideoStatus {
        VideoStatus::from_str(&self.status).unwrap_or(VideoStatus::Uploading)
    }

    pub fn get_visibility(&self) -> VideoVisibility {
        VideoVisibility::from_str(&self.visibility).unwrap_or(VideoVisibility::Public)
    }
}

/// Video response DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoResponse {
    pub id: String,
    pub creator_id: String,
    pub title: String,
    pub description: Option<String>,
    pub duration_seconds: u32,
    pub cdn_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub status: String,
    pub visibility: String,
    pub created_at: i64,
}

impl From<Video> for VideoResponse {
    fn from(video: Video) -> Self {
        Self {
            id: video.id.to_string(),
            creator_id: video.creator_id.to_string(),
            title: video.title,
            description: video.description,
            duration_seconds: video.duration_seconds as u32,
            cdn_url: video.cdn_url,
            thumbnail_url: video.thumbnail_url,
            status: video.status,
            visibility: video.visibility,
            created_at: video.created_at.timestamp(),
        }
    }
}

/// Create video request DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateVideoRequest {
    pub title: String,
    pub description: Option<String>,
    pub visibility: Option<String>,
}

/// Update video request DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateVideoRequest {
    pub title: Option<String>,
    pub description: Option<String>,
    pub visibility: Option<String>,
}

// ========================================
// Upload Models
// ========================================

/// Upload status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum UploadStatus {
    Uploading,
    Completed,
    Failed,
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

/// Upload session
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Upload {
    pub id: Uuid,
    pub user_id: Uuid,
    pub video_id: Option<Uuid>,
    pub file_name: String,
    pub file_size: i64,
    pub uploaded_size: i64,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Upload {
    pub fn get_status(&self) -> UploadStatus {
        UploadStatus::from_str(&self.status).unwrap_or(UploadStatus::Uploading)
    }

    pub fn progress_percent(&self) -> f64 {
        if self.file_size == 0 {
            0.0
        } else {
            (self.uploaded_size as f64 / self.file_size as f64) * 100.0
        }
    }
}

/// Upload response DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadResponse {
    pub id: String,
    pub video_id: Option<String>,
    pub file_name: String,
    pub file_size: i64,
    pub uploaded_size: i64,
    pub status: String,
    pub progress_percent: f64,
    pub created_at: i64,
}

impl From<Upload> for UploadResponse {
    fn from(upload: Upload) -> Self {
        let progress_percent = upload.progress_percent();
        Self {
            id: upload.id.to_string(),
            video_id: upload.video_id.map(|id| id.to_string()),
            file_name: upload.file_name,
            file_size: upload.file_size,
            uploaded_size: upload.uploaded_size,
            status: upload.status,
            progress_percent,
            created_at: upload.created_at.timestamp(),
        }
    }
}

/// Start upload request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartUploadRequest {
    pub file_name: String,
    pub file_size: i64,
    pub content_type: String,
}

// ========================================
// Reel Models
// ========================================

/// Reel (short-form video) entity
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Reel {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub upload_id: Option<Uuid>,
    pub caption: Option<String>,
    pub music_title: Option<String>,
    pub music_artist: Option<String>,
    pub music_id: Option<Uuid>,
    pub duration_seconds: Option<i32>,
    pub visibility: String,
    pub status: String,
    pub processing_stage: String,
    pub processing_progress: i16,
    pub view_count: i64,
    pub like_count: i64,
    pub share_count: i64,
    pub comment_count: i64,
    pub allow_comments: bool,
    pub allow_shares: bool,
    pub audio_track: Option<serde_json::Value>,
    pub cover_image_url: Option<String>,
    pub source_video_url: Option<String>,
    pub published_at: Option<DateTime<Utc>>,
    pub failed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
}

/// Reel variant produced by the transcoding pipeline
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ReelVariant {
    pub id: Uuid,
    pub reel_id: Uuid,
    pub quality: String,
    pub codec: String,
    pub bitrate_kbps: i32,
    pub width: i32,
    pub height: i32,
    pub frame_rate: f32,
    pub cdn_url: Option<String>,
    pub file_size_bytes: Option<i64>,
    pub is_default: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Reel transcoding job metadata
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ReelTranscodeJob {
    pub id: Uuid,
    pub reel_id: Uuid,
    pub upload_id: Option<Uuid>,
    pub target_quality: String,
    pub status: String,
    pub stage: String,
    pub progress: i16,
    pub retry_count: i32,
    pub error_message: Option<String>,
    pub worker_id: Option<String>,
    pub started_at: Option<DateTime<Utc>>,
    pub finished_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Reel variant response DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelVariantResponse {
    pub quality: String,
    pub codec: String,
    pub bitrate_kbps: i32,
    pub width: i32,
    pub height: i32,
    pub frame_rate: f32,
    pub cdn_url: Option<String>,
    pub file_size_bytes: Option<i64>,
    pub is_default: bool,
}

impl From<ReelVariant> for ReelVariantResponse {
    fn from(variant: ReelVariant) -> Self {
        Self {
            quality: variant.quality,
            codec: variant.codec,
            bitrate_kbps: variant.bitrate_kbps,
            width: variant.width,
            height: variant.height,
            frame_rate: variant.frame_rate,
            cdn_url: variant.cdn_url,
            file_size_bytes: variant.file_size_bytes,
            is_default: variant.is_default,
        }
    }
}

/// Transcoding job status response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelTranscodeJobResponse {
    pub target_quality: String,
    pub status: String,
    pub stage: String,
    pub progress: i16,
    pub updated_at: i64,
    pub error_message: Option<String>,
}

impl From<ReelTranscodeJob> for ReelTranscodeJobResponse {
    fn from(job: ReelTranscodeJob) -> Self {
        Self {
            target_quality: job.target_quality,
            status: job.status,
            stage: job.stage,
            progress: job.progress,
            updated_at: job.updated_at.timestamp(),
            error_message: job.error_message,
        }
    }
}

/// Reel response DTO including current variants + job statuses
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelResponse {
    pub id: String,
    pub creator_id: String,
    pub upload_id: Option<String>,
    pub caption: Option<String>,
    pub music_title: Option<String>,
    pub music_artist: Option<String>,
    pub duration_seconds: Option<i32>,
    pub visibility: String,
    pub status: String,
    pub processing_stage: String,
    pub processing_progress: i16,
    pub allow_comments: bool,
    pub allow_shares: bool,
    pub cover_image_url: Option<String>,
    pub source_video_url: Option<String>,
    pub variants: Vec<ReelVariantResponse>,
    pub transcode_jobs: Vec<ReelTranscodeJobResponse>,
    pub published_at: Option<i64>,
    pub failed_at: Option<i64>,
    pub created_at: i64,
    pub updated_at: i64,
}

impl ReelResponse {
    /// Create a response DTO from database entities
    pub fn from_entities(
        reel: Reel,
        variants: Vec<ReelVariant>,
        jobs: Vec<ReelTranscodeJob>,
    ) -> Self {
        Self {
            id: reel.id.to_string(),
            creator_id: reel.creator_id.to_string(),
            upload_id: reel.upload_id.map(|id| id.to_string()),
            caption: reel.caption,
            music_title: reel.music_title,
            music_artist: reel.music_artist,
            duration_seconds: reel.duration_seconds,
            visibility: reel.visibility,
            status: reel.status,
            processing_stage: reel.processing_stage,
            processing_progress: reel.processing_progress,
            allow_comments: reel.allow_comments,
            allow_shares: reel.allow_shares,
            cover_image_url: reel.cover_image_url,
            source_video_url: reel.source_video_url,
            variants: variants.into_iter().map(Into::into).collect(),
            transcode_jobs: jobs.into_iter().map(Into::into).collect(),
            published_at: reel.published_at.map(|dt| dt.timestamp()),
            failed_at: reel.failed_at.map(|dt| dt.timestamp()),
            created_at: reel.created_at.timestamp(),
            updated_at: reel.updated_at.timestamp(),
        }
    }
}

impl From<Reel> for ReelResponse {
    fn from(reel: Reel) -> Self {
        ReelResponse::from_entities(reel, Vec::new(), Vec::new())
    }
}

/// Create reel request payload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateReelRequest {
    pub upload_id: String,
    pub caption: Option<String>,
    pub music_title: Option<String>,
    pub music_artist: Option<String>,
    pub duration_seconds: Option<i32>,
    pub visibility: Option<String>,
    pub allow_comments: Option<bool>,
    pub allow_shares: Option<bool>,
    pub cover_image_url: Option<String>,
}

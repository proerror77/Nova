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
    pub video_id: Uuid,
    pub title: String,
    pub music: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Reel response DTO
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelResponse {
    pub id: String,
    pub creator_id: String,
    pub video_id: String,
    pub title: String,
    pub music: Option<String>,
    pub created_at: i64,
}

impl From<Reel> for ReelResponse {
    fn from(reel: Reel) -> Self {
        Self {
            id: reel.id.to_string(),
            creator_id: reel.creator_id.to_string(),
            video_id: reel.video_id.to_string(),
            title: reel.title,
            music: reel.music,
            created_at: reel.created_at.timestamp(),
        }
    }
}

/// Create reel request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateReelRequest {
    pub video_id: String,
    pub title: String,
    pub music: Option<String>,
}

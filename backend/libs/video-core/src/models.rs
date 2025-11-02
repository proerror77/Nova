//! Core video data models

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Video status enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum VideoStatus {
    #[serde(rename = "pending")]
    Pending,
    #[serde(rename = "processing")]
    Processing,
    #[serde(rename = "ready")]
    Ready,
    #[serde(rename = "failed")]
    Failed,
    #[serde(rename = "deleted")]
    Deleted,
}

impl VideoStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            VideoStatus::Pending => "pending",
            VideoStatus::Processing => "processing",
            VideoStatus::Ready => "ready",
            VideoStatus::Failed => "failed",
            VideoStatus::Deleted => "deleted",
        }
    }
}

/// Video quality/transcoding profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoQuality {
    pub resolution: String,  // e.g., "1080p", "720p"
    pub bitrate: i32,        // in kbps
    pub format: String,      // "mp4", "webm", etc.
    pub codec: String,       // "h264", "h265", etc.
    pub url: Option<String>, // CDN URL after transcoding
}

/// Core video metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Video {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub status: VideoStatus,
    pub duration: Option<i32>, // in seconds
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub file_size: Option<i64>,    // in bytes
    pub file_path: Option<String>, // S3 or storage path
    pub thumbnail_url: Option<String>,
    pub hls_url: Option<String>, // HLS streaming URL
    pub qualities: Vec<VideoQuality>,
    pub views: i64,
    pub likes: i64,
    pub is_public: bool,
    pub is_deleted: bool,
    pub transcoding_started_at: Option<DateTime<Utc>>,
    pub transcoding_completed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Request to create a new video
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateVideoRequest {
    pub user_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub is_public: bool,
}

/// Request to update video metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateVideoRequest {
    pub title: Option<String>,
    pub description: Option<String>,
    pub is_public: Option<bool>,
}

/// Transcoding request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodingRequest {
    pub video_id: Uuid,
    pub target_qualities: Vec<String>, // ["1080p", "720p", "480p"]
}

/// Transcoding progress
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodingProgress {
    pub video_id: Uuid,
    pub quality: String,
    pub progress_percentage: i32,
    pub status: String,
    pub error_message: Option<String>,
    pub started_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Video upload response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadResponse {
    pub video_id: Uuid,
    pub upload_url: String,
    pub expires_at: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_status_str() {
        assert_eq!(VideoStatus::Pending.as_str(), "pending");
        assert_eq!(VideoStatus::Processing.as_str(), "processing");
        assert_eq!(VideoStatus::Ready.as_str(), "ready");
    }
}

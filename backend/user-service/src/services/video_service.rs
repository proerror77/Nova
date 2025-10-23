/// Video Upload & Management Service
///
/// Handles video uploads, processing, and storage integration
use crate::config::video_config::VideoConfig;
use crate::error::{AppError, Result};
use chrono::Utc;
use uuid::Uuid;

use tracing::{debug, info};

/// Video service for uploads and processing
pub struct VideoService {
    _config: VideoConfig,
}

impl VideoService {
    /// Create new video service instance
    pub fn new(config: VideoConfig) -> Self {
        Self { _config: config }
    }

    /// Generate presigned URL for video upload
    ///
    /// Returns URL that client can use to upload directly to S3
    pub async fn generate_upload_url(&self, user_id: Uuid) -> Result<PresignedUploadResponse> {
        // 最小实现：返回占位的上传 URL（前端可据此走直传逻辑）
        let token = uuid::Uuid::new_v4().to_string();
        let url = format!("/upload/videos/{}?user={}", token, user_id);
        Ok(PresignedUploadResponse { video_id: token, upload_url: url, expiry_seconds: 900 })
    }

    /// Validate uploaded video metadata
    pub async fn validate_video_metadata(
        &self,
        _title: &str,
        _description: Option<&str>,
        _duration_seconds: u32,
    ) -> Result<()> {
        // 最小校验：标题非空，时长 > 0
        if _title.trim().is_empty() { return Err(AppError::BadRequest("title required".into())); }
        if _duration_seconds == 0 { return Err(AppError::BadRequest("duration must be > 0".into())); }
        Ok(())
    }

    /// Start video processing job
    pub async fn start_processing(&self, video_id: &Uuid, title: &str, _upload_url: &str) -> Result<()> {
        // 最小实现：仅记录开始处理的日志
        info!("start processing video: {} - {}", video_id, title);
        Ok(())
    }

    /// Utility: normalize/parse hashtags array
    pub fn parse_hashtags(input: Option<&Vec<String>>) -> Vec<String> {
        input
            .unwrap_or(&Vec::new())
            .iter()
            .map(|s| s.trim().trim_start_matches('#').to_string())
            .filter(|s| !s.is_empty())
            .collect()
    }
}

/// Presigned upload response
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct PresignedUploadResponse {
    pub video_id: String,
    pub upload_url: String,
    pub expiry_seconds: u32,
}

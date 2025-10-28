/// Video Upload & Management Service
///
/// Handles video uploads, processing, and storage integration
use crate::config::video_config::VideoConfig;
use crate::config::S3Config;
use crate::error::{AppError, Result};
use crate::services::s3_service;
use uuid::Uuid;

use tracing::info;

/// Video service for uploads and processing
pub struct VideoService {
    _config: VideoConfig,
}

impl VideoService {
    /// Create new video service instance
    pub fn new(config: VideoConfig) -> Self {
        Self { _config: config }
    }

    /// Generate presigned S3 URL for video upload with proper S3 integration
    ///
    /// Returns presigned URL that client can use to upload directly to S3
    pub async fn generate_presigned_upload_url(
        &self,
        s3_config: &S3Config,
        video_id: Uuid,
        content_type: &str,
    ) -> Result<String> {
        // Generate S3 key: videos/{video_id}/original.mp4
        let s3_key = format!("videos/{}/original.mp4", video_id);

        // Create S3 client
        let s3_client = s3_service::get_s3_client(s3_config).await?;

        // Generate presigned URL for PUT upload
        let presigned_url =
            s3_service::generate_presigned_url(&s3_client, s3_config, &s3_key, content_type)
                .await?;

        Ok(presigned_url)
    }

    /// Validate uploaded video metadata
    pub async fn validate_video_metadata(
        &self,
        _title: &str,
        _description: Option<&str>,
        _duration_seconds: u32,
    ) -> Result<()> {
        // 最小校验：标题非空，时长 > 0
        if _title.trim().is_empty() {
            return Err(AppError::BadRequest("title required".into()));
        }
        if _duration_seconds == 0 {
            return Err(AppError::BadRequest("duration must be > 0".into()));
        }
        Ok(())
    }

    /// Start video processing job
    pub async fn start_processing(
        &self,
        video_id: &Uuid,
        title: &str,
        _upload_url: &str,
    ) -> Result<()> {
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

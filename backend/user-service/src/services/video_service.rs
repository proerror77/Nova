/// Video Upload & Management Service
///
/// Handles video uploads, processing, and storage integration
use crate::config::video_config::VideoConfig;
use crate::error::{AppError, Result};
use crate::models::video::*;
use chrono::Utc;
use uuid::Uuid;

use tracing::{debug, error, info, warn};

/// Video service for uploads and processing
pub struct VideoService {
    config: VideoConfig,
}

impl VideoService {
    /// Create new video service instance
    pub fn new(config: VideoConfig) -> Self {
        Self { config }
    }

    /// Generate presigned URL for video upload
    ///
    /// Returns URL that client can use to upload directly to S3
    pub async fn generate_upload_url(&self, user_id: Uuid) -> Result<PresignedUploadResponse> {
        // Generate a unique video ID
        let video_id = Uuid::new_v4();

        // Construct S3 key
        let s3_key = format!(
            "{}{}/{}",
            self.config.upload.s3_upload_prefix, user_id, video_id
        );

        // In production, this would call AWS SDK to generate presigned URL
        // For now, return a placeholder
        info!("Generating presigned URL for video: {}", video_id);

        let upload_url = format!("s3://{}/{}", self.config.upload.s3_upload_bucket, s3_key);

        Ok(PresignedUploadResponse {
            video_id: video_id.to_string(),
            upload_url,
            expiry_seconds: 3600,
        })
    }

    /// Validate uploaded video metadata
    pub async fn validate_video_metadata(
        &self,
        title: &str,
        description: Option<&str>,
        duration_seconds: u32,
    ) -> Result<()> {
        // Validate title
        if title.is_empty() || title.len() > 255 {
            return Err(AppError::Validation(
                "Video title must be between 1-255 characters".to_string(),
            ));
        }

        // Validate description
        if let Some(desc) = description {
            if desc.len() > 5000 {
                return Err(AppError::Validation(
                    "Video description cannot exceed 5000 characters".to_string(),
                ));
            }
        }

        // Validate duration
        if duration_seconds == 0 || duration_seconds > self.config.upload.max_duration_seconds {
            return Err(AppError::Validation(format!(
                "Video duration must be between 1 and {} seconds",
                self.config.upload.max_duration_seconds
            )));
        }

        Ok(())
    }

    /// Start video processing job
    pub async fn start_processing(
        &self,
        video_id: &Uuid,
        title: &str,
        upload_url: &str,
    ) -> Result<()> {
        info!(
            "Starting video processing: video_id={}, title={}",
            video_id, title
        );

        // In production, this would:
        // 1. Create a job record in database
        // 2. Publish to Kafka job queue
        // 3. Return job ID for tracking

        // For now, just validate the setup
        if self.config.processing.ffmpeg_path.is_empty() {
            return Err(AppError::Internal("FFmpeg path not configured".to_string()));
        }

        debug!(
            "Video processing job queued: {} (FFmpeg: {})",
            video_id, self.config.processing.ffmpeg_path
        );

        Ok(())
    }

    /// Get supported video codecs
    pub fn get_supported_codecs(&self) -> Vec<String> {
        self.config.upload.allowed_codecs.clone()
    }

    /// Get supported container formats
    pub fn get_supported_formats(&self) -> Vec<String> {
        self.config.upload.allowed_formats.clone()
    }

    /// Get target bitrates for transcoding
    pub fn get_target_bitrates(&self) -> std::collections::HashMap<String, u32> {
        self.config.processing.target_bitrates.clone()
    }

    /// Get maximum file size in bytes
    pub fn get_max_file_size(&self) -> u64 {
        self.config.upload.max_file_size_bytes
    }

    /// Check if virus scanning is enabled
    pub fn is_virus_scan_enabled(&self) -> bool {
        self.config.upload.enable_virus_scan
    }

    /// Parse hashtags from request
    pub fn parse_hashtags(hashtags: Option<&Vec<String>>) -> Vec<String> {
        hashtags
            .map(|tags| {
                tags.iter()
                    .filter(|tag| !tag.is_empty() && tag.len() <= 50)
                    .take(30) // Limit to 30 hashtags
                    .map(|tag| tag.trim_start_matches('#').to_lowercase())
                    .collect()
            })
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_service_creation() {
        let config = VideoConfig::from_env();
        let service = VideoService::new(config);
        assert!(!service.get_supported_codecs().is_empty());
    }

    #[test]
    fn test_hashtag_parsing() {
        let tags_vec = vec!["#Music".to_string(), "Dance".to_string(), "".to_string()];
        let tags = Some(&tags_vec);
        let parsed = VideoService::parse_hashtags(tags);
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0], "music");
        assert_eq!(parsed[1], "dance");
    }

    #[tokio::test]
    async fn test_validate_video_metadata() {
        let config = VideoConfig::from_env();
        let service = VideoService::new(config);

        // Valid metadata should pass
        let result = service
            .validate_video_metadata("My Video", Some("Description"), 300)
            .await;
        assert!(result.is_ok());

        // Empty title should fail
        let result = service
            .validate_video_metadata("", Some("Description"), 300)
            .await;
        assert!(result.is_err());

        // Excessive duration should fail
        let result = service
            .validate_video_metadata("My Video", Some("Description"), 700)
            .await;
        assert!(result.is_err());
    }
}

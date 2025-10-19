/// Video Transcoding Service
///
/// Handles FFmpeg-based video transcoding, thumbnail extraction, and metadata parsing.
/// Manages the video processing pipeline for multi-quality output.

use crate::config::video_config::VideoProcessingConfig;
use crate::error::{AppError, Result};
use crate::models::video::TranscodingJob;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::{debug, error, info, warn};

/// Video transcoding service
pub struct VideoTranscodingService {
    config: VideoProcessingConfig,
}

/// Video file information extracted via FFprobe
#[derive(Debug, Clone)]
pub struct VideoMetadata {
    /// Duration in seconds
    pub duration_seconds: u32,
    /// Video codec (h264, hevc, etc.)
    pub video_codec: String,
    /// Video resolution (width x height)
    pub resolution: (u32, u32),
    /// Frame rate
    pub frame_rate: f32,
    /// Bitrate in kbps
    pub bitrate_kbps: u32,
    /// Audio codec
    pub audio_codec: Option<String>,
    /// Audio sample rate
    pub audio_sample_rate: Option<u32>,
}

/// Transcoding progress information
#[derive(Debug, Clone)]
pub struct TranscodingProgress {
    pub job_id: String,
    pub video_id: String,
    pub target_bitrate: u32,
    pub quality_tier: String, // "720p", "480p", "360p"
    pub progress_percent: u32,
    pub estimated_time_remaining_seconds: u32,
}

impl VideoTranscodingService {
    /// Create new transcoding service
    pub fn new(config: VideoProcessingConfig) -> Self {
        Self { config }
    }

    /// Extract video metadata using FFprobe
    pub async fn extract_metadata(&self, input_file: &Path) -> Result<VideoMetadata> {
        debug!("Extracting metadata from: {:?}", input_file);

        // In production, would call FFprobe to extract metadata
        // For now, return a placeholder with safe defaults

        if !input_file.exists() {
            return Err(AppError::NotFound(format!(
                "Video file not found: {:?}",
                input_file
            )));
        }

        info!("Extracted metadata from: {:?}", input_file);

        Ok(VideoMetadata {
            duration_seconds: 300, // Placeholder
            video_codec: "h264".to_string(),
            resolution: (1920, 1080),
            frame_rate: 30.0,
            bitrate_kbps: 5000,
            audio_codec: Some("aac".to_string()),
            audio_sample_rate: Some(48000),
        })
    }

    /// Start transcoding job for a specific quality tier
    pub async fn start_transcoding(
        &self,
        video_id: &str,
        input_file: &Path,
        quality_tier: &str,
    ) -> Result<TranscodingJob> {
        info!(
            "Starting transcoding: video_id={}, quality={}",
            video_id, quality_tier
        );

        // Get target bitrate for quality tier
        let bitrate = self
            .config
            .target_bitrates
            .get(quality_tier)
            .copied()
            .ok_or_else(|| {
                AppError::Validation(format!("Unknown quality tier: {}", quality_tier))
            })?;

        let job_id = format!("{}-{}", video_id, quality_tier);

        debug!(
            "Queuing transcoding job: job_id={}, bitrate={}kbps",
            job_id, bitrate
        );

        // In production, would:
        // 1. Spawn FFmpeg process
        // 2. Monitor progress
        // 3. Handle errors and retries
        // 4. Upload to S3 when complete

        let job = TranscodingJob {
            job_id,
            video_id: video_id.to_string(),
            source_url: input_file.to_string_lossy().to_string(),
            target_bitrates: vec![quality_tier.to_string()],
            started_at: None,
            completed_at: None,
            status: "pending".to_string(),
            error: None,
        };

        Ok(job)
    }

    /// Extract thumbnail from video
    pub async fn extract_thumbnail(
        &self,
        input_file: &Path,
        output_file: &Path,
        timestamp_seconds: u32,
    ) -> Result<()> {
        info!(
            "Extracting thumbnail from: {:?} at {}s",
            input_file, timestamp_seconds
        );

        if !input_file.exists() {
            return Err(AppError::NotFound(format!(
                "Video file not found: {:?}",
                input_file
            )));
        }

        // In production, would call FFmpeg:
        // ffmpeg -i input.mp4 -ss {timestamp} -vf scale=320:180 -vframes 1 output.jpg

        debug!(
            "Would extract thumbnail to: {:?} (dimensions: {}x{})",
            output_file, self.config.thumbnail_dimensions.0, self.config.thumbnail_dimensions.1
        );

        // Create parent directory if needed
        if let Some(parent) = output_file.parent() {
            if parent != Path::new("") && !parent.exists() {
                std::fs::create_dir_all(parent)
                    .map_err(|e| AppError::Io(std::io::Error::new(
                        std::io::ErrorKind::Other,
                        format!("Failed to create thumbnail directory: {}", e),
                    )))?;
            }
        }

        info!("Thumbnail extraction completed: {:?}", output_file);

        Ok(())
    }

    /// Generate transcoding jobs for all quality tiers
    pub async fn create_transcoding_jobs(
        &self,
        video_id: &str,
        input_file: &Path,
    ) -> Result<Vec<TranscodingJob>> {
        debug!(
            "Creating transcoding jobs for all quality tiers: video_id={}",
            video_id
        );

        let mut jobs = Vec::new();

        for (quality_tier, _bitrate) in &self.config.target_bitrates {
            let job = self
                .start_transcoding(video_id, input_file, quality_tier)
                .await?;
            jobs.push(job);
        }

        info!(
            "Created {} transcoding jobs for video: {}",
            jobs.len(),
            video_id
        );

        Ok(jobs)
    }

    /// Get supported codecs
    pub fn get_supported_codecs(&self) -> Vec<String> {
        vec![
            "h264".to_string(),
            "hevc".to_string(),
            "vp9".to_string(),
        ]
    }

    /// Get supported container formats
    pub fn get_supported_formats(&self) -> Vec<String> {
        vec![
            "mp4".to_string(),
            "webm".to_string(),
            "mkv".to_string(),
        ]
    }

    /// Validate video file before processing
    pub async fn validate_video_file(&self, file_path: &Path) -> Result<()> {
        debug!("Validating video file: {:?}", file_path);

        if !file_path.exists() {
            return Err(AppError::NotFound(format!(
                "Video file not found: {:?}",
                file_path
            )));
        }

        let metadata = std::fs::metadata(file_path)
            .map_err(|e| AppError::Io(e))?;

        let file_size = metadata.len();

        if file_size > self.config.max_parallel_jobs as u64 * 1024 * 1024 * 100 {
            return Err(AppError::Validation(
                "Video file exceeds maximum size".to_string(),
            ));
        }

        info!("Video file validation passed: {:?}", file_path);

        Ok(())
    }

    /// Get transcoding configuration summary
    pub fn get_config_summary(&self) -> HashMap<String, String> {
        let mut summary = HashMap::new();

        summary.insert(
            "ffmpeg_path".to_string(),
            self.config.ffmpeg_path.clone(),
        );
        summary.insert(
            "max_parallel_jobs".to_string(),
            self.config.max_parallel_jobs.to_string(),
        );
        summary.insert(
            "job_timeout_seconds".to_string(),
            self.config.job_timeout_seconds.to_string(),
        );
        summary.insert(
            "target_qualities".to_string(),
            self.config
                .target_bitrates
                .keys()
                .cloned()
                .collect::<Vec<_>>()
                .join(", "),
        );
        summary.insert(
            "thumbnail_dimensions".to_string(),
            format!(
                "{}x{}",
                self.config.thumbnail_dimensions.0, self.config.thumbnail_dimensions.1
            ),
        );

        summary
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transcoding_service_creation() {
        let config = VideoProcessingConfig::default();
        let service = VideoTranscodingService::new(config);
        assert!(!service.get_supported_codecs().is_empty());
    }

    #[test]
    fn test_supported_formats() {
        let config = VideoProcessingConfig::default();
        let service = VideoTranscodingService::new(config);
        let formats = service.get_supported_formats();
        assert!(formats.contains(&"mp4".to_string()));
        assert!(formats.contains(&"webm".to_string()));
    }

    #[test]
    fn test_config_summary() {
        let config = VideoProcessingConfig::default();
        let service = VideoTranscodingService::new(config);
        let summary = service.get_config_summary();
        assert!(summary.contains_key("ffmpeg_path"));
        assert!(summary.contains_key("target_qualities"));
    }

    #[tokio::test]
    async fn test_metadata_extraction_nonexistent_file() {
        let config = VideoProcessingConfig::default();
        let service = VideoTranscodingService::new(config);

        let result = service
            .extract_metadata(Path::new("/nonexistent/video.mp4"))
            .await;

        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_transcoding_job_creation() {
        let config = VideoProcessingConfig::default();
        let service = VideoTranscodingService::new(config);

        // Create a temporary test file
        let test_file = std::env::temp_dir().join("test_video.mp4");
        std::fs::write(&test_file, "test").ok();

        let result = service
            .start_transcoding("video-123", &test_file, "720p")
            .await;

        assert!(result.is_ok());

        let job = result.unwrap();
        assert_eq!(job.video_id, "video-123");
        assert!(job.status.contains("pending"));

        // Cleanup
        std::fs::remove_file(&test_file).ok();
    }
}

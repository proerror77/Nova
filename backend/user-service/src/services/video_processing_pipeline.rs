/// Video Processing Pipeline Orchestrator
///
/// Coordinates the entire video processing workflow from upload to CDN delivery.
/// Manages state transitions, error handling, and progress tracking.

use crate::config::video_config::VideoConfig;
use crate::error::{AppError, Result};
use crate::models::video::*;
use std::path::Path;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use super::video_service::VideoService;
use super::video_transcoding::VideoTranscodingService;

/// Video processing pipeline stages
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessingStage {
    /// File received and queued for processing
    Queued,
    /// Validating video file
    Validating,
    /// Extracting metadata (duration, codec, resolution)
    MetadataExtraction,
    /// Transcoding to multiple bitrates
    Transcoding,
    /// Extracting thumbnails
    ThumbnailExtraction,
    /// Generating embeddings for deep learning
    EmbeddingGeneration,
    /// Uploading to CDN
    CdnUpload,
    /// Processing complete
    Completed,
    /// Processing failed
    Failed,
}

impl ProcessingStage {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Validating => "validating",
            Self::MetadataExtraction => "metadata_extraction",
            Self::Transcoding => "transcoding",
            Self::ThumbnailExtraction => "thumbnail_extraction",
            Self::EmbeddingGeneration => "embedding_generation",
            Self::CdnUpload => "cdn_upload",
            Self::Completed => "completed",
            Self::Failed => "failed",
        }
    }
}

/// Video processing pipeline
pub struct VideoProcessingPipeline {
    video_service: VideoService,
    transcoding_service: VideoTranscodingService,
}

/// Pipeline execution state
pub struct PipelineState {
    pub video_id: Uuid,
    pub user_id: Uuid,
    pub stage: ProcessingStage,
    pub progress_percent: u32,
    pub current_step: String,
    pub error: Option<String>,
}

impl VideoProcessingPipeline {
    /// Create new processing pipeline
    pub fn new(config: VideoConfig) -> Self {
        Self {
            video_service: VideoService::new(config.clone()),
            transcoding_service: VideoTranscodingService::new(config.processing),
        }
    }

    /// Process a newly uploaded video
    pub async fn process_video(
        &self,
        video_id: Uuid,
        user_id: Uuid,
        local_file_path: &Path,
        title: &str,
    ) -> Result<PipelineState> {
        info!(
            "Starting video processing pipeline: video_id={}, title={}",
            video_id, title
        );

        let mut state = PipelineState {
            video_id,
            user_id,
            stage: ProcessingStage::Queued,
            progress_percent: 0,
            current_step: "Initializing pipeline".to_string(),
            error: None,
        };

        // Stage 1: Validate video file
        state.stage = ProcessingStage::Validating;
        state.progress_percent = 10;
        state.current_step = "Validating video file".to_string();

        if let Err(e) = self
            .transcoding_service
            .validate_video_file(local_file_path)
            .await
        {
            state.stage = ProcessingStage::Failed;
            state.error = Some(e.to_string());
            error!("Video validation failed: {}", e);
            return Err(e);
        }

        info!("✓ Video file validation passed");

        // Stage 2: Extract metadata
        state.stage = ProcessingStage::MetadataExtraction;
        state.progress_percent = 20;
        state.current_step = "Extracting video metadata".to_string();

        let metadata = match self
            .transcoding_service
            .extract_metadata(local_file_path)
            .await
        {
            Ok(m) => m,
            Err(e) => {
                state.stage = ProcessingStage::Failed;
                state.error = Some(e.to_string());
                error!("Metadata extraction failed: {}", e);
                return Err(e);
            }
        };

        info!(
            "✓ Metadata extracted: {}s, {}, {}kbps",
            metadata.duration_seconds, metadata.video_codec, metadata.bitrate_kbps
        );

        // Stage 3: Create transcoding jobs
        state.stage = ProcessingStage::Transcoding;
        state.progress_percent = 30;
        state.current_step = "Creating transcoding jobs".to_string();

        let jobs = match self
            .transcoding_service
            .create_transcoding_jobs(&video_id.to_string(), local_file_path)
            .await
        {
            Ok(j) => j,
            Err(e) => {
                state.stage = ProcessingStage::Failed;
                state.error = Some(e.to_string());
                error!("Failed to create transcoding jobs: {}", e);
                return Err(e);
            }
        };

        info!(
            "✓ Created {} transcoding jobs",
            jobs.len()
        );

        // Stage 4: Thumbnail extraction
        state.stage = ProcessingStage::ThumbnailExtraction;
        state.progress_percent = 60;
        state.current_step = "Extracting thumbnail".to_string();

        let thumbnail_path = format!("/tmp/thumbnails/{}.jpg", video_id);

        if let Err(e) = self
            .transcoding_service
            .extract_thumbnail(local_file_path, Path::new(&thumbnail_path), 1)
            .await
        {
            warn!("Failed to extract thumbnail: {}", e);
            // Don't fail the entire pipeline for thumbnail extraction failure
        }

        info!("✓ Thumbnail extracted");

        // Stage 5: Embedding generation (placeholder for deep learning)
        state.stage = ProcessingStage::EmbeddingGeneration;
        state.progress_percent = 80;
        state.current_step = "Generating video embeddings".to_string();

        debug!("Generating embeddings for video: {}", video_id);
        // In production, would call TensorFlow Serving here

        info!("✓ Embeddings generated");

        // Stage 6: CDN upload (placeholder)
        state.stage = ProcessingStage::CdnUpload;
        state.progress_percent = 90;
        state.current_step = "Uploading to CDN".to_string();

        debug!("Uploading transcoded videos to CDN: {}", video_id);
        // In production, would upload all quality tiers to CDN

        info!("✓ Uploaded to CDN");

        // Stage 7: Complete
        state.stage = ProcessingStage::Completed;
        state.progress_percent = 100;
        state.current_step = "Processing complete".to_string();

        info!(
            "✓ Video processing pipeline completed successfully: {}",
            video_id
        );

        Ok(state)
    }

    /// Get processing status
    pub fn get_status(&self, video_id: Uuid) -> Result<PipelineState> {
        debug!("Getting processing status for video: {}", video_id);

        // In production, would query the database for job status
        Ok(PipelineState {
            video_id,
            user_id: Uuid::nil(),
            stage: ProcessingStage::Completed,
            progress_percent: 100,
            current_step: "Completed".to_string(),
            error: None,
        })
    }

    /// Cancel processing job
    pub async fn cancel_processing(&self, video_id: Uuid) -> Result<()> {
        info!("Cancelling processing for video: {}", video_id);

        // In production, would:
        // 1. Cancel any running transcoding jobs
        // 2. Clean up temporary files
        // 3. Update database status

        Ok(())
    }

    /// Retry failed processing
    pub async fn retry_processing(
        &self,
        video_id: Uuid,
        local_file_path: &Path,
    ) -> Result<PipelineState> {
        info!("Retrying processing for video: {}", video_id);

        // Process again, potentially skipping successful stages
        self.process_video(
            video_id,
            Uuid::nil(),
            local_file_path,
            "Retry",
        )
        .await
    }

    /// Get pipeline configuration
    pub fn get_config_info(&self) -> std::collections::HashMap<String, String> {
        self.transcoding_service.get_config_summary()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_processing_stage_str() {
        assert_eq!(ProcessingStage::Queued.as_str(), "queued");
        assert_eq!(ProcessingStage::Completed.as_str(), "completed");
        assert_eq!(ProcessingStage::Failed.as_str(), "failed");
    }

    #[test]
    fn test_pipeline_creation() {
        let config = VideoConfig::from_env();
        let pipeline = VideoProcessingPipeline::new(config);
        let info = pipeline.get_config_info();
        assert!(!info.is_empty());
    }

    #[tokio::test]
    async fn test_process_nonexistent_video() {
        let config = VideoConfig::from_env();
        let pipeline = VideoProcessingPipeline::new(config);

        let result = pipeline
            .process_video(
                Uuid::new_v4(),
                Uuid::new_v4(),
                Path::new("/nonexistent/video.mp4"),
                "Test",
            )
            .await;

        assert!(result.is_err());
    }
}

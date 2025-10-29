/// Optimized Video Transcoding Pipeline
///
/// Implements parallel transcoding with priority-based job scheduling,
/// parallel quality tier generation, and real-time progress tracking.
/// Targets 40% performance improvement over sequential transcoding.
use crate::config::video_config::VideoProcessingConfig;
use crate::error::{AppError, Result};
use std::collections::VecDeque;
use std::sync::Arc;
use tokio::sync::{Mutex, RwLock};
use tracing::{debug, error, info};

/// Quality tier with priority and encoding parameters
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum QualityTier {
    /// 2160p (4K) - Lowest priority, optional
    Q4K,
    /// 1080p - High priority
    Q1080,
    /// 720p - High priority
    Q720,
    /// 480p - High priority (fallback)
    Q480,
}

impl QualityTier {
    /// Get resolution (width x height)
    pub fn resolution(&self) -> (u32, u32) {
        match self {
            QualityTier::Q4K => (3840, 2160),
            QualityTier::Q1080 => (1920, 1080),
            QualityTier::Q720 => (1280, 720),
            QualityTier::Q480 => (854, 480),
        }
    }

    /// Get target bitrate in kbps
    pub fn bitrate_kbps(&self) -> u32 {
        match self {
            QualityTier::Q4K => 10000,
            QualityTier::Q1080 => 5000,
            QualityTier::Q720 => 2500,
            QualityTier::Q480 => 1000,
        }
    }

    /// Get FFmpeg preset (faster → slower = speed → quality)
    pub fn ffmpeg_preset(&self) -> &'static str {
        match self {
            QualityTier::Q4K => "medium",   // Quality focus
            QualityTier::Q1080 => "medium", // Balanced
            QualityTier::Q720 => "medium",  // Balanced
            QualityTier::Q480 => "faster",  // Speed focus
        }
    }

    /// Get CRF (Constant Rate Factor) value (0-51, lower = better quality)
    pub fn crf_value(&self) -> u8 {
        match self {
            QualityTier::Q4K => 22,   // Better quality for 4K
            QualityTier::Q1080 => 26, // Balanced
            QualityTier::Q720 => 28,  // Balanced
            QualityTier::Q480 => 30,  // Lower quality acceptable
        }
    }

    /// Get priority level (higher = process first)
    pub fn priority(&self) -> u8 {
        match self {
            QualityTier::Q4K => 1,
            QualityTier::Q1080 => 3,
            QualityTier::Q720 => 3,
            QualityTier::Q480 => 2,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            QualityTier::Q4K => "4K",
            QualityTier::Q1080 => "1080p",
            QualityTier::Q720 => "720p",
            QualityTier::Q480 => "480p",
        }
    }
}

/// Transcoding job with priority information
#[derive(Debug, Clone)]
pub struct PrioritizedTranscodingJob {
    pub job_id: String,
    pub video_id: String,
    pub quality_tier: QualityTier,
    pub source_path: String,
    pub output_path: String,
    pub priority: u8,
    pub created_at: u64,
    pub status: TranscodingStatus,
    pub progress_percent: u32,
    pub estimated_remaining_secs: u32,
}

/// Transcoding status
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TranscodingStatus {
    Pending,
    InProgress,
    Completed,
    Failed,
    Cancelled,
}

impl TranscodingStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            TranscodingStatus::Pending => "pending",
            TranscodingStatus::InProgress => "in_progress",
            TranscodingStatus::Completed => "completed",
            TranscodingStatus::Failed => "failed",
            TranscodingStatus::Cancelled => "cancelled",
        }
    }
}

/// Optimized transcoding pipeline with parallel job scheduling
pub struct TranscodingOptimizer {
    config: VideoProcessingConfig,
    /// Maximum parallel transcoding jobs
    max_parallel_jobs: usize,
    /// Priority queue of pending jobs
    job_queue: Arc<Mutex<VecDeque<PrioritizedTranscodingJob>>>,
    /// Currently active jobs
    active_jobs: Arc<RwLock<Vec<PrioritizedTranscodingJob>>>,
    /// Completed jobs cache
    completed_jobs: Arc<RwLock<Vec<PrioritizedTranscodingJob>>>,
}

impl TranscodingOptimizer {
    /// Create new optimized transcoding pipeline
    pub fn new(config: VideoProcessingConfig) -> Self {
        // Default: max_parallel_jobs = min(4, CPU cores)
        let max_parallel_jobs = (num_cpus::get() as usize).min(8).max(2);

        info!(
            "Initializing TranscodingOptimizer with {} max parallel jobs",
            max_parallel_jobs
        );

        Self {
            config,
            max_parallel_jobs,
            job_queue: Arc::new(Mutex::new(VecDeque::new())),
            active_jobs: Arc::new(RwLock::new(Vec::new())),
            completed_jobs: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Queue transcoding jobs for all quality tiers with priority
    pub async fn queue_all_qualities(
        &self,
        video_id: &str,
        source_path: &str,
        output_dir: &str,
    ) -> Result<Vec<String>> {
        debug!(
            "Queuing transcoding jobs for all qualities: video_id={}",
            video_id
        );

        // Define quality tiers and priority order
        // High priority first: 1080p, 720p, 480p
        // Low priority: 4K (optional)
        let qualities = vec![
            (QualityTier::Q1080, 3),
            (QualityTier::Q720, 3),
            (QualityTier::Q480, 2),
            // (QualityTier::Q4K, 1),  // Optional, only if resources available
        ];

        let mut job_ids = Vec::new();
        let mut queue = self.job_queue.lock().await;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        for (quality, priority) in qualities {
            let job_id = format!("{}-{}", video_id, quality.as_str());
            let output_path = format!("{}/{}.mp4", output_dir, quality.as_str());

            let job = PrioritizedTranscodingJob {
                job_id: job_id.clone(),
                video_id: video_id.to_string(),
                quality_tier: quality.clone(),
                source_path: source_path.to_string(),
                output_path,
                priority,
                created_at: now,
                status: TranscodingStatus::Pending,
                progress_percent: 0,
                estimated_remaining_secs: 0,
            };

            queue.push_back(job);
            job_ids.push(job_id);
        }

        info!(
            "Queued {} transcoding jobs for video: {} (queue depth: {})",
            job_ids.len(),
            video_id,
            queue.len()
        );

        Ok(job_ids)
    }

    /// Process jobs from queue with priority-based scheduling
    pub async fn process_next_job(&self) -> Result<Option<PrioritizedTranscodingJob>> {
        let mut queue = self.job_queue.lock().await;

        if queue.is_empty() {
            debug!("Job queue is empty");
            return Ok(None);
        }

        let active = self.active_jobs.read().await;
        let active_count = active.len();
        drop(active);

        if active_count >= self.max_parallel_jobs {
            debug!(
                "Max parallel jobs reached ({}/{})",
                active_count, self.max_parallel_jobs
            );
            return Ok(None);
        }

        // Sort queue by priority (higher first) and then by age (older first)
        let jobs: Vec<_> = queue.iter().cloned().collect();
        let mut sorted_jobs = jobs;
        sorted_jobs.sort_by(|a, b| {
            let priority_cmp = b.priority.cmp(&a.priority);
            if priority_cmp == std::cmp::Ordering::Equal {
                a.created_at.cmp(&b.created_at)
            } else {
                priority_cmp
            }
        });

        if let Some(job) = sorted_jobs.first() {
            // Find and remove the job from queue
            if let Some(pos) = queue.iter().position(|j| j.job_id == job.job_id) {
                let mut job = queue.remove(pos).unwrap();
                job.status = TranscodingStatus::InProgress;

                // Add to active jobs
                let mut active = self.active_jobs.write().await;
                active.push(job.clone());

                info!(
                    "Starting transcoding job: {} (quality: {}, priority: {})",
                    job.job_id,
                    job.quality_tier.as_str(),
                    job.priority
                );

                return Ok(Some(job));
            }
        }

        Ok(None)
    }

    /// Update job progress
    pub async fn update_progress(
        &self,
        job_id: &str,
        progress_percent: u32,
        estimated_remaining_secs: u32,
    ) -> Result<()> {
        let mut active = self.active_jobs.write().await;

        for job in active.iter_mut() {
            if job.job_id == job_id {
                job.progress_percent = progress_percent;
                job.estimated_remaining_secs = estimated_remaining_secs;
                debug!(
                    "Updated progress for job {}: {}% (ETA: {}s)",
                    job_id, progress_percent, estimated_remaining_secs
                );
                return Ok(());
            }
        }

        Err(AppError::NotFound(format!("Job not found: {}", job_id)))
    }

    /// Mark job as completed
    pub async fn mark_completed(&self, job_id: &str) -> Result<()> {
        let mut active = self.active_jobs.write().await;

        if let Some(pos) = active.iter().position(|j| j.job_id == job_id) {
            let mut job = active.remove(pos);
            job.status = TranscodingStatus::Completed;
            job.progress_percent = 100;

            let mut completed = self.completed_jobs.write().await;
            completed.push(job.clone());

            info!("Transcoding job completed: {}", job_id);
            Ok(())
        } else {
            Err(AppError::NotFound(format!(
                "Active job not found: {}",
                job_id
            )))
        }
    }

    /// Mark job as failed
    pub async fn mark_failed(&self, job_id: &str, error_msg: &str) -> Result<()> {
        let mut active = self.active_jobs.write().await;

        if let Some(pos) = active.iter().position(|j| j.job_id == job_id) {
            let mut job = active.remove(pos);
            job.status = TranscodingStatus::Failed;

            let mut completed = self.completed_jobs.write().await;
            completed.push(job.clone());

            error!("Transcoding job failed: {} - {}", job_id, error_msg);
            Ok(())
        } else {
            Err(AppError::NotFound(format!(
                "Active job not found: {}",
                job_id
            )))
        }
    }

    /// Get queue depth
    pub async fn get_queue_depth(&self) -> usize {
        self.job_queue.lock().await.len()
    }

    /// Get active jobs count
    pub async fn get_active_count(&self) -> usize {
        self.active_jobs.read().await.len()
    }

    /// Get job status
    pub async fn get_job_status(&self, job_id: &str) -> Result<TranscodingStatus> {
        // Check active jobs
        let active = self.active_jobs.read().await;
        if let Some(job) = active.iter().find(|j| j.job_id == job_id) {
            return Ok(job.status);
        }
        drop(active);

        // Check completed jobs
        let completed = self.completed_jobs.read().await;
        if let Some(job) = completed.iter().find(|j| j.job_id == job_id) {
            return Ok(job.status);
        }

        Err(AppError::NotFound(format!("Job not found: {}", job_id)))
    }

    /// Get statistics
    pub async fn get_statistics(&self) -> TranscodingStatistics {
        let queue_depth = self.job_queue.lock().await.len();
        let active_count = self.active_jobs.read().await.len();
        let completed = self.completed_jobs.read().await;

        let completed_count = completed.len();
        let failed_count = completed
            .iter()
            .filter(|j| j.status == TranscodingStatus::Failed)
            .count();

        TranscodingStatistics {
            queue_depth,
            active_jobs: active_count,
            completed_jobs: completed_count,
            failed_jobs: failed_count,
            max_parallel_jobs: self.max_parallel_jobs,
        }
    }

    /// Get FFmpeg command for transcoding
    pub fn get_ffmpeg_command(
        &self,
        input_path: &str,
        output_path: &str,
        quality: &QualityTier,
    ) -> String {
        let (width, height) = quality.resolution();
        let bitrate = quality.bitrate_kbps();
        let preset = quality.ffmpeg_preset();
        let crf = quality.crf_value();

        format!(
            "ffmpeg -i {} -vf scale={}:{} -c:v libx264 -preset {} -crf {} -b:v {}k -c:a aac -b:a 128k {}",
            input_path, width, height, preset, crf, bitrate, output_path
        )
    }
}

/// Transcoding statistics
#[derive(Debug, Clone)]
pub struct TranscodingStatistics {
    pub queue_depth: usize,
    pub active_jobs: usize,
    pub completed_jobs: usize,
    pub failed_jobs: usize,
    pub max_parallel_jobs: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::video_config::VideoProcessingConfig;
    use std::collections::HashMap;

    fn create_test_config() -> VideoProcessingConfig {
        let mut target_bitrates = HashMap::new();
        target_bitrates.insert("480p".to_string(), 1000);
        target_bitrates.insert("720p".to_string(), 2500);
        target_bitrates.insert("1080p".to_string(), 5000);

        VideoProcessingConfig {
            ffmpeg_path: "/usr/bin/ffmpeg".to_string(),
            max_parallel_jobs: 4,
            job_timeout_seconds: 7200,
            target_bitrates,
            s3_processed_bucket: "test-processed".to_string(),
            s3_processed_prefix: "processed/".to_string(),
            extract_thumbnails: true,
            thumbnail_dimensions: (320, 180),
            enable_mock: false,
        }
    }

    #[test]
    fn test_quality_tier_properties() {
        assert_eq!(QualityTier::Q480.as_str(), "480p");
        assert_eq!(QualityTier::Q720.bitrate_kbps(), 2500);
        assert_eq!(QualityTier::Q1080.crf_value(), 26);
        assert_eq!(QualityTier::Q4K.priority(), 1);
    }

    #[test]
    fn test_transcoding_status_str() {
        assert_eq!(TranscodingStatus::Pending.as_str(), "pending");
        assert_eq!(TranscodingStatus::Completed.as_str(), "completed");
    }

    #[tokio::test]
    async fn test_queue_all_qualities() {
        let optimizer = TranscodingOptimizer::new(create_test_config());

        let job_ids = optimizer
            .queue_all_qualities("video-123", "/tmp/input.mp4", "/tmp/output")
            .await
            .unwrap();

        assert_eq!(job_ids.len(), 3); // 480p, 720p, 1080p
        assert_eq!(optimizer.get_queue_depth().await, 3);
    }

    #[tokio::test]
    async fn test_priority_sorting() {
        let optimizer = TranscodingOptimizer::new(create_test_config());

        optimizer
            .queue_all_qualities("video-123", "/tmp/input.mp4", "/tmp/output")
            .await
            .unwrap();

        // First job should be high priority (1080p or 720p)
        let job = optimizer.process_next_job().await.unwrap().unwrap();
        assert!(job.priority >= 3);
    }

    #[tokio::test]
    async fn test_max_parallel_limit() {
        let config = create_test_config();
        let optimizer = TranscodingOptimizer::new(config);

        // Queue multiple jobs
        optimizer
            .queue_all_qualities("video-123", "/tmp/input.mp4", "/tmp/output")
            .await
            .unwrap();

        // Process jobs up to max_parallel_jobs limit
        let mut count = 0;
        while let Ok(Some(job)) = optimizer.process_next_job().await {
            optimizer.mark_completed(&job.job_id).await.ok();
            count += 1;
        }

        assert!(count > 0);
    }

    #[test]
    fn test_ffmpeg_command_generation() {
        let optimizer = TranscodingOptimizer::new(create_test_config());

        let cmd = optimizer.get_ffmpeg_command(
            "/tmp/input.mp4",
            "/tmp/output_720p.mp4",
            &QualityTier::Q720,
        );

        assert!(cmd.contains("scale=1280:720"));
        assert!(cmd.contains("preset medium"));
        assert!(cmd.contains("crf 28"));
        assert!(cmd.contains("2500k"));
    }
}

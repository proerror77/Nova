//! Video service core models and types
//!
//! Shared data structures for video-service and related systems

pub mod constants;
pub mod models;

pub use models::*;

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn test_video_status_transitions() {
        let mut status = VideoStatus::Pending;
        assert_eq!(status, VideoStatus::Pending);

        status = VideoStatus::Processing;
        assert_eq!(status, VideoStatus::Processing);

        status = VideoStatus::Ready;
        assert_eq!(status, VideoStatus::Ready);
    }

    #[test]
    fn test_video_quality_creation() {
        let quality = VideoQuality {
            resolution: "1080p".to_string(),
            bitrate: 5000,
            format: "mp4".to_string(),
            codec: "h264".to_string(),
            url: None,
        };
        assert_eq!(quality.bitrate, 5000);
    }
}

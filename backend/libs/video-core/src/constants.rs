//! Video service constants

/// Maximum video file size (500 MB)
pub const MAX_VIDEO_SIZE: i64 = 500 * 1024 * 1024;

/// Maximum video title length
pub const MAX_TITLE_LENGTH: usize = 200;

/// Maximum video description length
pub const MAX_DESCRIPTION_LENGTH: usize = 5000;

/// Allowed video file extensions
pub const ALLOWED_EXTENSIONS: &[&str] = &["mp4", "webm", "avi", "mov", "mkv"];

/// Default transcoding qualities
pub const DEFAULT_QUALITIES: &[&str] = &["1080p", "720p", "480p"];

/// FFmpeg timeout (60 minutes)
pub const FFMPEG_TIMEOUT_SECS: u64 = 60 * 60;

/// Chunk upload timeout (30 minutes per chunk)
pub const CHUNK_UPLOAD_TIMEOUT_SECS: u64 = 30 * 60;

/// Maximum concurrent transcoding jobs
pub const MAX_CONCURRENT_TRANSCODING: usize = 5;

#![cfg(feature = "legacy_video_tests")]
/// Unit Tests for Video Metadata Validation (T131)
/// Tests file size validation, codec detection, metadata extraction
use std::collections::HashMap;

/// Mock video metadata structure
#[derive(Debug, Clone)]
pub struct VideoMetadata {
    pub file_name: String,
    pub file_size_bytes: u64,
    pub duration_seconds: u32,
    pub width: u32,
    pub height: u32,
    pub codec: String,
    pub bitrate_kbps: u32,
    pub frame_rate: f32,
    pub mime_type: String,
}

/// Video validation errors
#[derive(Debug, PartialEq)]
pub enum VideoValidationError {
    FileTooLarge,
    FileTooSmall,
    InvalidCodec,
    InvalidResolution,
    InvalidFrameRate,
    InvalidMimeType,
    CorruptedMetadata,
}

/// Video metadata validator
pub struct VideoMetadataValidator {
    max_file_size_mb: u64,
    min_file_size_bytes: u64,
    allowed_codecs: Vec<String>,
    allowed_resolutions: Vec<(u32, u32)>,
    allowed_mime_types: Vec<String>,
}

impl VideoMetadataValidator {
    pub fn new() -> Self {
        Self {
            max_file_size_mb: 500,
            min_file_size_bytes: 100_000, // 100KB minimum
            allowed_codecs: vec![
                "h264".to_string(),
                "h265".to_string(),
                "vp9".to_string(),
                "av1".to_string(),
            ],
            allowed_resolutions: vec![
                (1920, 1080), // Full HD
                (1280, 720),  // HD
                (854, 480),   // SD
                (640, 360),   // Low quality
            ],
            allowed_mime_types: vec![
                "video/mp4".to_string(),
                "video/webm".to_string(),
                "video/quicktime".to_string(),
            ],
        }
    }

    /// Validate video file size
    pub fn validate_file_size(&self, size_bytes: u64) -> Result<(), VideoValidationError> {
        if size_bytes < self.min_file_size_bytes {
            return Err(VideoValidationError::FileTooSmall);
        }

        let max_bytes = self.max_file_size_mb * 1_024 * 1_024;
        if size_bytes > max_bytes {
            return Err(VideoValidationError::FileTooLarge);
        }

        Ok(())
    }

    /// Validate video codec
    pub fn validate_codec(&self, codec: &str) -> Result<(), VideoValidationError> {
        if self.allowed_codecs.contains(&codec.to_lowercase()) {
            Ok(())
        } else {
            Err(VideoValidationError::InvalidCodec)
        }
    }

    /// Validate video resolution
    pub fn validate_resolution(&self, width: u32, height: u32) -> Result<(), VideoValidationError> {
        if self.allowed_resolutions.contains(&(width, height)) {
            Ok(())
        } else {
            Err(VideoValidationError::InvalidResolution)
        }
    }

    /// Validate frame rate
    pub fn validate_frame_rate(&self, fps: f32) -> Result<(), VideoValidationError> {
        if fps > 0.0 && fps <= 120.0 {
            Ok(())
        } else {
            Err(VideoValidationError::InvalidFrameRate)
        }
    }

    /// Validate MIME type
    pub fn validate_mime_type(&self, mime_type: &str) -> Result<(), VideoValidationError> {
        if self.allowed_mime_types.contains(&mime_type.to_string()) {
            Ok(())
        } else {
            Err(VideoValidationError::InvalidMimeType)
        }
    }

    /// Validate complete metadata
    pub fn validate_metadata(&self, metadata: &VideoMetadata) -> Result<(), VideoValidationError> {
        self.validate_file_size(metadata.file_size_bytes)?;
        self.validate_codec(&metadata.codec)?;
        self.validate_resolution(metadata.width, metadata.height)?;
        self.validate_frame_rate(metadata.frame_rate)?;
        self.validate_mime_type(&metadata.mime_type)?;

        Ok(())
    }

    /// Extract codec from filename
    pub fn extract_codec_from_filename(&self, filename: &str) -> Option<String> {
        if filename.ends_with(".mp4") {
            Some("h264".to_string())
        } else if filename.ends_with(".webm") {
            Some("vp9".to_string())
        } else if filename.ends_with(".mov") {
            Some("h264".to_string())
        } else {
            None
        }
    }
}

// ============================================
// Unit Tests (T131)
// ============================================

#[test]
fn test_file_size_valid() {
    let validator = VideoMetadataValidator::new();

    // Valid file size: 50MB
    let result = validator.validate_file_size(50 * 1_024 * 1_024);
    assert!(result.is_ok());
}

#[test]
fn test_file_size_too_small() {
    let validator = VideoMetadataValidator::new();

    // File too small: 50KB
    let result = validator.validate_file_size(50 * 1_024);
    assert_eq!(result, Err(VideoValidationError::FileTooSmall));
}

#[test]
fn test_file_size_too_large() {
    let validator = VideoMetadataValidator::new();

    // File too large: 1000MB
    let result = validator.validate_file_size(1000 * 1_024 * 1_024);
    assert_eq!(result, Err(VideoValidationError::FileTooLarge));
}

#[test]
fn test_codec_valid_h264() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_codec("h264");
    assert!(result.is_ok());
}

#[test]
fn test_codec_valid_vp9() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_codec("VP9");
    assert!(result.is_ok()); // Case insensitive
}

#[test]
fn test_codec_invalid() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_codec("mpeg2");
    assert_eq!(result, Err(VideoValidationError::InvalidCodec));
}

#[test]
fn test_resolution_valid_1080p() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_resolution(1920, 1080);
    assert!(result.is_ok());
}

#[test]
fn test_resolution_valid_720p() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_resolution(1280, 720);
    assert!(result.is_ok());
}

#[test]
fn test_resolution_invalid() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_resolution(2560, 1440); // 2K - not in allowed list
    assert_eq!(result, Err(VideoValidationError::InvalidResolution));
}

#[test]
fn test_frame_rate_valid_30fps() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_frame_rate(30.0);
    assert!(result.is_ok());
}

#[test]
fn test_frame_rate_valid_60fps() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_frame_rate(60.0);
    assert!(result.is_ok());
}

#[test]
fn test_frame_rate_valid_120fps() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_frame_rate(120.0);
    assert!(result.is_ok());
}

#[test]
fn test_frame_rate_invalid_zero() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_frame_rate(0.0);
    assert_eq!(result, Err(VideoValidationError::InvalidFrameRate));
}

#[test]
fn test_frame_rate_invalid_too_high() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_frame_rate(240.0);
    assert_eq!(result, Err(VideoValidationError::InvalidFrameRate));
}

#[test]
fn test_mime_type_valid_mp4() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_mime_type("video/mp4");
    assert!(result.is_ok());
}

#[test]
fn test_mime_type_valid_webm() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_mime_type("video/webm");
    assert!(result.is_ok());
}

#[test]
fn test_mime_type_invalid() {
    let validator = VideoMetadataValidator::new();

    let result = validator.validate_mime_type("video/mpeg");
    assert_eq!(result, Err(VideoValidationError::InvalidMimeType));
}

#[test]
fn test_complete_metadata_valid() {
    let validator = VideoMetadataValidator::new();

    let metadata = VideoMetadata {
        file_name: "sample.mp4".to_string(),
        file_size_bytes: 100 * 1_024 * 1_024, // 100MB
        duration_seconds: 300,
        width: 1920,
        height: 1080,
        codec: "h264".to_string(),
        bitrate_kbps: 5000,
        frame_rate: 30.0,
        mime_type: "video/mp4".to_string(),
    };

    let result = validator.validate_metadata(&metadata);
    assert!(result.is_ok());
}

#[test]
fn test_complete_metadata_invalid_codec() {
    let validator = VideoMetadataValidator::new();

    let metadata = VideoMetadata {
        file_name: "sample.mp4".to_string(),
        file_size_bytes: 100 * 1_024 * 1_024,
        duration_seconds: 300,
        width: 1920,
        height: 1080,
        codec: "mpeg2".to_string(), // Invalid codec
        bitrate_kbps: 5000,
        frame_rate: 30.0,
        mime_type: "video/mp4".to_string(),
    };

    let result = validator.validate_metadata(&metadata);
    assert_eq!(result, Err(VideoValidationError::InvalidCodec));
}

#[test]
fn test_extract_codec_from_filename_mp4() {
    let validator = VideoMetadataValidator::new();

    let codec = validator.extract_codec_from_filename("video.mp4");
    assert_eq!(codec, Some("h264".to_string()));
}

#[test]
fn test_extract_codec_from_filename_webm() {
    let validator = VideoMetadataValidator::new();

    let codec = validator.extract_codec_from_filename("video.webm");
    assert_eq!(codec, Some("vp9".to_string()));
}

#[test]
fn test_extract_codec_from_filename_mov() {
    let validator = VideoMetadataValidator::new();

    let codec = validator.extract_codec_from_filename("video.mov");
    assert_eq!(codec, Some("h264".to_string()));
}

#[test]
fn test_extract_codec_from_filename_unknown() {
    let validator = VideoMetadataValidator::new();

    let codec = validator.extract_codec_from_filename("video.avi");
    assert_eq!(codec, None);
}

#[test]
fn test_metadata_edge_case_minimum_file_size() {
    let validator = VideoMetadataValidator::new();

    let metadata = VideoMetadata {
        file_name: "tiny.mp4".to_string(),
        file_size_bytes: 100_000, // Exactly minimum
        duration_seconds: 1,
        width: 640,
        height: 360,
        codec: "h264".to_string(),
        bitrate_kbps: 500,
        frame_rate: 24.0,
        mime_type: "video/mp4".to_string(),
    };

    let result = validator.validate_metadata(&metadata);
    assert!(result.is_ok());
}

#[test]
fn test_metadata_edge_case_maximum_file_size() {
    let validator = VideoMetadataValidator::new();

    let metadata = VideoMetadata {
        file_name: "large.mp4".to_string(),
        file_size_bytes: 500 * 1_024 * 1_024, // Exactly maximum
        duration_seconds: 3600,
        width: 1920,
        height: 1080,
        codec: "h265".to_string(),
        bitrate_kbps: 10000,
        frame_rate: 60.0,
        mime_type: "video/mp4".to_string(),
    };

    let result = validator.validate_metadata(&metadata);
    assert!(result.is_ok());
}

#[test]
fn test_all_supported_codecs() {
    let validator = VideoMetadataValidator::new();

    for codec in &["h264", "h265", "vp9", "av1"] {
        let result = validator.validate_codec(codec);
        assert!(result.is_ok(), "Codec {} should be valid", codec);
    }
}

#[test]
fn test_all_supported_resolutions() {
    let validator = VideoMetadataValidator::new();

    let resolutions = vec![(1920, 1080), (1280, 720), (854, 480), (640, 360)];

    for (width, height) in resolutions {
        let result = validator.validate_resolution(width, height);
        assert!(
            result.is_ok(),
            "Resolution {}x{} should be valid",
            width,
            height
        );
    }
}

#[test]
fn test_all_supported_mime_types() {
    let validator = VideoMetadataValidator::new();

    for mime in &["video/mp4", "video/webm", "video/quicktime"] {
        let result = validator.validate_mime_type(mime);
        assert!(result.is_ok(), "MIME type {} should be valid", mime);
    }
}

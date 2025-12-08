pub mod gcs;
/// Video service module
///
/// Provides video-related services migrated from video-service:
/// - S3 upload and management for video files
/// - Presigned URL generation for direct client uploads
/// - File verification and integrity checks
///
/// Part of Phase C: Media Consolidation
pub mod s3;

// Re-export commonly used functions
pub use s3::{
    delete_s3_object, generate_presigned_url, get_s3_client, health_check, upload_video_to_s3,
    verify_file_hash, verify_s3_object_exists,
};

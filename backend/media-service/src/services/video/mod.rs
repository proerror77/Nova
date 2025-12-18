pub mod gcs;
/// Video service module
///
/// Provides video-related services:
/// - GCS upload and management for video files
/// - Presigned URL generation for direct client uploads
/// - File verification and integrity checks
/// - GCP Transcoder API integration for real video transcoding
///
/// Part of Phase C: Media Consolidation + GCP Migration
pub mod storage;
pub mod transcoder;

// Re-export GCS storage client and functions
pub use storage::{get_gcs_client, GcsStorageClient};

// Re-export GCP Transcoder client
pub use transcoder::{
    is_transcoding_enabled, GcpTranscoderClient, TranscodeJobResult, TranscodeJobStatus,
    TranscodeOutput, TranscodeProfile, TranscoderConfig,
};

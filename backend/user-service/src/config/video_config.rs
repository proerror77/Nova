/// Video Processing Configuration (Phase 4)
///
/// Configuration for video upload, transcoding, streaming, and deep learning inference.
use serde::{Deserialize, Serialize};
use std::env;

/// Video Service Configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoConfig {
    /// Video upload configuration
    pub upload: VideoUploadConfig,
    /// Video processing configuration
    pub processing: VideoProcessingConfig,
    /// Deep learning inference configuration
    pub inference: DeepLearningConfig,
    /// Video streaming configuration
    pub streaming: StreamingConfig,
    /// CDN configuration
    pub cdn: CdnConfig,
}

/// Video Upload Configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoUploadConfig {
    /// Maximum file size in bytes (default: 500MB)
    pub max_file_size_bytes: u64,
    /// Allowed video codecs (H.264, HEVC, etc.)
    pub allowed_codecs: Vec<String>,
    /// Allowed container formats (mp4, webm, etc.)
    pub allowed_formats: Vec<String>,
    /// Maximum video duration in seconds (default: 600 = 10 minutes)
    pub max_duration_seconds: u32,
    /// S3 bucket for raw uploads
    pub s3_upload_bucket: String,
    /// S3 prefix for uploads
    pub s3_upload_prefix: String,
    /// Enable virus scanning on upload
    pub enable_virus_scan: bool,
}

/// Video Processing Configuration (FFmpeg)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoProcessingConfig {
    /// Path to FFmpeg binary
    pub ffmpeg_path: String,
    /// Enable parallel transcoding jobs
    pub max_parallel_jobs: usize,
    /// Job timeout in seconds
    pub job_timeout_seconds: u32,
    /// Target bitrates for transcoding (bitrate_key -> bitrate in kbps)
    pub target_bitrates: std::collections::HashMap<String, u32>,
    /// S3 bucket for processed videos
    pub s3_processed_bucket: String,
    /// S3 prefix for processed videos
    pub s3_processed_prefix: String,
    /// Enable thumbnail extraction
    pub extract_thumbnails: bool,
    /// Thumbnail dimensions (width, height)
    pub thumbnail_dimensions: (u32, u32),
}

impl Default for VideoProcessingConfig {
    fn default() -> Self {
        let mut bitrates = std::collections::HashMap::new();
        bitrates.insert("720p".to_string(), 2500);
        bitrates.insert("480p".to_string(), 1500);
        bitrates.insert("360p".to_string(), 800);

        Self {
            ffmpeg_path: "ffmpeg".to_string(),
            max_parallel_jobs: 4,
            job_timeout_seconds: 3600,
            target_bitrates: bitrates,
            s3_processed_bucket: "nova-videos".to_string(),
            s3_processed_prefix: "processed/".to_string(),
            extract_thumbnails: true,
            thumbnail_dimensions: (320, 180),
        }
    }
}

/// Deep Learning Configuration (TensorFlow Serving + Milvus)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeepLearningConfig {
    /// TensorFlow Serving endpoint URL
    pub tf_serving_url: String,
    /// Model name in TensorFlow Serving
    pub model_name: String,
    /// Model version
    pub model_version: String,
    /// Embedding dimension
    pub embedding_dim: usize,
    /// Milvus vector database URL
    pub milvus_url: String,
    /// Milvus collection name
    pub milvus_collection: String,
    /// Inference timeout in seconds
    pub inference_timeout_seconds: u32,
    /// Batch size for inference
    pub inference_batch_size: usize,
    /// Enable model caching
    pub enable_cache: bool,
}

impl Default for DeepLearningConfig {
    fn default() -> Self {
        Self {
            tf_serving_url: "http://tf-serving:8500".to_string(),
            model_name: "video_embeddings".to_string(),
            model_version: "1".to_string(),
            embedding_dim: 256,
            milvus_url: "http://milvus:19530".to_string(),
            milvus_collection: "video_embeddings".to_string(),
            inference_timeout_seconds: 30,
            inference_batch_size: 32,
            enable_cache: true,
        }
    }
}

/// Video Streaming Configuration (HLS/DASH)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamingConfig {
    /// Enable HLS streaming
    pub enable_hls: bool,
    /// Enable DASH streaming
    pub enable_dash: bool,
    /// HLS segment duration in seconds
    pub hls_segment_duration: u32,
    /// DASH segment duration in seconds
    pub dash_segment_duration: u32,
    /// Enable adaptive bitrate switching
    pub enable_abr: bool,
    /// Bandwidth estimation window in seconds
    pub bandwidth_estimation_window: u32,
    /// Video pre-load duration in seconds
    pub preload_duration: u32,
}

impl Default for StreamingConfig {
    fn default() -> Self {
        Self {
            enable_hls: true,
            enable_dash: true,
            hls_segment_duration: 10,
            dash_segment_duration: 10,
            enable_abr: true,
            bandwidth_estimation_window: 20,
            preload_duration: 30,
        }
    }
}

/// CDN Configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CdnConfig {
    /// CDN provider (cloudflare, cloudfront, etc.)
    pub provider: String,
    /// CDN endpoint URL
    pub endpoint_url: String,
    /// CDN cache TTL in seconds
    pub cache_ttl_seconds: u32,
    /// Enable geographic caching
    pub enable_geo_cache: bool,
    /// Fallback to S3 if CDN fails
    pub fallback_to_s3: bool,
}

impl Default for CdnConfig {
    fn default() -> Self {
        Self {
            provider: "cloudflare".to_string(),
            endpoint_url: "https://video.nova.dev".to_string(),
            cache_ttl_seconds: 3600,
            enable_geo_cache: true,
            fallback_to_s3: true,
        }
    }
}

impl VideoConfig {
    /// Load video configuration from environment variables
    pub fn from_env() -> Self {
        let mut bitrates = std::collections::HashMap::new();
        bitrates.insert("720p".to_string(), 2500);
        bitrates.insert("480p".to_string(), 1500);
        bitrates.insert("360p".to_string(), 800);

        Self {
            upload: VideoUploadConfig {
                max_file_size_bytes: env::var("VIDEO_MAX_FILE_SIZE")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(500 * 1024 * 1024), // 500MB default
                allowed_codecs: vec!["h264".to_string(), "hevc".to_string()],
                allowed_formats: vec!["mp4".to_string(), "webm".to_string()],
                max_duration_seconds: env::var("VIDEO_MAX_DURATION")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(600), // 10 minutes default
                s3_upload_bucket: env::var("VIDEO_UPLOAD_BUCKET")
                    .unwrap_or_else(|_| "nova-videos-upload".to_string()),
                s3_upload_prefix: env::var("VIDEO_UPLOAD_PREFIX")
                    .unwrap_or_else(|_| "uploads/".to_string()),
                enable_virus_scan: env::var("VIDEO_ENABLE_VIRUS_SCAN")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(true),
            },
            processing: VideoProcessingConfig {
                ffmpeg_path: env::var("FFMPEG_PATH").unwrap_or_else(|_| "ffmpeg".to_string()),
                max_parallel_jobs: env::var("VIDEO_MAX_PARALLEL_JOBS")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(4),
                job_timeout_seconds: env::var("VIDEO_JOB_TIMEOUT")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(3600),
                target_bitrates: bitrates,
                s3_processed_bucket: env::var("VIDEO_PROCESSED_BUCKET")
                    .unwrap_or_else(|_| "nova-videos".to_string()),
                s3_processed_prefix: env::var("VIDEO_PROCESSED_PREFIX")
                    .unwrap_or_else(|_| "processed/".to_string()),
                extract_thumbnails: true,
                thumbnail_dimensions: (320, 180),
            },
            inference: DeepLearningConfig {
                tf_serving_url: env::var("TF_SERVING_URL")
                    .unwrap_or_else(|_| "http://tf-serving:8500".to_string()),
                model_name: env::var("TF_MODEL_NAME")
                    .unwrap_or_else(|_| "video_embeddings".to_string()),
                model_version: env::var("TF_MODEL_VERSION").unwrap_or_else(|_| "1".to_string()),
                embedding_dim: env::var("EMBEDDING_DIM")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(256),
                milvus_url: env::var("MILVUS_URL")
                    .unwrap_or_else(|_| "http://milvus:19530".to_string()),
                milvus_collection: env::var("MILVUS_COLLECTION")
                    .unwrap_or_else(|_| "video_embeddings".to_string()),
                inference_timeout_seconds: env::var("INFERENCE_TIMEOUT")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(30),
                inference_batch_size: env::var("INFERENCE_BATCH_SIZE")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(32),
                enable_cache: env::var("INFERENCE_ENABLE_CACHE")
                    .ok()
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(true),
            },
            streaming: StreamingConfig::default(),
            cdn: CdnConfig::default(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_video_config_defaults() {
        let config = VideoConfig::from_env();
        assert_eq!(config.upload.max_file_size_bytes, 500 * 1024 * 1024);
        assert_eq!(config.upload.max_duration_seconds, 600);
        assert_eq!(config.inference.embedding_dim, 256);
    }

    #[test]
    fn test_processing_config_defaults() {
        let config = VideoProcessingConfig::default();
        assert_eq!(config.max_parallel_jobs, 4);
        assert_eq!(config.target_bitrates.get("720p"), Some(&2500));
    }
}

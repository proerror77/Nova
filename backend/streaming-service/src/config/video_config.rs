/// Video Streaming Configuration
///
/// Configuration structures for streaming manifest generation and CDN delivery.

use serde::{Deserialize, Serialize};

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

/// CDN Integration Service for Video Streaming
///
/// Manages content delivery through CDN providers with caching, failover,
/// and geographic routing capabilities. Supports CloudFront, Cloudflare,
/// and fallback to S3 origin.
use crate::config::video_config::CdnConfig;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info};

/// Cache entry for manifests
#[derive(Debug, Clone)]
pub struct CacheEntry {
    /// Manifest content
    pub content: String,
    /// Cache creation timestamp (Unix seconds)
    pub created_at: u64,
    /// TTL in seconds
    pub ttl_seconds: u32,
}

impl CacheEntry {
    /// Check if cache entry has expired
    pub fn is_expired(&self) -> bool {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        now > self.created_at + self.ttl_seconds as u64
    }
}

/// CDN Provider type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CdnProvider {
    CloudFront,
    Cloudflare,
    Generic,
}

impl CdnProvider {
    /// Parse provider from string
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "cloudfront" | "aws" => Self::CloudFront,
            "cloudflare" | "cf" => Self::Cloudflare,
            _ => Self::Generic,
        }
    }

    /// Get provider name
    pub fn name(&self) -> &'static str {
        match self {
            Self::CloudFront => "CloudFront",
            Self::Cloudflare => "Cloudflare",
            Self::Generic => "Generic",
        }
    }
}

/// CDN Service for manifest delivery and caching
pub struct CdnService {
    config: CdnConfig,
    provider: CdnProvider,
    /// In-memory manifest cache (video_id:quality -> manifest)
    cache: Arc<RwLock<HashMap<String, CacheEntry>>>,
}

impl CdnService {
    /// Create a new CDN service
    pub fn new(config: CdnConfig) -> Self {
        let provider = CdnProvider::from_str(&config.provider);

        info!(
            "Initializing CDN service: provider={}, ttl={}s, geo_cache={}",
            provider.name(),
            config.cache_ttl_seconds,
            config.enable_geo_cache
        );

        Self {
            config,
            provider,
            cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Get CDN URL for a manifest
    /// # Arguments
    /// * `video_id` - Video identifier
    /// * `quality` - Quality tier (e.g., "720p")
    /// * `format` - Manifest format ("hls" or "dash")
    pub fn get_manifest_url(&self, video_id: &str, quality: Option<&str>, format: &str) -> String {
        let path = match (quality, format) {
            (Some(q), _) => format!("videos/{}/{}.m3u8", video_id, q),
            (None, "dash") => format!("videos/{}.mpd", video_id),
            _ => format!("videos/{}/index.m3u8", video_id),
        };

        format!(
            "{}/{}",
            self.config.endpoint_url.trim_end_matches('/'),
            path
        )
    }

    /// Get manifest with caching support
    pub async fn get_cached_manifest(
        &self,
        cache_key: &str,
        manifest_generator: impl std::future::Future<Output = String>,
    ) -> String {
        // Try to get from cache
        {
            let cache = self.cache.read().await;
            if let Some(entry) = cache.get(cache_key) {
                if !entry.is_expired() {
                    debug!("Manifest cache hit: {}", cache_key);
                    return entry.content.clone();
                }
            }
        }

        debug!("Manifest cache miss: {}", cache_key);

        // Generate manifest
        let content = manifest_generator.await;

        // Store in cache
        {
            let mut cache = self.cache.write().await;
            cache.insert(
                cache_key.to_string(),
                CacheEntry {
                    content: content.clone(),
                    created_at: std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_secs())
                        .unwrap_or(0),
                    ttl_seconds: self.config.cache_ttl_seconds,
                },
            );
        }

        content
    }

    /// Invalidate manifest cache entry
    pub async fn invalidate_cache(&self, cache_key: &str) {
        let mut cache = self.cache.write().await;
        if cache.remove(cache_key).is_some() {
            info!("Cache invalidated: {}", cache_key);
        }
    }

    /// Clear all cache (for specific video or all)
    pub async fn clear_cache(&self, video_id: Option<&str>) {
        let mut cache = self.cache.write().await;

        if let Some(vid) = video_id {
            // Clear cache for specific video
            let keys_to_remove: Vec<_> = cache
                .keys()
                .filter(|k| k.starts_with(vid))
                .cloned()
                .collect();

            for key in keys_to_remove {
                cache.remove(&key);
            }

            info!("Cache cleared for video: {}", vid);
        } else {
            // Clear all cache
            let count = cache.len();
            cache.clear();
            info!("Cache cleared: {} entries", count);
        }
    }

    /// Get cache statistics
    pub async fn get_cache_stats(&self) -> CacheStats {
        let cache = self.cache.read().await;

        let mut expired_count = 0;
        for entry in cache.values() {
            if entry.is_expired() {
                expired_count += 1;
            }
        }

        CacheStats {
            total_entries: cache.len(),
            expired_entries: expired_count,
            active_entries: cache.len() - expired_count,
        }
    }

    /// Build origin URL (fallback for CDN failures)
    pub fn get_origin_url(&self, video_id: &str, quality: Option<&str>, format: &str) -> String {
        // Format: s3://bucket/prefix/videos/video-id/quality.m3u8
        let path = match (quality, format) {
            (Some(q), _) => format!("videos/{}/{}.m3u8", video_id, q),
            (None, "dash") => format!("videos/{}.mpd", video_id),
            _ => format!("videos/{}/index.m3u8", video_id),
        };

        format!("s3://{}/{}{}", "nova-videos", "processed/", path)
    }

    /// Check CDN health (returns true if accessible)
    pub async fn check_cdn_health(&self) -> bool {
        // In production, would check CDN endpoint availability
        // For now, return true (assuming CDN is healthy)
        debug!("CDN health check: provider={}", self.provider.name());
        true
    }

    /// Get CDN configuration
    pub fn config(&self) -> &CdnConfig {
        &self.config
    }

    /// Get CDN provider
    pub fn provider(&self) -> CdnProvider {
        self.provider
    }

    /// Get fallback URL when CDN fails
    pub fn get_fallback_url(&self, video_id: &str, quality: Option<&str>) -> String {
        if self.config.fallback_to_s3 {
            self.get_origin_url(video_id, quality, "hls")
        } else {
            // If no fallback, return empty string
            String::new()
        }
    }

    /// Add cache control headers for response
    pub fn get_cache_headers(&self) -> HashMap<String, String> {
        let mut headers = HashMap::new();

        // Cache-Control header for browser caching
        headers.insert(
            "Cache-Control".to_string(),
            format!("public, max-age={}", self.config.cache_ttl_seconds),
        );

        // ETag for conditional requests
        headers.insert(
            "ETag".to_string(),
            format!("W/\"{}\"", chrono::Utc::now().timestamp()),
        );

        // CDN-specific headers
        match self.provider {
            CdnProvider::CloudFront => {
                headers.insert("X-Cache".to_string(), "from-cloudfront".to_string());
            }
            CdnProvider::Cloudflare => {
                headers.insert("X-Cache".to_string(), "from-cloudflare".to_string());
            }
            CdnProvider::Generic => {
                headers.insert("X-Cache".to_string(), "from-cdn".to_string());
            }
        }

        // CORS headers for cross-origin access
        headers.insert("Access-Control-Allow-Origin".to_string(), "*".to_string());
        headers.insert(
            "Access-Control-Allow-Methods".to_string(),
            "GET, HEAD, OPTIONS".to_string(),
        );

        headers
    }

    /// Get geographic routing info based on IP
    pub fn get_geo_routing(&self, client_ip: Option<&str>) -> GeographicRouting {
        if !self.config.enable_geo_cache {
            return GeographicRouting::default();
        }

        // In production, would use GeoIP database to determine location
        // For now, return default routing
        debug!("Geographic routing: client_ip={:?}", client_ip);

        GeographicRouting {
            enabled: true,
            client_ip: client_ip.map(|s| s.to_string()),
            region: None,
            country: None,
            preferred_cdn: self.provider.name().to_string(),
        }
    }

    /// Get manifest with proper CDN routing
    pub async fn get_manifest_with_routing(
        &self,
        cache_key: &str,
        video_id: &str,
        quality: Option<&str>,
        format: &str,
        client_ip: Option<&str>,
        manifest_generator: impl std::future::Future<Output = String>,
    ) -> CDNManifestResponse {
        // Get geographic routing info
        let geo_routing = self.get_geo_routing(client_ip);

        // Try to get from cache first
        let manifest = self
            .get_cached_manifest(cache_key, manifest_generator)
            .await;

        // Get CDN URL and fallback
        let cdn_url = self.get_manifest_url(video_id, quality, format);
        let fallback_url = if self.config.fallback_to_s3 {
            Some(self.get_origin_url(video_id, quality, format))
        } else {
            None
        };

        CDNManifestResponse {
            manifest,
            cdn_url,
            fallback_url,
            headers: self.get_cache_headers(),
            geo_routing,
            provider: self.provider.name().to_string(),
        }
    }
}

/// Cache statistics
#[derive(Debug, Clone)]
pub struct CacheStats {
    pub total_entries: usize,
    pub expired_entries: usize,
    pub active_entries: usize,
}

/// Geographic routing information
#[derive(Debug, Clone, Default)]
pub struct GeographicRouting {
    pub enabled: bool,
    pub client_ip: Option<String>,
    pub region: Option<String>,
    pub country: Option<String>,
    pub preferred_cdn: String,
}

/// CDN manifest response with metadata
#[derive(Debug, Clone)]
pub struct CDNManifestResponse {
    pub manifest: String,
    pub cdn_url: String,
    pub fallback_url: Option<String>,
    pub headers: HashMap<String, String>,
    pub geo_routing: GeographicRouting,
    pub provider: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_config() -> CdnConfig {
        CdnConfig {
            provider: "cloudflare".to_string(),
            endpoint_url: "https://cdn.example.com".to_string(),
            cache_ttl_seconds: 300,
            enable_geo_cache: true,
            fallback_to_s3: true,
        }
    }

    #[test]
    fn test_cdn_provider_parsing() {
        assert_eq!(CdnProvider::from_str("cloudfront"), CdnProvider::CloudFront);
        assert_eq!(CdnProvider::from_str("aws"), CdnProvider::CloudFront);
        assert_eq!(CdnProvider::from_str("cloudflare"), CdnProvider::Cloudflare);
        assert_eq!(CdnProvider::from_str("cf"), CdnProvider::Cloudflare);
        assert_eq!(CdnProvider::from_str("generic"), CdnProvider::Generic);
    }

    #[test]
    fn test_cache_entry_expiration() {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let mut entry = CacheEntry {
            content: "test".to_string(),
            created_at: now - 400, // 400 seconds ago
            ttl_seconds: 300,      // 300 second TTL
        };

        assert!(entry.is_expired()); // 400 > 300, so expired

        entry.ttl_seconds = 500;
        assert!(!entry.is_expired()); // 400 < 500, so not expired
    }

    #[test]
    fn test_cdn_url_generation() {
        let service = CdnService::new(create_test_config());

        // HLS master playlist
        let url = service.get_manifest_url("video-123", None, "hls");
        assert!(url.contains("video-123"));
        assert!(url.contains("index.m3u8"));

        // HLS media playlist for quality
        let url = service.get_manifest_url("video-123", Some("720p"), "hls");
        assert!(url.contains("video-123"));
        assert!(url.contains("720p"));
        assert!(url.contains(".m3u8"));

        // DASH MPD
        let url = service.get_manifest_url("video-123", None, "dash");
        assert!(url.contains("video-123"));
        assert!(url.contains(".mpd"));
    }

    #[test]
    fn test_cache_headers() {
        let service = CdnService::new(create_test_config());
        let headers = service.get_cache_headers();

        assert!(headers.contains_key("Cache-Control"));
        assert!(headers.contains_key("ETag"));
        assert!(headers.contains_key("X-Cache"));
        assert!(headers.contains_key("Access-Control-Allow-Origin"));

        let cache_control = headers.get("Cache-Control").unwrap();
        assert!(cache_control.contains("300")); // TTL value
    }

    #[test]
    fn test_fallback_url_generation() {
        // Test with fallback enabled
        let mut config = create_test_config();
        config.fallback_to_s3 = true;

        let service = CdnService::new(config.clone());
        let fallback = service.get_fallback_url("video-123", Some("720p"));

        assert!(fallback.contains("s3://"));
        assert!(fallback.contains("video-123"));

        // Test with fallback disabled
        let mut config2 = create_test_config();
        config2.fallback_to_s3 = false;
        let service2 = CdnService::new(config2);
        let fallback2 = service2.get_fallback_url("video-123", Some("720p"));
        assert!(fallback2.is_empty());
    }

    #[test]
    fn test_origin_url_generation() {
        let service = CdnService::new(create_test_config());

        let url = service.get_origin_url("video-123", None, "hls");
        assert!(url.contains("s3://"));
        assert!(url.contains("video-123"));
        assert!(url.contains(".m3u8"));

        let url = service.get_origin_url("video-123", Some("720p"), "hls");
        assert!(url.contains("720p"));
    }

    #[test]
    fn test_geo_routing() {
        let service = CdnService::new(create_test_config());

        let routing = service.get_geo_routing(Some("192.168.1.1"));
        assert!(routing.enabled);
        assert_eq!(routing.client_ip, Some("192.168.1.1".to_string()));

        let routing = service.get_geo_routing(None);
        assert!(routing.enabled);
        assert!(routing.client_ip.is_none());
    }

    #[test]
    fn test_geo_routing_disabled() {
        let mut config = create_test_config();
        config.enable_geo_cache = false;

        let service = CdnService::new(config);
        let routing = service.get_geo_routing(Some("192.168.1.1"));
        assert!(!routing.enabled);
    }

    #[tokio::test]
    async fn test_cache_statistics() {
        let service = CdnService::new(create_test_config());

        // Initially empty
        let stats = service.get_cache_stats().await;
        assert_eq!(stats.total_entries, 0);
        assert_eq!(stats.active_entries, 0);
    }

    #[test]
    fn test_provider_names() {
        assert_eq!(CdnProvider::CloudFront.name(), "CloudFront");
        assert_eq!(CdnProvider::Cloudflare.name(), "Cloudflare");
        assert_eq!(CdnProvider::Generic.name(), "Generic");
    }
}

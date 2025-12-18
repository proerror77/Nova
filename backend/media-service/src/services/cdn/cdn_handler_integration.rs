/// CDN Handler Integration Layer
///
/// Combines CDN Service, Origin Shield, and Failover Manager into a unified
/// interface for video streaming manifest delivery.
use crate::error::Result;
use std::sync::Arc;
use tracing::{debug, info};

use super::cdn_failover::FailoverManager;
use super::cdn_service::{CdnConfig, CdnService};
use super::origin_shield::OriginShield;

/// Integrated CDN handler for manifest delivery
pub struct CdnHandler {
    cdn_service: Arc<CdnService>,
    origin_shield: Arc<OriginShield>,
    failover_manager: Arc<FailoverManager>,
}

impl CdnHandler {
    /// Create a new CDN handler
    pub fn new(config: CdnConfig) -> Self {
        info!("Initializing CDN Handler");

        Self {
            cdn_service: Arc::new(CdnService::new(config)),
            origin_shield: Arc::new(OriginShield::new(1000, 60)),
            failover_manager: Arc::new(FailoverManager::new(5, 3)),
        }
    }

    /// Get manifest with full CDN stack
    pub async fn get_manifest(
        &self,
        video_id: &str,
        quality: Option<&str>,
        format: &str,
        client_ip: Option<&str>,
        manifest_generator: impl std::future::Future<Output = String>,
    ) -> Result<CdnHandlerResponse> {
        let cache_key = format!("{}:{}:{}", video_id, quality.unwrap_or("master"), format);

        // Generate manifest first (we'll use it multiple times)
        let generated_manifest = manifest_generator.await;

        // Check if should use fallback
        let should_fallback = self.failover_manager.should_use_fallback().await;

        let manifest = if should_fallback {
            debug!("Using fallback due to CDN issues: video_id={}", video_id);

            // Use manifest directly (no caching on fallback)
            generated_manifest
        } else {
            // Use full CDN stack: Origin Shield → CDN Service → Failover
            // First, get from origin shield with coalescing
            let manifest_clone = generated_manifest.clone();
            let shielded_manifest = self
                .origin_shield
                .get_shielded_response(
                    &cache_key,
                    self.cdn_service.config().cache_ttl_seconds,
                    async { Ok::<String, String>(manifest_clone) },
                )
                .await;

            match shielded_manifest {
                Ok(manifest_content) => {
                    // Then cache it via CDN service
                    let cached_manifest = self
                        .cdn_service
                        .get_cached_manifest(&cache_key, async { manifest_content.clone() })
                        .await;

                    // Record success for failover tracking
                    self.failover_manager.record_success().await;
                    cached_manifest
                }
                Err(e) => {
                    debug!("Origin shield error: {}", e);
                    // Fallback to generated manifest
                    generated_manifest
                }
            }
        };

        // Get CDN routing info
        let response = self
            .cdn_service
            .get_manifest_with_routing(&cache_key, video_id, quality, format, client_ip, async {
                manifest.clone()
            })
            .await;

        // Get cache statistics
        let cache_stats = self.cdn_service.get_cache_stats().await;
        let failover_stats = self.failover_manager.get_stats().await;
        let shield_stats = self.origin_shield.get_stats().await;

        info!(
            "Manifest delivered: video_id={}, format={}, quality={:?}, failover_state={}",
            video_id,
            format,
            quality,
            failover_stats.state.as_str()
        );

        Ok(CdnHandlerResponse {
            manifest: response.manifest,
            cdn_url: response.cdn_url,
            fallback_url: response.fallback_url,
            headers: response.headers,
            geo_routing: response.geo_routing,
            provider: response.provider,
            cache_stats,
            failover_stats,
            shield_stats,
            using_fallback: should_fallback,
        })
    }

    /// Record a CDN error for failover tracking
    pub async fn record_error(&self, error_type: &str, reason: &str) {
        self.failover_manager
            .record_failure(error_type, reason)
            .await;
    }

    /// Get CDN health status
    pub async fn get_health(&self) -> CdnHealthStatus {
        let failover_state = self.failover_manager.get_state().await;
        let shield_state = self.origin_shield.get_state().await;
        let cdn_health = self.cdn_service.check_cdn_health().await;
        let shield_health = self.origin_shield.check_health().await;

        let failover_stats = self.failover_manager.get_stats().await;

        CdnHealthStatus {
            overall_healthy: cdn_health && shield_health,
            cdn_healthy: cdn_health,
            shield_healthy: shield_health,
            failover_state: failover_state.as_str(),
            shield_state: shield_state.as_str(),
            success_rate: failover_stats.success_rate,
            failure_count: failover_stats.failure_count,
            cache_entries: 0, // Would be populated from cache_stats
        }
    }

    /// Invalidate cache for a video
    pub async fn invalidate_video_cache(&self, video_id: &str) {
        info!("Invalidating cache for video: {}", video_id);
        self.cdn_service
            .invalidate_cache(&format!("{}:", video_id))
            .await;
        self.origin_shield
            .invalidate(&format!("{}:", video_id))
            .await;
    }

    /// Clear all caches
    pub async fn clear_all_caches(&self) {
        info!("Clearing all CDN caches");
        self.cdn_service.clear_cache(None).await;
        self.origin_shield.clear_cache().await;
    }

    /// Reset failover manager (admin operation)
    pub async fn reset_failover(&self) {
        info!("Resetting failover manager");
        self.failover_manager.reset().await;
    }

    /// Get backoff delay for retry
    pub fn get_backoff_delay(&self) -> u32 {
        self.failover_manager.get_backoff_delay()
    }

    /// Get detailed statistics
    pub async fn get_statistics(&self) -> CdnStatistics {
        let cache_stats = self.cdn_service.get_cache_stats().await;
        let failover_stats = self.failover_manager.get_stats().await;
        let shield_stats = self.origin_shield.get_stats().await;

        CdnStatistics {
            cache_total: cache_stats.total_entries,
            cache_active: cache_stats.active_entries,
            cache_expired: cache_stats.expired_entries,
            shield_total: shield_stats.total_cached,
            shield_valid: shield_stats.valid_entries,
            shield_expired: shield_stats.expired_entries,
            failover_success_count: failover_stats.success_count,
            failover_failure_count: failover_stats.failure_count,
            failover_success_rate: failover_stats.success_rate,
            failover_state: failover_stats.state.as_str(),
        }
    }
}

/// CDN handler response
#[derive(Debug, Clone)]
pub struct CdnHandlerResponse {
    pub manifest: String,
    pub cdn_url: String,
    pub fallback_url: Option<String>,
    pub headers: std::collections::HashMap<String, String>,
    pub geo_routing: super::cdn_service::GeographicRouting,
    pub provider: String,
    pub cache_stats: super::cdn_service::CacheStats,
    pub failover_stats: super::cdn_failover::FailoverStats,
    pub shield_stats: super::origin_shield::ShieldStats,
    pub using_fallback: bool,
}

/// CDN health status
#[derive(Debug, Clone)]
pub struct CdnHealthStatus {
    pub overall_healthy: bool,
    pub cdn_healthy: bool,
    pub shield_healthy: bool,
    pub failover_state: &'static str,
    pub shield_state: &'static str,
    pub success_rate: f64,
    pub failure_count: u32,
    pub cache_entries: usize,
}

/// CDN statistics
#[derive(Debug, Clone)]
pub struct CdnStatistics {
    pub cache_total: usize,
    pub cache_active: usize,
    pub cache_expired: usize,
    pub shield_total: usize,
    pub shield_valid: usize,
    pub shield_expired: usize,
    pub failover_success_count: u32,
    pub failover_failure_count: u32,
    pub failover_success_rate: f64,
    pub failover_state: &'static str,
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
            fallback_to_gcs: true,
        }
    }

    #[tokio::test]
    async fn test_cdn_handler_creation() {
        let config = create_test_config();
        let _handler = CdnHandler::new(config);
        // Handler created successfully
    }

    #[tokio::test]
    async fn test_cdn_handler_health() {
        let config = create_test_config();
        let handler = CdnHandler::new(config);
        let health = handler.get_health().await;

        assert!(health.overall_healthy); // Initially healthy
        assert!(health.cdn_healthy);
        assert!(health.shield_healthy);
    }

    #[tokio::test]
    async fn test_cdn_handler_statistics() {
        let config = create_test_config();
        let handler = CdnHandler::new(config);
        let stats = handler.get_statistics().await;

        assert_eq!(stats.cache_total, 0); // Initially empty
        assert_eq!(stats.shield_total, 0);
    }

    #[tokio::test]
    async fn test_cdn_handler_error_recording() {
        let config = create_test_config();
        let handler = CdnHandler::new(config);

        handler.record_error("timeout", "CDN request timeout").await;

        let stats = handler.get_statistics().await;
        assert!(stats.failover_failure_count > 0);
    }

    #[tokio::test]
    async fn test_cdn_handler_cache_invalidation() {
        let config = create_test_config();
        let handler = CdnHandler::new(config);

        // This should not error even for non-existent video
        handler.invalidate_video_cache("video-123").await;
    }

    #[tokio::test]
    async fn test_cdn_handler_cache_clearing() {
        let config = create_test_config();
        let handler = CdnHandler::new(config);

        handler.clear_all_caches().await;
        // Should complete without error
    }

    #[tokio::test]
    async fn test_cdn_handler_failover_reset() {
        let config = create_test_config();
        let handler = CdnHandler::new(config);

        handler.reset_failover().await;
        let health = handler.get_health().await;

        assert!(health.overall_healthy); // Should be healthy after reset
    }

    #[test]
    fn test_cdn_handler_backoff_calculation() {
        let config = create_test_config();
        let handler = CdnHandler::new(config);

        let backoff = handler.get_backoff_delay();
        assert!(backoff >= 100 && backoff <= 10000); // Valid backoff range
    }
}

/// CDN module for content delivery network management
///
/// This module provides comprehensive CDN functionality including:
/// - Cache invalidation (Redis-backed)
/// - CDN service integration (CloudFront, Cloudflare, Generic)
/// - Asset management (S3-backed storage)
/// - URL signing (HMAC-SHA256)
/// - Origin shield (request coalescing, cache warming)
/// - CDN failover (circuit breaker, exponential backoff)
/// - Handler integration (unified interface)

pub mod asset_manager;
pub mod cache_invalidator;
pub mod cdn_failover;
pub mod cdn_handler_integration;
pub mod cdn_service;
pub mod origin_shield;
pub mod url_signer;

// Re-export commonly used types
pub use asset_manager::{AssetInfo, AssetManager, CdnQuota};
pub use cache_invalidator::{CacheInvalidation, CacheInvalidator, CacheStats};
pub use cdn_failover::{ErrorHandler, ErrorSeverity, FailoverManager, FailoverState, FailoverStats};
pub use cdn_handler_integration::{CdnHandler, CdnHandlerResponse, CdnHealthStatus, CdnStatistics};
pub use cdn_service::{
    CDNManifestResponse, CacheEntry, CdnConfig, CdnProvider, CdnService, GeographicRouting,
};
pub use origin_shield::{OriginShield, ShieldState, ShieldStats, ShieldedRequest};
pub use url_signer::UrlSigner;

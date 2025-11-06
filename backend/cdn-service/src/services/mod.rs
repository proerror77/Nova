pub mod asset_manager;
pub mod cache_invalidator;
pub mod url_signer;

// Legacy modules (keep for backward compatibility)
pub mod cdn_failover;
pub mod cdn_handler_integration;
pub mod cdn_service;
pub mod origin_shield;

pub use asset_manager::AssetManager;
pub use cache_invalidator::CacheInvalidator;
pub use url_signer::UrlSigner;

pub use cdn_failover::*;
pub use cdn_handler_integration::*;
pub use cdn_service::*;
pub use origin_shield::*;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Asset metadata stored in database
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Asset {
    pub asset_id: Uuid,
    pub user_id: Uuid,
    pub original_filename: String,
    pub file_size: i64,
    pub content_type: String,
    pub storage_key: String,
    pub cdn_url: Option<String>,
    pub upload_timestamp: DateTime<Utc>,
    pub access_count: i64,
    pub last_accessed: Option<DateTime<Utc>>,
    pub is_deleted: bool,
    pub deleted_at: Option<DateTime<Utc>>,
}

/// Cache invalidation record
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct CacheInvalidation {
    pub invalidation_id: Uuid,
    pub asset_id: Option<Uuid>,
    pub invalidation_reason: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub resolved_at: Option<DateTime<Utc>>,
}

/// CDN quota information
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct CdnQuota {
    pub user_id: Uuid,
    pub total_quota_bytes: i64,
    pub used_bytes: i64,
    pub last_updated: DateTime<Utc>,
}

/// Asset info for API responses
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssetInfo {
    pub asset_id: Uuid,
    pub user_id: Uuid,
    pub original_filename: String,
    pub file_size: i64,
    pub content_type: String,
    pub cdn_url: String,
    pub upload_timestamp: i64, // Unix timestamp
    pub access_count: i64,
}

impl From<Asset> for AssetInfo {
    fn from(asset: Asset) -> Self {
        AssetInfo {
            asset_id: asset.asset_id,
            user_id: asset.user_id,
            original_filename: asset.original_filename,
            file_size: asset.file_size,
            content_type: asset.content_type,
            cdn_url: asset.cdn_url.unwrap_or_default(),
            upload_timestamp: asset.upload_timestamp.timestamp(),
            access_count: asset.access_count,
        }
    }
}

/// Cache statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheStats {
    pub total_invalidations: i64,
    pub pending_invalidations: i64,
    pub completed_invalidations: i64,
    pub failed_invalidations: i64,
}

// Asset Manager Service - S3-backed asset storage
// Linus philosophy: Data structure first, simple operations, no special cases

use crate::error::{AppError, Result};
use aws_sdk_s3::Client as S3Client;
use chrono::Utc;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

use super::url_signer::UrlSigner;

const DEFAULT_QUOTA_BYTES: i64 = 10_737_418_240; // 10GB

/// Asset information
#[derive(Debug, Clone)]
pub struct AssetInfo {
    pub asset_id: Uuid,
    pub user_id: Uuid,
    pub original_filename: String,
    pub file_size: i64,
    pub content_type: String,
    pub cdn_url: String,
    pub upload_timestamp: i64,
    pub access_count: i64,
}

/// Asset database model
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Asset {
    pub asset_id: Uuid,
    pub user_id: Uuid,
    pub original_filename: String,
    pub file_size: i64,
    pub content_type: String,
    pub storage_key: String,
    pub cdn_url: String,
    pub upload_timestamp: chrono::DateTime<Utc>,
    pub access_count: i64,
    pub is_deleted: bool,
}

/// CDN quota information
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct CdnQuota {
    pub user_id: Uuid,
    pub total_quota_bytes: i64,
    pub used_bytes: i64,
    pub last_updated: chrono::DateTime<Utc>,
}

/// Asset manager with S3 storage and PostgreSQL metadata
pub struct AssetManager {
    db: Arc<PgPool>,
    s3_client: Arc<S3Client>,
    s3_bucket: String,
    url_signer: Arc<UrlSigner>,
}

impl AssetManager {
    /// Create new asset manager
    pub fn new(
        db: Arc<PgPool>,
        s3_client: Arc<S3Client>,
        s3_bucket: String,
        url_signer: Arc<UrlSigner>,
    ) -> Self {
        Self {
            db,
            s3_client,
            s3_bucket,
            url_signer,
        }
    }

    /// Upload asset to S3 and record metadata
    pub async fn upload_asset(
        &self,
        user_id: Uuid,
        content: Vec<u8>,
        content_type: &str,
        original_filename: &str,
    ) -> Result<AssetInfo> {
        // Check quota first
        self.check_quota(user_id, content.len() as i64).await?;

        let asset_id = Uuid::new_v4();
        let file_size = content.len() as i64;

        // Storage key format: {user_id}/{asset_id}/{filename}
        let storage_key = format!("{}/{}/{}", user_id, asset_id, original_filename);

        // Upload to S3
        self.s3_client
            .put_object()
            .bucket(&self.s3_bucket)
            .key(&storage_key)
            .body(content.into())
            .content_type(content_type)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("S3 upload failed: {}", e)))?;

        // Generate signed CDN URL (24h TTL for metadata storage)
        let cdn_url = self.url_signer.sign_url(&storage_key, 86400)?;

        // Insert into database
        let asset = sqlx::query_as::<_, Asset>(
            r#"
            INSERT INTO assets (
                asset_id, user_id, original_filename, file_size,
                content_type, storage_key, cdn_url, upload_timestamp
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            RETURNING *
            "#,
        )
        .bind(asset_id)
        .bind(user_id)
        .bind(original_filename)
        .bind(file_size)
        .bind(content_type)
        .bind(&storage_key)
        .bind(&cdn_url)
        .bind(Utc::now())
        .fetch_one(self.db.as_ref())
        .await?;

        Ok(asset.into())
    }

    /// Delete asset (soft delete)
    pub async fn delete_asset(&self, asset_id: Uuid, user_id: Uuid) -> Result<()> {
        // Verify ownership
        let asset = self.get_asset_by_id(asset_id).await?;
        if asset.user_id != user_id {
            return Err(AppError::ValidationError("Permission denied".into()));
        }

        // Soft delete in database
        let updated = sqlx::query(
            r#"
            UPDATE assets
            SET is_deleted = TRUE, deleted_at = $1
            WHERE asset_id = $2 AND is_deleted = FALSE
            "#,
        )
        .bind(Utc::now())
        .bind(asset_id)
        .execute(self.db.as_ref())
        .await?;

        if updated.rows_affected() == 0 {
            return Err(AppError::NotFound("Asset not found".into()));
        }

        // Note: S3 deletion happens async (cleanup job)
        Ok(())
    }

    /// Get asset info by ID
    pub async fn get_asset_info(&self, asset_id: Uuid) -> Result<AssetInfo> {
        let asset = self.get_asset_by_id(asset_id).await?;

        if asset.is_deleted {
            return Err(AppError::NotFound("Asset deleted".into()));
        }

        // Generate fresh signed URL
        let cdn_url = self.url_signer.sign_url(&asset.storage_key, 86400)?;

        Ok(AssetInfo {
            asset_id: asset.asset_id,
            user_id: asset.user_id,
            original_filename: asset.original_filename,
            file_size: asset.file_size,
            content_type: asset.content_type,
            cdn_url,
            upload_timestamp: asset.upload_timestamp.timestamp(),
            access_count: asset.access_count,
        })
    }

    /// List user's assets with pagination
    pub async fn list_user_assets(
        &self,
        user_id: Uuid,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<AssetInfo>> {
        let assets = sqlx::query_as::<_, Asset>(
            r#"
            SELECT * FROM assets
            WHERE user_id = $1 AND is_deleted = FALSE
            ORDER BY upload_timestamp DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit as i64)
        .bind(offset as i64)
        .fetch_all(self.db.as_ref())
        .await?;

        // Generate fresh signed URLs for all assets
        let mut infos = Vec::new();
        for asset in assets {
            let cdn_url = self.url_signer.sign_url(&asset.storage_key, 86400)?;
            infos.push(AssetInfo {
                asset_id: asset.asset_id,
                user_id: asset.user_id,
                original_filename: asset.original_filename,
                file_size: asset.file_size,
                content_type: asset.content_type,
                cdn_url,
                upload_timestamp: asset.upload_timestamp.timestamp(),
                access_count: asset.access_count,
            });
        }

        Ok(infos)
    }

    /// Get quota info for user
    pub async fn get_quota(&self, user_id: Uuid) -> Result<CdnQuota> {
        let quota = sqlx::query_as::<_, CdnQuota>(
            r#"
            SELECT * FROM cdn_quota WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_optional(self.db.as_ref())
        .await?;

        Ok(quota.unwrap_or_else(|| CdnQuota {
            user_id,
            total_quota_bytes: DEFAULT_QUOTA_BYTES,
            used_bytes: 0,
            last_updated: Utc::now(),
        }))
    }

    // === Private helpers ===

    /// Check quota before upload
    async fn check_quota(&self, user_id: Uuid, file_size: i64) -> Result<()> {
        let quota = self.get_quota(user_id).await?;

        if quota.used_bytes + file_size > quota.total_quota_bytes {
            return Err(AppError::ValidationError(format!(
                "Quota exceeded: {}/{} bytes used",
                quota.used_bytes, quota.total_quota_bytes
            )));
        }

        Ok(())
    }

    /// Get asset by ID (internal)
    async fn get_asset_by_id(&self, asset_id: Uuid) -> Result<Asset> {
        sqlx::query_as::<_, Asset>(
            r#"
            SELECT * FROM assets WHERE asset_id = $1
            "#,
        )
        .bind(asset_id)
        .fetch_optional(self.db.as_ref())
        .await?
        .ok_or_else(|| AppError::NotFound("Asset not found".into()))
    }
}

impl From<Asset> for AssetInfo {
    fn from(asset: Asset) -> Self {
        AssetInfo {
            asset_id: asset.asset_id,
            user_id: asset.user_id,
            original_filename: asset.original_filename,
            file_size: asset.file_size,
            content_type: asset.content_type,
            cdn_url: asset.cdn_url,
            upload_timestamp: asset.upload_timestamp.timestamp(),
            access_count: asset.access_count,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: Integration tests require database setup
    // Unit tests focus on logic without DB

    #[test]
    fn test_storage_key_format() {
        let user_id = Uuid::new_v4();
        let asset_id = Uuid::new_v4();
        let filename = "test.jpg";

        let storage_key = format!("{}/{}/{}", user_id, asset_id, filename);

        assert!(storage_key.contains(&user_id.to_string()));
        assert!(storage_key.contains(&asset_id.to_string()));
        assert!(storage_key.ends_with("test.jpg"));
    }

    #[test]
    fn test_default_quota() {
        assert_eq!(DEFAULT_QUOTA_BYTES, 10_737_418_240);
    }
}

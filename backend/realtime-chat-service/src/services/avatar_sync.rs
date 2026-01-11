/// Avatar synchronization service for Matrix
///
/// This service handles syncing Nova avatar URLs to Matrix mxc:// URLs.
/// It downloads avatars from Nova CDN, uploads them to Matrix media repository,
/// and caches the mapping to avoid re-uploading the same avatar.
use crate::error::AppError;
use crate::services::matrix_admin::MatrixAdminClient;
use deadpool_postgres::Pool;
use tracing::{error, info, warn};
use uuid::Uuid;

/// Service for syncing avatars from Nova to Matrix
#[derive(Clone)]
pub struct AvatarSyncService {
    /// Matrix admin client for uploading media
    matrix_admin: MatrixAdminClient,
    /// Database pool for caching
    db_pool: Pool,
}

impl AvatarSyncService {
    /// Create a new avatar sync service
    pub fn new(matrix_admin: MatrixAdminClient, db_pool: Pool) -> Self {
        Self {
            matrix_admin,
            db_pool,
        }
    }

    /// Sync avatar from Nova to Matrix
    ///
    /// # Arguments
    /// * `user_id` - Nova user UUID
    /// * `avatar_url` - Avatar URL from Nova (can be empty, relative, or full URL)
    ///
    /// # Returns
    /// Matrix mxc:// URL if avatar was synced, None if avatar_url is empty
    pub async fn sync_avatar_to_matrix(
        &self,
        user_id: Uuid,
        avatar_url: Option<String>,
    ) -> Result<Option<String>, AppError> {
        // Handle empty/None avatar_url
        let avatar_url = match avatar_url {
            Some(url) if !url.is_empty() => url,
            _ => {
                info!("No avatar URL provided for user {}, skipping sync", user_id);
                return Ok(None);
            }
        };

        // Check if it's already an mxc:// URL (shouldn't happen, but handle it)
        if avatar_url.starts_with("mxc://") {
            info!("Avatar URL is already mxc:// format for user {}", user_id);
            return Ok(Some(avatar_url));
        }

        // Only sync HTTP(S) URLs
        if !avatar_url.starts_with("http://") && !avatar_url.starts_with("https://") {
            warn!(
                "Avatar URL is not HTTP(S) for user {}: {}. Skipping sync.",
                user_id, avatar_url
            );
            return Ok(None);
        }

        // Sync HTTP avatar with caching
        self.sync_http_avatar(user_id, &avatar_url).await
    }

    /// Sync HTTP(S) avatar URL to Matrix with caching
    async fn sync_http_avatar(&self, user_id: Uuid, avatar_url: &str) -> Result<Option<String>, AppError> {
        // Calculate hash for cache lookup
        let avatar_hash = MatrixAdminClient::calculate_hash(avatar_url);

        // Check cache first
        if let Some(cached_mxc) = self.get_cached_mxc(user_id, &avatar_hash).await? {
            info!(
                "Using cached mxc:// URL for user {}: {}",
                user_id, cached_mxc
            );
            return Ok(Some(cached_mxc));
        }

        // Cache miss - download and upload to Matrix
        info!(
            "Cache miss for user {} avatar. Downloading and uploading to Matrix: {}",
            user_id, avatar_url
        );

        match self.matrix_admin.download_and_upload_avatar(avatar_url).await {
            Ok(mxc_url) => {
                // Save to cache
                if let Err(e) = self.save_to_cache(user_id, &avatar_hash, &mxc_url).await {
                    // Log error but don't fail the operation
                    error!("Failed to save avatar to cache: {}", e);
                }

                info!(
                    "Successfully synced avatar for user {}: {} -> {}",
                    user_id, avatar_url, mxc_url
                );
                Ok(Some(mxc_url))
            }
            Err(e) => {
                error!(
                    "Failed to download and upload avatar for user {}: {}",
                    user_id, e
                );
                Err(e)
            }
        }
    }

    /// Get cached mxc:// URL for a given user and avatar hash
    async fn get_cached_mxc(&self, user_id: Uuid, avatar_hash: &str) -> Result<Option<String>, AppError> {
        let client = self.db_pool.get().await.map_err(|e| {
            error!("Failed to get database connection: {}", e);
            AppError::Database(format!("Connection pool error: {}", e))
        })?;

        let row = client
            .query_opt(
                "SELECT mxc_url FROM matrix_avatar_cache WHERE user_id = $1 AND avatar_url_hash = $2",
                &[&user_id, &avatar_hash.to_string()],
            )
            .await
            .map_err(|e| {
                error!("Failed to query avatar cache: {}", e);
                AppError::Database(format!("Cache query failed: {}", e))
            })?;

        Ok(row.map(|r| r.get("mxc_url")))
    }

    /// Save mxc:// URL to cache
    async fn save_to_cache(&self, user_id: Uuid, avatar_hash: &str, mxc_url: &str) -> Result<(), AppError> {
        let client = self.db_pool.get().await.map_err(|e| {
            error!("Failed to get database connection: {}", e);
            AppError::Database(format!("Connection pool error: {}", e))
        })?;

        client
            .execute(
                "INSERT INTO matrix_avatar_cache (user_id, avatar_url_hash, mxc_url)
                 VALUES ($1, $2, $3)
                 ON CONFLICT (user_id, avatar_url_hash)
                 DO UPDATE SET mxc_url = EXCLUDED.mxc_url, updated_at = CURRENT_TIMESTAMP",
                &[&user_id, &avatar_hash.to_string(), &mxc_url.to_string()],
            )
            .await
            .map_err(|e| {
                error!("Failed to save to avatar cache: {}", e);
                AppError::Database(format!("Cache save failed: {}", e))
            })?;

        Ok(())
    }
}

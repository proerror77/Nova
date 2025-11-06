// Cache Invalidation Service - Redis-backed cache management
// Linus philosophy: Async invalidation, don't block main flow

use crate::error::{AppError, Result};
use crate::models::{CacheInvalidation, CacheStats};
use chrono::Utc;
use redis::AsyncCommands;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

const CACHE_TTL_SECONDS: i64 = 86400; // 24 hours

/// Cache invalidator with Redis and Kafka
pub struct CacheInvalidator {
    db: Arc<PgPool>,
    redis: Arc<redis::Client>,
}

impl CacheInvalidator {
    /// Create new cache invalidator
    pub fn new(db: Arc<PgPool>, redis: Arc<redis::Client>) -> Self {
        Self { db, redis }
    }

    /// Invalidate cache for specific asset
    pub async fn invalidate_asset(&self, asset_id: Uuid, reason: &str) -> Result<Uuid> {
        let invalidation_id = Uuid::new_v4();

        // Record invalidation in database
        sqlx::query(
            r#"
            INSERT INTO cache_invalidations (
                invalidation_id, asset_id, invalidation_reason, status, created_at
            )
            VALUES ($1, $2, $3, 'pending', $4)
            "#,
        )
        .bind(invalidation_id)
        .bind(asset_id)
        .bind(reason)
        .bind(Utc::now())
        .execute(self.db.as_ref())
        .await?;

        // Delete from Redis cache
        let cache_key = format!("cdn:asset:{}", asset_id);
        self.delete_cache_key(&cache_key).await?;

        // Mark as completed
        sqlx::query(
            r#"
            UPDATE cache_invalidations
            SET status = 'completed', resolved_at = $1
            WHERE invalidation_id = $2
            "#,
        )
        .bind(Utc::now())
        .bind(invalidation_id)
        .execute(self.db.as_ref())
        .await?;

        Ok(invalidation_id)
    }

    /// Invalidate all assets for a user
    pub async fn invalidate_user_assets(&self, user_id: Uuid, reason: &str) -> Result<Vec<Uuid>> {
        // Get all asset IDs for user
        let asset_ids: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT asset_id FROM assets
            WHERE user_id = $1 AND is_deleted = FALSE
            "#,
        )
        .bind(user_id)
        .fetch_all(self.db.as_ref())
        .await?;

        let mut invalidation_ids = Vec::new();

        for asset_id in asset_ids {
            let inv_id = self.invalidate_asset(asset_id, reason).await?;
            invalidation_ids.push(inv_id);
        }

        Ok(invalidation_ids)
    }

    /// Get cache statistics
    pub async fn get_cache_stats(&self) -> Result<CacheStats> {
        let stats = sqlx::query_as::<_, (i64, i64, i64, i64)>(
            r#"
            SELECT
                COUNT(*) as total,
                COUNT(*) FILTER (WHERE status = 'pending') as pending,
                COUNT(*) FILTER (WHERE status = 'completed') as completed,
                COUNT(*) FILTER (WHERE status = 'failed') as failed
            FROM cache_invalidations
            WHERE created_at > NOW() - INTERVAL '24 hours'
            "#,
        )
        .fetch_one(self.db.as_ref())
        .await?;

        Ok(CacheStats {
            total_invalidations: stats.0,
            pending_invalidations: stats.1,
            completed_invalidations: stats.2,
            failed_invalidations: stats.3,
        })
    }

    /// Get invalidation status
    pub async fn get_invalidation_status(&self, invalidation_id: Uuid) -> Result<CacheInvalidation> {
        sqlx::query_as::<_, CacheInvalidation>(
            r#"
            SELECT * FROM cache_invalidations WHERE invalidation_id = $1
            "#,
        )
        .bind(invalidation_id)
        .fetch_optional(self.db.as_ref())
        .await?
        .ok_or_else(|| AppError::NotFound("Invalidation not found".into()))
    }

    /// Cache asset metadata in Redis
    pub async fn cache_asset_metadata(
        &self,
        asset_id: Uuid,
        metadata: &str, // JSON string
    ) -> Result<()> {
        let cache_key = format!("cdn:asset:{}", asset_id);

        let mut conn = self.redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| AppError::InternalError(format!("Redis connection failed: {}", e)))?;

        let _: () = conn
            .set_ex(&cache_key, metadata, CACHE_TTL_SECONDS as u64)
            .await
            .map_err(|e| AppError::InternalError(format!("Redis set failed: {}", e)))?;

        Ok(())
    }

    /// Get cached asset metadata
    pub async fn get_cached_metadata(&self, asset_id: Uuid) -> Result<Option<String>> {
        let cache_key = format!("cdn:asset:{}", asset_id);

        let mut conn = self.redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| AppError::InternalError(format!("Redis connection failed: {}", e)))?;

        let result: Option<String> = conn
            .get(&cache_key)
            .await
            .map_err(|e| AppError::InternalError(format!("Redis get failed: {}", e)))?;

        Ok(result)
    }

    // === Private helpers ===

    /// Delete cache key from Redis
    async fn delete_cache_key(&self, cache_key: &str) -> Result<()> {
        let mut conn = self.redis
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| AppError::InternalError(format!("Redis connection failed: {}", e)))?;

        let _: () = conn
            .del(cache_key)
            .await
            .map_err(|e| AppError::InternalError(format!("Redis delete failed: {}", e)))?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_key_format() {
        let asset_id = Uuid::new_v4();
        let key = format!("cdn:asset:{}", asset_id);

        assert!(key.starts_with("cdn:asset:"));
        assert!(key.contains(&asset_id.to_string()));
    }

    #[test]
    fn test_cache_ttl() {
        assert_eq!(CACHE_TTL_SECONDS, 86400);
    }
}

/// Post service - handles post creation, retrieval, and management
use crate::cache::ContentCache;
use crate::error::Result;
use crate::kafka::events::{
    publish_post_created, publish_post_deleted, publish_post_status_updated,
};
use crate::models::Post;
use sqlx::PgPool;
use std::sync::Arc;
use transactional_outbox::SqlxOutboxRepository;
use uuid::Uuid;

pub struct PostService {
    pool: PgPool,
    cache: Option<Arc<ContentCache>>,
    outbox_repo: Option<Arc<SqlxOutboxRepository>>,
}

impl PostService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            cache: None,
            outbox_repo: None,
        }
    }

    pub fn with_cache(pool: PgPool, cache: Arc<ContentCache>) -> Self {
        Self {
            pool,
            cache: Some(cache),
            outbox_repo: None,
        }
    }

    pub fn with_outbox(
        pool: PgPool,
        cache: Arc<ContentCache>,
        outbox_repo: Arc<SqlxOutboxRepository>,
    ) -> Self {
        Self {
            pool,
            cache: Some(cache),
            outbox_repo: Some(outbox_repo),
        }
    }

    fn cache(&self) -> Option<&Arc<ContentCache>> {
        self.cache.as_ref()
    }

    /// Get a post by ID
    pub async fn get_post(&self, post_id: Uuid) -> Result<Option<Post>> {
        if let Some(cache) = self.cache() {
            if let Some(cached) = cache.get_post(post_id).await? {
                return Ok(Some(cached));
            }
        }

        let post = sqlx::query_as::<_, Post>(
            r#"
            SELECT id, user_id, content, caption, media_key, media_type, media_urls, status,
                   created_at, updated_at, deleted_at, soft_delete
            FROM posts
            WHERE id = $1 AND soft_delete IS NULL
            "#,
        )
        .bind(post_id)
        .fetch_optional(&self.pool)
        .await?;

        if let (Some(cache), Some(post)) = (self.cache(), &post) {
            if let Err(err) = cache.cache_post(post).await {
                tracing::debug!(%post_id, "post cache set failed: {}", err);
            }
        }

        Ok(post)
    }

    /// Get posts for a user
    pub async fn get_user_posts(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Post>> {
        let posts = sqlx::query_as::<_, Post>(
            r#"
            SELECT id, user_id, content, caption, media_key, media_type, media_urls, status,
                   created_at, updated_at, deleted_at, soft_delete
            FROM posts
            WHERE user_id = $1 AND soft_delete IS NULL
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(posts)
    }

    /// Create a new post
    pub async fn create_post(
        &self,
        user_id: Uuid,
        caption: Option<&str>,
        media_key: &str,
        media_type: &str,
    ) -> Result<Post> {
        // Start transaction for atomic post creation + event publishing
        let mut tx = self.pool.begin().await?;

        let post = sqlx::query_as::<_, Post>(
            r#"
            INSERT INTO posts (user_id, caption, media_key, media_type, media_urls, status)
            VALUES (
                $1,
                $2,
                $3,
                $4,
                CASE WHEN $3 = 'text-only' THEN '[]'::jsonb ELSE jsonb_build_array($3) END,
                'published'
            )
            RETURNING id, user_id, content, caption, media_key, media_type, media_urls, status,
                      created_at, updated_at, deleted_at, soft_delete
            "#,
        )
        .bind(user_id)
        .bind(caption)
        .bind(media_key)
        .bind(media_type)
        .fetch_one(&mut *tx)
        .await?;

        // Publish event to outbox (same transaction)
        if let Some(outbox) = &self.outbox_repo {
            publish_post_created(&mut tx, outbox.as_ref(), &post).await?;
        }

        // Commit transaction (both post and event committed atomically)
        tx.commit().await?;

        // Cache post after successful commit (fire-and-forget, not transactional)
        if let Some(cache) = self.cache() {
            if let Err(err) = cache.cache_post(&post).await {
                tracing::debug!(post_id = %post.id, "post cache set failed: {}", err);
            }
        }

        Ok(post)
    }

    /// Update post status
    pub async fn update_post_status(
        &self,
        post_id: Uuid,
        user_id: Uuid,
        status: &str,
    ) -> Result<bool> {
        // Start transaction for atomic status update + event publishing
        let mut tx = self.pool.begin().await?;

        let result = sqlx::query(
            r#"
            UPDATE posts
            SET status = $1, updated_at = NOW()
            WHERE id = $2 AND user_id = $3 AND soft_delete IS NULL
            "#,
        )
        .bind(status)
        .bind(post_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

        let updated = result.rows_affected() > 0;

        if updated {
            // Publish event to outbox (same transaction)
            if let Some(outbox) = &self.outbox_repo {
                publish_post_status_updated(&mut tx, outbox.as_ref(), post_id, user_id, status)
                    .await?;
            }
        }

        // Commit transaction (both update and event committed atomically)
        tx.commit().await?;

        // Invalidate cache after successful commit (fire-and-forget, not transactional)
        if updated {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.invalidate_post(post_id).await {
                    tracing::debug!(%post_id, "post cache invalidation failed: {}", err);
                }
            }
        }

        Ok(updated)
    }

    /// Soft delete a post
    pub async fn delete_post(&self, post_id: Uuid, user_id: Uuid) -> Result<bool> {
        // Start transaction for atomic soft delete + event publishing
        let mut tx = self.pool.begin().await?;

        let result = sqlx::query(
            r#"
            UPDATE posts
            SET soft_delete = NOW()
            WHERE id = $1 AND user_id = $2 AND soft_delete IS NULL
            "#,
        )
        .bind(post_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

        let deleted = result.rows_affected() > 0;

        if deleted {
            // Publish event to outbox (same transaction)
            if let Some(outbox) = &self.outbox_repo {
                publish_post_deleted(&mut tx, outbox.as_ref(), post_id, user_id).await?;
            }
        }

        // Commit transaction (both delete and event committed atomically)
        tx.commit().await?;

        // Invalidate cache after successful commit (fire-and-forget, not transactional)
        if deleted {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.invalidate_post(post_id).await {
                    tracing::debug!(%post_id, "post cache invalidation failed: {}", err);
                }
            }
        }

        Ok(deleted)
    }
}

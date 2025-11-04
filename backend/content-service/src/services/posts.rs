/// Post service - handles post creation, retrieval, and management
use crate::cache::ContentCache;
use crate::error::Result;
use crate::models::Post;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

pub struct PostService {
    pool: PgPool,
    cache: Option<Arc<ContentCache>>,
}

impl PostService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool, cache: None }
    }

    pub fn with_cache(pool: PgPool, cache: Arc<ContentCache>) -> Self {
        Self {
            pool,
            cache: Some(cache),
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
            SELECT id, user_id, caption, image_key, image_sizes, status, content_type,
                   created_at, updated_at, soft_delete
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
            SELECT id, user_id, caption, image_key, image_sizes, status, content_type,
                   created_at, updated_at, soft_delete
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
        image_key: &str,
        content_type: &str,
    ) -> Result<Post> {
        let post = sqlx::query_as::<_, Post>(
            r#"
            INSERT INTO posts (user_id, caption, image_key, status, content_type)
            VALUES ($1, $2, $3, 'published', $4)
            RETURNING id, user_id, caption, image_key, image_sizes, status, content_type,
                      created_at, updated_at, soft_delete
            "#,
        )
        .bind(user_id)
        .bind(caption)
        .bind(image_key)
        .bind(content_type)
        .fetch_one(&self.pool)
        .await?;

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
        .execute(&self.pool)
        .await?;

        let updated = result.rows_affected() > 0;

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
        let result = sqlx::query(
            r#"
            UPDATE posts
            SET soft_delete = NOW()
            WHERE id = $1 AND user_id = $2 AND soft_delete IS NULL
            "#,
        )
        .bind(post_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        let deleted = result.rows_affected() > 0;

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

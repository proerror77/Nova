use crate::domain::models::Like;
use anyhow::Result;
use sqlx::PgPool;
use uuid::Uuid;

/// Repository for Like operations
#[derive(Clone)]
pub struct LikeRepository {
    pool: PgPool,
}

impl LikeRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create a new like (idempotent - returns success if already exists)
    pub async fn create_like(&self, user_id: Uuid, post_id: Uuid) -> Result<Like> {
        let like = sqlx::query_as::<_, Like>(
            r#"
            INSERT INTO likes (user_id, post_id)
            VALUES ($1, $2)
            ON CONFLICT (user_id, post_id) DO UPDATE
            SET user_id = EXCLUDED.user_id
            RETURNING id, user_id, post_id, created_at
            "#,
        )
        .bind(user_id)
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(like)
    }

    /// Delete a like (idempotent - returns success if doesn't exist)
    pub async fn delete_like(&self, user_id: Uuid, post_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"
            DELETE FROM likes
            WHERE user_id = $1 AND post_id = $2
            "#,
        )
        .bind(user_id)
        .bind(post_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Check if user has liked a post
    pub async fn check_user_liked(&self, user_id: Uuid, post_id: Uuid) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM likes
                WHERE user_id = $1 AND post_id = $2
            )
            "#,
        )
        .bind(user_id)
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(exists)
    }

    /// Get like count for a post (fallback when Redis is unavailable)
    pub async fn get_like_count(&self, post_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM likes
            WHERE post_id = $1
            "#,
        )
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Get paginated likes for a post
    pub async fn get_post_likes(
        &self,
        post_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<Vec<Like>> {
        let likes = sqlx::query_as::<_, Like>(
            r#"
            SELECT id, user_id, post_id, created_at
            FROM likes
            WHERE post_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(post_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(likes)
    }

    /// Batch check like status for multiple posts
    pub async fn batch_check_user_liked(
        &self,
        user_id: Uuid,
        post_ids: &[Uuid],
    ) -> Result<Vec<Uuid>> {
        if post_ids.is_empty() {
            return Ok(Vec::new());
        }

        let liked_posts = sqlx::query_scalar(
            r#"
            SELECT post_id
            FROM likes
            WHERE user_id = $1 AND post_id = ANY($2)
            "#,
        )
        .bind(user_id)
        .bind(post_ids)
        .fetch_all(&self.pool)
        .await?;

        Ok(liked_posts)
    }
}

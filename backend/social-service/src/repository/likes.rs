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
    /// Returns (Like, was_created) where was_created is true if this is a new like
    pub async fn create_like(&self, user_id: Uuid, post_id: Uuid) -> Result<(Like, bool)> {
        // First check if already liked
        let already_liked = self.check_user_liked(user_id, post_id).await?;

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

        // was_created is true only if it didn't exist before
        Ok((like, !already_liked))
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

    /// Get posts liked by a user (paginated)
    pub async fn get_user_liked_posts(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32)> {
        // Get post IDs liked by user
        let post_ids: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT post_id
            FROM likes
            WHERE user_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        // Get total count
        let total: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM likes
            WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        Ok((post_ids, total as i32))
    }

    /// Batch check if user has liked multiple posts
    /// Returns a HashMap of post_id -> is_liked
    pub async fn batch_check_liked(
        &self,
        user_id: Uuid,
        post_ids: &[Uuid],
    ) -> Result<std::collections::HashMap<Uuid, bool>> {
        use std::collections::HashMap;

        if post_ids.is_empty() {
            return Ok(HashMap::new());
        }

        // Get all posts that the user has liked from the given list
        let liked_posts: Vec<Uuid> = sqlx::query_scalar(
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

        // Build the result map
        let liked_set: std::collections::HashSet<Uuid> = liked_posts.into_iter().collect();
        let result: HashMap<Uuid, bool> = post_ids
            .iter()
            .map(|id| (*id, liked_set.contains(id)))
            .collect();

        Ok(result)
    }
}

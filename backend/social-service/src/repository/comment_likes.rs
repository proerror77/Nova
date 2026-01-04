use crate::domain::models::CommentLike;
use anyhow::Result;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// Helper struct for create_like with was_created flag
#[derive(sqlx::FromRow)]
struct CommentLikeWithFlag {
    id: Uuid,
    comment_id: Uuid,
    user_id: Uuid,
    created_at: DateTime<Utc>,
    was_created: i64,
}

/// Repository for CommentLike operations (IG/小红书风格评论点赞)
#[derive(Clone)]
pub struct CommentLikeRepository {
    pool: PgPool,
}

impl CommentLikeRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create a new comment like (idempotent - returns success if already exists)
    /// Returns (CommentLike, was_created) where was_created is true if this is a new like
    pub async fn create_like(&self, user_id: Uuid, comment_id: Uuid) -> Result<(CommentLike, bool)> {
        // Use INSERT ... ON CONFLICT with xmax to detect if row was inserted or updated
        // xmax = 0 means the row was newly inserted, xmax != 0 means it was updated
        let result = sqlx::query_as::<_, CommentLikeWithFlag>(
            r#"
            INSERT INTO comment_likes (user_id, comment_id)
            VALUES ($1, $2)
            ON CONFLICT (comment_id, user_id) DO UPDATE
            SET user_id = EXCLUDED.user_id
            RETURNING id, comment_id, user_id, created_at, (xmax = 0)::int8 as was_created
            "#,
        )
        .bind(user_id)
        .bind(comment_id)
        .fetch_one(&self.pool)
        .await?;

        let comment_like = CommentLike {
            id: result.id,
            comment_id: result.comment_id,
            user_id: result.user_id,
            created_at: result.created_at,
        };

        // was_created is true if xmax = 0 (new insert)
        Ok((comment_like, result.was_created == 1))
    }

    /// Delete a comment like (idempotent - returns success if doesn't exist)
    pub async fn delete_like(&self, user_id: Uuid, comment_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"
            DELETE FROM comment_likes
            WHERE user_id = $1 AND comment_id = $2
            "#,
        )
        .bind(user_id)
        .bind(comment_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Check if user has liked a comment
    pub async fn check_user_liked(&self, user_id: Uuid, comment_id: Uuid) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM comment_likes
                WHERE user_id = $1 AND comment_id = $2
            )
            "#,
        )
        .bind(user_id)
        .bind(comment_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(exists)
    }

    /// Get like count for a comment (reads from comments table's denormalized like_count)
    pub async fn get_like_count(&self, comment_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT like_count FROM comments
            WHERE id = $1
            "#,
        )
        .bind(comment_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Get like count by counting actual likes (fallback)
    pub async fn get_like_count_raw(&self, comment_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM comment_likes
            WHERE comment_id = $1
            "#,
        )
        .bind(comment_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Get paginated likes for a comment
    pub async fn get_comment_likes(
        &self,
        comment_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<Vec<CommentLike>> {
        let likes = sqlx::query_as::<_, CommentLike>(
            r#"
            SELECT id, comment_id, user_id, created_at
            FROM comment_likes
            WHERE comment_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(comment_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(likes)
    }

    /// Batch check if user has liked multiple comments
    /// Returns a HashMap of comment_id -> is_liked
    pub async fn batch_check_liked(
        &self,
        user_id: Uuid,
        comment_ids: &[Uuid],
    ) -> Result<std::collections::HashMap<Uuid, bool>> {
        use std::collections::HashMap;

        if comment_ids.is_empty() {
            return Ok(HashMap::new());
        }

        // Get all comments that the user has liked from the given list
        let liked_comments: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT comment_id
            FROM comment_likes
            WHERE user_id = $1 AND comment_id = ANY($2)
            "#,
        )
        .bind(user_id)
        .bind(comment_ids)
        .fetch_all(&self.pool)
        .await?;

        // Build the result map
        let liked_set: std::collections::HashSet<Uuid> = liked_comments.into_iter().collect();
        let result: HashMap<Uuid, bool> = comment_ids
            .iter()
            .map(|id| (*id, liked_set.contains(id)))
            .collect();

        Ok(result)
    }

    /// Batch get like counts for multiple comments
    /// Reads from comments table's denormalized like_count column
    /// Returns a HashMap of comment_id -> like_count
    pub async fn batch_get_like_counts(
        &self,
        comment_ids: &[Uuid],
    ) -> Result<std::collections::HashMap<Uuid, i64>> {
        use std::collections::HashMap;

        if comment_ids.is_empty() {
            return Ok(HashMap::new());
        }

        // Query all like counts in a single batch query
        let rows: Vec<(Uuid, i64)> = sqlx::query_as(
            r#"
            SELECT id, like_count
            FROM comments
            WHERE id = ANY($1)
            "#,
        )
        .bind(comment_ids)
        .fetch_all(&self.pool)
        .await?;

        // Build the result map
        let result: HashMap<Uuid, i64> = rows.into_iter().collect();

        Ok(result)
    }
}

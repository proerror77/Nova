/// Comment service - handles comment creation, retrieval, and management
use crate::error::Result;
use crate::models::Comment;
use sqlx::{PgPool, Row};
use uuid::Uuid;

pub struct CommentService {
    pool: PgPool,
}

impl CommentService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Get a comment by ID
    pub async fn get_comment(&self, comment_id: Uuid) -> Result<Option<Comment>> {
        let comment = sqlx::query_as::<_, Comment>(
            r#"
            SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
            FROM comments
            WHERE id = $1 AND soft_delete IS NULL
            "#,
        )
        .bind(comment_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(comment)
    }

    /// Get comments for a post
    pub async fn get_post_comments(
        &self,
        post_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Comment>> {
        let comments = sqlx::query_as::<_, Comment>(
            r#"
            SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
            FROM comments
            WHERE post_id = $1 AND soft_delete IS NULL
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(post_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(comments)
    }

    /// Get replies to a comment
    pub async fn get_comment_replies(
        &self,
        parent_comment_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Comment>> {
        let replies = sqlx::query_as::<_, Comment>(
            r#"
            SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
            FROM comments
            WHERE parent_comment_id = $1 AND soft_delete IS NULL
            ORDER BY created_at ASC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(parent_comment_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(replies)
    }

    /// Create a new comment
    pub async fn create_comment(
        &self,
        post_id: Uuid,
        user_id: Uuid,
        content: &str,
        parent_comment_id: Option<Uuid>,
    ) -> Result<Comment> {
        let comment = sqlx::query_as::<_, Comment>(
            r#"
            INSERT INTO comments (post_id, user_id, content, parent_comment_id)
            VALUES ($1, $2, $3, $4)
            RETURNING id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
            "#,
        )
        .bind(post_id)
        .bind(user_id)
        .bind(content)
        .bind(parent_comment_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(comment)
    }

    /// Update comment content
    pub async fn update_comment(
        &self,
        comment_id: Uuid,
        user_id: Uuid,
        content: &str,
    ) -> Result<bool> {
        let result = sqlx::query(
            r#"
            UPDATE comments
            SET content = $1, updated_at = NOW()
            WHERE id = $2 AND user_id = $3 AND soft_delete IS NULL
            "#,
        )
        .bind(content)
        .bind(comment_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Soft delete a comment
    pub async fn delete_comment(&self, comment_id: Uuid, user_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"
            UPDATE comments
            SET soft_delete = NOW()
            WHERE id = $1 AND user_id = $2 AND soft_delete IS NULL
            "#,
        )
        .bind(comment_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Count comments for a post
    pub async fn count_post_comments(&self, post_id: Uuid) -> Result<i32> {
        let row = sqlx::query(
            "SELECT COUNT(*) as count FROM comments WHERE post_id = $1 AND soft_delete IS NULL",
        )
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(row.get::<i32, _>("count"))
    }
}

use crate::domain::models::Comment;
use anyhow::Result;
use sqlx::PgPool;
use uuid::Uuid;

/// Repository for Comment operations
#[derive(Clone)]
pub struct CommentRepository {
    pool: PgPool,
}

impl CommentRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create a new comment
    pub async fn create_comment(
        &self,
        post_id: Uuid,
        user_id: Uuid,
        content: String,
        parent_comment_id: Option<Uuid>,
    ) -> Result<Comment> {
        let comment = sqlx::query_as::<_, Comment>(
            r#"
            INSERT INTO comments (post_id, user_id, content, parent_comment_id)
            VALUES ($1, $2, $3, $4)
            RETURNING id, post_id, user_id, content, parent_comment_id, created_at, updated_at
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

    /// Update a comment
    #[allow(dead_code)]
    pub async fn update_comment(
        &self,
        comment_id: Uuid,
        user_id: Uuid,
        content: String,
    ) -> Result<Option<Comment>> {
        let comment = sqlx::query_as::<_, Comment>(
            r#"
            UPDATE comments
            SET content = $3, updated_at = NOW()
            WHERE id = $1 AND user_id = $2
            RETURNING id, post_id, user_id, content, parent_comment_id, created_at, updated_at
            "#,
        )
        .bind(comment_id)
        .bind(user_id)
        .bind(content)
        .fetch_optional(&self.pool)
        .await?;

        Ok(comment)
    }

    /// Delete a comment (soft delete by user_id validation)
    pub async fn delete_comment(&self, comment_id: Uuid, user_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"
            DELETE FROM comments
            WHERE id = $1 AND user_id = $2
            "#,
        )
        .bind(comment_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Get a single comment by ID
    pub async fn get_comment(&self, comment_id: Uuid) -> Result<Option<Comment>> {
        let comment = sqlx::query_as::<_, Comment>(
            r#"
            SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at
            FROM comments
            WHERE id = $1
            "#,
        )
        .bind(comment_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(comment)
    }

    /// Get paginated comments for a post
    pub async fn get_comments(
        &self,
        post_id: Uuid,
        limit: i32,
        offset: i32,
        sort_by: &str,
        order: &str,
    ) -> Result<Vec<Comment>> {
        let order_clause = match order.to_lowercase().as_str() {
            "asc" => "ASC",
            _ => "DESC",
        };

        let sort_column = match sort_by.to_lowercase().as_str() {
            "updated_at" => "updated_at",
            _ => "created_at",
        };

        let query = format!(
            r#"
            SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at
            FROM comments
            WHERE post_id = $1
            ORDER BY {} {}
            LIMIT $2 OFFSET $3
            "#,
            sort_column, order_clause
        );

        let comments = sqlx::query_as::<_, Comment>(&query)
            .bind(post_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await?;

        Ok(comments)
    }

    /// Get comment count for a post (fallback when Redis is unavailable)
    pub async fn get_comment_count(&self, post_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM comments
            WHERE post_id = $1
            "#,
        )
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }
}

use crate::domain::models::Bookmark;
use anyhow::Result;
use sqlx::PgPool;
use uuid::Uuid;

/// Repository for Bookmark operations
#[derive(Clone)]
pub struct BookmarkRepository {
    pool: PgPool,
}

impl BookmarkRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create a new bookmark (idempotent - returns success if already exists)
    pub async fn create_bookmark(&self, user_id: Uuid, post_id: Uuid) -> Result<Bookmark> {
        let bookmark = sqlx::query_as::<_, Bookmark>(
            r#"
            INSERT INTO bookmarks (user_id, post_id)
            VALUES ($1, $2)
            ON CONFLICT (user_id, post_id) DO UPDATE
            SET user_id = EXCLUDED.user_id
            RETURNING id, user_id, post_id, bookmarked_at, collection_id
            "#,
        )
        .bind(user_id)
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(bookmark)
    }

    /// Delete a bookmark (idempotent - returns success if doesn't exist)
    pub async fn delete_bookmark(&self, user_id: Uuid, post_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"
            DELETE FROM bookmarks
            WHERE user_id = $1 AND post_id = $2
            "#,
        )
        .bind(user_id)
        .bind(post_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Check if user has bookmarked a post
    pub async fn check_user_bookmarked(&self, user_id: Uuid, post_id: Uuid) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM bookmarks
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

    /// Get bookmark count for a post
    pub async fn get_bookmark_count(&self, post_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM bookmarks
            WHERE post_id = $1
            "#,
        )
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Get paginated bookmarks for a user
    pub async fn get_user_bookmarks(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<Vec<Bookmark>> {
        let bookmarks = sqlx::query_as::<_, Bookmark>(
            r#"
            SELECT id, user_id, post_id, bookmarked_at, collection_id
            FROM bookmarks
            WHERE user_id = $1
            ORDER BY bookmarked_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(bookmarks)
    }

    /// Get total bookmark count for a user
    pub async fn get_user_bookmark_count(&self, user_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM bookmarks
            WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    /// Get post IDs bookmarked by a user (for feed integration)
    pub async fn get_bookmarked_post_ids(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<Vec<Uuid>> {
        let post_ids: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT post_id
            FROM bookmarks
            WHERE user_id = $1
            ORDER BY bookmarked_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(post_ids)
    }

    /// Batch check if user has bookmarked multiple posts
    pub async fn batch_check_bookmarked(
        &self,
        user_id: Uuid,
        post_ids: &[Uuid],
    ) -> Result<Vec<Uuid>> {
        if post_ids.is_empty() {
            return Ok(vec![]);
        }

        let bookmarked_ids: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT post_id
            FROM bookmarks
            WHERE user_id = $1 AND post_id = ANY($2)
            "#,
        )
        .bind(user_id)
        .bind(post_ids)
        .fetch_all(&self.pool)
        .await?;

        Ok(bookmarked_ids)
    }
}

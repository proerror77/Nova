use crate::domain::models::Share;
use anyhow::Result;
use sqlx::PgPool;
use uuid::Uuid;

/// Repository for Share operations
#[derive(Clone)]
pub struct ShareRepository {
    pool: PgPool,
}

impl ShareRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create a new share (idempotent - returns success if already exists)
    pub async fn create_share(
        &self,
        user_id: Uuid,
        post_id: Uuid,
        share_type: String,
    ) -> Result<Share> {
        let share = sqlx::query_as::<_, Share>(
            r#"
            INSERT INTO shares (user_id, post_id, share_type)
            VALUES ($1, $2, $3)
            ON CONFLICT (user_id, post_id) DO UPDATE
            SET share_type = EXCLUDED.share_type
            RETURNING id, user_id, post_id, share_type, created_at
            "#,
        )
        .bind(user_id)
        .bind(post_id)
        .bind(share_type)
        .fetch_one(&self.pool)
        .await?;

        Ok(share)
    }

    /// Check if user has shared a post
    #[allow(dead_code)]
    pub async fn check_user_shared(&self, user_id: Uuid, post_id: Uuid) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM shares
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

    /// Get share count for a post (fallback when Redis is unavailable)
    pub async fn get_share_count(&self, post_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM shares
            WHERE post_id = $1
            "#,
        )
        .bind(post_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }
}

use sqlx::PgPool;
use uuid::Uuid;

#[derive(Clone)]
pub struct FollowService {
    pub pool: PgPool,
}

impl FollowService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Idempotent create follow; returns true if a new row was inserted.
    pub async fn create_follow(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
    ) -> anyhow::Result<bool> {
        let inserted = sqlx::query_as::<_, (Uuid,)>(
            r#"
            INSERT INTO follows (id, follower_id, followee_id, created_at)
            VALUES ($1, $2, $3, NOW())
            ON CONFLICT (follower_id, followee_id) DO NOTHING
            RETURNING id
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(follower_id)
        .bind(followee_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(inserted.is_some())
    }

    /// Idempotent delete; returns true if a row was removed.
    pub async fn delete_follow(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
    ) -> anyhow::Result<bool> {
        let affected = sqlx::query(
            r#"
            DELETE FROM follows
            WHERE follower_id = $1 AND followee_id = $2
            "#,
        )
        .bind(follower_id)
        .bind(followee_id)
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(affected > 0)
    }
}

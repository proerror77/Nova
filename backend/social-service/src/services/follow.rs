use chrono::{DateTime, Utc};
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

    /// Get followers (user_ids) with pagination; returns (followers, total)
    pub async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<(Vec<Uuid>, i64)> {
        let rows: Vec<(Uuid,)> = sqlx::query_as(
            r#"
            SELECT follower_id
            FROM follows
            WHERE followee_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        let total: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM follows WHERE followee_id = $1")
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

        Ok((rows.into_iter().map(|(id,)| id).collect(), total.0))
    }

    /// Get following (user_ids) with pagination; returns (followees, total)
    pub async fn get_following(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<(Vec<Uuid>, i64)> {
        let rows: Vec<(Uuid,)> = sqlx::query_as(
            r#"
            SELECT followee_id
            FROM follows
            WHERE follower_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        let total: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM follows WHERE follower_id = $1")
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

        Ok((rows.into_iter().map(|(id,)| id).collect(), total.0))
    }

    /// Get follow relationship metadata if exists
    pub async fn get_relationship(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
    ) -> anyhow::Result<Option<(Uuid, DateTime<Utc>)>> {
        let row: Option<(Uuid, DateTime<Utc>)> = sqlx::query_as(
            "SELECT id, created_at FROM follows WHERE follower_id = $1 AND followee_id = $2",
        )
        .bind(follower_id)
        .bind(followee_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row)
    }
}

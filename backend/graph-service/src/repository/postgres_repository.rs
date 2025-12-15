use anyhow::{Context, Result};
use sqlx::PgPool;
use tracing::debug;
use uuid::Uuid;

/// PostgreSQL repository for social graph (source of truth)
#[derive(Clone)]
pub struct PostgresGraphRepository {
    pool: PgPool,
}

impl PostgresGraphRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Health check
    pub async fn health_check(&self) -> Result<bool> {
        sqlx::query("SELECT 1")
            .fetch_one(&self.pool)
            .await
            .context("PostgreSQL health check failed")?;
        Ok(true)
    }

    /// P1: Ensure user exists in the local users table before creating relationships
    /// This avoids FK constraint violations when follow/block/mute events arrive
    /// before user sync events from identity-service.
    async fn ensure_user_exists(&self, user_id: Uuid) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO users (id, username, created_at, updated_at)
            VALUES ($1, $1::text, NOW(), NOW())
            ON CONFLICT (id) DO NOTHING
            "#,
        )
        .bind(user_id)
        .execute(&self.pool)
        .await
        .context("Failed to ensure user exists in PostgreSQL")?;
        Ok(())
    }

    /// Upsert user with full details (called from identity event consumer)
    pub async fn upsert_user(&self, user_id: Uuid, username: &str) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO users (id, username, created_at, updated_at)
            VALUES ($1, $2, NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET
                username = EXCLUDED.username,
                updated_at = NOW()
            "#,
        )
        .bind(user_id)
        .bind(username)
        .execute(&self.pool)
        .await
        .context("Failed to upsert user in PostgreSQL")?;

        debug!("Upserted user in PostgreSQL: {} ({})", user_id, username);
        Ok(())
    }

    /// Soft delete user (called from identity event consumer)
    pub async fn soft_delete_user(&self, user_id: Uuid) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE users SET deleted_at = NOW(), updated_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(user_id)
        .execute(&self.pool)
        .await
        .context("Failed to soft delete user in PostgreSQL")?;

        debug!("Soft deleted user in PostgreSQL: {}", user_id);
        Ok(())
    }

    /// Create follow relationship (source of truth)
    pub async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        // P1: Ensure both users exist before creating the relationship
        self.ensure_user_exists(follower_id).await?;
        self.ensure_user_exists(followee_id).await?;
        sqlx::query(
            r#"
            INSERT INTO follows (follower_id, following_id, created_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (follower_id, following_id) DO NOTHING
            "#,
        )
        .bind(follower_id)
        .bind(followee_id)
        .execute(&self.pool)
        .await
        .context("Failed to create follow in PostgreSQL")?;

        debug!(
            "Created FOLLOWS in PostgreSQL: {} -> {}",
            follower_id, followee_id
        );
        Ok(())
    }

    /// Delete follow relationship
    pub async fn delete_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM follows WHERE follower_id = $1 AND following_id = $2")
            .bind(follower_id)
            .bind(followee_id)
            .execute(&self.pool)
            .await
            .context("Failed to delete follow in PostgreSQL")?;

        debug!(
            "Deleted FOLLOWS in PostgreSQL: {} -> {}",
            follower_id, followee_id
        );
        Ok(())
    }

    /// Create mute relationship
    pub async fn create_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        // P1: Ensure both users exist before creating the relationship
        self.ensure_user_exists(muter_id).await?;
        self.ensure_user_exists(mutee_id).await?;

        sqlx::query(
            r#"
            INSERT INTO mutes (muter_id, muted_id, created_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (muter_id, muted_id) DO NOTHING
            "#,
        )
        .bind(muter_id)
        .bind(mutee_id)
        .execute(&self.pool)
        .await
        .context("Failed to create mute in PostgreSQL - ensure mutes table exists")?;

        debug!("Created MUTES in PostgreSQL: {} -> {}", muter_id, mutee_id);
        Ok(())
    }

    /// Delete mute relationship
    pub async fn delete_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM mutes WHERE muter_id = $1 AND muted_id = $2")
            .bind(muter_id)
            .bind(mutee_id)
            .execute(&self.pool)
            .await
            .context("Failed to delete mute in PostgreSQL")?;

        debug!("Deleted MUTES in PostgreSQL: {} -> {}", muter_id, mutee_id);
        Ok(())
    }

    /// Create block relationship
    pub async fn create_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        // P1: Ensure both users exist before creating the relationship
        self.ensure_user_exists(blocker_id).await?;
        self.ensure_user_exists(blocked_id).await?;

        sqlx::query(
            r#"
            INSERT INTO blocks (blocker_id, blocked_id, created_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (blocker_id, blocked_id) DO NOTHING
            "#,
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .execute(&self.pool)
        .await
        .context("Failed to create block in PostgreSQL - ensure blocks table exists")?;

        debug!(
            "Created BLOCKS in PostgreSQL: {} -> {}",
            blocker_id, blocked_id
        );
        Ok(())
    }

    /// Delete block relationship
    pub async fn delete_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2")
            .bind(blocker_id)
            .bind(blocked_id)
            .execute(&self.pool)
            .await
            .context("Failed to delete block in PostgreSQL")?;

        debug!(
            "Deleted BLOCKS in PostgreSQL: {} -> {}",
            blocker_id, blocked_id
        );
        Ok(())
    }

    /// Get followers (PostgreSQL fallback)
    pub async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let effective_limit = limit.min(10000);

        // Get total count
        let total_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM follows WHERE following_id = $1")
                .bind(user_id)
                .fetch_one(&self.pool)
                .await?;

        // Get paginated followers
        let followers: Vec<(Uuid,)> = sqlx::query_as(
            "SELECT follower_id FROM follows
             WHERE following_id = $1
             ORDER BY created_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(user_id)
        .bind(effective_limit as i64)
        .bind(offset as i64)
        .fetch_all(&self.pool)
        .await?;

        let follower_ids: Vec<Uuid> = followers.into_iter().map(|(id,)| id).collect();
        let has_more = (offset as i64 + effective_limit as i64) < total_count;

        Ok((follower_ids, total_count as i32, has_more))
    }

    /// Get following (PostgreSQL fallback)
    pub async fn get_following(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let effective_limit = limit.min(10000);

        let total_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM follows WHERE follower_id = $1")
                .bind(user_id)
                .fetch_one(&self.pool)
                .await?;

        let following: Vec<(Uuid,)> = sqlx::query_as(
            "SELECT following_id FROM follows
             WHERE follower_id = $1
             ORDER BY created_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(user_id)
        .bind(effective_limit as i64)
        .bind(offset as i64)
        .fetch_all(&self.pool)
        .await?;

        let following_ids: Vec<Uuid> = following.into_iter().map(|(id,)| id).collect();
        let has_more = (offset as i64 + effective_limit as i64) < total_count;

        Ok((following_ids, total_count as i32, has_more))
    }

    /// Check if following
    pub async fn is_following(&self, follower_id: Uuid, followee_id: Uuid) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2)",
        )
        .bind(follower_id)
        .bind(followee_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(exists)
    }

    /// Check if blocked
    #[allow(dead_code)] // PostgreSQL fallback - primary queries use Neo4j
    pub async fn is_blocked(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2)",
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(exists)
    }

    /// Get blocked users with pagination (PostgreSQL fallback)
    pub async fn get_blocked_users(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let effective_limit = limit.min(10000);

        // Get total count
        let total_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM blocks WHERE blocker_id = $1")
                .bind(user_id)
                .fetch_one(&self.pool)
                .await?;

        // Get paginated blocked users
        let blocked: Vec<(Uuid,)> = sqlx::query_as(
            "SELECT blocked_id FROM blocks
             WHERE blocker_id = $1
             ORDER BY created_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(user_id)
        .bind(effective_limit as i64)
        .bind(offset as i64)
        .fetch_all(&self.pool)
        .await?;

        let blocked_ids: Vec<Uuid> = blocked.into_iter().map(|(id,)| id).collect();
        let has_more = (offset as i64 + effective_limit as i64) < total_count;

        debug!(
            "Got {} blocked users for user {} from PostgreSQL (offset: {}, has_more: {})",
            blocked_ids.len(),
            user_id,
            offset,
            has_more
        );

        Ok((blocked_ids, total_count as i32, has_more))
    }

    /// Get mutual followers (friends) - users who both follow each other
    pub async fn get_mutual_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)> {
        let effective_limit = limit.min(10000);

        // Get total count of mutual followers
        // A mutual follower is someone who follows me AND I follow them
        let total_count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*)
            FROM follows f1
            INNER JOIN follows f2 ON f1.follower_id = f2.following_id AND f1.following_id = f2.follower_id
            WHERE f1.following_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        // Get paginated mutual followers
        let mutual_followers: Vec<(Uuid,)> = sqlx::query_as(
            r#"
            SELECT f1.follower_id
            FROM follows f1
            INNER JOIN follows f2 ON f1.follower_id = f2.following_id AND f1.following_id = f2.follower_id
            WHERE f1.following_id = $1
            ORDER BY f1.created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(effective_limit as i64)
        .bind(offset as i64)
        .fetch_all(&self.pool)
        .await?;

        let friend_ids: Vec<Uuid> = mutual_followers.into_iter().map(|(id,)| id).collect();
        let has_more = (offset as i64 + effective_limit as i64) < total_count;

        debug!(
            "Got {} mutual followers (friends) for user {} from PostgreSQL (offset: {}, has_more: {})",
            friend_ids.len(),
            user_id,
            offset,
            has_more
        );

        Ok((friend_ids, total_count as i32, has_more))
    }
}

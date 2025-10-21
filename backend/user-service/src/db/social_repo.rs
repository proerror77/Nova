/// Social relationships repository (follows, blocks, mutes)
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::error::{AppError, Result};

/// Follow record in the database
#[derive(Debug, Clone)]
pub struct FollowRecord {
    pub follower_id: Uuid,
    pub followed_id: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// Block record in the database
#[derive(Debug, Clone)]
pub struct BlockRecord {
    pub blocker_id: Uuid,
    pub blocked_id: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// Mute record in the database
#[derive(Debug, Clone)]
pub struct MuteRecord {
    pub muter_id: Uuid,
    pub muted_id: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

pub struct SocialRepository;

impl SocialRepository {
    /// Create a follow relationship
    pub async fn follow(pool: &PgPool, follower_id: Uuid, followed_id: Uuid) -> Result<()> {
        if follower_id == followed_id {
            return Err(AppError::BadRequest(
                "Cannot follow yourself".to_string(),
            ));
        }

        let result = sqlx::query(
            "INSERT INTO follows (follower_id, followed_id, created_at)
             VALUES ($1, $2, NOW())
             ON CONFLICT (follower_id, followed_id) DO NOTHING"
        )
        .bind(follower_id)
        .bind(followed_id)
        .execute(pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to create follow: {}", e);
            AppError::Internal(format!("Failed to create follow relationship: {}", e))
        })?;

        if result.rows_affected() == 0 {
            tracing::warn!(
                "Follow relationship already exists: {} -> {}",
                follower_id,
                followed_id
            );
        }

        Ok(())
    }

    /// Remove a follow relationship
    pub async fn unfollow(pool: &PgPool, follower_id: Uuid, followed_id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM follows WHERE follower_id = $1 AND followed_id = $2")
            .bind(follower_id)
            .bind(followed_id)
            .execute(pool)
            .await
            .map_err(|e| {
                tracing::error!("Failed to delete follow: {}", e);
                AppError::Internal(format!("Failed to remove follow relationship: {}", e))
            })?;

        Ok(())
    }

    /// Block a user
    pub async fn block(pool: &PgPool, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        if blocker_id == blocked_id {
            return Err(AppError::BadRequest(
                "Cannot block yourself".to_string(),
            ));
        }

        // Automatically unfollow when blocking
        Self::unfollow(pool, blocker_id, blocked_id).await.ok();

        sqlx::query(
            "INSERT INTO blocks (blocker_id, blocked_id, created_at)
             VALUES ($1, $2, NOW())
             ON CONFLICT (blocker_id, blocked_id) DO NOTHING"
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .execute(pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to block user: {}", e);
            AppError::Internal(format!("Failed to block user: {}", e))
        })?;

        Ok(())
    }

    /// Unblock a user
    pub async fn unblock(pool: &PgPool, blocker_id: Uuid, blocked_id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2")
            .bind(blocker_id)
            .bind(blocked_id)
            .execute(pool)
            .await
            .map_err(|e| {
                tracing::error!("Failed to unblock user: {}", e);
                AppError::Internal(format!("Failed to unblock user: {}", e))
            })?;

        Ok(())
    }

    /// Mute a user
    pub async fn mute(pool: &PgPool, muter_id: Uuid, muted_id: Uuid) -> Result<()> {
        if muter_id == muted_id {
            return Err(AppError::BadRequest(
                "Cannot mute yourself".to_string(),
            ));
        }

        sqlx::query(
            "INSERT INTO mutes (muter_id, muted_id, created_at)
             VALUES ($1, $2, NOW())
             ON CONFLICT (muter_id, muted_id) DO NOTHING"
        )
        .bind(muter_id)
        .bind(muted_id)
        .execute(pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to mute user: {}", e);
            AppError::Internal(format!("Failed to mute user: {}", e))
        })?;

        Ok(())
    }

    /// Unmute a user
    pub async fn unmute(pool: &PgPool, muter_id: Uuid, muted_id: Uuid) -> Result<()> {
        sqlx::query("DELETE FROM mutes WHERE muter_id = $1 AND muted_id = $2")
            .bind(muter_id)
            .bind(muted_id)
            .execute(pool)
            .await
            .map_err(|e| {
                tracing::error!("Failed to unmute user: {}", e);
                AppError::Internal(format!("Failed to unmute user: {}", e))
            })?;

        Ok(())
    }

    /// Check if user A follows user B
    pub async fn is_following(pool: &PgPool, follower_id: Uuid, followed_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            "SELECT EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND followed_id = $2)"
        )
        .bind(follower_id)
        .bind(followed_id)
        .fetch_one(pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to check follow status: {}", e);
            AppError::Internal(format!("Failed to check follow status: {}", e))
        })?;

        Ok(result.get::<bool, _>(0))
    }

    /// Check if user A has blocked user B
    pub async fn is_blocked(pool: &PgPool, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            "SELECT EXISTS(SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2)"
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .fetch_one(pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to check block status: {}", e);
            AppError::Internal(format!("Failed to check block status: {}", e))
        })?;

        Ok(result.get::<bool, _>(0))
    }

    /// Get followers count for a user
    pub async fn get_followers_count(pool: &PgPool, user_id: Uuid) -> Result<i64> {
        let result = sqlx::query("SELECT COUNT(*) as count FROM follows WHERE followed_id = $1")
            .bind(user_id)
            .fetch_one(pool)
            .await
            .map_err(|e| {
                tracing::error!("Failed to get followers count: {}", e);
                AppError::Internal(format!("Failed to get followers count: {}", e))
            })?;

        Ok(result.get::<i64, _>(0))
    }

    /// Get following count for a user
    pub async fn get_following_count(pool: &PgPool, user_id: Uuid) -> Result<i64> {
        let result = sqlx::query("SELECT COUNT(*) as count FROM follows WHERE follower_id = $1")
            .bind(user_id)
            .fetch_one(pool)
            .await
            .map_err(|e| {
                tracing::error!("Failed to get following count: {}", e);
                AppError::Internal(format!("Failed to get following count: {}", e))
            })?;

        Ok(result.get::<i64, _>(0))
    }

    /// Get paginated followers list
    pub async fn get_followers(
        pool: &PgPool,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Uuid>> {
        let result = sqlx::query(
            "SELECT follower_id FROM follows WHERE followed_id = $1
             ORDER BY created_at DESC LIMIT $2 OFFSET $3"
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to get followers: {}", e);
            AppError::Internal(format!("Failed to get followers: {}", e))
        })?;

        Ok(result.iter().map(|row| row.get::<Uuid, _>(0)).collect())
    }

    /// Get paginated following list
    pub async fn get_following(
        pool: &PgPool,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Uuid>> {
        let result = sqlx::query(
            "SELECT followed_id FROM follows WHERE follower_id = $1
             ORDER BY created_at DESC LIMIT $2 OFFSET $3"
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await
        .map_err(|e| {
            tracing::error!("Failed to get following: {}", e);
            AppError::Internal(format!("Failed to get following: {}", e))
        })?;

        Ok(result.iter().map(|row| row.get::<Uuid, _>(0)).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_follow_record_creation() {
        let follower = Uuid::new_v4();
        let followed = Uuid::new_v4();
        let now = chrono::Utc::now();

        let record = FollowRecord {
            follower_id: follower,
            followed_id: followed,
            created_at: now,
        };

        assert_eq!(record.follower_id, follower);
        assert_eq!(record.followed_id, followed);
    }
}

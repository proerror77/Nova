use crate::error::AppError;
use crate::services::graph_client::GraphClient;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, Pool, Postgres};
use uuid::Uuid;

/// Result of checking if a user can message another user
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CanMessageResult {
    /// User is allowed to send messages
    Allowed,
    /// User is blocked by recipient
    Blocked,
    /// Recipient doesn't accept DMs from anyone
    NotAllowed,
    /// Sender needs to follow recipient first
    NeedToFollow,
    /// Both users need to follow each other (mutual follow required)
    NeedMutualFollow,
    /// A message request should be created instead
    NeedMessageRequest,
}

/// DM permission settings for a user
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DmSettings {
    pub dm_permission: String,
}

/// Block record
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct BlockRecord {
    pub id: Uuid,
    pub blocker_id: Uuid,
    pub blocked_id: Uuid,
    pub reason: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Relationship status between two users
#[derive(Debug, Clone, Serialize)]
pub struct RelationshipStatus {
    pub is_following: bool,
    pub is_followed_by: bool,
    pub is_mutual: bool,
    pub is_blocked: bool,
    pub is_blocking: bool,
}

/// Message request record
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct MessageRequest {
    pub id: Uuid,
    pub requester_id: Uuid,
    pub recipient_id: Uuid,
    pub conversation_id: Option<Uuid>,
    pub status: String,
    pub message_preview: Option<String>,
    pub created_at: DateTime<Utc>,
    pub responded_at: Option<DateTime<Utc>>,
}

pub struct RelationshipService;

/// P0 Migration: RelationshipServiceV2 uses gRPC for block/follow operations
/// This is the target state - block/follow queries go through graph-service
pub struct RelationshipServiceV2 {
    graph_client: GraphClient,
    db: Pool<Postgres>,
}

impl RelationshipServiceV2 {
    pub fn new(graph_client: GraphClient, db: Pool<Postgres>) -> Self {
        Self { graph_client, db }
    }

    /// Check if sender can message recipient (uses graph-service gRPC)
    pub async fn can_message(
        &self,
        sender_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<CanMessageResult, AppError> {
        // Same user can always "message" themselves (edge case)
        if sender_id == recipient_id {
            return Ok(CanMessageResult::Allowed);
        }

        // 1. Check if sender is blocked by recipient (via graph-service)
        if self.graph_client.is_blocked(recipient_id, sender_id).await? {
            return Ok(CanMessageResult::Blocked);
        }

        // 2. Get recipient's DM permission settings (still from local DB for now)
        let settings = RelationshipService::get_dm_settings(&self.db, recipient_id).await?;

        match settings.dm_permission.as_str() {
            "anyone" => Ok(CanMessageResult::Allowed),
            "nobody" => Ok(CanMessageResult::NotAllowed),
            "followers" => {
                // Sender must be following recipient (via graph-service)
                if self.graph_client.is_following(sender_id, recipient_id).await? {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedToFollow)
                }
            }
            "mutuals" | _ => {
                // Both users must follow each other (via graph-service)
                let (are_mutuals, _, _) = self
                    .graph_client
                    .are_mutual_followers(sender_id, recipient_id)
                    .await?;
                if are_mutuals {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedMutualFollow)
                }
            }
        }
    }

    /// Check if user_a is blocked by user_b (via graph-service)
    pub async fn is_blocked_by(&self, user_a: Uuid, user_b: Uuid) -> Result<bool, AppError> {
        self.graph_client.is_blocked(user_b, user_a).await
    }

    /// Check if either user has blocked the other (via graph-service)
    pub async fn has_block_between(&self, user_a: Uuid, user_b: Uuid) -> Result<bool, AppError> {
        let (has_block, _, _) = self.graph_client.has_block_between(user_a, user_b).await?;
        Ok(has_block)
    }

    /// Check if user_a follows user_b (via graph-service)
    pub async fn is_following(&self, follower_id: Uuid, following_id: Uuid) -> Result<bool, AppError> {
        self.graph_client.is_following(follower_id, following_id).await
    }

    /// Check if two users are mutual followers (via graph-service)
    pub async fn are_mutuals(&self, user_a: Uuid, user_b: Uuid) -> Result<bool, AppError> {
        let (are_mutuals, _, _) = self.graph_client.are_mutual_followers(user_a, user_b).await?;
        Ok(are_mutuals)
    }

    /// Get full relationship status between two users (via graph-service)
    pub async fn get_relationship_status(
        &self,
        user_id: Uuid,
        target_id: Uuid,
    ) -> Result<RelationshipStatus, AppError> {
        // Use are_mutual_followers for both directions in one call
        let (_, user_follows_target, target_follows_user) = self
            .graph_client
            .are_mutual_followers(user_id, target_id)
            .await?;

        // Use has_block_between for both directions in one call
        let (_, user_blocked_target, target_blocked_user) = self
            .graph_client
            .has_block_between(user_id, target_id)
            .await?;

        Ok(RelationshipStatus {
            is_following: user_follows_target,
            is_followed_by: target_follows_user,
            is_mutual: user_follows_target && target_follows_user,
            is_blocked: target_blocked_user, // target blocked user
            is_blocking: user_blocked_target, // user blocked target
        })
    }
}

/// Legacy implementation - uses direct PostgreSQL queries
/// TODO: Deprecate after full migration to RelationshipServiceV2
impl RelationshipService {
    /// Check if sender can message recipient based on blocks and privacy settings
    pub async fn can_message(
        db: &Pool<Postgres>,
        sender_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<CanMessageResult, AppError> {
        // Same user can always "message" themselves (edge case)
        if sender_id == recipient_id {
            return Ok(CanMessageResult::Allowed);
        }

        // 1. Check if sender is blocked by recipient
        if Self::is_blocked_by(db, sender_id, recipient_id).await? {
            return Ok(CanMessageResult::Blocked);
        }

        // 2. Get recipient's DM permission settings
        let settings = Self::get_dm_settings(db, recipient_id).await?;

        match settings.dm_permission.as_str() {
            "anyone" => Ok(CanMessageResult::Allowed),
            "nobody" => Ok(CanMessageResult::NotAllowed),
            "followers" => {
                // Sender must be following recipient (sender follows recipient)
                if Self::is_following(db, sender_id, recipient_id).await? {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedToFollow)
                }
            }
            "mutuals" | _ => {
                // Both users must follow each other
                if Self::are_mutuals(db, sender_id, recipient_id).await? {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedMutualFollow)
                }
            }
        }
    }

    /// Check if user_a is blocked by user_b
    pub async fn is_blocked_by(
        db: &Pool<Postgres>,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let result: Option<(i32,)> = sqlx::query_as(
            "SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2 LIMIT 1",
        )
        .bind(user_b) // user_b blocked user_a
        .bind(user_a)
        .fetch_optional(db)
        .await
        .map_err(|e| AppError::Database(format!("is_blocked_by check failed: {}", e)))?;

        Ok(result.is_some())
    }

    /// Check if either user has blocked the other
    pub async fn has_block_between(
        db: &Pool<Postgres>,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let result: Option<(i32,)> = sqlx::query_as(
            r#"
            SELECT 1 FROM blocks
            WHERE (blocker_id = $1 AND blocked_id = $2)
               OR (blocker_id = $2 AND blocked_id = $1)
            LIMIT 1
            "#,
        )
        .bind(user_a)
        .bind(user_b)
        .fetch_optional(db)
        .await
        .map_err(|e| AppError::Database(format!("has_block_between check failed: {}", e)))?;

        Ok(result.is_some())
    }

    /// Check if user_a follows user_b
    pub async fn is_following(
        db: &Pool<Postgres>,
        follower_id: Uuid,
        following_id: Uuid,
    ) -> Result<bool, AppError> {
        let result: Option<(i32,)> = sqlx::query_as(
            "SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2 LIMIT 1",
        )
        .bind(follower_id)
        .bind(following_id)
        .fetch_optional(db)
        .await
        .map_err(|e| AppError::Database(format!("is_following check failed: {}", e)))?;

        Ok(result.is_some())
    }

    /// Check if two users follow each other (mutual follows = friends)
    pub async fn are_mutuals(
        db: &Pool<Postgres>,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM follows
            WHERE (follower_id = $1 AND following_id = $2)
               OR (follower_id = $2 AND following_id = $1)
            "#,
        )
        .bind(user_a)
        .bind(user_b)
        .fetch_one(db)
        .await
        .map_err(|e| AppError::Database(format!("are_mutuals check failed: {}", e)))?;

        Ok(count == 2) // Two records = mutual follow
    }

    /// Get DM permission settings for a user
    pub async fn get_dm_settings(
        db: &Pool<Postgres>,
        user_id: Uuid,
    ) -> Result<DmSettings, AppError> {
        let result: Option<(String,)> = sqlx::query_as(
            "SELECT dm_permission FROM user_settings WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_optional(db)
        .await
        .map_err(|e| AppError::Database(format!("get_dm_settings failed: {}", e)))?;

        Ok(DmSettings {
            dm_permission: result.map(|(p,)| p).unwrap_or_else(|| "mutuals".to_string()),
        })
    }

    /// Update DM permission settings for a user
    pub async fn update_dm_settings(
        db: &Pool<Postgres>,
        user_id: Uuid,
        dm_permission: &str,
    ) -> Result<(), AppError> {
        // Validate permission value
        if !["anyone", "followers", "mutuals", "nobody"].contains(&dm_permission) {
            return Err(AppError::BadRequest(format!(
                "Invalid dm_permission: {}. Must be one of: anyone, followers, mutuals, nobody",
                dm_permission
            )));
        }

        sqlx::query(
            r#"
            INSERT INTO user_settings (user_id, dm_permission)
            VALUES ($1, $2)
            ON CONFLICT (user_id) DO UPDATE SET dm_permission = $2, updated_at = NOW()
            "#,
        )
        .bind(user_id)
        .bind(dm_permission)
        .execute(db)
        .await
        .map_err(|e| AppError::Database(format!("update_dm_settings failed: {}", e)))?;

        Ok(())
    }

    /// Block a user
    pub async fn block_user(
        db: &Pool<Postgres>,
        blocker_id: Uuid,
        blocked_id: Uuid,
        reason: Option<String>,
    ) -> Result<bool, AppError> {
        if blocker_id == blocked_id {
            return Err(AppError::BadRequest("Cannot block yourself".to_string()));
        }

        let result = sqlx::query(
            r#"
            INSERT INTO blocks (blocker_id, blocked_id, reason)
            VALUES ($1, $2, $3)
            ON CONFLICT (blocker_id, blocked_id) DO NOTHING
            "#,
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .bind(reason)
        .execute(db)
        .await
        .map_err(|e| AppError::Database(format!("block_user failed: {}", e)))?;

        // Note: The trigger trg_remove_follows_on_block handles removing follows
        Ok(result.rows_affected() > 0)
    }

    /// Unblock a user
    pub async fn unblock_user(
        db: &Pool<Postgres>,
        blocker_id: Uuid,
        blocked_id: Uuid,
    ) -> Result<bool, AppError> {
        let result = sqlx::query(
            "DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2",
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .execute(db)
        .await
        .map_err(|e| AppError::Database(format!("unblock_user failed: {}", e)))?;

        Ok(result.rows_affected() > 0)
    }

    /// Get list of blocked users
    pub async fn get_blocked_users(
        db: &Pool<Postgres>,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<BlockRecord>, AppError> {
        let records = sqlx::query_as::<_, BlockRecord>(
            r#"
            SELECT id, blocker_id, blocked_id, reason, created_at
            FROM blocks
            WHERE blocker_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await
        .map_err(|e| AppError::Database(format!("get_blocked_users failed: {}", e)))?;

        Ok(records)
    }

    /// Get full relationship status between two users
    pub async fn get_relationship_status(
        db: &Pool<Postgres>,
        user_id: Uuid,
        target_id: Uuid,
    ) -> Result<RelationshipStatus, AppError> {
        let is_following = Self::is_following(db, user_id, target_id).await?;
        let is_followed_by = Self::is_following(db, target_id, user_id).await?;
        let is_blocked = Self::is_blocked_by(db, user_id, target_id).await?;
        let is_blocking = Self::is_blocked_by(db, target_id, user_id).await?;

        Ok(RelationshipStatus {
            is_following,
            is_followed_by,
            is_mutual: is_following && is_followed_by,
            is_blocked,
            is_blocking,
        })
    }

    // ==================== Message Requests ====================

    /// Create a message request
    pub async fn create_message_request(
        db: &Pool<Postgres>,
        requester_id: Uuid,
        recipient_id: Uuid,
        message_preview: Option<String>,
    ) -> Result<Uuid, AppError> {
        if requester_id == recipient_id {
            return Err(AppError::BadRequest(
                "Cannot send message request to yourself".to_string(),
            ));
        }

        // Check if blocked
        if Self::is_blocked_by(db, requester_id, recipient_id).await? {
            return Err(AppError::Forbidden);
        }

        let id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO message_requests (id, requester_id, recipient_id, message_preview)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (requester_id, recipient_id) DO UPDATE
            SET message_preview = COALESCE($4, message_requests.message_preview),
                status = 'pending',
                created_at = NOW()
            "#,
        )
        .bind(id)
        .bind(requester_id)
        .bind(recipient_id)
        .bind(message_preview)
        .execute(db)
        .await
        .map_err(|e| AppError::Database(format!("create_message_request failed: {}", e)))?;

        Ok(id)
    }

    /// Get pending message requests for a user
    pub async fn get_pending_message_requests(
        db: &Pool<Postgres>,
        recipient_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<MessageRequest>, AppError> {
        let requests = sqlx::query_as::<_, MessageRequest>(
            r#"
            SELECT id, requester_id, recipient_id, conversation_id, status,
                   message_preview, created_at, responded_at
            FROM message_requests
            WHERE recipient_id = $1 AND status = 'pending'
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(recipient_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(db)
        .await
        .map_err(|e| AppError::Database(format!("get_pending_message_requests failed: {}", e)))?;

        Ok(requests)
    }

    /// Accept a message request
    pub async fn accept_message_request(
        db: &Pool<Postgres>,
        request_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<MessageRequest, AppError> {
        let request = sqlx::query_as::<_, MessageRequest>(
            r#"
            UPDATE message_requests
            SET status = 'accepted', responded_at = NOW()
            WHERE id = $1 AND recipient_id = $2 AND status = 'pending'
            RETURNING id, requester_id, recipient_id, conversation_id, status,
                      message_preview, created_at, responded_at
            "#,
        )
        .bind(request_id)
        .bind(recipient_id)
        .fetch_optional(db)
        .await
        .map_err(|e| AppError::Database(format!("accept_message_request failed: {}", e)))?
        .ok_or(AppError::NotFound)?;

        Ok(request)
    }

    /// Reject a message request
    pub async fn reject_message_request(
        db: &Pool<Postgres>,
        request_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<(), AppError> {
        let result = sqlx::query(
            r#"
            UPDATE message_requests
            SET status = 'rejected', responded_at = NOW()
            WHERE id = $1 AND recipient_id = $2 AND status = 'pending'
            "#,
        )
        .bind(request_id)
        .bind(recipient_id)
        .execute(db)
        .await
        .map_err(|e| AppError::Database(format!("reject_message_request failed: {}", e)))?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound);
        }

        Ok(())
    }
}

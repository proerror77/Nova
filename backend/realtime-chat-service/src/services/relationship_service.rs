use crate::error::AppError;
use crate::services::graph_client::GraphClient;
use crate::services::identity_client::IdentityClient;
use chrono::{DateTime, Utc};
use deadpool_postgres::Pool;
use serde::{Deserialize, Serialize};
use tokio_postgres::Row;
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
#[derive(Debug, Clone, Serialize)]
pub struct BlockRecord {
    pub id: Uuid,
    pub blocker_id: Uuid,
    pub blocked_id: Uuid,
    pub reason: Option<String>,
    pub created_at: DateTime<Utc>,
}

impl BlockRecord {
    fn from_row(row: &Row) -> Result<Self, AppError> {
        Ok(Self {
            id: row.get("id"),
            blocker_id: row.get("blocker_id"),
            blocked_id: row.get("blocked_id"),
            reason: row.get("reason"),
            created_at: row.get("created_at"),
        })
    }
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
#[derive(Debug, Clone, Serialize)]
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

impl MessageRequest {
    fn from_row(row: &Row) -> Result<Self, AppError> {
        Ok(Self {
            id: row.get("id"),
            requester_id: row.get("requester_id"),
            recipient_id: row.get("recipient_id"),
            conversation_id: row.get("conversation_id"),
            status: row.get("status"),
            message_preview: row.get("message_preview"),
            created_at: row.get("created_at"),
            responded_at: row.get("responded_at"),
        })
    }
}

pub struct RelationshipService;

/// P0 Migration: RelationshipServiceV2 uses gRPC for block/follow operations
/// This is the target state - block/follow queries go through graph-service
///
/// **IMPORTANT**: dm_permission is now read from identity-service (single source of truth)
/// Do NOT use local database for dm_permission reads or writes.
pub struct RelationshipServiceV2 {
    graph_client: GraphClient,
    identity_client: IdentityClient,
    /// Kept for potential fallback during migration; not actively used
    #[allow(dead_code)]
    db: Pool,
}

impl RelationshipServiceV2 {
    pub fn new(graph_client: GraphClient, identity_client: IdentityClient, db: Pool) -> Self {
        Self { graph_client, identity_client, db }
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
        if self
            .graph_client
            .is_blocked(recipient_id, sender_id)
            .await?
        {
            return Ok(CanMessageResult::Blocked);
        }

        // 2. Get recipient's DM permission settings from identity-service (SINGLE SOURCE OF TRUTH)
        let settings = self.identity_client.get_dm_settings(recipient_id).await?;

        match settings.dm_permission.as_str() {
            "anyone" => Ok(CanMessageResult::Allowed),
            "nobody" => Ok(CanMessageResult::NotAllowed),
            "followers" => {
                // Sender must be following recipient (via graph-service)
                if self
                    .graph_client
                    .is_following(sender_id, recipient_id)
                    .await?
                {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedToFollow)
                }
            }
            "mutuals" => {
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
            _ => Ok(CanMessageResult::NeedToFollow),
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
    pub async fn is_following(
        &self,
        follower_id: Uuid,
        following_id: Uuid,
    ) -> Result<bool, AppError> {
        self.graph_client
            .is_following(follower_id, following_id)
            .await
    }

    /// Check if two users are mutual followers (via graph-service)
    pub async fn are_mutuals(&self, user_a: Uuid, user_b: Uuid) -> Result<bool, AppError> {
        let (are_mutuals, _, _) = self
            .graph_client
            .are_mutual_followers(user_a, user_b)
            .await?;
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
            is_blocked: target_blocked_user,  // target blocked user
            is_blocking: user_blocked_target, // user blocked target
        })
    }

    /// Block a user (via graph-service)
    /// Replaces local DB block_user operation with gRPC call
    pub async fn block_user(
        &self,
        blocker_id: Uuid,
        blocked_id: Uuid,
    ) -> Result<bool, AppError> {
        if blocker_id == blocked_id {
            return Err(AppError::BadRequest("Cannot block yourself".to_string()));
        }

        self.graph_client.create_block(blocker_id, blocked_id).await
    }

    /// Unblock a user (via graph-service)
    /// Replaces local DB unblock_user operation with gRPC call
    pub async fn unblock_user(
        &self,
        blocker_id: Uuid,
        blocked_id: Uuid,
    ) -> Result<bool, AppError> {
        self.graph_client.delete_block(blocker_id, blocked_id).await
    }

    /// Get list of blocked users (via graph-service)
    /// Replaces local DB get_blocked_users operation with gRPC call
    pub async fn get_blocked_users(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Uuid>, AppError> {
        let (blocked_user_ids, _, _) = self
            .graph_client
            .get_blocked_users(user_id, limit as i32, offset as i32)
            .await?;

        // Convert Vec<String> to Vec<Uuid>
        let uuids: Result<Vec<Uuid>, _> = blocked_user_ids
            .iter()
            .map(|id| Uuid::parse_str(id))
            .collect();

        uuids.map_err(|e| AppError::BadRequest(format!("Invalid UUID in response: {}", e)))
    }
}

/// Legacy implementation - uses direct PostgreSQL queries
/// TODO: Deprecate after full migration to RelationshipServiceV2
impl RelationshipService {
    /// Check if sender can message recipient based on blocks and privacy settings
    pub async fn can_message(
        db: &Pool,
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
            "mutuals" => {
                // Both users must follow each other
                if Self::are_mutuals(db, sender_id, recipient_id).await? {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedMutualFollow)
                }
            }
            _ => Ok(CanMessageResult::NeedToFollow),
        }
    }

    /// Check if user_a is blocked by user_b
    pub async fn is_blocked_by(
        db: &Pool,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let client = db.get().await?;
        let result = client.query_opt(
            "SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2 LIMIT 1",
            &[&user_b, &user_a], // user_b blocked user_a
        )
        .await
        .map_err(|e| AppError::Database(format!("is_blocked_by check failed: {}", e)))?;

        Ok(result.is_some())
    }

    /// Check if either user has blocked the other
    pub async fn has_block_between(
        db: &Pool,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let client = db.get().await?;
        let result = client.query_opt(
            r#"
            SELECT 1 FROM blocks
            WHERE (blocker_id = $1 AND blocked_id = $2)
               OR (blocker_id = $2 AND blocked_id = $1)
            LIMIT 1
            "#,
            &[&user_a, &user_b],
        )
        .await
        .map_err(|e| AppError::Database(format!("has_block_between check failed: {}", e)))?;

        Ok(result.is_some())
    }

    /// Check if user_a follows user_b
    pub async fn is_following(
        db: &Pool,
        follower_id: Uuid,
        following_id: Uuid,
    ) -> Result<bool, AppError> {
        let client = db.get().await?;
        let result = client.query_opt(
            "SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2 LIMIT 1",
            &[&follower_id, &following_id],
        )
        .await
        .map_err(|e| AppError::Database(format!("is_following check failed: {}", e)))?;

        Ok(result.is_some())
    }

    /// Check if two users follow each other (mutual follows = friends)
    pub async fn are_mutuals(
        db: &Pool,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let client = db.get().await?;
        let count: i64 = client.query_one(
            r#"
            SELECT COUNT(*) FROM follows
            WHERE (follower_id = $1 AND following_id = $2)
               OR (follower_id = $2 AND following_id = $1)
            "#,
            &[&user_a, &user_b],
        )
        .await
        .map_err(|e| AppError::Database(format!("are_mutuals check failed: {}", e)))?
        .get(0);

        Ok(count == 2) // Two records = mutual follow
    }

    /// Get DM permission settings for a user (LOCAL DATABASE)
    /// 
    /// **DEPRECATED**: Use `IdentityClient::get_dm_settings()` instead.
    /// The single source of truth for dm_permission is identity-service.
    /// This method is kept for backward compatibility during migration.
    #[deprecated(
        since = "P0-migration",
        note = "Use IdentityClient::get_dm_settings() instead. identity-service is the single source of truth."
    )]
    pub async fn get_dm_settings(
        db: &Pool,
        user_id: Uuid,
    ) -> Result<DmSettings, AppError> {
        let client = db.get().await?;
        let result: Option<String> = client.query_opt(
            "SELECT dm_permission FROM user_settings WHERE user_id = $1",
            &[&user_id],
        )
        .await
        .map_err(|e| AppError::Database(format!("get_dm_settings failed: {}", e)))?
        .map(|row| row.get(0));

        Ok(DmSettings {
            dm_permission: result.unwrap_or_else(|| "everyone".to_string()),
        })
    }

    /// Update DM permission settings for a user (LOCAL DATABASE)
    /// 
    /// **DEPRECATED**: Use identity-service API (`PUT /api/v2/auth/users/{user_id}/settings`) instead.
    /// The single source of truth for dm_permission is identity-service.
    /// This method should NOT be called - all updates should go through identity-service.
    #[deprecated(
        since = "P0-migration",
        note = "Use identity-service UpdateUserSettings API instead. identity-service is the single source of truth."
    )]
    pub async fn update_dm_settings(
        _db: &Pool,
        _user_id: Uuid,
        _dm_permission: &str,
    ) -> Result<(), AppError> {
        // P0: This method is deprecated. Updates should go through identity-service.
        // Return error to prevent accidental local writes.
        Err(AppError::BadRequest(
            "dm_permission updates must go through identity-service API. \
             Use PUT /api/v2/auth/users/{user_id}/settings instead.".to_string()
        ))
    }

    /// Block a user
    pub async fn block_user(
        db: &Pool,
        blocker_id: Uuid,
        blocked_id: Uuid,
        reason: Option<String>,
    ) -> Result<bool, AppError> {
        if blocker_id == blocked_id {
            return Err(AppError::BadRequest("Cannot block yourself".to_string()));
        }

        let client = db.get().await?;
        let rows_affected = client.execute(
            r#"
            INSERT INTO blocks (blocker_id, blocked_id, reason)
            VALUES ($1, $2, $3)
            ON CONFLICT (blocker_id, blocked_id) DO NOTHING
            "#,
            &[&blocker_id, &blocked_id, &reason],
        )
        .await
        .map_err(|e| AppError::Database(format!("block_user failed: {}", e)))?;

        // Note: The trigger trg_remove_follows_on_block handles removing follows
        Ok(rows_affected > 0)
    }

    /// Unblock a user
    pub async fn unblock_user(
        db: &Pool,
        blocker_id: Uuid,
        blocked_id: Uuid,
    ) -> Result<bool, AppError> {
        let client = db.get().await?;
        let rows_affected = client.execute(
            "DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2",
            &[&blocker_id, &blocked_id],
        )
        .await
        .map_err(|e| AppError::Database(format!("unblock_user failed: {}", e)))?;

        Ok(rows_affected > 0)
    }

    /// Get list of blocked users
    pub async fn get_blocked_users(
        db: &Pool,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<BlockRecord>, AppError> {
        let client = db.get().await?;
        let rows = client.query(
            r#"
            SELECT id, blocker_id, blocked_id, reason, created_at
            FROM blocks
            WHERE blocker_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
            &[&user_id, &limit, &offset],
        )
        .await
        .map_err(|e| AppError::Database(format!("get_blocked_users failed: {}", e)))?;

        let records: Vec<BlockRecord> = rows
            .iter()
            .map(|row| BlockRecord::from_row(row))
            .collect::<Result<Vec<_>, _>>()?;

        Ok(records)
    }

    /// Get full relationship status between two users
    pub async fn get_relationship_status(
        db: &Pool,
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
        db: &Pool,
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
        let client = db.get().await?;
        client.execute(
            r#"
            INSERT INTO message_requests (id, requester_id, recipient_id, message_preview)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (requester_id, recipient_id) DO UPDATE
            SET message_preview = COALESCE($4, message_requests.message_preview),
                status = 'pending',
                created_at = NOW()
            "#,
            &[&id, &requester_id, &recipient_id, &message_preview],
        )
        .await
        .map_err(|e| AppError::Database(format!("create_message_request failed: {}", e)))?;

        Ok(id)
    }

    /// Get pending message requests for a user
    pub async fn get_pending_message_requests(
        db: &Pool,
        recipient_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<MessageRequest>, AppError> {
        let client = db.get().await?;
        let rows = client.query(
            r#"
            SELECT id, requester_id, recipient_id, conversation_id, status,
                   message_preview, created_at, responded_at
            FROM message_requests
            WHERE recipient_id = $1 AND status = 'pending'
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
            &[&recipient_id, &limit, &offset],
        )
        .await
        .map_err(|e| AppError::Database(format!("get_pending_message_requests failed: {}", e)))?;

        let requests: Vec<MessageRequest> = rows
            .iter()
            .map(|row| MessageRequest::from_row(row))
            .collect::<Result<Vec<_>, _>>()?;

        Ok(requests)
    }

    /// Accept a message request
    pub async fn accept_message_request(
        db: &Pool,
        request_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<MessageRequest, AppError> {
        let client = db.get().await?;
        let row = client.query_opt(
            r#"
            UPDATE message_requests
            SET status = 'accepted', responded_at = NOW()
            WHERE id = $1 AND recipient_id = $2 AND status = 'pending'
            RETURNING id, requester_id, recipient_id, conversation_id, status,
                      message_preview, created_at, responded_at
            "#,
            &[&request_id, &recipient_id],
        )
        .await
        .map_err(|e| AppError::Database(format!("accept_message_request failed: {}", e)))?
        .ok_or(AppError::NotFound)?;

        Ok(MessageRequest::from_row(&row)?)
    }

    /// Reject a message request
    pub async fn reject_message_request(
        db: &Pool,
        request_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<(), AppError> {
        let client = db.get().await?;
        let rows_affected = client.execute(
            r#"
            UPDATE message_requests
            SET status = 'rejected', responded_at = NOW()
            WHERE id = $1 AND recipient_id = $2 AND status = 'pending'
            "#,
            &[&request_id, &recipient_id],
        )
        .await
        .map_err(|e| AppError::Database(format!("reject_message_request failed: {}", e)))?;

        if rows_affected == 0 {
            return Err(AppError::NotFound);
        }

        Ok(())
    }
}

use crate::services::graph_client::GraphClient;
use crate::services::identity_client::IdentityClient;
use crate::services::relationship_service::{CanMessageResult, RelationshipServiceV2};
use chrono::{DateTime, Utc};
use grpc_clients::AuthClient;
use serde::{Deserialize, Serialize};
use deadpool_postgres::Pool;
use std::sync::Arc;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub enum PrivacyMode {
    #[serde(rename = "strict_e2e")]
    #[default]
    StrictE2e,
    #[serde(rename = "search_enabled")]
    SearchEnabled,
}

impl PrivacyMode {
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(value: &str) -> Self {
        match value {
            "search_enabled" => PrivacyMode::SearchEnabled,
            _ => PrivacyMode::StrictE2e,
        }
    }
}

pub struct ConversationDetails {
    pub id: Uuid,
    pub member_count: i32,
    pub last_message_id: Option<Uuid>,
}

pub struct ConversationMember {
    pub user_id: Uuid,
    pub role: String,
    pub joined_at: DateTime<Utc>,
    pub last_read_at: Option<DateTime<Utc>>,
    pub is_muted: bool,
}

pub struct ConversationWithMembers {
    pub id: Uuid,
    pub member_count: i32,
    pub last_message_id: Option<Uuid>,
    pub members: Vec<ConversationMember>,
}

pub struct ConversationService;

impl ConversationService {
    /// Create a direct (1:1) conversation between two users
    /// Performs authorization checks based on recipient's DM settings and block status
    ///
    /// P0: Uses identity-service as SSOT for dm_permission via RelationshipServiceV2
    pub async fn create_direct_conversation(
        db: &Pool,
        auth_client: &AuthClient,
        graph_client: Option<&Arc<GraphClient>>,
        identity_client: Option<&Arc<IdentityClient>>,
        initiator: Uuid,
        recipient: Uuid,
    ) -> Result<Uuid, crate::error::AppError> {
        // Validate users exist via identity-service (replaces FK constraint validation)
        for user_id in [initiator, recipient] {
            let exists = auth_client.user_exists(user_id).await.map_err(|e| {
                tracing::error!(user_id = %user_id, error = %e, "auth-service user_exists failed");
                crate::error::AppError::ServiceUnavailable(format!(
                    "Failed to check user existence via auth-service: {e}"
                ))
            })?;
            if !exists {
                return Err(crate::error::AppError::BadRequest(format!(
                    "User {} does not exist",
                    user_id
                )));
            }
        }

        // Check if conversation already exists between these users
        if let Some(existing_id) =
            Self::find_existing_direct_conversation(db, initiator, recipient).await?
        {
            return Ok(existing_id);
        }

        // Authorization check: can initiator message recipient?
        // P0: Use RelationshipServiceV2 which reads dm_permission from identity-service (SSOT)
        let can_message = match (graph_client, identity_client) {
            (Some(gc), Some(ic)) => {
                let relationship_service = RelationshipServiceV2::new(
                    (**gc).clone(),
                    (**ic).clone(),
                    db.clone(),
                );
                relationship_service.can_message(initiator, recipient).await?
            }
            _ => {
                // Fallback: If clients not available, allow messaging (graceful degradation)
                // This maintains backwards compatibility during migration
                tracing::warn!(
                    "graph_client or identity_client not available, skipping DM permission check"
                );
                CanMessageResult::Allowed
            }
        };

        match can_message {
            CanMessageResult::Allowed => {
                // Proceed with conversation creation
            }
            CanMessageResult::Blocked => {
                // Don't reveal block status - return generic forbidden
                return Err(crate::error::AppError::Forbidden);
            }
            CanMessageResult::NeedMutualFollow => {
                return Err(crate::error::AppError::BadRequest(
                    "You must be mutual followers to send messages to this user".to_string(),
                ));
            }
            CanMessageResult::NeedToFollow => {
                return Err(crate::error::AppError::BadRequest(
                    "You must follow this user to send them messages".to_string(),
                ));
            }
            CanMessageResult::NotAllowed => {
                return Err(crate::error::AppError::BadRequest(
                    "This user doesn't accept direct messages".to_string(),
                ));
            }
            CanMessageResult::NeedMessageRequest => {
                // Could create a message request instead, but for now return error
                return Err(crate::error::AppError::BadRequest(
                    "You need to send a message request first".to_string(),
                ));
            }
        }

        let id = Uuid::new_v4();
        let mut client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;
        let tx = client.transaction().await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;

        // Note: Do not attempt to upsert into the canonical users table here.
        // The users table is owned by user-service and may have stricter NOT NULL
        // constraints (e.g., password_hash). Assume provided user IDs already exist
        // and let FK constraints enforce integrity.

        // Insert conversation
        // conversations(id, kind, member_count, privacy_mode)
        tx.execute(
            "INSERT INTO conversations (id, kind, member_count, privacy_mode) VALUES ($1, 'direct'::conversation_type, 2, 'strict_e2e'::privacy_mode)",
            &[&id]
        )
        .await
        .map_err(|e| {
            crate::error::AppError::StartServer(format!("insert conversation: {e}"))
        })?;

        tx.execute(
            "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'member'), ($1, $3, 'member') ON CONFLICT DO NOTHING",
            &[&id, &initiator, &recipient]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert members: {e}")))?;

        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("commit: {e}")))?;

        Ok(id)
    }

    /// Find existing direct conversation between two users
    async fn find_existing_direct_conversation(
        db: &Pool,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<Option<Uuid>, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        let result = client.query_opt(
            r#"
            SELECT c.id
            FROM conversations c
            WHERE c.conversation_type = 'direct'
              AND c.deleted_at IS NULL
              AND EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = c.id AND user_id = $1)
              AND EXISTS (SELECT 1 FROM conversation_members WHERE conversation_id = c.id AND user_id = $2)
            LIMIT 1
            "#,
            &[&user_a, &user_b]
        )
        .await
        .map_err(|e| crate::error::AppError::Database(format!("find_existing_conversation: {e}")))?;

        Ok(result.map(|row| row.get(0)))
    }

    pub async fn get_conversation_db(
        db: &Pool,
        id: Uuid,
    ) -> Result<ConversationDetails, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        // Compute derived fields against user-service schema
        let r = client.query_one(
            r#"
            SELECT
              c.id AS id,
              (
                SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id = c.id
              ) AS member_count,
              (
                SELECT m.id FROM messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1
              ) AS last_message_id
            FROM conversations c
            WHERE c.id = $1 AND c.deleted_at IS NULL
            "#,
            &[&id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?;

        let id: Uuid = r.get("id");
        let member_count: i32 = r.get("member_count");
        let last_message_id: Option<Uuid> = r.get("last_message_id");

        Ok(ConversationDetails {
            id,
            member_count,
            last_message_id,
        })
    }

    /// List all conversations for a user
    /// Returns conversation IDs sorted by most recent update (conversations.updated_at DESC)
    /// Security: Only returns conversations where user is a member
    pub async fn list_conversations(
        db: &Pool,
        user_id: Uuid,
    ) -> Result<Vec<ConversationDetails>, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        // Query conversations where user is a member, ordered by most recent first
        let rows = client.query(
            r#"
            SELECT c.id, c.member_count, c.last_message_id
            FROM conversations c
            JOIN conversation_members cm ON c.id = cm.conversation_id
            WHERE cm.user_id = $1 AND c.deleted_at IS NULL
            ORDER BY c.updated_at DESC
            LIMIT 100
            "#,
            &[&user_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("list conversations: {e}")))?;

        let conversations = rows
            .into_iter()
            .map(|row| {
                let id: Uuid = row.get("id");
                let member_count: i32 = row.get("member_count");
                let last_message_id: Option<Uuid> = row.get("last_message_id");
                ConversationDetails {
                    id,
                    member_count,
                    last_message_id,
                }
            })
            .collect();

        Ok(conversations)
    }

    pub async fn is_member(
        db: &Pool,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        let rec = client.query_opt(
            r#"
            SELECT 1
            FROM conversation_members cm
            JOIN conversations c ON c.id = cm.conversation_id
            WHERE cm.conversation_id = $1
              AND cm.user_id = $2
              AND c.deleted_at IS NULL
            LIMIT 1
            "#,
            &[&conversation_id, &user_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("is_member: {e}")))?;
        Ok(rec.is_some())
    }

    /// Check if a user is a member of a conversation with Redis caching
    /// Cache TTL: 60 seconds - reduces DB load for rapid conversation browsing
    pub async fn is_member_cached(
        db: &Pool,
        redis: &crate::redis_client::RedisClient,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, crate::error::AppError> {
        use redis::AsyncCommands;

        let cache_key = format!("chat:member:{}:{}", conversation_id, user_id);

        // Try Redis cache first
        if let Ok(mut conn) = redis.get_multiplexed_async_connection().await {
            if let Ok(Some(cached)) = conn.get::<_, Option<String>>(&cache_key).await {
                return Ok(cached == "1");
            }
        }

        // Cache miss - query database
        let is_member = Self::is_member(db, conversation_id, user_id).await?;

        // Cache the result for 60 seconds
        if let Ok(mut conn) = redis.get_multiplexed_async_connection().await {
            let _: Result<(), _> = conn.set_ex(&cache_key, if is_member { "1" } else { "0" }, 60).await;
        }

        Ok(is_member)
    }

    /// Invalidate membership cache when membership changes (add/remove member)
    pub async fn invalidate_membership_cache(
        redis: &crate::redis_client::RedisClient,
        conversation_id: Uuid,
        user_id: Uuid,
    ) {
        use redis::AsyncCommands;

        let cache_key = format!("chat:member:{}:{}", conversation_id, user_id);
        if let Ok(mut conn) = redis.get_multiplexed_async_connection().await {
            let _: Result<(), _> = conn.del(&cache_key).await;
        }
    }

    /// Get conversation with full member details
    /// Security: Validates that requesting user is a member before returning data
    pub async fn get_conversation_with_members(
        db: &Pool,
        conversation_id: Uuid,
        requesting_user_id: Uuid,
    ) -> Result<ConversationWithMembers, crate::error::AppError> {
        // Security check: verify requesting user is a member
        let is_member = Self::is_member(db, conversation_id, requesting_user_id).await?;
        if !is_member {
            return Err(crate::error::AppError::Config(
                "You are not a member of this conversation".into(),
            ));
        }

        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        // Get conversation details (derived fields)
        let conv_row = client.query_one(
            r#"
            SELECT
              c.id AS id,
              (
                SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id = c.id
              ) AS member_count,
              (
                SELECT m.id FROM messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1
              ) AS last_message_id
            FROM conversations c
            WHERE c.id = $1 AND c.deleted_at IS NULL
            "#,
            &[&conversation_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?;

        let id: Uuid = conv_row.get("id");
        let member_count: i32 = conv_row.get("member_count");
        let last_message_id: Option<Uuid> = conv_row.get("last_message_id");

        // Get all members of the conversation
        let member_rows = client.query(
            r#"
            SELECT user_id, role, joined_at, last_read_at, is_muted
            FROM conversation_members
            WHERE conversation_id = $1
            ORDER BY joined_at ASC
            "#,
            &[&conversation_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get members: {e}")))?;

        let members = member_rows
            .into_iter()
            .map(|row| {
                let user_id: Uuid = row.get("user_id");
                let role: String = row.get("role");
                let joined_at: DateTime<Utc> = row.get("joined_at");
                let last_read_at: Option<DateTime<Utc>> = row.get("last_read_at");
                let is_muted: bool = row.get("is_muted");
                ConversationMember {
                    user_id,
                    role,
                    joined_at,
                    last_read_at,
                    is_muted,
                }
            })
            .collect();

        Ok(ConversationWithMembers {
            id,
            member_count,
            last_message_id,
            members,
        })
    }

    /// Mark conversation as read by user (update last_read_at timestamp)
    pub async fn mark_as_read(
        db: &Pool,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        // Verify user is member
        if !Self::is_member(db, conversation_id, user_id).await? {
            return Err(crate::error::AppError::Forbidden);
        }

        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        client.execute(
            "UPDATE conversation_members SET last_read_at = NOW() WHERE conversation_id = $1 AND user_id = $2",
            &[&conversation_id, &user_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("mark read: {e}")))?;

        Ok(())
    }

    /// Create a group conversation with specified members and creator as owner
    /// Parameters:
    ///   - creator_id: User creating the group (becomes owner)
    ///   - name: Group name
    ///   - description: Optional group description
    ///   - avatar_url: Optional group avatar URL
    ///   - member_ids: List of additional members to add (creator is always added as owner)
    ///   - privacy_mode: Privacy mode (default: strict_e2e)
    #[allow(clippy::too_many_arguments)]
    pub async fn create_group_conversation(
        db: &Pool,
        auth_client: &AuthClient,
        creator_id: Uuid,
        name: String,
        description: Option<String>,
        avatar_url: Option<String>,
        member_ids: Vec<Uuid>,
        privacy_mode: Option<PrivacyMode>,
    ) -> Result<Uuid, crate::error::AppError> {
        // Validate inputs
        if name.trim().is_empty() {
            return Err(crate::error::AppError::Config(
                "Group name cannot be empty".into(),
            ));
        }
        if name.len() > 255 {
            return Err(crate::error::AppError::Config(
                "Group name too long (max 255)".into(),
            ));
        }
        if let Some(ref desc) = description {
            if desc.len() > 1000 {
                return Err(crate::error::AppError::Config(
                    "Group description too long (max 1000)".into(),
                ));
            }
        }

        // Calculate total member count (creator + members, deduplicated)
        let mut all_members = vec![creator_id];
        for member_id in &member_ids {
            if member_id != &creator_id && !all_members.contains(member_id) {
                all_members.push(*member_id);
            }
        }

        // Validate all users exist via identity-service (replaces FK constraint validation)
        // Single-writer principle: identity-service owns users table
        for user_id in &all_members {
            let exists = auth_client.user_exists(*user_id).await.map_err(|e| {
                tracing::error!(user_id = %user_id, error = %e, "auth-service user_exists failed");
                crate::error::AppError::ServiceUnavailable(format!(
                    "Failed to check user existence via auth-service: {e}"
                ))
            })?;
            if !exists {
                return Err(crate::error::AppError::BadRequest(format!(
                    "User {} does not exist",
                    user_id
                )));
            }
        }

        let conversation_id = Uuid::new_v4();
        let privacy = privacy_mode.unwrap_or_default();
        let privacy_str = match privacy {
            PrivacyMode::StrictE2e => "strict_e2e",
            PrivacyMode::SearchEnabled => "search_enabled",
        };

        let mut client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;
        let tx = client.transaction().await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;
        let member_count = all_members.len() as i32;

        // Create conversation
        tx.execute(
            r#"
            INSERT INTO conversations (id, kind, name, description, avatar_url, member_count, privacy_mode, admin_key_version)
            VALUES ($1, 'group', $2, $3, $4, $5, $6::privacy_mode, 1)
            "#,
            &[&conversation_id, &name, &description, &avatar_url, &member_count, &privacy_str]
        )
        .await
        .map_err(|e| {
            crate::error::AppError::StartServer(format!("create group conversation: {e}"))
        })?;

        // Add members - creator as owner, others as members
        for member_id in &all_members {
            let role = if member_id == &creator_id {
                "owner"
            } else {
                "member"
            };

            tx.execute(
                "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
                &[&conversation_id, member_id, &role]
            )
            .await
            .map_err(|e| {
                crate::error::AppError::StartServer(format!("add member {}: {e}", member_id))
            })?;
        }

        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("commit: {e}")))?;

        Ok(conversation_id)
    }

    /// Delete/dissolve a group conversation (owner permission required)
    /// Only group conversations can be deleted
    /// Removes all members and deletes the conversation
    pub async fn delete_group_conversation(
        db: &Pool,
        conversation_id: Uuid,
        requester_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        let mut client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        // Get conversation kind to ensure it's a group
        let conv_row = client.query_opt(
            "SELECT kind FROM conversations WHERE id = $1 AND deleted_at IS NULL",
            &[&conversation_id],
        )
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?
            .ok_or_else(|| crate::error::AppError::Config("Conversation not found".into()))?;

        let kind: String = conv_row.get("kind");

        if kind != "group" {
            return Err(crate::error::AppError::Config(
                "Only group conversations can be deleted".into(),
            ));
        }

        // Verify requester is owner
        let member_row = client.query_opt(
            "SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
            &[&conversation_id, &requester_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get member: {e}")))?
        .ok_or(crate::error::AppError::Forbidden)?;

        let role: String = member_row.get("role");
        if role != "owner" {
            return Err(crate::error::AppError::Forbidden);
        }

        let tx = client.transaction().await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;

        // Soft delete the conversation (preserve members/messages for audit)
        tx.execute(
            "UPDATE conversations SET deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND deleted_at IS NULL",
            &[&conversation_id],
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("delete conversation: {e}")))?;

        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("commit: {e}")))?;

        Ok(())
    }

    /// Remove a member from a conversation (user leaves)
    /// If removing self and conversation is a group, user leaves
    /// If removing other user from group, requires admin/owner permission
    pub async fn remove_member(
        db: &Pool,
        conversation_id: Uuid,
        member_id: Uuid,
        requester_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        // Get conversation kind
        let conv_row = client.query_opt(
            "SELECT kind FROM conversations WHERE id = $1 AND deleted_at IS NULL",
            &[&conversation_id],
        )
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?
            .ok_or_else(|| crate::error::AppError::Config("Conversation not found".into()))?;

        let kind: String = conv_row.get("kind");

        if kind == "direct" && member_id != requester_id {
            return Err(crate::error::AppError::Forbidden);
        }

        // If removing someone else, need permission check
        if member_id != requester_id {
            // Get requester's role
            let requester_row = client.query_opt(
                "SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
                &[&conversation_id, &requester_id]
            )
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get requester: {e}")))?
            .ok_or(crate::error::AppError::Forbidden)?;

            let requester_role: String = requester_row.get("role");
            // Only admin and owner can remove members
            if requester_role != "admin" && requester_role != "owner" {
                return Err(crate::error::AppError::Forbidden);
            }

            // Cannot remove owner
            let member_row = client.query_opt(
                "SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
                &[&conversation_id, &member_id]
            )
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get member: {e}")))?
            .ok_or_else(|| crate::error::AppError::Config("Member not found".into()))?;

            let member_role: String = member_row.get("role");
            if member_role == "owner" {
                return Err(crate::error::AppError::Config(
                    "Cannot remove the group owner".into(),
                ));
            }
        }

        // Remove member
        let result = client.execute(
            "DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
            &[&conversation_id, &member_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("delete member: {e}")))?;

        if result == 0 {
            return Err(crate::error::AppError::Config("Member not found".into()));
        }

        // Update member count
        client.execute(
            "UPDATE conversations SET member_count = member_count - 1 WHERE id = $1 AND deleted_at IS NULL AND member_count > 0",
            &[&conversation_id]
        )
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update count: {e}")))?;

        Ok(())
    }

    /// Get conversation type and basic info
    pub async fn get_conversation_type(
        db: &Pool,
        conversation_id: Uuid,
    ) -> Result<String, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        let row = client.query_opt(
            "SELECT kind FROM conversations WHERE id = $1 AND deleted_at IS NULL",
            &[&conversation_id],
        )
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?
            .ok_or_else(|| crate::error::AppError::Config("Conversation not found".into()))?;

        Ok(row.get("kind"))
    }

    pub async fn get_privacy_mode(
        db: &Pool,
        conversation_id: Uuid,
    ) -> Result<PrivacyMode, crate::error::AppError> {
        let client = db.get().await.map_err(|e| {
            crate::error::AppError::StartServer(format!("get client: {e}"))
        })?;

        let value: Option<String> =
            client.query_opt(
                "SELECT privacy_mode::text FROM conversations WHERE id = $1 AND deleted_at IS NULL",
                &[&conversation_id],
            )
                .await
                .map_err(|e| crate::error::AppError::StartServer(format!("get privacy: {e}")))?
                .map(|row| row.get(0));

        value
            .map(|v| PrivacyMode::from_str(&v))
            .ok_or(crate::error::AppError::NotFound)
    }
}

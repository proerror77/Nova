use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres, Row};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PrivacyMode {
    #[serde(rename = "strict_e2e")]
    StrictE2e,
    #[serde(rename = "search_enabled")]
    SearchEnabled,
}

impl Default for PrivacyMode {
    fn default() -> Self {
        PrivacyMode::StrictE2e
    }
}

impl PrivacyMode {
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
    pub async fn create_direct_conversation(
        db: &Pool<Postgres>,
        a: Uuid,
        b: Uuid,
    ) -> Result<Uuid, crate::error::AppError> {
        let id = Uuid::new_v4();
        let mut tx = db
            .begin()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;
        // Note: Do not attempt to upsert into the canonical users table here.
        // The users table is owned by user-service and may have stricter NOT NULL
        // constraints (e.g., password_hash). Assume provided user IDs already exist
        // and let FK constraints enforce integrity.
        // Insert conversation using user-service schema
        // conversations(id, conversation_type, created_by)
        sqlx::query(
            "INSERT INTO conversations (id, conversation_type, created_by) VALUES ($1, 'direct', $2)",
        )
        .bind(id)
        .bind(a)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            crate::error::AppError::StartServer(format!("insert conversation: {e}"))
        })?;
        sqlx::query(
            "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'member'), ($1, $3, 'member') ON CONFLICT DO NOTHING"
        )
        .bind(id)
        .bind(a)
        .bind(b)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert members: {e}")))?;
        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("commit: {e}")))?;
        Ok(id)
    }

    pub async fn get_conversation_db(
        db: &Pool<Postgres>,
        id: Uuid,
    ) -> Result<ConversationDetails, crate::error::AppError> {
        // Compute derived fields against user-service schema
        let r = sqlx::query(
            r#"
            SELECT
              $1::uuid AS id,
              (
                SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id = $1
              ) AS member_count,
              (
                SELECT m.id FROM messages m WHERE m.conversation_id = $1 ORDER BY m.created_at DESC LIMIT 1
              ) AS last_message_id
            "#,
        )
        .bind(id)
        .fetch_one(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?;

        let id: Uuid = r.get("id");
        let member_count: i32 = r.get("member_count");
        let last_message_id: Option<Uuid> = r.try_get("last_message_id").ok();

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
        db: &Pool<Postgres>,
        user_id: Uuid,
    ) -> Result<Vec<ConversationDetails>, crate::error::AppError> {
        // Query conversations where user is a member, ordered by most recent first
        let rows = sqlx::query(
            r#"
            SELECT c.id, c.member_count, c.last_message_id
            FROM conversations c
            JOIN conversation_members cm ON c.id = cm.conversation_id
            WHERE cm.user_id = $1
            ORDER BY c.updated_at DESC
            LIMIT 100
            "#,
        )
        .bind(user_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("list conversations: {e}")))?;

        let conversations = rows
            .into_iter()
            .map(|row| {
                let id: Uuid = row.get("id");
                let member_count: i32 = row.get("member_count");
                let last_message_id: Option<Uuid> = row.try_get("last_message_id").ok();
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
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, crate::error::AppError> {
        let rec = sqlx::query(
            "SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2 LIMIT 1",
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_optional(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("is_member: {e}")))?;
        Ok(rec.is_some())
    }

    /// Get conversation with full member details
    /// Security: Validates that requesting user is a member before returning data
    pub async fn get_conversation_with_members(
        db: &Pool<Postgres>,
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

        // Get conversation details (derived fields)
        let conv_row = sqlx::query(
            r#"
            SELECT
              $1::uuid AS id,
              (
                SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id = $1
              ) AS member_count,
              (
                SELECT m.id FROM messages m WHERE m.conversation_id = $1 ORDER BY m.created_at DESC LIMIT 1
              ) AS last_message_id
            "#,
        )
        .bind(conversation_id)
        .fetch_one(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?;

        let id: Uuid = conv_row.get("id");
        let member_count: i32 = conv_row.get("member_count");
        let last_message_id: Option<Uuid> = conv_row.try_get("last_message_id").ok();

        // Get all members of the conversation
        let member_rows = sqlx::query(
            r#"
            SELECT user_id, role, joined_at, last_read_at, is_muted
            FROM conversation_members
            WHERE conversation_id = $1
            ORDER BY joined_at ASC
            "#,
        )
        .bind(conversation_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get members: {e}")))?;

        let members = member_rows
            .into_iter()
            .map(|row| {
                let user_id: Uuid = row.get("user_id");
                let role: String = row.get("role");
                let joined_at: DateTime<Utc> = row.get("joined_at");
                let last_read_at: Option<DateTime<Utc>> = row.try_get("last_read_at").ok();
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
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        // Verify user is member
        if !Self::is_member(db, conversation_id, user_id).await? {
            return Err(crate::error::AppError::Forbidden);
        }

        sqlx::query(
            "UPDATE conversation_members SET last_read_at = NOW() WHERE conversation_id = $1 AND user_id = $2"
        )
        .bind(conversation_id)
        .bind(user_id)
        .execute(db)
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
    pub async fn create_group_conversation(
        db: &Pool<Postgres>,
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

        let conversation_id = Uuid::new_v4();
        let privacy = privacy_mode.unwrap_or_default();
        let privacy_str = match privacy {
            PrivacyMode::StrictE2e => "strict_e2e",
            PrivacyMode::SearchEnabled => "search_enabled",
        };

        let mut tx = db
            .begin()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;

        // Ensure creator exists
        let creator_username = format!("u_{}", creator_id.to_string()[..8].to_string());
        sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING")
            .bind(creator_id)
            .bind(creator_username)
            .execute(&mut *tx)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("ensure creator: {e}")))?;

        // Ensure all members exist
        for member_id in &member_ids {
            let username = format!("u_{}", member_id.to_string()[..8].to_string());
            sqlx::query(
                "INSERT INTO users (id, username) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING",
            )
            .bind(member_id)
            .bind(username)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                crate::error::AppError::StartServer(format!("ensure member {}: {e}", member_id))
            })?;
        }

        // Calculate total member count (creator + members, deduplicated)
        let mut all_members = vec![creator_id];
        for member_id in &member_ids {
            if member_id != &creator_id && !all_members.contains(member_id) {
                all_members.push(*member_id);
            }
        }
        let member_count = all_members.len() as i32;

        // Create conversation
        sqlx::query(
            r#"
            INSERT INTO conversations (id, kind, name, description, avatar_url, member_count, privacy_mode, admin_key_version)
            VALUES ($1, 'group', $2, $3, $4, $5, $6, 1)
            "#
        )
        .bind(conversation_id)
        .bind(name)
        .bind(description)
        .bind(avatar_url)
        .bind(member_count)
        .bind(privacy_str)
        .execute(&mut *tx)
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

            sqlx::query(
                "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
            )
            .bind(conversation_id)
            .bind(member_id)
            .bind(role)
            .execute(&mut *tx)
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
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        requester_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        // Get conversation kind to ensure it's a group
        let conv_row = sqlx::query("SELECT kind FROM conversations WHERE id = $1")
            .bind(conversation_id)
            .fetch_optional(db)
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
        let member_row = sqlx::query(
            "SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        )
        .bind(conversation_id)
        .bind(requester_id)
        .fetch_optional(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get member: {e}")))?
        .ok_or_else(|| crate::error::AppError::Forbidden)?;

        let role: String = member_row.get("role");
        if role != "owner" {
            return Err(crate::error::AppError::Forbidden);
        }

        let mut tx = db
            .begin()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;

        // Delete all members
        sqlx::query("DELETE FROM conversation_members WHERE conversation_id = $1")
            .bind(conversation_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("delete members: {e}")))?;

        // Delete the conversation
        sqlx::query("DELETE FROM conversations WHERE id = $1")
            .bind(conversation_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                crate::error::AppError::StartServer(format!("delete conversation: {e}"))
            })?;

        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("commit: {e}")))?;

        Ok(())
    }

    /// Remove a member from a conversation (user leaves)
    /// If removing self and conversation is a group, user leaves
    /// If removing other user from group, requires admin/owner permission
    pub async fn remove_member(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        member_id: Uuid,
        requester_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        // Get conversation kind
        let conv_row = sqlx::query("SELECT kind FROM conversations WHERE id = $1")
            .bind(conversation_id)
            .fetch_optional(db)
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
            let requester_row = sqlx::query(
                "SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
            )
            .bind(conversation_id)
            .bind(requester_id)
            .fetch_optional(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get requester: {e}")))?
            .ok_or_else(|| crate::error::AppError::Forbidden)?;

            let requester_role: String = requester_row.get("role");
            // Only admin and owner can remove members
            if requester_role != "admin" && requester_role != "owner" {
                return Err(crate::error::AppError::Forbidden);
            }

            // Cannot remove owner
            let member_row = sqlx::query(
                "SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
            )
            .bind(conversation_id)
            .bind(member_id)
            .fetch_optional(db)
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
        let result = sqlx::query(
            "DELETE FROM conversation_members WHERE conversation_id = $1 AND user_id = $2",
        )
        .bind(conversation_id)
        .bind(member_id)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("delete member: {e}")))?;

        if result.rows_affected() == 0 {
            return Err(crate::error::AppError::Config("Member not found".into()));
        }

        // Update member count
        sqlx::query(
            "UPDATE conversations SET member_count = member_count - 1 WHERE id = $1 AND member_count > 0"
        )
        .bind(conversation_id)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update count: {e}")))?;

        Ok(())
    }

    /// Get conversation type and basic info
    pub async fn get_conversation_type(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
    ) -> Result<String, crate::error::AppError> {
        let row = sqlx::query("SELECT kind FROM conversations WHERE id = $1")
            .bind(conversation_id)
            .fetch_optional(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?
            .ok_or_else(|| crate::error::AppError::Config("Conversation not found".into()))?;

        Ok(row.get("kind"))
    }

    pub async fn get_privacy_mode(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
    ) -> Result<PrivacyMode, crate::error::AppError> {
        let value: Option<String> = sqlx::query_scalar(
            "SELECT privacy_mode::text FROM conversations WHERE id = $1",
        )
        .bind(conversation_id)
        .fetch_optional(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("get privacy: {e}")))?;

        value
            .map(|v| PrivacyMode::from_str(&v))
            .ok_or(crate::error::AppError::NotFound)
    }
}

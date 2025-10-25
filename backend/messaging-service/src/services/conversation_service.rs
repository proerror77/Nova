use uuid::Uuid;
use sqlx::{Pool, Postgres, Row};
use chrono::{DateTime, Utc};

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
    pub async fn create_direct_conversation(db: &Pool<Postgres>, a: Uuid, b: Uuid) -> Result<Uuid, crate::error::AppError> {
        let id = Uuid::new_v4();
        let mut tx = db.begin().await.map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;
        // Dev convenience: ensure users exist to satisfy FK (idempotent). Always safe due to ON CONFLICT DO NOTHING.
        let uname_a = format!("u_{}", &a.to_string()[..8]);
        let uname_b = format!("u_{}", &b.to_string()[..8]);
        sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING")
            .bind(a)
            .bind(uname_a)
            .execute(&mut *tx)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("ensure user a: {e}")))?;
        sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING")
            .bind(b)
            .bind(uname_b)
            .execute(&mut *tx)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("ensure user b: {e}")))?;
        // kind: 'direct'
        sqlx::query(
            "INSERT INTO conversations (id, kind, member_count) VALUES ($1, 'direct', 2)"
        )
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert conversation: {e}")))?;
        sqlx::query(
            "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'member'), ($1, $3, 'member')"
        )
        .bind(id)
        .bind(a)
        .bind(b)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert members: {e}")))?;
        tx.commit().await.map_err(|e| crate::error::AppError::StartServer(format!("commit: {e}")))?;
        Ok(id)
    }

    pub async fn get_conversation_db(db: &Pool<Postgres>, id: Uuid) -> Result<ConversationDetails, crate::error::AppError> {
        let r = sqlx::query("SELECT id, member_count, last_message_id FROM conversations WHERE id = $1")
            .bind(id)
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?;
        let id: Uuid = r.get("id");
        let member_count: i32 = r.get("member_count");
        let last_message_id: Option<Uuid> = r.try_get("last_message_id").ok();
        Ok(ConversationDetails { id, member_count, last_message_id })
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
            "#
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

    pub async fn is_member(db: &Pool<Postgres>, conversation_id: Uuid, user_id: Uuid) -> Result<bool, crate::error::AppError> {
        let rec = sqlx::query(
            "SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2 LIMIT 1"
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

        // Get conversation details
        let conv_row = sqlx::query(
            "SELECT id, member_count, last_message_id FROM conversations WHERE id = $1"
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
            "#
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
}

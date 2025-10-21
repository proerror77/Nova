// Messaging Repository: Database operations for messaging system
// Phase 7B Feature 2: Data access layer

use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::error::AppError;

// ============================================
// Domain Models
// ============================================

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "VARCHAR", rename_all = "lowercase")]
pub enum ConversationType {
    #[sqlx(rename = "direct")]
    Direct,
    #[sqlx(rename = "group")]
    Group,
}

#[derive(Debug, Clone, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "VARCHAR", rename_all = "lowercase")]
pub enum MemberRole {
    #[sqlx(rename = "owner")]
    Owner,
    #[sqlx(rename = "admin")]
    Admin,
    #[sqlx(rename = "member")]
    Member,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Conversation {
    pub id: Uuid,
    pub conversation_type: ConversationType,
    pub name: Option<String>,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ConversationMember {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub user_id: Uuid,
    pub role: MemberRole,
    pub joined_at: DateTime<Utc>,
    pub last_read_message_id: Option<Uuid>,
    pub last_read_at: Option<DateTime<Utc>>,
    pub is_muted: bool,
    pub is_archived: bool,
}

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Message {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub encrypted_content: String,
    pub nonce: String,
    pub message_type: String,
    pub created_at: DateTime<Utc>,
    pub edited_at: Option<DateTime<Utc>>,
    pub deleted_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MessageType {
    Text,
    System,
}

impl ToString for MessageType {
    fn to_string(&self) -> String {
        match self {
            MessageType::Text => "text".to_string(),
            MessageType::System => "system".to_string(),
        }
    }
}

// ============================================
// Repository
// ============================================

pub struct MessagingRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> MessagingRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    // ============================================
    // Conversation Operations
    // ============================================

    /// Create a new conversation
    pub async fn create_conversation(
        &self,
        created_by: Uuid,
        conversation_type: ConversationType,
        name: Option<String>,
    ) -> Result<Conversation, AppError> {
        let conversation = sqlx::query_as::<_, Conversation>(
            r#"
            INSERT INTO conversations (conversation_type, name, created_by)
            VALUES ($1, $2, $3)
            RETURNING id, conversation_type, name, created_by, created_at, updated_at
            "#,
        )
        .bind(conversation_type)
        .bind(name)
        .bind(created_by)
        .fetch_one(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(conversation)
    }

    /// Get conversation by ID
    pub async fn get_conversation(&self, conversation_id: Uuid) -> Result<Conversation, AppError> {
        let conversation = sqlx::query_as::<_, Conversation>(
            r#"
            SELECT id, conversation_type, name, created_by, created_at, updated_at
            FROM conversations
            WHERE id = $1
            "#,
        )
        .bind(conversation_id)
        .fetch_one(self.pool)
        .await
        .map_err(|e| AppError::NotFound(format!("Conversation not found: {}", e)))?;

        Ok(conversation)
    }

    /// Get all members of a conversation
    pub async fn get_conversation_members(
        &self,
        conversation_id: Uuid,
    ) -> Result<Vec<ConversationMember>, AppError> {
        let members = sqlx::query_as::<_, ConversationMember>(
            r#"
            SELECT id, conversation_id, user_id, role, joined_at,
                   last_read_message_id, last_read_at, is_muted, is_archived
            FROM conversation_members
            WHERE conversation_id = $1
            ORDER BY joined_at ASC
            "#,
        )
        .bind(conversation_id)
        .fetch_all(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(members)
    }

    /// Check if user is a member of conversation
    pub async fn is_conversation_member(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, AppError> {
        let result: Option<(bool,)> = sqlx::query_as(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM conversation_members
                WHERE conversation_id = $1 AND user_id = $2
            )
            "#,
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_optional(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(result.map(|(exists,)| exists).unwrap_or(false))
    }

    /// Get specific conversation member
    pub async fn get_conversation_member(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<ConversationMember, AppError> {
        let member = sqlx::query_as::<_, ConversationMember>(
            r#"
            SELECT id, conversation_id, user_id, role, joined_at,
                   last_read_message_id, last_read_at, is_muted, is_archived
            FROM conversation_members
            WHERE conversation_id = $1 AND user_id = $2
            "#,
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_one(self.pool)
        .await
        .map_err(|e| AppError::NotFound(format!("Member not found: {}", e)))?;

        Ok(member)
    }

    // ============================================
    // Conversation Member Operations
    // ============================================

    /// Add a member to a conversation
    pub async fn add_member(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        role: MemberRole,
    ) -> Result<ConversationMember, AppError> {
        let member = sqlx::query_as::<_, ConversationMember>(
            r#"
            INSERT INTO conversation_members (conversation_id, user_id, role)
            VALUES ($1, $2, $3)
            ON CONFLICT (conversation_id, user_id) DO NOTHING
            RETURNING id, conversation_id, user_id, role, joined_at,
                      last_read_message_id, last_read_at, is_muted, is_archived
            "#,
        )
        .bind(conversation_id)
        .bind(user_id)
        .bind(role)
        .fetch_one(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(member)
    }

    /// Remove a member from a conversation
    pub async fn remove_member(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), AppError> {
        sqlx::query(
            r#"
            DELETE FROM conversation_members
            WHERE conversation_id = $1 AND user_id = $2
            "#,
        )
        .bind(conversation_id)
        .bind(user_id)
        .execute(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(())
    }

    /// Update member settings (mute, archive)
    pub async fn update_member_settings(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        is_muted: Option<bool>,
        is_archived: Option<bool>,
    ) -> Result<ConversationMember, AppError> {
        // Build dynamic UPDATE query
        let mut query = String::from("UPDATE conversation_members SET ");
        let mut updates = Vec::new();
        let mut param_index = 1;

        if let Some(muted) = is_muted {
            updates.push(format!("is_muted = ${}", param_index));
            param_index += 1;
        }

        if let Some(archived) = is_archived {
            updates.push(format!("is_archived = ${}", param_index));
            param_index += 1;
        }

        query.push_str(&updates.join(", "));
        query.push_str(&format!(
            " WHERE conversation_id = ${} AND user_id = ${}",
            param_index,
            param_index + 1
        ));
        query.push_str(" RETURNING id, conversation_id, user_id, role, joined_at, last_read_message_id, last_read_at, is_muted, is_archived");

        let mut q = sqlx::query_as::<_, ConversationMember>(&query);

        if let Some(muted) = is_muted {
            q = q.bind(muted);
        }
        if let Some(archived) = is_archived {
            q = q.bind(archived);
        }

        q = q.bind(conversation_id).bind(user_id);

        let member = q
            .fetch_one(self.pool)
            .await
            .map_err(|e| AppError::Database(e))?;

        Ok(member)
    }

    // ============================================
    // Message Operations
    // ============================================

    /// Create a new message
    pub async fn create_message(
        &self,
        conversation_id: Uuid,
        sender_id: Uuid,
        encrypted_content: String,
        nonce: String,
        message_type: MessageType,
    ) -> Result<Message, AppError> {
        let message = sqlx::query_as::<_, Message>(
            r#"
            INSERT INTO messages (conversation_id, sender_id, encrypted_content, nonce, message_type)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, conversation_id, sender_id, encrypted_content, nonce, message_type, created_at, edited_at, deleted_at
            "#,
        )
        .bind(conversation_id)
        .bind(sender_id)
        .bind(encrypted_content)
        .bind(nonce)
        .bind(message_type.to_string())
        .fetch_one(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(message)
    }

    /// Get message by ID
    pub async fn get_message(&self, message_id: Uuid) -> Result<Message, AppError> {
        let message = sqlx::query_as::<_, Message>(
            r#"
            SELECT id, conversation_id, sender_id, encrypted_content, nonce, message_type, created_at, edited_at, deleted_at
            FROM messages
            WHERE id = $1
            "#,
        )
        .bind(message_id)
        .fetch_one(self.pool)
        .await
        .map_err(|e| AppError::NotFound(format!("Message not found: {}", e)))?;

        Ok(message)
    }

    /// Get message history (cursor-based pagination)
    pub async fn get_messages(
        &self,
        conversation_id: Uuid,
        limit: i64,
        before: Option<Uuid>, // Cursor (message_id)
    ) -> Result<Vec<Message>, AppError> {
        let messages = if let Some(before_id) = before {
            // Paginated query using cursor
            sqlx::query_as::<_, Message>(
                r#"
                SELECT id, conversation_id, sender_id, encrypted_content, nonce, message_type, created_at, edited_at, deleted_at
                FROM messages
                WHERE conversation_id = $1
                  AND created_at < (SELECT created_at FROM messages WHERE id = $2)
                ORDER BY created_at DESC
                LIMIT $3
                "#,
            )
            .bind(conversation_id)
            .bind(before_id)
            .bind(limit)
            .fetch_all(self.pool)
            .await
        } else {
            // Initial query (most recent messages)
            sqlx::query_as::<_, Message>(
                r#"
                SELECT id, conversation_id, sender_id, encrypted_content, nonce, message_type, created_at, edited_at, deleted_at
                FROM messages
                WHERE conversation_id = $1
                ORDER BY created_at DESC
                LIMIT $2
                "#,
            )
            .bind(conversation_id)
            .bind(limit)
            .fetch_all(self.pool)
            .await
        }
        .map_err(|e| AppError::Database(e))?;

        Ok(messages)
    }

    /// Update last_read_message_id for a user
    pub async fn update_last_read(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        message_id: Uuid,
    ) -> Result<(), AppError> {
        sqlx::query(
            r#"
            UPDATE conversation_members
            SET last_read_message_id = $1, last_read_at = NOW()
            WHERE conversation_id = $2 AND user_id = $3
            "#,
        )
        .bind(message_id)
        .bind(conversation_id)
        .bind(user_id)
        .execute(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(())
    }

    /// Get unread message count
    pub async fn get_unread_count(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<i64, AppError> {
        let result: (i64,) = sqlx::query_as(
            r#"
            SELECT get_unread_count($1, $2)
            "#,
        )
        .bind(conversation_id)
        .bind(user_id)
        .fetch_one(self.pool)
        .await
        .map_err(|e| AppError::Database(e))?;

        Ok(result.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // TODO: Integration tests for repository
    // Requires test database setup

    #[tokio::test]
    #[ignore] // Requires database
    async fn test_create_conversation() {
        // TODO: Implement test
        unimplemented!("T217: Add integration test for create_conversation");
    }

    #[tokio::test]
    #[ignore] // Requires database
    async fn test_message_pagination() {
        // TODO: Implement test
        unimplemented!("T217: Add integration test for pagination");
    }
}

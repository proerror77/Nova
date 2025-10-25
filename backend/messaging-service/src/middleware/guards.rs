//! Authorization guards that enforce permission checks at the type level
//! This prevents developers from accidentally bypassing authorization

use axum::{
    async_trait,
    extract::FromRequestParts,
    http::request::Parts,
};
use uuid::Uuid;
use sqlx::PgPool;

use crate::error::AppError;

/// Represents an authenticated user extracted from JWT claims
#[derive(Debug, Clone)]
pub struct User {
    pub id: Uuid,
}

#[async_trait]
impl<S> FromRequestParts<S> for User
where
    S: Send + Sync,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        // Extract from JWT claim in extensions (set by auth middleware)
        let user_id = parts
            .extensions
            .get::<Uuid>()
            .cloned()
            .ok_or(AppError::Unauthorized)?;

        Ok(User { id: user_id })
    }
}

/// Represents a verified conversation member with all permission context
#[derive(Debug, Clone)]
pub struct ConversationMember {
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    pub role: String,  // "member" or "admin"
    pub is_muted: bool,
    pub can_send_messages: bool,
    pub can_delete_others_messages: bool,  // Only admins
}

impl ConversationMember {
    /// Factory method to create and verify a conversation member
    /// This performs ONE database query to check all permissions
    pub async fn verify(
        db: &PgPool,
        user_id: Uuid,
        conversation_id: Uuid,
    ) -> Result<Self, AppError> {
        let member = sqlx::query_as::<_, ConversationMemberRecord>(
            r#"
            SELECT
                user_id,
                conversation_id,
                role,
                is_muted,
                EXISTS(
                    SELECT 1 FROM conversations
                    WHERE id = conversation_members.conversation_id
                    AND deleted_at IS NULL
                ) AS conversation_exists,
                (role = 'admin') AS is_admin
            FROM conversation_members
            WHERE user_id = $1 AND conversation_id = $2
            "#,
        )
        .bind(user_id)
        .bind(conversation_id)
        .fetch_optional(db)
        .await
        .map_err(|_| AppError::Database(sqlx::Error::RowNotFound))?
        .ok_or(AppError::Unauthorized)?;

        Ok(ConversationMember {
            user_id: member.user_id,
            conversation_id: member.conversation_id,
            role: member.role,
            is_muted: member.is_muted,
            can_send_messages: member.conversation_exists && !member.is_muted,
            can_delete_others_messages: member.is_admin,
        })
    }

    pub fn is_admin(&self) -> bool {
        self.role == "admin"
    }

    pub fn can_send(&self) -> Result<(), AppError> {
        if self.is_muted {
            return Err(AppError::Forbidden);
        }
        if !self.can_send_messages {
            return Err(AppError::Forbidden);
        }
        Ok(())
    }

    pub fn can_delete_message(&self, is_own_message: bool) -> Result<(), AppError> {
        if is_own_message {
            // Users can delete their own messages (enforced at service layer)
            return Ok(());
        }
        if !self.can_delete_others_messages {
            return Err(AppError::Forbidden);
        }
        Ok(())
    }
}

// Helper struct for querying (similar to ConversationMember but with DB fields)
#[derive(sqlx::FromRow)]
struct ConversationMemberRecord {
    user_id: Uuid,
    conversation_id: Uuid,
    role: String,
    is_muted: bool,
    conversation_exists: bool,
    is_admin: bool,
}

/// Represents an admin of a conversation
/// This is a stricter guard than ConversationMember
#[derive(Debug, Clone)]
pub struct ConversationAdmin {
    pub inner: ConversationMember,
}

impl ConversationAdmin {
    /// Factory method to create and verify a conversation admin
    pub async fn verify(
        db: &PgPool,
        user_id: Uuid,
        conversation_id: Uuid,
    ) -> Result<Self, AppError> {
        let member = ConversationMember::verify(db, user_id, conversation_id).await?;

        if !member.is_admin() {
            return Err(AppError::Forbidden);
        }

        Ok(ConversationAdmin { inner: member })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_member_can_send_when_not_muted() {
        let member = ConversationMember {
            user_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            role: "member".to_string(),
            is_muted: false,
            can_send_messages: true,
            can_delete_others_messages: false,
        };

        assert!(member.can_send().is_ok());
    }

    #[test]
    fn test_member_cannot_send_when_muted() {
        let member = ConversationMember {
            user_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            role: "member".to_string(),
            is_muted: true,
            can_send_messages: false,
            can_delete_others_messages: false,
        };

        assert!(member.can_send().is_err());
    }

    #[test]
    fn test_member_cannot_delete_others_messages() {
        let member = ConversationMember {
            user_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            role: "member".to_string(),
            is_muted: false,
            can_send_messages: true,
            can_delete_others_messages: false,
        };

        let other_user_id = Uuid::new_v4();
        assert!(member.can_delete_message(false).is_err());
        assert!(member.can_delete_message(true).is_ok()); // Own message is ok
    }

    #[test]
    fn test_admin_can_delete_others_messages() {
        let admin = ConversationMember {
            user_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            role: "admin".to_string(),
            is_muted: false,
            can_send_messages: true,
            can_delete_others_messages: true,
        };

        assert!(admin.can_delete_message(false).is_ok());
        assert!(admin.can_delete_message(true).is_ok());
    }
}

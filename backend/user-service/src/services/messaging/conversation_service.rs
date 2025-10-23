// Conversation Service: Manages conversation creation, listing, and member operations
// Phase 7B Feature 2: T212 - Conversation Manager

use crate::db::messaging::{
    Conversation, ConversationMember, ConversationType, MemberRole, MessagingRepository,
};
use crate::error::AppError;
use sqlx::PgPool;
use uuid::Uuid;

pub struct ConversationService {
    pool: PgPool,
}

impl ConversationService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create a new conversation (1:1 or group)
    /// For direct conversations, checks if one already exists between the same users
    pub async fn create_conversation(
        &self,
        creator_id: Uuid,
        conversation_type: ConversationType,
        name: Option<String>,
        participant_ids: Vec<Uuid>,
    ) -> Result<Conversation, AppError> {
        // Validation
        if conversation_type == ConversationType::Group && name.is_none() {
            return Err(AppError::BadRequest(
                "Group conversations must have a name".to_string(),
            ));
        }

        if participant_ids.is_empty() {
            return Err(AppError::BadRequest(
                "Conversation must have at least one participant".to_string(),
            ));
        }

        // For direct conversations, check if one already exists
        if conversation_type == ConversationType::Direct {
            if participant_ids.len() != 1 {
                return Err(AppError::BadRequest(
                    "Direct conversations must have exactly 2 participants (creator + 1 other)"
                        .to_string(),
                ));
            }

            // TODO: Check for existing direct conversation
            // If exists, return existing conversation (idempotency)
        }

        // Create conversation
        let repo = MessagingRepository::new(&self.pool);
        let conversation = repo
            .create_conversation(creator_id, conversation_type, name)
            .await?;

        // Add creator as owner
        repo.add_member(conversation.id, creator_id, MemberRole::Owner)
            .await?;

        // Add other participants as members
        for participant_id in participant_ids {
            repo.add_member(conversation.id, participant_id, MemberRole::Member)
                .await?;
        }

        Ok(conversation)
    }

    /// List conversations for a user
    /// Returns conversations sorted by updated_at (most recent first)
    pub async fn list_conversations(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
        include_archived: bool,
    ) -> Result<Vec<ConversationWithMetadata>, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // TODO: Implement repository method
        // Should return:
        // - Conversation details
        // - Last message
        // - Unread count
        // - Member settings (muted, archived)

        unimplemented!("T212: Implement conversation listing")
    }

    /// Get conversation by ID (with member validation)
    pub async fn get_conversation(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<ConversationWithMembers, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Verify user is a member
        let is_member = repo.is_conversation_member(conversation_id, user_id).await?;
        if !is_member {
            return Err(AppError::Authorization(
                "You are not a member of this conversation".to_string(),
            ));
        }

        // Get conversation with members
        let conversation = repo.get_conversation(conversation_id).await?;
        let members = repo.get_conversation_members(conversation_id).await?;

        Ok(ConversationWithMembers {
            conversation,
            members,
        })
    }

    /// Update member settings (mute, archive)
    pub async fn update_member_settings(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        is_muted: Option<bool>,
        is_archived: Option<bool>,
    ) -> Result<ConversationMember, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Verify user is a member
        let is_member = repo.is_conversation_member(conversation_id, user_id).await?;
        if !is_member {
            return Err(AppError::Authorization(
                "You are not a member of this conversation".to_string(),
            ));
        }

        // Update settings
        repo.update_member_settings(conversation_id, user_id, is_muted, is_archived)
            .await
    }

    /// Add members to a group conversation (owner/admin only)
    pub async fn add_members(
        &self,
        conversation_id: Uuid,
        requester_id: Uuid,
        user_ids: Vec<Uuid>,
    ) -> Result<Vec<ConversationMember>, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Verify requester is owner or admin
        let member = repo
            .get_conversation_member(conversation_id, requester_id)
            .await?;
        if member.role != MemberRole::Owner && member.role != MemberRole::Admin {
            return Err(AppError::Authorization(
                "Only owners and admins can add members".to_string(),
            ));
        }

        // Verify conversation is a group
        let conversation = repo.get_conversation(conversation_id).await?;
        if conversation.conversation_type != ConversationType::Group {
            return Err(AppError::BadRequest(
                "Cannot add members to direct conversations".to_string(),
            ));
        }

        // Add members
        let mut added_members = Vec::new();
        for user_id in user_ids {
            let member = repo
                .add_member(conversation_id, user_id, MemberRole::Member)
                .await?;
            added_members.push(member);
        }

        // TODO: Send system message: "User X added User Y"
        // TODO: Regenerate group encryption key and distribute to new members

        Ok(added_members)
    }

    /// Remove member from group conversation (owner/admin only, or self)
    pub async fn remove_member(
        &self,
        conversation_id: Uuid,
        requester_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // User can remove themselves
        if requester_id == user_id {
            repo.remove_member(conversation_id, user_id).await?;
            // TODO: Send system message: "User X left the conversation"
            return Ok(());
        }

        // Otherwise, verify requester is owner or admin
        let member = repo
            .get_conversation_member(conversation_id, requester_id)
            .await?;
        if member.role != MemberRole::Owner && member.role != MemberRole::Admin {
            return Err(AppError::Authorization(
                "Only owners and admins can remove members".to_string(),
            ));
        }

        repo.remove_member(conversation_id, user_id).await?;
        // TODO: Send system message: "User X removed User Y"

        Ok(())
    }
}

// ============================================
// DTOs (Data Transfer Objects)
// ============================================

#[derive(Debug, Clone)]
pub struct ConversationWithMetadata {
    pub conversation: Conversation,
    pub last_message: Option<MessagePreview>,
    pub unread_count: i64,
    pub is_muted: bool,
    pub is_archived: bool,
}

#[derive(Debug, Clone)]
pub struct MessagePreview {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub encrypted_content: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
pub struct ConversationWithMembers {
    pub conversation: Conversation,
    pub members: Vec<ConversationMember>,
}

#[derive(Debug, Clone)]
pub struct ConversationMemberWithUser {
    pub user_id: Uuid,
    pub username: String,
    pub role: MemberRole,
    pub joined_at: chrono::DateTime<chrono::Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    // TODO: Unit tests for conversation service
    // - create_conversation: direct and group
    // - list_conversations: sorting, pagination, archived filter
    // - add_members: permission checks
    // - update_settings: mute, archive

    #[tokio::test]
    async fn test_create_direct_conversation() {
        // TODO: Implement test
        unimplemented!("T217: Add unit test for create_conversation");
    }

    #[tokio::test]
    async fn test_group_conversation_requires_name() {
        // TODO: Implement test
        unimplemented!("T217: Add unit test for validation");
    }
}

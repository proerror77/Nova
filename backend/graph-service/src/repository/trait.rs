use anyhow::Result;
use std::collections::HashMap;
use uuid::Uuid;

/// Trait defining the interface for graph repository operations.
/// Both GraphRepository (Neo4j-only) and DualWriteRepository (PostgreSQL + Neo4j) implement this.
#[async_trait::async_trait]
pub trait GraphRepositoryTrait: Send + Sync {
    /// Create a follow relationship
    async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()>;

    /// Delete a follow relationship
    async fn delete_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()>;

    /// Create a mute relationship
    async fn create_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()>;

    /// Delete a mute relationship
    async fn delete_mute(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<()>;

    /// Create a block relationship
    async fn create_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()>;

    /// Delete a block relationship
    async fn delete_block(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<()>;

    /// Get followers of a user with pagination
    /// Returns: (follower_ids, total_count, has_more)
    async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)>;

    /// Get users that a user is following with pagination
    /// Returns: (following_ids, total_count, has_more)
    async fn get_following(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)>;

    /// Check if follower is following followee
    async fn is_following(&self, follower_id: Uuid, followee_id: Uuid) -> Result<bool>;

    /// Check if muter has muted mutee
    async fn is_muted(&self, muter_id: Uuid, mutee_id: Uuid) -> Result<bool>;

    /// Check if blocker has blocked blocked
    async fn is_blocked(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool>;

    /// Check if either user has blocked the other (bidirectional)
    /// Returns: (has_block, a_blocked_b, b_blocked_a)
    async fn has_block_between(&self, user_a: Uuid, user_b: Uuid) -> Result<(bool, bool, bool)> {
        let a_blocked_b = self.is_blocked(user_a, user_b).await?;
        let b_blocked_a = self.is_blocked(user_b, user_a).await?;
        Ok((a_blocked_b || b_blocked_a, a_blocked_b, b_blocked_a))
    }

    /// Get list of users blocked by a user
    /// Returns: (blocked_user_ids, total_count, has_more)
    async fn get_blocked_users(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)>;

    /// Check if two users are mutual followers
    /// Returns: (are_mutuals, a_follows_b, b_follows_a)
    async fn are_mutual_followers(&self, user_a: Uuid, user_b: Uuid) -> Result<(bool, bool, bool)> {
        let a_follows_b = self.is_following(user_a, user_b).await?;
        let b_follows_a = self.is_following(user_b, user_a).await?;
        Ok((a_follows_b && b_follows_a, a_follows_b, b_follows_a))
    }

    /// Get mutual followers (friends) of a user with pagination
    /// Friends = users who both follow each other
    /// Returns: (friend_ids, total_count, has_more)
    async fn get_mutual_followers(
        &self,
        user_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<Uuid>, i32, bool)>;

    /// Batch check if follower is following multiple followees
    /// Returns: HashMap<followee_id_string, is_following>
    async fn batch_check_following(
        &self,
        follower_id: Uuid,
        followee_ids: Vec<Uuid>,
    ) -> Result<HashMap<String, bool>>;

    /// Health check (optional)
    async fn health_check(&self) -> Result<()> {
        Ok(())
    }
}

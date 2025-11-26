//! Unified cache key schema
//!
//! All services must use these key generators to ensure consistency.
//! Key format: v{VERSION}:{entity}:{identifier}[:sub_key]

use uuid::Uuid;

/// Cache schema version - increment when changing key formats
pub const CACHE_VERSION: u32 = 2;

/// Cache key builder
pub struct CacheKey;

impl CacheKey {
    // ============= Feed Keys =============

    /// Feed cache for a user
    /// Format: v2:feed:{user_id}
    pub fn feed(user_id: Uuid) -> String {
        format!("v{}:feed:{}", CACHE_VERSION, user_id)
    }

    /// Feed snapshot (no TTL, for fallback)
    /// Format: v2:feed:snapshot:{user_id}
    pub fn feed_snapshot(user_id: Uuid) -> String {
        format!("v{}:feed:snapshot:{}", CACHE_VERSION, user_id)
    }

    /// Seen posts tracking
    /// Format: v2:feed:seen:{user_id}
    pub fn feed_seen(user_id: Uuid) -> String {
        format!("v{}:feed:seen:{}", CACHE_VERSION, user_id)
    }

    /// Pattern for all feed keys of a user
    pub fn feed_pattern(user_id: Uuid) -> String {
        format!("v{}:feed:*:{}", CACHE_VERSION, user_id)
    }

    // ============= Graph Keys (Following/Followers) =============

    /// Following list cache
    /// Format: v2:graph:following:{user_id}
    pub fn following(user_id: Uuid) -> String {
        format!("v{}:graph:following:{}", CACHE_VERSION, user_id)
    }

    /// Followers list cache
    /// Format: v2:graph:followers:{user_id}
    pub fn followers(user_id: Uuid) -> String {
        format!("v{}:graph:followers:{}", CACHE_VERSION, user_id)
    }

    /// Is-following relationship cache
    /// Format: v2:graph:is_following:{follower_id}:{followee_id}
    pub fn is_following(follower_id: Uuid, followee_id: Uuid) -> String {
        format!(
            "v{}:graph:is_following:{}:{}",
            CACHE_VERSION, follower_id, followee_id
        )
    }

    /// Is-muted relationship cache
    pub fn is_muted(muter_id: Uuid, mutee_id: Uuid) -> String {
        format!(
            "v{}:graph:is_muted:{}:{}",
            CACHE_VERSION, muter_id, mutee_id
        )
    }

    /// Is-blocked relationship cache
    pub fn is_blocked(blocker_id: Uuid, blocked_id: Uuid) -> String {
        format!(
            "v{}:graph:is_blocked:{}:{}",
            CACHE_VERSION, blocker_id, blocked_id
        )
    }

    /// Pattern for all graph keys of a user (as subject)
    pub fn graph_user_pattern(user_id: Uuid) -> String {
        format!("v{}:graph:*:{}*", CACHE_VERSION, user_id)
    }

    // ============= Post Keys =============

    /// Post metadata cache
    /// Format: v2:post:{post_id}
    pub fn post(post_id: Uuid) -> String {
        format!("v{}:post:{}", CACHE_VERSION, post_id)
    }

    /// User's posts list
    /// Format: v2:posts:user:{user_id}
    pub fn user_posts(user_id: Uuid) -> String {
        format!("v{}:posts:user:{}", CACHE_VERSION, user_id)
    }

    /// Post likes count
    pub fn post_likes(post_id: Uuid) -> String {
        format!("v{}:post:likes:{}", CACHE_VERSION, post_id)
    }

    /// User liked post check
    pub fn user_liked_post(user_id: Uuid, post_id: Uuid) -> String {
        format!("v{}:liked:{}:{}", CACHE_VERSION, user_id, post_id)
    }

    // ============= User Keys =============

    /// User profile cache
    /// Format: v2:user:{user_id}
    pub fn user(user_id: Uuid) -> String {
        format!("v{}:user:{}", CACHE_VERSION, user_id)
    }

    /// User by username lookup
    pub fn user_by_username(username: &str) -> String {
        format!(
            "v{}:user:username:{}",
            CACHE_VERSION,
            username.to_lowercase()
        )
    }

    // ============= Search Keys =============

    /// Search results cache
    /// Format: v2:search:{query_hash}
    pub fn search(query_hash: &str) -> String {
        format!("v{}:search:{}", CACHE_VERSION, query_hash)
    }

    // ============= Utility =============

    /// Extract entity type from key
    pub fn entity_type(key: &str) -> Option<&str> {
        // Format: v{N}:{entity}:...
        let parts: Vec<&str> = key.split(':').collect();
        if parts.len() >= 2 {
            Some(parts[1])
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feed_key() {
        let user_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let key = CacheKey::feed(user_id);
        assert_eq!(key, "v2:feed:550e8400-e29b-41d4-a716-446655440000");
    }

    #[test]
    fn test_following_key() {
        let user_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let key = CacheKey::following(user_id);
        assert_eq!(
            key,
            "v2:graph:following:550e8400-e29b-41d4-a716-446655440000"
        );
    }

    #[test]
    fn test_is_following_key() {
        let follower = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let followee = Uuid::parse_str("660e8400-e29b-41d4-a716-446655440001").unwrap();
        let key = CacheKey::is_following(follower, followee);
        assert!(key.contains(&follower.to_string()));
        assert!(key.contains(&followee.to_string()));
    }

    #[test]
    fn test_entity_type() {
        assert_eq!(CacheKey::entity_type("v2:feed:123"), Some("feed"));
        assert_eq!(
            CacheKey::entity_type("v2:graph:following:123"),
            Some("graph")
        );
        assert_eq!(CacheKey::entity_type("invalid"), None);
    }
}

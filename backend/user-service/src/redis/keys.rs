/// Redis key naming conventions
/// Establishes consistent, predictable key naming across all Redis usage
use uuid::Uuid;

/// Base namespace for all Redis keys
const NOVA_NAMESPACE: &str = "nova";

/// Email verification keys
pub struct EmailVerificationKey;

impl EmailVerificationKey {
    /// Key for forward mapping: user_id + email -> verification token
    /// Used to look up a token by user/email
    pub fn forward(user_id: Uuid, email: &str) -> String {
        format!("{}:verify_email:{}:{}", NOVA_NAMESPACE, user_id, email)
    }

    /// Key for reverse mapping: verification token -> user_id + email
    /// Used to look up user info from a verification token
    pub fn reverse(token: &str) -> String {
        format!("{}:verify_email_token:{}", NOVA_NAMESPACE, token)
    }
}

/// Password reset keys
pub struct PasswordResetKey;

impl PasswordResetKey {
    /// Key for password reset token -> user info mapping
    pub fn token(token_hash: &str) -> String {
        format!("{}:password_reset:{}", NOVA_NAMESPACE, token_hash)
    }
}

/// Token revocation keys (blacklist)
pub struct TokenRevocationKey;

impl TokenRevocationKey {
    /// Key for revoked JWT token blacklist
    pub fn blacklist(token: &str) -> String {
        format!("{}:token_blacklist:{}", NOVA_NAMESPACE, token)
    }
}

/// Feed cache keys
pub struct FeedCacheKey;

impl FeedCacheKey {
    /// Key for cached feed: user_id + offset + limit
    /// Pattern: nova:feed:user_id:offset:limit
    pub fn feed(user_id: Uuid, offset: i64, limit: i32) -> String {
        format!(
            "{}:feed:{}:{}:{}",
            NOVA_NAMESPACE, user_id, offset, limit
        )
    }

    /// Key for suggested users cache
    pub fn suggested_users(user_id: Uuid) -> String {
        format!("{}:suggested_users:{}", NOVA_NAMESPACE, user_id)
    }

    /// Key for trending feed cache
    pub fn trending(user_id: Uuid) -> String {
        format!("{}:trending:{}", NOVA_NAMESPACE, user_id)
    }

    /// Key for hot posts cache
    pub fn hot_posts() -> String {
        format!("{}:hot_posts", NOVA_NAMESPACE)
    }
}

/// Two-Factor Authentication (2FA) temporary session keys
pub struct TwoFactorKey;

impl TwoFactorKey {
    /// Key for 2FA pending session: session_type + session_id
    /// Stores user_id during 2FA verification flow
    /// Pattern: nova:2fa_pending:session_id or nova:2fa_setup:session_id
    pub fn temp_session(session_type: &str, session_id: &str) -> String {
        format!("{}:{}:{}", NOVA_NAMESPACE, session_type, session_id)
    }
}

/// Generic Redis key builder for consistency
pub struct RedisKeyBuilder {
    namespace: String,
}

impl RedisKeyBuilder {
    /// Create a new key builder with default Nova namespace
    pub fn new() -> Self {
        Self {
            namespace: NOVA_NAMESPACE.to_string(),
        }
    }

    /// Build a key from segments
    /// Automatically joins with colons
    pub fn build(segments: &[&str]) -> String {
        let mut key = NOVA_NAMESPACE.to_string();
        for segment in segments {
            key.push(':');
            key.push_str(segment);
        }
        key
    }

    /// Build a key with a custom namespace
    pub fn with_namespace(namespace: &str, segments: &[&str]) -> String {
        let mut key = namespace.to_string();
        for segment in segments {
            key.push(':');
            key.push_str(segment);
        }
        key
    }
}

impl Default for RedisKeyBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_email_verification_keys() {
        let user_id = Uuid::nil();
        let email = "user@example.com";

        let forward = EmailVerificationKey::forward(user_id, email);
        assert!(forward.contains("verify_email"));
        assert!(forward.contains(email));

        let reverse = EmailVerificationKey::reverse("token123");
        assert!(reverse.contains("verify_email_token"));
        assert!(reverse.contains("token123"));
    }

    #[test]
    fn test_password_reset_keys() {
        let key = PasswordResetKey::token("hash123");
        assert!(key.contains("password_reset"));
        assert!(key.contains("hash123"));
    }

    #[test]
    fn test_feed_cache_keys() {
        let user_id = Uuid::nil();

        let feed_key = FeedCacheKey::feed(user_id, 0, 20);
        assert!(feed_key.contains("feed"));
        assert!(feed_key.contains("0"));
        assert!(feed_key.contains("20"));

        let suggested = FeedCacheKey::suggested_users(user_id);
        assert!(suggested.contains("suggested_users"));

        let trending = FeedCacheKey::trending(user_id);
        assert!(trending.contains("trending"));

        let hot = FeedCacheKey::hot_posts();
        assert!(hot.contains("hot_posts"));
    }

    #[test]
    fn test_redis_key_builder() {
        let key = RedisKeyBuilder::build(&["my", "custom", "key"]);
        assert_eq!(key, "nova:my:custom:key");

        let key = RedisKeyBuilder::with_namespace("custom", &["test"]);
        assert_eq!(key, "custom:test");
    }

    #[test]
    fn test_two_factor_keys() {
        let session_key = TwoFactorKey::temp_session("2fa_pending", "session123");
        assert!(session_key.contains("2fa_pending"));
        assert!(session_key.contains("session123"));

        let setup_key = TwoFactorKey::temp_session("2fa_setup", "setup456");
        assert!(setup_key.contains("2fa_setup"));
        assert!(setup_key.contains("setup456"));
    }

    #[test]
    fn test_consistent_key_format() {
        // All keys should follow pattern: nova:category:id:...
        let keys = vec![
            EmailVerificationKey::forward(Uuid::nil(), "test@example.com"),
            FeedCacheKey::hot_posts(),
            TokenRevocationKey::blacklist("token"),
            TwoFactorKey::temp_session("2fa_pending", "session123"),
        ];

        for key in keys {
            assert!(key.starts_with("nova:"), "Key must start with 'nova:' namespace");
            assert!(key.matches(':').count() >= 1, "Key must have at least one colon separator");
        }
    }
}

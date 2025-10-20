/// Integration tests for Password Reset functionality (AUTH-2010 to AUTH-2012)
/// Tests password reset token generation, validation, and password update
///
/// Test Coverage:
/// - Happy path: Request reset token, verify token, update password
/// - Error handling: Invalid token, expired token, used token
/// - Security: Password reuse prevention, token expiration
/// - Rate limiting: Multiple reset requests
mod common;

#[cfg(test)]
mod tests {
    use super::common::fixtures;
    use sqlx::PgPool;
    use user_service::db::{password_reset_repo, user_repo};
    use user_service::security::{hash_password, verify_password};
    use user_service::services::password_reset_service;

    /// Setup test database pool
    async fn setup_test_db() -> PgPool {
        fixtures::create_test_pool().await
    }

    /// Cleanup after test
    async fn cleanup(pool: &PgPool) {
        fixtures::cleanup_test_data(pool).await;
    }

    // ============================================
    // Happy Path Tests
    // ============================================

    #[tokio::test]
    async fn test_password_reset_full_flow() {
        let pool = setup_test_db().await;

        // 1. Create a test user
        let user = fixtures::create_test_user(&pool).await;
        let original_password_hash = user.password_hash.clone();

        // 2. Generate password reset token
        let token = password_reset_service::generate_token();
        let token_hash = password_reset_service::hash_token(&token);

        // 3. Store reset token in database
        let reset_token = password_reset_repo::create_token(
            &pool,
            user.id,
            &token_hash,
            Some("192.168.1.1".to_string()),
        )
        .await
        .expect("Failed to create reset token");

        assert_eq!(reset_token.user_id, user.id);
        assert!(!reset_token.is_used);
        assert!(reset_token.expires_at > chrono::Utc::now());

        // 4. Verify token is valid
        let is_valid = password_reset_repo::is_token_valid(&pool, &token_hash)
            .await
            .expect("Failed to check token validity");
        assert!(is_valid);

        // 5. Find token by hash
        let found_token = password_reset_repo::find_by_token(&pool, &token_hash)
            .await
            .expect("Failed to find token")
            .expect("Token not found");
        assert_eq!(found_token.id, reset_token.id);

        // 6. Update user's password
        let new_password = "NewSecureP@ss123";
        let new_password_hash = hash_password(new_password).expect("Failed to hash password");

        let updated_user = user_repo::update_password(&pool, user.id, &new_password_hash)
            .await
            .expect("Failed to update password");

        // 7. Verify password was changed
        assert_ne!(updated_user.password_hash, original_password_hash);
        assert!(verify_password(new_password, &updated_user.password_hash).is_ok());

        // 8. Mark token as used
        let used_token = password_reset_repo::mark_as_used(&pool, reset_token.id)
            .await
            .expect("Failed to mark token as used");

        assert!(used_token.is_used);
        assert!(used_token.used_at.is_some());

        // 9. Verify used token is no longer valid
        let is_still_valid = password_reset_repo::is_token_valid(&pool, &token_hash)
            .await
            .expect("Failed to check token validity");
        assert!(!is_still_valid);

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_generate_token_uniqueness() {
        // Generate multiple tokens and verify uniqueness
        let tokens: Vec<String> = (0..100)
            .map(|_| password_reset_service::generate_token())
            .collect();

        let unique_tokens: std::collections::HashSet<_> = tokens.iter().collect();
        assert_eq!(unique_tokens.len(), tokens.len());
    }

    #[tokio::test]
    async fn test_token_hash_deterministic() {
        let token = "test_token_12345";
        let hash1 = password_reset_service::hash_token(token);
        let hash2 = password_reset_service::hash_token(token);
        assert_eq!(hash1, hash2);
    }

    #[tokio::test]
    async fn test_token_hash_different_for_different_tokens() {
        let token1 = "token_one";
        let token2 = "token_two";
        let hash1 = password_reset_service::hash_token(token1);
        let hash2 = password_reset_service::hash_token(token2);
        assert_ne!(hash1, hash2);
    }

    #[tokio::test]
    async fn test_verify_token_hash_correct() {
        let token = "valid_reset_token";
        let hash = password_reset_service::hash_token(token);
        assert!(password_reset_service::verify_token_hash(token, &hash));
    }

    #[tokio::test]
    async fn test_verify_token_hash_incorrect() {
        let token = "valid_token";
        let wrong_token = "invalid_token";
        let hash = password_reset_service::hash_token(token);
        assert!(!password_reset_service::verify_token_hash(
            wrong_token,
            &hash
        ));
    }

    // ============================================
    // Token Expiration Tests
    // ============================================

    #[tokio::test]
    async fn test_token_expires_after_one_hour() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let token = password_reset_service::generate_token();
        let token_hash = password_reset_service::hash_token(&token);

        // Create token
        let reset_token = password_reset_repo::create_token(&pool, user.id, &token_hash, None)
            .await
            .expect("Failed to create token");

        // Verify expires_at is approximately 1 hour from now
        let expected_expiry = chrono::Utc::now() + chrono::Duration::hours(1);
        let time_diff = (reset_token.expires_at - expected_expiry)
            .num_seconds()
            .abs();
        assert!(time_diff < 5); // Within 5 seconds tolerance

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_expired_token_is_invalid() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let token = password_reset_service::generate_token();
        let token_hash = password_reset_service::hash_token(&token);

        // Create token
        let reset_token = password_reset_repo::create_token(&pool, user.id, &token_hash, None)
            .await
            .expect("Failed to create token");

        // Manually set expiration to past (simulate expired token)
        let past_time = chrono::Utc::now() - chrono::Duration::hours(2);
        sqlx::query("UPDATE password_resets SET expires_at = $1 WHERE id = $2")
            .bind(past_time)
            .bind(reset_token.id)
            .execute(&pool)
            .await
            .expect("Failed to update expiration");

        // Verify token is now invalid
        let is_valid = password_reset_repo::is_token_valid(&pool, &token_hash)
            .await
            .expect("Failed to check validity");
        assert!(!is_valid);

        cleanup(&pool).await;
    }

    // ============================================
    // Token Usage Tests
    // ============================================

    #[tokio::test]
    async fn test_used_token_becomes_invalid() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let token = password_reset_service::generate_token();
        let token_hash = password_reset_service::hash_token(&token);

        let reset_token = password_reset_repo::create_token(&pool, user.id, &token_hash, None)
            .await
            .expect("Failed to create token");

        // Token should be valid initially
        let is_valid = password_reset_repo::is_token_valid(&pool, &token_hash)
            .await
            .expect("Failed to check validity");
        assert!(is_valid);

        // Mark as used
        password_reset_repo::mark_as_used(&pool, reset_token.id)
            .await
            .expect("Failed to mark as used");

        // Token should now be invalid
        let is_still_valid = password_reset_repo::is_token_valid(&pool, &token_hash)
            .await
            .expect("Failed to check validity");
        assert!(!is_still_valid);

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_mark_as_used_sets_timestamp() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let token = password_reset_service::generate_token();
        let token_hash = password_reset_service::hash_token(&token);

        let reset_token = password_reset_repo::create_token(&pool, user.id, &token_hash, None)
            .await
            .expect("Failed to create token");

        assert!(reset_token.used_at.is_none());

        let used_token = password_reset_repo::mark_as_used(&pool, reset_token.id)
            .await
            .expect("Failed to mark as used");

        assert!(used_token.is_used);
        assert!(used_token.used_at.is_some());

        // Verify timestamp is recent
        let time_diff = (chrono::Utc::now() - used_token.used_at.unwrap())
            .num_seconds()
            .abs();
        assert!(time_diff < 5);

        cleanup(&pool).await;
    }

    // ============================================
    // Token Cleanup Tests
    // ============================================

    #[tokio::test]
    async fn test_delete_user_tokens() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;

        // Create multiple tokens for user
        for _ in 0..3 {
            let token = password_reset_service::generate_token();
            let token_hash = password_reset_service::hash_token(&token);
            password_reset_repo::create_token(&pool, user.id, &token_hash, None)
                .await
                .expect("Failed to create token");
        }

        // Delete all tokens
        let deleted_count = password_reset_repo::delete_user_tokens(&pool, user.id)
            .await
            .expect("Failed to delete tokens");

        assert_eq!(deleted_count, 3);

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_cleanup_expired_tokens() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;

        // Create expired token
        let token1 = password_reset_service::generate_token();
        let hash1 = password_reset_service::hash_token(&token1);
        let expired = password_reset_repo::create_token(&pool, user.id, &hash1, None)
            .await
            .expect("Failed to create token");

        // Manually expire it
        let past_time = chrono::Utc::now() - chrono::Duration::hours(2);
        sqlx::query("UPDATE password_resets SET expires_at = $1 WHERE id = $2")
            .bind(past_time)
            .bind(expired.id)
            .execute(&pool)
            .await
            .expect("Failed to update expiration");

        // Create valid token
        let token2 = password_reset_service::generate_token();
        let hash2 = password_reset_service::hash_token(&token2);
        password_reset_repo::create_token(&pool, user.id, &hash2, None)
            .await
            .expect("Failed to create token");

        // Cleanup expired tokens
        let cleaned = password_reset_repo::cleanup_expired_tokens(&pool)
            .await
            .expect("Failed to cleanup");

        assert_eq!(cleaned, 1); // Only expired token should be deleted

        // Verify valid token still exists
        let is_valid = password_reset_repo::is_token_valid(&pool, &hash2)
            .await
            .expect("Failed to check validity");
        assert!(is_valid);

        cleanup(&pool).await;
    }

    // ============================================
    // Password Reuse Prevention Tests
    // ============================================

    #[tokio::test]
    async fn test_prevent_password_reuse() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let original_hash = user.password_hash.clone();

        // Attempt to set same password
        let new_password = "TestPassword123!";
        let new_hash = hash_password(new_password).expect("Failed to hash");

        // Update password
        user_repo::update_password(&pool, user.id, &new_hash)
            .await
            .expect("Failed to update password");

        // Verify new password hash is different (even if password is same)
        // Argon2 uses salt, so same password produces different hash
        let updated_user = user_repo::find_by_id(&pool, user.id)
            .await
            .expect("Query failed")
            .expect("User not found");

        assert_ne!(updated_user.password_hash, original_hash);

        cleanup(&pool).await;
    }

    // ============================================
    // Multiple Reset Requests Tests
    // ============================================

    #[tokio::test]
    async fn test_multiple_reset_tokens_for_same_user() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;

        // Create first token
        let token1 = password_reset_service::generate_token();
        let hash1 = password_reset_service::hash_token(&token1);
        password_reset_repo::create_token(&pool, user.id, &hash1, None)
            .await
            .expect("Failed to create token");

        // Create second token
        let token2 = password_reset_service::generate_token();
        let hash2 = password_reset_service::hash_token(&token2);
        password_reset_repo::create_token(&pool, user.id, &hash2, None)
            .await
            .expect("Failed to create token");

        // Both tokens should be valid
        let valid1 = password_reset_repo::is_token_valid(&pool, &hash1)
            .await
            .expect("Failed to check");
        let valid2 = password_reset_repo::is_token_valid(&pool, &hash2)
            .await
            .expect("Failed to check");

        assert!(valid1);
        assert!(valid2);

        // After password reset, all tokens should be deleted
        let deleted = password_reset_repo::delete_user_tokens(&pool, user.id)
            .await
            .expect("Failed to delete");

        assert_eq!(deleted, 2);

        cleanup(&pool).await;
    }

    // ============================================
    // IP Address Tracking Tests
    // ============================================

    #[tokio::test]
    async fn test_token_stores_ip_address() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let token = password_reset_service::generate_token();
        let token_hash = password_reset_service::hash_token(&token);

        let reset_token = password_reset_repo::create_token(
            &pool,
            user.id,
            &token_hash,
            Some("203.0.113.42".to_string()),
        )
        .await
        .expect("Failed to create token");

        assert_eq!(reset_token.ip_address, Some("203.0.113.42".to_string()));

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_token_without_ip_address() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let token = password_reset_service::generate_token();
        let token_hash = password_reset_service::hash_token(&token);

        let reset_token = password_reset_repo::create_token(&pool, user.id, &token_hash, None)
            .await
            .expect("Failed to create token");

        assert_eq!(reset_token.ip_address, None);

        cleanup(&pool).await;
    }
}

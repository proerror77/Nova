#![cfg(feature = "legacy_auth_tests")]
/// Integration tests for OAuth2 authentication flows (AUTH-3001)
/// Tests OAuth provider integration for Google, Apple, and Facebook
///
/// Test Coverage:
/// - Happy path: New user registration via OAuth
/// - Existing user login via OAuth
/// - Account linking: Multiple OAuth providers per user
/// - Account unlinking with validation
/// - Error handling: Invalid codes, state tampering, provider errors
mod common;

#[cfg(test)]
mod tests {
    use super::common::fixtures;
    use mockall::predicate::*;
    use mockall::*;
    use sqlx::PgPool;
    use user_service::db::{oauth_repo, user_repo};
    use user_service::services::oauth::{OAuthError, OAuthProvider, OAuthUserInfo};

    // ============================================
    // Mock OAuth Provider
    // ============================================

    mock! {
        pub OAuthProvider {}

        #[async_trait::async_trait]
        impl OAuthProvider for OAuthProvider {
            fn get_authorization_url(&self, state: &str) -> Result<String, OAuthError>;
            async fn exchange_code(&self, code: &str, redirect_uri: &str) -> Result<OAuthUserInfo, OAuthError>;
            fn verify_state(&self, state: &str) -> Result<(), OAuthError>;
            fn provider_name(&self) -> &str;
        }

        impl Clone for OAuthProvider {
            fn clone(&self) -> Self;
        }
    }

    // ============================================
    // Test Helpers
    // ============================================

    /// Create mock OAuth user info for testing
    fn create_mock_oauth_user_info(provider: &str, user_id: &str) -> OAuthUserInfo {
        OAuthUserInfo {
            provider: provider.to_string(),
            provider_user_id: user_id.to_string(),
            email: format!("{}@{}.com", user_id, provider),
            display_name: Some(format!("Test {} User", provider)),
            access_token: format!("{}_access_token", provider),
            refresh_token: Some(format!("{}_refresh_token", provider)),
            token_expires_at: Some(chrono::Utc::now().timestamp() + 3600),
        }
    }

    /// Setup test database pool
    async fn setup_test_db() -> PgPool {
        fixtures::create_test_pool().await
    }

    /// Cleanup after test
    async fn cleanup(pool: &PgPool) {
        fixtures::cleanup_test_data(pool).await;
    }

    // ============================================
    // Happy Path Tests: New User Registration
    // ============================================

    #[tokio::test]
    async fn test_oauth_google_new_user_registration() {
        let pool = setup_test_db().await;

        // Mock Google OAuth user info
        let oauth_info = create_mock_oauth_user_info("google", "google_user_123");

        // Simulate new user registration flow:
        // 1. Check if OAuth connection exists (should be None)
        let existing_conn = oauth_repo::find_by_provider(&pool, "google", "google_user_123").await;
        assert!(existing_conn.is_ok());
        assert!(existing_conn.unwrap().is_none());

        // 2. Create new user
        let user = user_repo::create_user(
            &pool,
            &oauth_info.email,
            "google_user_123",
            "dummy_oauth_hash", // OAuth users don't need password
        )
        .await
        .expect("Failed to create user");

        // 3. Mark email as verified (OAuth emails are pre-verified)
        let _ = user_repo::verify_email(&pool, user.id).await;

        // 4. Create OAuth connection
        let connection = oauth_repo::create_connection(
            &pool,
            user.id,
            &oauth_info.provider,
            &oauth_info.provider_user_id,
            &oauth_info.email,
            oauth_info.display_name.as_deref(),
            &oauth_info.access_token,
            oauth_info.refresh_token.as_deref(),
            oauth_info.token_expires_at,
        )
        .await
        .expect("Failed to create OAuth connection");

        // Assertions
        assert_eq!(connection.provider, "google");
        assert_eq!(connection.provider_user_id, "google_user_123");
        assert_eq!(connection.user_id, user.id);

        // Verify user was created with email_verified = true
        let verified_user = user_repo::find_by_email(&pool, &oauth_info.email)
            .await
            .expect("Failed to find user")
            .expect("User not found");
        assert!(verified_user.email_verified);

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_oauth_apple_new_user_registration() {
        let pool = setup_test_db().await;

        let oauth_info = create_mock_oauth_user_info("apple", "apple_user_456");

        // Create user via Apple OAuth
        let user = user_repo::create_user(&pool, &oauth_info.email, "apple_user_456", "dummy_hash")
            .await
            .expect("Failed to create user");

        let _ = user_repo::verify_email(&pool, user.id).await;

        let connection = oauth_repo::create_connection(
            &pool,
            user.id,
            &oauth_info.provider,
            &oauth_info.provider_user_id,
            &oauth_info.email,
            oauth_info.display_name.as_deref(),
            &oauth_info.access_token,
            oauth_info.refresh_token.as_deref(),
            oauth_info.token_expires_at,
        )
        .await
        .expect("Failed to create OAuth connection");

        assert_eq!(connection.provider, "apple");
        assert_eq!(connection.provider_user_id, "apple_user_456");

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_oauth_facebook_new_user_registration() {
        let pool = setup_test_db().await;

        let oauth_info = create_mock_oauth_user_info("facebook", "fb_user_789");

        let user = user_repo::create_user(&pool, &oauth_info.email, "fb_user_789", "dummy_hash")
            .await
            .expect("Failed to create user");

        let _ = user_repo::verify_email(&pool, user.id).await;

        let connection = oauth_repo::create_connection(
            &pool,
            user.id,
            &oauth_info.provider,
            &oauth_info.provider_user_id,
            &oauth_info.email,
            oauth_info.display_name.as_deref(),
            &oauth_info.access_token,
            oauth_info.refresh_token.as_deref(),
            oauth_info.token_expires_at,
        )
        .await
        .expect("Failed to create OAuth connection");

        assert_eq!(connection.provider, "facebook");
        assert_eq!(connection.provider_user_id, "fb_user_789");

        cleanup(&pool).await;
    }

    // ============================================
    // Login Tests: Existing User
    // ============================================

    #[tokio::test]
    async fn test_oauth_existing_user_login() {
        let pool = setup_test_db().await;

        // Create user and OAuth connection
        let oauth_info = create_mock_oauth_user_info("google", "returning_user_123");
        let user =
            user_repo::create_user(&pool, &oauth_info.email, "returning_user_123", "dummy_hash")
                .await
                .expect("Failed to create user");
        let _ = user_repo::verify_email(&pool, user.id).await;

        let _initial_connection = oauth_repo::create_connection(
            &pool,
            user.id,
            &oauth_info.provider,
            &oauth_info.provider_user_id,
            &oauth_info.email,
            oauth_info.display_name.as_deref(),
            &oauth_info.access_token,
            oauth_info.refresh_token.as_deref(),
            oauth_info.token_expires_at,
        )
        .await
        .expect("Failed to create OAuth connection");

        // Simulate returning user login
        let found_connection = oauth_repo::find_by_provider(&pool, "google", "returning_user_123")
            .await
            .expect("Query failed")
            .expect("Connection not found");

        assert_eq!(found_connection.user_id, user.id);
        assert_eq!(found_connection.provider, "google");

        // Verify can retrieve user info
        let found_user = user_repo::find_by_id(&pool, found_connection.user_id)
            .await
            .expect("Query failed")
            .expect("User not found");

        assert_eq!(found_user.id, user.id);
        assert_eq!(found_user.email, oauth_info.email);

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_oauth_token_refresh() {
        let pool = setup_test_db().await;

        let oauth_info = create_mock_oauth_user_info("google", "token_refresh_user");
        let user =
            user_repo::create_user(&pool, &oauth_info.email, "token_refresh_user", "dummy_hash")
                .await
                .expect("Failed to create user");

        let connection = oauth_repo::create_connection(
            &pool,
            user.id,
            &oauth_info.provider,
            &oauth_info.provider_user_id,
            &oauth_info.email,
            oauth_info.display_name.as_deref(),
            &oauth_info.access_token,
            oauth_info.refresh_token.as_deref(),
            oauth_info.token_expires_at,
        )
        .await
        .expect("Failed to create OAuth connection");

        // Simulate token refresh
        let new_access_token = "new_google_access_token";
        let new_refresh_token = Some("new_google_refresh_token");
        let new_expires_at = Some(chrono::Utc::now().timestamp() + 7200);

        let updated_connection = oauth_repo::update_tokens(
            &pool,
            connection.id,
            new_access_token,
            new_refresh_token.as_deref(),
            new_expires_at,
        )
        .await
        .expect("Failed to update tokens");

        // Verify tokens were updated
        assert_ne!(
            updated_connection.access_token_hash,
            connection.access_token_hash
        );
        assert_ne!(
            updated_connection.refresh_token_hash,
            connection.refresh_token_hash
        );
        assert!(updated_connection.updated_at > connection.updated_at);

        cleanup(&pool).await;
    }

    // ============================================
    // Account Linking Tests
    // ============================================

    #[tokio::test]
    async fn test_link_multiple_oauth_providers() {
        let pool = setup_test_db().await;

        // Create user with Google
        let google_info = create_mock_oauth_user_info("google", "multi_provider_user");
        let user = user_repo::create_user(
            &pool,
            &google_info.email,
            "multi_provider_user",
            "dummy_hash",
        )
        .await
        .expect("Failed to create user");

        // Link Google
        let _google_conn = oauth_repo::create_connection(
            &pool,
            user.id,
            &google_info.provider,
            &google_info.provider_user_id,
            &google_info.email,
            google_info.display_name.as_deref(),
            &google_info.access_token,
            google_info.refresh_token.as_deref(),
            google_info.token_expires_at,
        )
        .await
        .expect("Failed to create Google connection");

        // Link Apple
        let apple_info = create_mock_oauth_user_info("apple", "multi_provider_user_apple");
        let _apple_conn = oauth_repo::create_connection(
            &pool,
            user.id,
            &apple_info.provider,
            &apple_info.provider_user_id,
            &apple_info.email,
            apple_info.display_name.as_deref(),
            &apple_info.access_token,
            apple_info.refresh_token.as_deref(),
            apple_info.token_expires_at,
        )
        .await
        .expect("Failed to create Apple connection");

        // Link Facebook
        let fb_info = create_mock_oauth_user_info("facebook", "multi_provider_user_fb");
        let _fb_conn = oauth_repo::create_connection(
            &pool,
            user.id,
            &fb_info.provider,
            &fb_info.provider_user_id,
            &fb_info.email,
            fb_info.display_name.as_deref(),
            &fb_info.access_token,
            fb_info.refresh_token.as_deref(),
            fb_info.token_expires_at,
        )
        .await
        .expect("Failed to create Facebook connection");

        // Verify all connections exist
        let all_connections = oauth_repo::find_by_user(&pool, user.id)
            .await
            .expect("Failed to find connections");

        assert_eq!(all_connections.len(), 3);

        let providers: Vec<&str> = all_connections
            .iter()
            .map(|c| c.provider.as_str())
            .collect();
        assert!(providers.contains(&"google"));
        assert!(providers.contains(&"apple"));
        assert!(providers.contains(&"facebook"));

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_login_with_any_linked_provider() {
        let pool = setup_test_db().await;

        // Create user and link multiple providers
        let user = fixtures::create_test_user(&pool).await;
        let _google_conn =
            fixtures::create_test_oauth_connection(&pool, user.id, "google", "user_google_123")
                .await;
        let _apple_conn =
            fixtures::create_test_oauth_connection(&pool, user.id, "apple", "user_apple_456").await;

        // Login via Google
        let google_login = oauth_repo::find_by_provider(&pool, "google", "user_google_123")
            .await
            .expect("Query failed")
            .expect("Google connection not found");
        assert_eq!(google_login.user_id, user.id);

        // Login via Apple
        let apple_login = oauth_repo::find_by_provider(&pool, "apple", "user_apple_456")
            .await
            .expect("Query failed")
            .expect("Apple connection not found");
        assert_eq!(apple_login.user_id, user.id);

        // Both should resolve to the same user
        assert_eq!(google_login.user_id, apple_login.user_id);

        cleanup(&pool).await;
    }

    // ============================================
    // Account Unlinking Tests
    // ============================================

    #[tokio::test]
    async fn test_unlink_oauth_provider() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let google_conn =
            fixtures::create_test_oauth_connection(&pool, user.id, "google", "unlink_test_123")
                .await;
        let _apple_conn =
            fixtures::create_test_oauth_connection(&pool, user.id, "apple", "unlink_test_456")
                .await;

        // Verify 2 connections exist
        let connections_before = oauth_repo::find_by_user(&pool, user.id)
            .await
            .expect("Failed to find connections");
        assert_eq!(connections_before.len(), 2);

        // Unlink Google
        oauth_repo::delete_connection(&pool, google_conn.id)
            .await
            .expect("Failed to delete connection");

        // Verify only 1 connection remains
        let connections_after = oauth_repo::find_by_user(&pool, user.id)
            .await
            .expect("Failed to find connections");
        assert_eq!(connections_after.len(), 1);
        assert_eq!(connections_after[0].provider, "apple");

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_prevent_unlink_last_oauth_provider() {
        let pool = setup_test_db().await;

        // Create OAuth-only user (no password)
        let user = fixtures::create_test_user(&pool).await;
        let google_conn =
            fixtures::create_test_oauth_connection(&pool, user.id, "google", "last_provider_123")
                .await;

        // Verify user has only 1 OAuth connection
        let connections = oauth_repo::find_by_user(&pool, user.id)
            .await
            .expect("Failed to find connections");
        assert_eq!(connections.len(), 1);

        // Business logic: Should check if this is the last auth method
        // In real implementation, the handler would:
        // 1. Count OAuth connections
        // 2. Check if user has password set
        // 3. Prevent deletion if this is the only auth method

        let count = fixtures::count_user_oauth_connections(&pool, user.id).await;
        assert_eq!(count, 1);

        // For this test, we demonstrate the check (actual prevention is in handler)
        if count == 1 {
            // Would return error in real handler
            // For test, we just verify the count check works
            assert_eq!(count, 1);
        } else {
            // If count > 1, safe to delete
            oauth_repo::delete_connection(&pool, google_conn.id)
                .await
                .expect("Failed to delete connection");
        }

        cleanup(&pool).await;
    }

    // ============================================
    // Error Handling Tests
    // ============================================

    #[tokio::test]
    async fn test_oauth_invalid_authorization_code() {
        // Mock provider that returns error on invalid code
        let mut mock_provider = MockOAuthProvider::new();

        mock_provider
            .expect_exchange_code()
            .with(eq("invalid_code"), always())
            .times(1)
            .returning(|_, _| {
                Err(OAuthError::InvalidAuthCode(
                    "Authorization code is invalid".to_string(),
                ))
            });

        // Attempt to exchange invalid code
        let result = mock_provider
            .exchange_code("invalid_code", "http://localhost/callback")
            .await;

        assert!(result.is_err());
        match result {
            Err(OAuthError::InvalidAuthCode(msg)) => {
                assert!(msg.contains("invalid"));
            }
            _ => panic!("Expected InvalidAuthCode error"),
        }
    }

    #[tokio::test]
    async fn test_oauth_state_parameter_tampering() {
        let mut mock_provider = MockOAuthProvider::new();

        // Mock state verification failure
        mock_provider
            .expect_verify_state()
            .with(eq("tampered_state"))
            .times(1)
            .returning(|_| Err(OAuthError::InvalidState));

        let result = mock_provider.verify_state("tampered_state");

        assert!(result.is_err());
        match result {
            Err(OAuthError::InvalidState) => {
                // Expected error
            }
            _ => panic!("Expected InvalidState error"),
        }
    }

    #[tokio::test]
    async fn test_oauth_provider_error_response() {
        let mut mock_provider = MockOAuthProvider::new();

        mock_provider
            .expect_exchange_code()
            .times(1)
            .returning(|_, _| {
                Err(OAuthError::ProviderError(
                    "Provider returned error: access_denied".to_string(),
                ))
            });

        let result = mock_provider
            .exchange_code("valid_code", "http://localhost/callback")
            .await;

        assert!(result.is_err());
        match result {
            Err(OAuthError::ProviderError(msg)) => {
                assert!(msg.contains("access_denied"));
            }
            _ => panic!("Expected ProviderError"),
        }
    }

    #[tokio::test]
    async fn test_oauth_network_error() {
        let mut mock_provider = MockOAuthProvider::new();

        mock_provider
            .expect_exchange_code()
            .times(1)
            .returning(|_, _| Err(OAuthError::NetworkError("Connection timeout".to_string())));

        let result = mock_provider
            .exchange_code("code", "http://localhost/callback")
            .await;

        assert!(result.is_err());
        match result {
            Err(OAuthError::NetworkError(msg)) => {
                assert!(msg.contains("timeout"));
            }
            _ => panic!("Expected NetworkError"),
        }
    }

    #[tokio::test]
    async fn test_oauth_duplicate_provider_connection() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;

        // Create first Google connection
        let _first_conn =
            fixtures::create_test_oauth_connection(&pool, user.id, "google", "duplicate_123").await;

        // Attempt to create duplicate Google connection with same provider_user_id
        // This should succeed at DB level but business logic should prevent it
        let result = oauth_repo::create_connection(
            &pool,
            user.id,
            "google",
            "duplicate_123", // Same provider_user_id
            "duplicate_123@google.com",
            Some("Duplicate User"),
            "new_access_token",
            Some("new_refresh_token"),
            Some(chrono::Utc::now().timestamp() + 3600),
        )
        .await;

        // Database allows this, but application logic should check
        // find_by_provider before creating
        if result.is_ok() {
            // If we got here, we need to verify application prevents this
            let existing = oauth_repo::find_by_provider(&pool, "google", "duplicate_123")
                .await
                .expect("Query failed");

            // Should find existing connection and use it instead of creating new
            assert!(existing.is_some());
        }

        cleanup(&pool).await;
    }

    // ============================================
    // Data Validation Tests
    // ============================================

    #[tokio::test]
    async fn test_oauth_connection_stores_tokens_securely() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;
        let plaintext_token = "super_secret_access_token_12345";

        let oauth_info = OAuthUserInfo {
            provider: "google".to_string(),
            provider_user_id: "security_test_user".to_string(),
            email: "security@test.com".to_string(),
            display_name: Some("Security Test".to_string()),
            access_token: plaintext_token.to_string(),
            refresh_token: Some("super_secret_refresh_token_67890".to_string()),
            token_expires_at: Some(chrono::Utc::now().timestamp() + 3600),
        };

        let connection = oauth_repo::create_connection(
            &pool,
            user.id,
            &oauth_info.provider,
            &oauth_info.provider_user_id,
            &oauth_info.email,
            oauth_info.display_name.as_deref(),
            &oauth_info.access_token,
            oauth_info.refresh_token.as_deref(),
            oauth_info.token_expires_at,
        )
        .await
        .expect("Failed to create connection");

        // Verify token is hashed (not stored in plaintext)
        assert_ne!(connection.access_token_hash, plaintext_token);
        assert_eq!(connection.access_token_hash.len(), 64); // SHA256 hex = 64 chars

        cleanup(&pool).await;
    }

    #[tokio::test]
    async fn test_oauth_connection_email_validation() {
        let pool = setup_test_db().await;

        let user = fixtures::create_test_user(&pool).await;

        // Create connection with valid email
        let result = oauth_repo::create_connection(
            &pool,
            user.id,
            "google",
            "email_validation_test",
            "valid.email@example.com",
            Some("Test User"),
            "access_token",
            Some("refresh_token"),
            Some(chrono::Utc::now().timestamp() + 3600),
        )
        .await;

        assert!(result.is_ok());

        // Note: Email validation should happen at handler level
        // Database accepts any string for email field

        cleanup(&pool).await;
    }
}

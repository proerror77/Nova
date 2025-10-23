/// Unit tests for OAuth token verification functions
/// Tests verify_apple_token, verify_google_token, and verify_facebook_token
///
/// These tests verify:
/// - Token validation logic
/// - Error handling for invalid tokens
/// - Response parsing
///
/// Note: These are unit tests that don't require real OAuth providers
/// Real integration tests would require actual tokens from providers

#[cfg(test)]
mod tests {
    use user_service::services::oauth::{
        apple::AppleOAuthProvider, facebook::FacebookOAuthProvider, google::GoogleOAuthProvider,
        OAuthError,
    };

    // ============================================
    // Apple Token Verification Tests
    // ============================================

    #[tokio::test]
    async fn test_apple_verify_token_requires_env_vars() {
        // Test that provider initialization fails without required env vars
        // This validates our configuration requirements

        // Clear environment variables to test configuration error handling
        std::env::remove_var("APPLE_TEAM_ID");
        std::env::remove_var("APPLE_CLIENT_ID");
        std::env::remove_var("APPLE_KEY_ID");

        let result = AppleOAuthProvider::new();

        assert!(result.is_err());
        match result {
            Err(OAuthError::ConfigError(msg)) => {
                assert!(
                    msg.contains("APPLE_TEAM_ID") || msg.contains("APPLE_CLIENT_ID"),
                    "Expected configuration error message"
                );
            }
            _ => panic!("Expected ConfigError"),
        }
    }

    #[tokio::test]
    async fn test_apple_verify_token_rejects_malformed_jwt() {
        // Skip if env vars not set (requires manual setup for testing)
        if std::env::var("APPLE_CLIENT_ID").is_err() {
            println!("Skipping test: APPLE_CLIENT_ID not set");
            return;
        }

        let provider = match AppleOAuthProvider::new() {
            Ok(p) => p,
            Err(_) => {
                println!("Skipping test: Apple provider configuration incomplete");
                return;
            }
        };

        // Test with obviously invalid JWT
        let result = provider.verify_apple_token("not.a.valid.jwt").await;

        assert!(result.is_err());
        match result {
            Err(OAuthError::InvalidAuthCode(_)) | Err(OAuthError::NetworkError(_)) => {
                // Expected - either JWT decode fails or network error fetching keys
            }
            _ => panic!("Expected InvalidAuthCode or NetworkError"),
        }
    }

    #[tokio::test]
    async fn test_apple_verify_token_empty_string() {
        if std::env::var("APPLE_CLIENT_ID").is_err() {
            return;
        }

        let provider = match AppleOAuthProvider::new() {
            Ok(p) => p,
            Err(_) => return,
        };

        let result = provider.verify_apple_token("").await;

        assert!(result.is_err());
    }

    // ============================================
    // Google Token Verification Tests
    // ============================================

    #[tokio::test]
    async fn test_google_verify_token_requires_env_vars() {
        std::env::remove_var("GOOGLE_CLIENT_ID");
        std::env::remove_var("GOOGLE_CLIENT_SECRET");

        let result = GoogleOAuthProvider::new();

        assert!(result.is_err());
        match result {
            Err(OAuthError::ConfigError(msg)) => {
                assert!(msg.contains("GOOGLE_CLIENT_ID") || msg.contains("GOOGLE_CLIENT_SECRET"));
            }
            _ => panic!("Expected ConfigError"),
        }
    }

    #[tokio::test]
    async fn test_google_verify_token_rejects_invalid_token() {
        if std::env::var("GOOGLE_CLIENT_ID").is_err() {
            println!("Skipping test: GOOGLE_CLIENT_ID not set");
            return;
        }

        let provider = match GoogleOAuthProvider::new() {
            Ok(p) => p,
            Err(_) => {
                println!("Skipping test: Google provider configuration incomplete");
                return;
            }
        };

        // Test with invalid token
        let result = provider
            .verify_google_token("invalid_google_id_token_123")
            .await;

        assert!(result.is_err());
        match result {
            Err(OAuthError::InvalidAuthCode(_)) | Err(OAuthError::NetworkError(_)) => {
                // Expected - Google API will reject invalid token
            }
            _ => panic!("Expected InvalidAuthCode or NetworkError"),
        }
    }

    #[tokio::test]
    async fn test_google_verify_token_empty_string() {
        if std::env::var("GOOGLE_CLIENT_ID").is_err() {
            return;
        }

        let provider = match GoogleOAuthProvider::new() {
            Ok(p) => p,
            Err(_) => return,
        };

        let result = provider.verify_google_token("").await;

        assert!(result.is_err());
    }

    // ============================================
    // Facebook Token Verification Tests
    // ============================================

    #[tokio::test]
    async fn test_facebook_verify_token_requires_env_vars() {
        std::env::remove_var("FACEBOOK_CLIENT_ID");
        std::env::remove_var("FACEBOOK_CLIENT_SECRET");

        let result = FacebookOAuthProvider::new();

        assert!(result.is_err());
        match result {
            Err(OAuthError::ConfigError(msg)) => {
                assert!(
                    msg.contains("FACEBOOK_CLIENT_ID")
                        || msg.contains("FACEBOOK_CLIENT_SECRET")
                );
            }
            _ => panic!("Expected ConfigError"),
        }
    }

    #[tokio::test]
    async fn test_facebook_verify_token_rejects_invalid_token() {
        if std::env::var("FACEBOOK_CLIENT_ID").is_err() {
            println!("Skipping test: FACEBOOK_CLIENT_ID not set");
            return;
        }

        let provider = match FacebookOAuthProvider::new() {
            Ok(p) => p,
            Err(_) => {
                println!("Skipping test: Facebook provider configuration incomplete");
                return;
            }
        };

        // Test with invalid token
        let result = provider
            .verify_facebook_token("invalid_facebook_access_token_123")
            .await;

        assert!(result.is_err());
        match result {
            Err(OAuthError::InvalidAuthCode(_)) | Err(OAuthError::NetworkError(_)) => {
                // Expected - Facebook API will reject invalid token
            }
            _ => panic!("Expected InvalidAuthCode or NetworkError"),
        }
    }

    #[tokio::test]
    async fn test_facebook_verify_token_empty_string() {
        if std::env::var("FACEBOOK_CLIENT_ID").is_err() {
            return;
        }

        let provider = match FacebookOAuthProvider::new() {
            Ok(p) => p,
            Err(_) => return,
        };

        let result = provider.verify_facebook_token("").await;

        assert!(result.is_err());
    }

    // ============================================
    // Error Type Tests
    // ============================================

    #[test]
    fn test_oauth_error_types() {
        let invalid_code = OAuthError::InvalidAuthCode("test".to_string());
        assert!(invalid_code.to_string().contains("Invalid authorization code"));

        let token_exchange = OAuthError::TokenExchange("test".to_string());
        assert!(token_exchange.to_string().contains("Failed to exchange token"));

        let user_info_fetch = OAuthError::UserInfoFetch("test".to_string());
        assert!(user_info_fetch
            .to_string()
            .contains("Failed to fetch user info"));

        let network_error = OAuthError::NetworkError("test".to_string());
        assert!(network_error.to_string().contains("Network error"));

        let config_error = OAuthError::ConfigError("test".to_string());
        assert!(config_error.to_string().contains("Configuration error"));

        let invalid_state = OAuthError::InvalidState;
        assert!(invalid_state.to_string().contains("Invalid state"));

        let provider_error = OAuthError::ProviderError("test".to_string());
        assert!(provider_error.to_string().contains("Provider error"));
    }
}

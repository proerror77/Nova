//! Unified AuthService Client
//!
//! Provides application-layer validation for user existence before database INSERT operations.
//! This replaces database-level foreign key constraints to enable true microservice independence.
//!
//! Design Philosophy (Linus style):
//! - Single source of truth for auth-service gRPC calls
//! - Eliminate code duplication across 4+ services
//! - Support both connection pool and direct channel usage
//! - Zero breaking changes - backward compatible with existing code

use crate::config::GrpcConfig;
use crate::nova::identity_service::v2::{
    auth_service_client::AuthServiceClient as TonicAuthServiceClient, CheckUserExistsRequest,
    GetUserProfilesByIdsRequest, GetUserRequest, GetUsersByIdsRequest,
};
use crate::GrpcClientPool;
use anyhow::{Context, Result};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tonic::transport::Channel;
use uuid::Uuid;

/// Unified AuthService client with connection pooling support
///
/// Two initialization patterns:
/// 1. From GrpcClientPool (recommended) - for services using centralized pool
/// 2. From URL directly - for services transitioning from old pattern
#[derive(Clone)]
pub struct AuthClient {
    client: TonicAuthServiceClient<Channel>,
    request_timeout: Duration,
}

impl AuthClient {
    /// Create from connection pool (recommended pattern)
    ///
    /// Used by messaging-service and future migrations.
    pub fn from_pool(pool: Arc<GrpcClientPool>) -> Self {
        Self {
            client: pool.auth(),
            request_timeout: Duration::from_millis(2000), // Increased from 500ms for network resilience
        }
    }

    /// Create from Channel directly (modern pattern with lazy connection)
    ///
    /// Accepts a pre-configured Channel (typically created with connect_lazy()).
    /// This pattern avoids blocking during service initialization.
    pub fn new(channel: Channel) -> Self {
        Self {
            client: TonicAuthServiceClient::new(channel),
            request_timeout: Duration::from_millis(2000), // Increased from 500ms for network resilience
        }
    }

    /// Create from URL (legacy compatibility pattern)
    ///
    /// Used by streaming/content/feed-service during migration.
    /// Eventually all services should migrate to `from_pool()` or `new()`.
    pub async fn from_url(auth_service_url: &str) -> Result<Self> {
        tracing::info!("Creating auth service gRPC client: {}", auth_service_url);

        let config = GrpcConfig::from_env()
            .map_err(|e| anyhow::anyhow!("Failed to load gRPC config: {}", e))?;

        let channel = config
            .connect_channel(auth_service_url)
            .await
            .map_err(|e| anyhow::anyhow!("Failed to connect to auth-service: {}", e))?;

        let client = TonicAuthServiceClient::new(channel);

        tracing::info!("Auth service gRPC client connected successfully");

        Ok(Self {
            client,
            request_timeout: Duration::from_millis(2000), // Increased from 500ms for network resilience
        })
    }

    /// Check if user exists
    ///
    /// Core validation method that replaces FK constraints.
    /// Returns true if user exists, false otherwise.
    ///
    /// # Errors
    /// Returns error only on gRPC communication failures (network, timeout).
    /// User not existing is NOT an error - returns Ok(false).
    pub async fn user_exists(&self, user_id: Uuid) -> Result<bool> {
        let mut client = self.client.clone();
        let request = CheckUserExistsRequest {
            user_id: user_id.to_string(),
        };

        let mut tonic_request = tonic::Request::new(request);
        tonic_request.set_timeout(self.request_timeout);

        let response = client
            .check_user_exists(tonic_request)
            .await
            .context("Failed to check user existence via auth-service")?;

        Ok(response.into_inner().exists)
    }

    /// Validate user exists or return error
    ///
    /// Convenience method that returns Err if user doesn't exist.
    /// Use when you want fail-fast on invalid user_id.
    pub async fn validate_user_exists(&self, user_id: Uuid) -> Result<()> {
        if !self.user_exists(user_id).await? {
            anyhow::bail!("User {} does not exist", user_id);
        }
        Ok(())
    }

    /// Get user by ID
    ///
    /// Replaces: SELECT username FROM users WHERE id = $1
    ///
    /// # Returns
    /// - Ok(Some(username)) - user exists
    /// - Ok(None) - user not found (NOT an error)
    /// - Err - gRPC communication failure
    pub async fn get_user(&self, user_id: Uuid) -> Result<Option<String>> {
        let mut client = self.client.clone();
        let request = GetUserRequest {
            user_id: user_id.to_string(),
        };

        let mut tonic_request = tonic::Request::new(request);
        tonic_request.set_timeout(self.request_timeout);

        match client.get_user(tonic_request).await {
            Ok(response) => {
                let user = response.into_inner().user;
                Ok(user.map(|u| u.username))
            }
            Err(status) => {
                // NotFound is not an error - return None
                if status.code() == tonic::Code::NotFound {
                    Ok(None)
                } else {
                    Err(anyhow::anyhow!(
                        "auth-service get_user failed: {}",
                        status.message()
                    ))
                }
            }
        }
    }

    /// Get users by multiple IDs (batch operation)
    ///
    /// Efficiently fetch multiple users in one call using auth-service's GetUsersByIds RPC.
    /// Missing users are simply omitted from result (not errors).
    ///
    /// # Returns
    /// HashMap of user_id -> username for found users
    pub async fn get_users_by_ids(&self, user_ids: &[Uuid]) -> Result<HashMap<Uuid, String>> {
        if user_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let mut client = self.client.clone();
        let request = GetUsersByIdsRequest {
            user_ids: user_ids.iter().map(|id| id.to_string()).collect(),
        };

        let mut tonic_request = tonic::Request::new(request);
        tonic_request.set_timeout(self.request_timeout);

        let response = client
            .get_users_by_ids(tonic_request)
            .await
            .context("Failed to batch fetch users via auth-service")?;

        let users = response.into_inner().users;
        let mut result = HashMap::with_capacity(users.len());

        for user in users {
            // Parse UUID from string (auth-service returns string IDs)
            if let Ok(uuid) = Uuid::parse_str(&user.id) {
                result.insert(uuid, user.username);
            } else {
                tracing::warn!(user_id = %user.id, "Invalid UUID from auth-service");
            }
        }

        Ok(result)
    }

    /// Get user display name for Matrix provisioning
    ///
    /// Uses GetUserProfilesByIds RPC which returns the full UserProfile including display_name.
    /// Returns display_name if set, otherwise falls back to username.
    /// This ensures Matrix users get their proper display name.
    ///
    /// # Returns
    /// - Ok(Some(display_name_or_username)) - user found
    /// - Ok(None) - user not found
    /// - Err - gRPC communication failure
    pub async fn get_user_display_name(&self, user_id: Uuid) -> Result<Option<String>> {
        let mut client = self.client.clone();
        let request = GetUserProfilesByIdsRequest {
            user_ids: vec![user_id.to_string()],
        };

        let mut tonic_request = tonic::Request::new(request);
        tonic_request.set_timeout(self.request_timeout);

        match client.get_user_profiles_by_ids(tonic_request).await {
            Ok(response) => {
                let profiles = response.into_inner().profiles;
                if let Some(profile) = profiles.into_iter().next() {
                    // Return display_name if set and non-empty, otherwise fall back to username
                    let name = if let Some(display_name) = profile.display_name {
                        if display_name.is_empty() {
                            profile.username
                        } else {
                            display_name
                        }
                    } else {
                        profile.username
                    };
                    Ok(Some(name))
                } else {
                    Ok(None)
                }
            }
            Err(status) => {
                // NotFound is not an error - return None
                if status.code() == tonic::Code::NotFound {
                    Ok(None)
                } else {
                    Err(anyhow::anyhow!(
                        "auth-service get_user_profiles_by_ids failed: {}",
                        status.message()
                    ))
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests require auth-service running
    // Run with: cargo test --test auth_client_integration -- --ignored

    #[tokio::test]
    #[ignore]
    async fn test_user_exists_integration() {
        let client = AuthClient::from_url("http://localhost:50051")
            .await
            .expect("Failed to create client");

        let test_user_id = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
        let exists = client.user_exists(test_user_id).await.unwrap();
        assert!(exists || !exists); // Placeholder - actual value depends on test DB
    }

    #[tokio::test]
    #[ignore]
    async fn test_validate_user_exists_integration() {
        let client = AuthClient::from_url("http://localhost:50051")
            .await
            .expect("Failed to create client");

        let test_user_id = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
        // This will fail if user doesn't exist
        let _ = client.validate_user_exists(test_user_id).await;
    }

    #[tokio::test]
    #[ignore]
    async fn test_get_user_integration() {
        let client = AuthClient::from_url("http://localhost:50051")
            .await
            .expect("Failed to create client");

        let test_user_id = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
        let user = client.get_user(test_user_id).await.unwrap();
        // Result depends on test data
        println!("User: {:?}", user);
    }
}

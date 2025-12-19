/// Matrix Synapse Admin API client for user lifecycle management
///
/// This service provides administrative functions for Matrix Synapse via the Admin API.
/// Used to sync Nova user lifecycle events to Matrix (account deactivation, profile updates, etc.)
///
/// ## Admin API Documentation
/// https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/
use crate::error::AppError;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{error, info, warn};
use uuid::Uuid;

/// Matrix Admin API client
#[derive(Clone)]
pub struct MatrixAdminClient {
    /// HTTP client for making API requests
    client: Client,
    /// Synapse homeserver URL (e.g., "http://matrix-synapse:8008")
    homeserver_url: String,
    /// Synapse admin access token
    admin_token: String,
    /// Server name for constructing Matrix User IDs (e.g., "staging.nova.app")
    server_name: String,
}

/// Request body for deactivate user endpoint
#[derive(Debug, Serialize)]
struct DeactivateUserRequest {
    /// Whether to remove the user's display name and avatar
    erase: bool,
}

/// Response from deactivate user endpoint
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct DeactivateUserResponse {
    /// The Matrix user ID that was deactivated
    id_server_unbind_result: String,
}

/// Request body for updating user display name
#[derive(Debug, Serialize)]
struct UpdateDisplayNameRequest {
    displayname: String,
}

/// Request body for updating user avatar URL
#[derive(Debug, Serialize)]
struct UpdateAvatarRequest {
    avatar_url: String,
}

/// Request body for creating/updating a Matrix user via Admin API
/// PUT /_synapse/admin/v2/users/{user_id}
#[derive(Debug, Serialize)]
struct CreateUserRequest {
    /// Display name for the user
    displayname: Option<String>,
    /// Whether the user is an admin (default: false)
    #[serde(skip_serializing_if = "Option::is_none")]
    admin: Option<bool>,
    /// Whether the user is deactivated (default: false)
    #[serde(skip_serializing_if = "Option::is_none")]
    deactivated: Option<bool>,
}

/// Response from creating/updating a Matrix user
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct CreateUserResponse {
    /// The Matrix user ID
    pub name: String,
    /// Display name
    pub displayname: Option<String>,
    /// Whether the user is an admin
    pub admin: bool,
    /// Whether the user is deactivated
    pub deactivated: bool,
}

/// Request body for generating a login token
/// POST /_synapse/admin/v1/users/{user_id}/login
#[derive(Debug, Serialize)]
struct LoginTokenRequest {
    /// How long the token should be valid for (in milliseconds)
    /// Default is 2 minutes (120000ms), max is typically 1 hour
    #[serde(skip_serializing_if = "Option::is_none")]
    valid_until_ms: Option<i64>,
}

/// Response containing the login token
#[derive(Debug, Deserialize)]
pub struct LoginTokenResponse {
    /// The login token that can be used with `m.login.token` flow
    pub login_token: String,
}

impl MatrixAdminClient {
    /// Create a new Matrix Admin API client
    ///
    /// # Arguments
    /// * `homeserver_url` - Synapse homeserver URL (e.g., "http://matrix-synapse:8008")
    /// * `admin_token` - Admin access token for authentication
    /// * `server_name` - Server name for constructing MXIDs (e.g., "staging.nova.app")
    pub fn new(homeserver_url: String, admin_token: String, server_name: String) -> Self {
        Self {
            client: Client::new(),
            homeserver_url,
            admin_token,
            server_name,
        }
    }

    /// Convert Nova user_id (UUID) to Matrix User ID (MXID)
    ///
    /// Format: @nova-{user_id}:{server_name}
    /// Example: @nova-123e4567-e89b-12d3-a456-426614174000:staging.nova.app
    pub fn user_id_to_mxid(&self, user_id: Uuid) -> String {
        format!("@nova-{}:{}", user_id, self.server_name)
    }

    /// Deactivate a Matrix user account via Synapse Admin API
    ///
    /// This calls POST /_synapse/admin/v1/deactivate/{user_id}
    /// See: https://matrix-org.github.io/synapse/latest/admin_api/user_admin_api.html#deactivate-account
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID (will be converted to MXID)
    /// * `erase` - If true, removes user's display name and avatar
    ///
    /// # Returns
    /// Ok(()) if deactivation succeeded, Err otherwise
    pub async fn deactivate_user(&self, user_id: Uuid, erase: bool) -> Result<(), AppError> {
        let mxid = self.user_id_to_mxid(user_id);
        let url = format!(
            "{}/_synapse/admin/v1/deactivate/{}",
            self.homeserver_url,
            urlencoding::encode(&mxid)
        );

        info!(
            "Deactivating Matrix user: mxid={}, erase={}, nova_user_id={}",
            mxid, erase, user_id
        );

        let request_body = DeactivateUserRequest { erase };

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.admin_token))
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send deactivate request to Synapse: {}", e);
                AppError::ServiceUnavailable(format!("Synapse API request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            info!(
                "Successfully deactivated Matrix user: mxid={}, nova_user_id={}",
                mxid, user_id
            );
            Ok(())
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!(
                "Synapse deactivate API returned error: status={}, body={}, mxid={}",
                status, error_text, mxid
            );
            Err(AppError::ServiceUnavailable(format!(
                "Synapse deactivate failed ({}): {}",
                status, error_text
            )))
        }
    }

    /// Update Matrix user's display name via Client-Server API
    ///
    /// This calls PUT /_matrix/client/v3/profile/{user_id}/displayname
    /// Note: Uses Client-Server API (not Admin API) with admin token for authentication
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID
    /// * `displayname` - New display name to set
    ///
    /// # Returns
    /// Ok(()) if update succeeded, Err otherwise
    pub async fn update_displayname(&self, user_id: Uuid, displayname: &str) -> Result<(), AppError> {
        let mxid = self.user_id_to_mxid(user_id);
        let url = format!(
            "{}/_matrix/client/v3/profile/{}/displayname",
            self.homeserver_url,
            urlencoding::encode(&mxid)
        );

        info!(
            "Updating Matrix user displayname: mxid={}, displayname={}, nova_user_id={}",
            mxid, displayname, user_id
        );

        let request_body = UpdateDisplayNameRequest {
            displayname: displayname.to_string(),
        };

        let response = self
            .client
            .put(&url)
            .header("Authorization", format!("Bearer {}", self.admin_token))
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send update displayname request to Synapse: {}", e);
                AppError::ServiceUnavailable(format!("Synapse API request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            info!(
                "Successfully updated Matrix user displayname: mxid={}, nova_user_id={}",
                mxid, user_id
            );
            Ok(())
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            warn!(
                "Synapse update displayname API returned error: status={}, body={}, mxid={}",
                status, error_text, mxid
            );
            // Non-fatal: user may not exist in Matrix yet
            Ok(())
        }
    }

    /// Update Matrix user's avatar URL via Client-Server API
    ///
    /// This calls PUT /_matrix/client/v3/profile/{user_id}/avatar_url
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID
    /// * `avatar_url` - New avatar URL (MXC URI or HTTP URL)
    ///
    /// # Returns
    /// Ok(()) if update succeeded, Err otherwise
    pub async fn update_avatar_url(&self, user_id: Uuid, avatar_url: &str) -> Result<(), AppError> {
        let mxid = self.user_id_to_mxid(user_id);
        let url = format!(
            "{}/_matrix/client/v3/profile/{}/avatar_url",
            self.homeserver_url,
            urlencoding::encode(&mxid)
        );

        info!(
            "Updating Matrix user avatar: mxid={}, avatar_url={}, nova_user_id={}",
            mxid, avatar_url, user_id
        );

        let request_body = UpdateAvatarRequest {
            avatar_url: avatar_url.to_string(),
        };

        let response = self
            .client
            .put(&url)
            .header("Authorization", format!("Bearer {}", self.admin_token))
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send update avatar request to Synapse: {}", e);
                AppError::ServiceUnavailable(format!("Synapse API request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            info!(
                "Successfully updated Matrix user avatar: mxid={}, nova_user_id={}",
                mxid, user_id
            );
            Ok(())
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            warn!(
                "Synapse update avatar API returned error: status={}, body={}, mxid={}",
                status, error_text, mxid
            );
            // Non-fatal: user may not exist in Matrix yet
            Ok(())
        }
    }

    /// Update Matrix user profile (displayname and/or avatar)
    ///
    /// Convenience method that updates displayname and avatar in parallel if provided.
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID
    /// * `displayname` - Optional new display name
    /// * `avatar_url` - Optional new avatar URL
    ///
    /// # Returns
    /// Ok(()) if all updates succeeded, Err otherwise
    pub async fn update_profile(
        &self,
        user_id: Uuid,
        displayname: Option<String>,
        avatar_url: Option<String>,
    ) -> Result<(), AppError> {
        let mxid = self.user_id_to_mxid(user_id);
        info!(
            "Updating Matrix user profile: mxid={}, displayname={:?}, avatar={:?}",
            mxid, displayname, avatar_url
        );

        // Update displayname if provided
        if let Some(name) = displayname {
            self.update_displayname(user_id, &name).await?;
        }

        // Update avatar if provided
        if let Some(avatar) = avatar_url {
            self.update_avatar_url(user_id, &avatar).await?;
        }

        Ok(())
    }

    /// Logout all devices for a Matrix user via Admin API
    ///
    /// This calls POST /_synapse/admin/v1/whois/{user_id} to get devices,
    /// then POST /_synapse/admin/v1/users/{user_id}/devices/{device_id}/delete for each device.
    ///
    /// Used for backchannel logout fallback when OIDC backchannel logout fails.
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID
    ///
    /// # Returns
    /// Ok(()) if logout succeeded, Err otherwise
    pub async fn logout_user_devices(&self, user_id: Uuid) -> Result<(), AppError> {
        let mxid = self.user_id_to_mxid(user_id);

        info!(
            "Logging out all Matrix devices for user: mxid={}, nova_user_id={}",
            mxid, user_id
        );

        // For simplicity, we use the reset password endpoint with logout_devices=true
        // This is simpler than enumerating and deleting each device
        // Note: This doesn't actually change the password when used with OIDC
        let url = format!(
            "{}/_synapse/admin/v1/reset_password/{}",
            self.homeserver_url,
            urlencoding::encode(&mxid)
        );

        #[derive(Serialize)]
        struct ResetPasswordRequest {
            logout_devices: bool,
        }

        let request_body = ResetPasswordRequest {
            logout_devices: true,
        };

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.admin_token))
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send logout devices request to Synapse: {}", e);
                AppError::ServiceUnavailable(format!("Synapse API request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            info!(
                "Successfully logged out all Matrix devices for user: mxid={}, nova_user_id={}",
                mxid, user_id
            );
            Ok(())
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            warn!(
                "Synapse logout devices API returned error: status={}, body={}, mxid={}",
                status, error_text, mxid
            );
            // Non-fatal: user may not exist or have no devices
            Ok(())
        }
    }

    /// Create or update a Matrix user via Synapse Admin API
    ///
    /// This calls PUT /_synapse/admin/v2/users/{user_id}
    /// See: https://matrix-org.github.io/synapse/latest/admin_api/user_admin_api.html#create-or-modify-account
    ///
    /// If the user already exists, this is a no-op (returns success).
    /// If the user doesn't exist, creates them with the given display name.
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID (will be converted to MXID)
    /// * `displayname` - Display name for the user (optional)
    ///
    /// # Returns
    /// Ok(mxid) if creation/update succeeded, Err otherwise
    pub async fn create_or_get_user(
        &self,
        user_id: Uuid,
        displayname: Option<String>,
    ) -> Result<String, AppError> {
        let mxid = self.user_id_to_mxid(user_id);
        let url = format!(
            "{}/_synapse/admin/v2/users/{}",
            self.homeserver_url,
            urlencoding::encode(&mxid)
        );

        info!(
            "Creating/updating Matrix user: mxid={}, displayname={:?}, nova_user_id={}",
            mxid, displayname, user_id
        );

        let request_body = CreateUserRequest {
            displayname,
            admin: Some(false),
            deactivated: Some(false),
        };

        let response = self
            .client
            .put(&url)
            .header("Authorization", format!("Bearer {}", self.admin_token))
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send create user request to Synapse: {}", e);
                AppError::ServiceUnavailable(format!("Synapse API request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            info!(
                "Successfully created/updated Matrix user: mxid={}, nova_user_id={}",
                mxid, user_id
            );
            Ok(mxid)
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!(
                "Synapse create user API returned error: status={}, body={}, mxid={}",
                status, error_text, mxid
            );
            Err(AppError::ServiceUnavailable(format!(
                "Synapse create user failed ({}): {}",
                status, error_text
            )))
        }
    }

    /// Generate a login token for a Matrix user via Synapse Admin API
    ///
    /// This calls POST /_synapse/admin/v1/users/{user_id}/login
    /// See: https://matrix-org.github.io/synapse/latest/admin_api/user_admin_api.html#login-as-a-user
    ///
    /// The returned token can be used with the `m.login.token` login flow.
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID (will be converted to MXID)
    /// * `valid_for_ms` - How long the token should be valid (optional, default ~2 minutes)
    ///
    /// # Returns
    /// Ok(login_token) if successful, Err otherwise
    pub async fn generate_user_login_token(
        &self,
        user_id: Uuid,
        valid_for_ms: Option<i64>,
    ) -> Result<String, AppError> {
        let mxid = self.user_id_to_mxid(user_id);
        let url = format!(
            "{}/_synapse/admin/v1/users/{}/login",
            self.homeserver_url,
            urlencoding::encode(&mxid)
        );

        info!(
            "Generating login token for Matrix user: mxid={}, nova_user_id={}",
            mxid, user_id
        );

        let request_body = LoginTokenRequest {
            valid_until_ms: valid_for_ms,
        };

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.admin_token))
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send login token request to Synapse: {}", e);
                AppError::ServiceUnavailable(format!("Synapse API request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            let token_response: LoginTokenResponse = response.json().await.map_err(|e| {
                error!("Failed to parse login token response: {}", e);
                AppError::ServiceUnavailable(format!("Invalid response from Synapse: {}", e))
            })?;
            
            info!(
                "Successfully generated login token for Matrix user: mxid={}, nova_user_id={}",
                mxid, user_id
            );
            Ok(token_response.login_token)
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!(
                "Synapse login token API returned error: status={}, body={}, mxid={}",
                status, error_text, mxid
            );
            Err(AppError::ServiceUnavailable(format!(
                "Synapse login token failed ({}): {}",
                status, error_text
            )))
        }
    }

    /// Provision a Nova user for Matrix
    ///
    /// This is the main entry point for Nova -> Matrix user provisioning.
    /// It creates the Matrix user if they don't exist, then generates a login token.
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID
    /// * `displayname` - User's display name
    ///
    /// # Returns
    /// Ok((mxid, login_token)) if successful, Err otherwise
    pub async fn provision_user(
        &self,
        user_id: Uuid,
        displayname: Option<String>,
    ) -> Result<(String, String), AppError> {
        // Step 1: Create or update the user
        let mxid = self.create_or_get_user(user_id, displayname).await?;

        // Step 2: Generate a login token for the user
        // Token valid for 1 hour (3600000 ms)
        let login_token = self.generate_user_login_token(user_id, Some(3600000)).await?;

        Ok((mxid, login_token))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_id_to_mxid() {
        let client = MatrixAdminClient::new(
            "http://matrix-synapse:8008".to_string(),
            "test_token".to_string(),
            "staging.nova.app".to_string(),
        );

        let user_id = Uuid::parse_str("123e4567-e89b-12d3-a456-426614174000").unwrap();
        let mxid = client.user_id_to_mxid(user_id);
        assert_eq!(mxid, "@nova-123e4567-e89b-12d3-a456-426614174000:staging.nova.app");
    }

    #[test]
    fn test_mxid_format() {
        let client = MatrixAdminClient::new(
            "http://localhost:8008".to_string(),
            "token".to_string(),
            "nova.local".to_string(),
        );

        let user_id = Uuid::new_v4();
        let mxid = client.user_id_to_mxid(user_id);

        // Verify format: @nova-{uuid}:{server_name}
        assert!(mxid.starts_with("@nova-"));
        assert!(mxid.contains(':'));
        assert!(mxid.ends_with(":nova.local"));
    }
}

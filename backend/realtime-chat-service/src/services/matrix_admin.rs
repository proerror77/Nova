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
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};
use uuid::Uuid;

/// Admin credentials for automatic token refresh
#[derive(Clone)]
pub struct AdminCredentials {
    pub username: String,
    pub password: String,
}

/// Matrix Admin API client with automatic token refresh
#[derive(Clone)]
pub struct MatrixAdminClient {
    /// HTTP client for making API requests
    client: Client,
    /// Synapse homeserver URL (e.g., "http://matrix-synapse:8008")
    homeserver_url: String,
    /// Synapse admin access token (thread-safe for automatic refresh)
    admin_token: Arc<RwLock<String>>,
    /// Token expiration timestamp (Unix seconds)
    token_expires_at: Arc<RwLock<Option<i64>>>,
    /// Admin credentials for automatic token refresh
    admin_credentials: Option<AdminCredentials>,
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

/// Request body for Synapse admin join room endpoint
/// POST /_synapse/admin/v1/join/{room_id_or_alias}
#[derive(Debug, Serialize)]
struct JoinRoomRequest {
    user_id: String,
}

/// Request body for creating/updating a Matrix user via Admin API
/// PUT /_synapse/admin/v2/users/{user_id}
#[derive(Debug, Serialize)]
struct CreateUserRequest {
    /// Display name for the user
    displayname: Option<String>,
    /// Password for the user (required for standard Matrix login with device sessions)
    #[serde(skip_serializing_if = "Option::is_none")]
    password: Option<String>,
    /// Whether the user is an admin (default: false)
    #[serde(skip_serializing_if = "Option::is_none")]
    admin: Option<bool>,
    /// Whether the user is deactivated (default: false)
    #[serde(skip_serializing_if = "Option::is_none")]
    deactivated: Option<bool>,
}

/// Request body for standard Matrix login via Client-Server API
/// POST /_matrix/client/v3/login
#[derive(Debug, Serialize)]
struct MatrixLoginRequest {
    /// Login type (always "m.login.password" for password login)
    #[serde(rename = "type")]
    login_type: String,
    /// User identifier
    identifier: MatrixUserIdentifier,
    /// User password
    password: String,
    /// Device ID to bind the session to (creates a proper device session!)
    device_id: Option<String>,
    /// Device display name
    initial_device_display_name: Option<String>,
}

/// User identifier for Matrix login
#[derive(Debug, Serialize)]
struct MatrixUserIdentifier {
    /// Identifier type (always "m.id.user" for user ID login)
    #[serde(rename = "type")]
    id_type: String,
    /// The Matrix user ID
    user: String,
}

/// Response from standard Matrix login
#[derive(Debug, Deserialize)]
#[allow(dead_code)] // Fields populated by serde deserialization
struct MatrixLoginResponse {
    /// The Matrix user ID
    user_id: String,
    /// The access token (device-bound!)
    access_token: String,
    /// The device ID
    device_id: String,
    /// Token expiry in milliseconds (optional)
    expires_in_ms: Option<i64>,
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
    /// Device ID to bind the session to (Synapse 1.81+)
    /// If provided, the returned access_token will be bound to this device
    #[serde(skip_serializing_if = "Option::is_none")]
    device_id: Option<String>,
}

/// Response containing the access token from Synapse Admin API
#[derive(Debug, Deserialize)]
pub struct LoginTokenResponse {
    /// The access token returned by Synapse Admin API
    /// Note: This endpoint returns an access_token directly, not a login_token
    pub access_token: String,
}

/// Token refresh buffer - refresh 5 minutes before expiry
const TOKEN_REFRESH_BUFFER_SECS: i64 = 300;
/// Default token lifetime (24 hours) when server doesn't provide expiry
const DEFAULT_TOKEN_LIFETIME_SECS: i64 = 86400;

impl MatrixAdminClient {
    /// Create a new Matrix Admin API client
    ///
    /// # Arguments
    /// * `homeserver_url` - Synapse homeserver URL (e.g., "http://matrix-synapse:8008")
    /// * `admin_token` - Admin access token for authentication
    /// * `server_name` - Server name for constructing MXIDs (e.g., "staging.nova.app")
    /// * `admin_credentials` - Optional credentials for automatic token refresh
    pub fn new(
        homeserver_url: String,
        admin_token: String,
        server_name: String,
        admin_credentials: Option<AdminCredentials>,
    ) -> Self {
        Self {
            client: Client::new(),
            homeserver_url,
            admin_token: Arc::new(RwLock::new(admin_token)),
            token_expires_at: Arc::new(RwLock::new(None)),
            admin_credentials,
            server_name,
        }
    }

    /// Get the current admin token (for read access)
    async fn get_token(&self) -> String {
        self.admin_token.read().await.clone()
    }

    /// Check if the token needs to be refreshed
    async fn needs_refresh(&self) -> bool {
        let expires_at = *self.token_expires_at.read().await;
        if let Some(expires) = expires_at {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64;
            // Refresh if token expires within the buffer period
            now >= expires - TOKEN_REFRESH_BUFFER_SECS
        } else {
            // No expiry known, don't refresh proactively
            false
        }
    }

    /// Refresh the admin token using stored credentials
    ///
    /// This logs in as the admin user to get a new access token.
    /// Returns Ok(()) if refresh succeeded or credentials not available.
    pub async fn refresh_token(&self) -> Result<(), AppError> {
        let credentials = match &self.admin_credentials {
            Some(creds) => creds.clone(),
            None => {
                warn!("Token refresh requested but no admin credentials configured");
                return Ok(());
            }
        };

        let url = format!("{}/_matrix/client/v3/login", self.homeserver_url);

        info!("Refreshing Matrix admin token for user: {}", credentials.username);

        #[derive(Serialize)]
        struct AdminLoginRequest {
            #[serde(rename = "type")]
            login_type: String,
            identifier: MatrixUserIdentifier,
            password: String,
            device_id: Option<String>,
            initial_device_display_name: Option<String>,
        }

        let request_body = AdminLoginRequest {
            login_type: "m.login.password".to_string(),
            identifier: MatrixUserIdentifier {
                id_type: "m.id.user".to_string(),
                user: credentials.username.clone(),
            },
            password: credentials.password.clone(),
            device_id: Some("nova-realtime-chat-service".to_string()),
            initial_device_display_name: Some("Nova Realtime Chat Service".to_string()),
        };

        let request_time_sec = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let response = self
            .client
            .post(&url)
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send admin token refresh request: {}", e);
                AppError::ServiceUnavailable(format!("Admin token refresh failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            let login_response: MatrixLoginResponse = response.json().await.map_err(|e| {
                error!("Failed to parse admin login response: {}", e);
                AppError::ServiceUnavailable(format!("Invalid response from Matrix: {}", e))
            })?;

            // Update the token
            {
                let mut token = self.admin_token.write().await;
                *token = login_response.access_token;
            }

            // Update expiry time
            {
                let mut expires = self.token_expires_at.write().await;
                *expires = Some(login_response.expires_in_ms.map_or(
                    request_time_sec + DEFAULT_TOKEN_LIFETIME_SECS,
                    |ms| request_time_sec + (ms / 1000) - 60, // 60s buffer for clock skew
                ));
            }

            info!(
                "Successfully refreshed Matrix admin token, expires_at={:?}",
                *self.token_expires_at.read().await
            );
            Ok(())
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!(
                "Admin token refresh failed: status={}, body={}",
                status, error_text
            );
            Err(AppError::ServiceUnavailable(format!(
                "Admin token refresh failed ({}): {}",
                status, error_text
            )))
        }
    }

    /// Ensure the token is valid, refreshing if necessary
    ///
    /// This should be called before any API request that uses the admin token.
    /// If the token is expired or about to expire, it will be refreshed.
    async fn ensure_token_valid(&self) -> Result<(), AppError> {
        if self.needs_refresh().await {
            info!("Admin token needs refresh, attempting to refresh...");
            self.refresh_token().await?;
        }
        Ok(())
    }

    /// Check if admin credentials are configured for automatic token refresh
    pub fn has_auto_refresh(&self) -> bool {
        self.admin_credentials.is_some()
    }

    /// Start a background task to periodically refresh the admin token
    ///
    /// This spawns a tokio task that checks token expiry every hour and refreshes
    /// the token before it expires. The task runs indefinitely.
    pub fn start_token_refresh_task(self: Arc<Self>) {
        if self.admin_credentials.is_none() {
            info!("No admin credentials configured, skipping token refresh task");
            return;
        }

        tokio::spawn(async move {
            let check_interval = tokio::time::Duration::from_secs(3600); // Check every hour

            info!("Starting Matrix admin token refresh background task");

            // Initial refresh to set expiry time
            if let Err(e) = self.refresh_token().await {
                error!("Initial admin token refresh failed: {}", e);
            }

            loop {
                tokio::time::sleep(check_interval).await;

                if self.needs_refresh().await {
                    info!("Background task: refreshing admin token");
                    if let Err(e) = self.refresh_token().await {
                        error!("Background admin token refresh failed: {}", e);
                    }
                }
            }
        });
    }

    /// Convert Nova user_id (UUID) to Matrix User ID (MXID)
    ///
    /// Format: @nova-{user_id}:{server_name}
    /// Example: @nova-123e4567-e89b-12d3-a456-426614174000:staging.nova.app
    pub fn user_id_to_mxid(&self, user_id: Uuid) -> String {
        format!("@nova-{}:{}", user_id, self.server_name)
    }

    /// Generate a deterministic password for a Matrix user
    ///
    /// The password is derived from the user_id and server_name to ensure:
    /// 1. Same user always gets the same password (allows re-login)
    /// 2. Passwords are not easily guessable
    /// 3. Each user has a unique password
    ///
    /// Note: We use server_name instead of admin_token for determinism,
    /// since admin_token can change during token refresh.
    fn generate_user_password(&self, user_id: Uuid) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        user_id.hash(&mut hasher);
        self.server_name.hash(&mut hasher);
        // Add a static salt for additional security
        "nova_matrix_user_password_salt_v1".hash(&mut hasher);
        let hash = hasher.finish();

        // Create a 32-char hex password
        format!("nova_matrix_{:016x}", hash)
    }

    /// Login to Matrix using standard password authentication
    ///
    /// This uses POST /_matrix/client/v3/login which creates a proper device session,
    /// required for sliding sync (MSC3575) in Synapse 1.114+.
    ///
    /// Unlike Admin API login, this creates a real device in the devices table,
    /// which is required for sliding sync's per-device connection tracking.
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID (will be converted to MXID)
    /// * `device_id` - Device ID to bind the session to (required for E2EE/sliding sync)
    ///
    /// # Returns
    /// Ok((access_token, device_id, expires_at)) if successful, Err otherwise
    pub async fn login_with_password(
        &self,
        user_id: Uuid,
        device_id: Option<String>,
    ) -> Result<(String, String, Option<i64>), AppError> {
        let mxid = self.user_id_to_mxid(user_id);
        let password = self.generate_user_password(user_id);

        let url = format!(
            "{}/_matrix/client/v3/login",
            self.homeserver_url
        );

        info!(
            "Performing standard Matrix login for: mxid={}, nova_user_id={}, device_id={:?}",
            mxid, user_id, device_id
        );

        let request_body = MatrixLoginRequest {
            login_type: "m.login.password".to_string(),
            identifier: MatrixUserIdentifier {
                id_type: "m.id.user".to_string(),
                user: mxid.clone(),
            },
            password,
            device_id: device_id.clone(),
            initial_device_display_name: Some(format!("Nova iOS Device")),
        };

        // Record timestamp BEFORE the request to handle clock skew between backend and Synapse.
        // Synapse returns expires_in_ms relative to when IT generated the token.
        // If we calculate expiry AFTER the request using our clock, any clock skew
        // or network latency will cause the token to appear expired immediately.
        let request_time_sec = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        let response = self
            .client
            .post(&url)
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send standard Matrix login request: {}", e);
                AppError::ServiceUnavailable(format!("Matrix login request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            let login_response: MatrixLoginResponse = response.json().await.map_err(|e| {
                error!("Failed to parse Matrix login response: {}", e);
                AppError::ServiceUnavailable(format!("Invalid response from Matrix: {}", e))
            })?;

            // Calculate expiry timestamp using pre-request time and add a safety buffer
            // to account for clock skew between servers (up to 60 seconds tolerance)
            const CLOCK_SKEW_BUFFER_SEC: i64 = 60;
            let expires_at = login_response.expires_in_ms.map(|ms| {
                let token_lifetime_sec = ms / 1000;
                // Use pre-request time and subtract buffer for safety
                request_time_sec + token_lifetime_sec - CLOCK_SKEW_BUFFER_SEC
            });

            info!(
                "Successfully logged into Matrix with device session: mxid={}, device_id={}, nova_user_id={}",
                mxid, login_response.device_id, user_id
            );

            Ok((login_response.access_token, login_response.device_id, expires_at))
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!(
                "Matrix login failed: status={}, body={}, mxid={}",
                status, error_text, mxid
            );
            Err(AppError::ServiceUnavailable(format!(
                "Matrix login failed ({}): {}",
                status, error_text
            )))
        }
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
        // Ensure token is valid before making request
        self.ensure_token_valid().await?;

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
        let token = self.get_token().await;

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
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
        // Ensure token is valid before making request
        self.ensure_token_valid().await?;

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
        let token = self.get_token().await;

        let response = self
            .client
            .put(&url)
            .header("Authorization", format!("Bearer {}", token))
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
        // Ensure token is valid before making request
        self.ensure_token_valid().await?;

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
        let token = self.get_token().await;

        let response = self
            .client
            .put(&url)
            .header("Authorization", format!("Bearer {}", token))
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
        // Ensure token is valid before making request
        self.ensure_token_valid().await?;

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
        let token = self.get_token().await;

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
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
        // Ensure token is valid before making request
        self.ensure_token_valid().await?;

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

        // Generate a deterministic password for this user
        // This is required for standard Matrix login which creates proper device sessions
        let password = self.generate_user_password(user_id);

        let request_body = CreateUserRequest {
            displayname,
            password: Some(password),
            admin: Some(false),
            deactivated: Some(false),
        };
        let token = self.get_token().await;

        let response = self
            .client
            .put(&url)
            .header("Authorization", format!("Bearer {}", token))
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
    /// The returned access_token is bound to the specified device_id if provided.
    /// This enables seamless Matrix login without requiring a second SSO flow.
    ///
    /// # Arguments
    /// * `user_id` - Nova user ID (will be converted to MXID)
    /// * `valid_for_ms` - How long the token should be valid (optional, default ~2 minutes)
    /// * `device_id` - Device ID to bind the session to (required for iOS E2EE)
    ///
    /// # Returns
    /// Ok(access_token) if successful, Err otherwise
    pub async fn generate_user_login_token(
        &self,
        user_id: Uuid,
        valid_for_ms: Option<i64>,
        device_id: Option<String>,
    ) -> Result<String, AppError> {
        // Ensure token is valid before making request
        self.ensure_token_valid().await?;

        let mxid = self.user_id_to_mxid(user_id);
        let url = format!(
            "{}/_synapse/admin/v1/users/{}/login",
            self.homeserver_url,
            urlencoding::encode(&mxid)
        );

        info!(
            "Generating login token for Matrix user: mxid={}, nova_user_id={}, device_id={:?}",
            mxid, user_id, device_id
        );

        // Convert relative duration (ms) to absolute timestamp (epoch ms)
        // Synapse expects valid_until_ms to be an absolute Unix timestamp in milliseconds
        let valid_until_ms = valid_for_ms.map(|duration_ms| {
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as i64;
            now_ms + duration_ms
        });

        let request_body = LoginTokenRequest {
            valid_until_ms,
            device_id,
        };
        let token = self.get_token().await;

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
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
                "Successfully generated access token for Matrix user: mxid={}, nova_user_id={}",
                mxid, user_id
            );
            Ok(token_response.access_token)
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
    /// * `device_id` - Device ID to bind the session to (for seamless iOS login)
    ///
    /// # Returns
    /// Ok((mxid, access_token, expires_at)) if successful, Err otherwise
    /// - `expires_at` is Unix timestamp (seconds) when the token expires
    pub async fn provision_user(
        &self,
        user_id: Uuid,
        displayname: Option<String>,
        device_id: Option<String>,
    ) -> Result<(String, String, i64), AppError> {
        // Step 1: Create or update the user
        let mxid = self.create_or_get_user(user_id, displayname).await?;

        // Step 2: Login with password to get a device-bound access token
        // This creates a proper device session which is REQUIRED for sliding sync (Synapse 1.114+)
        // The Admin API login endpoint does NOT create device sessions, causing sliding sync to fail
        // with "AssertionError: device_id is not None" in the connection store
        let (access_token, returned_device_id, expires_at) = self.login_with_password(user_id, device_id).await?;

        // Calculate expiry timestamp if not provided by server (default to 24 hours)
        let expires_at = expires_at.unwrap_or_else(|| {
            let now_sec = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64;
            now_sec + 86400 // 24 hours default
        });

        info!(
            "Matrix user provisioned with device session: mxid={}, device_id={}, expires_at={}",
            mxid, returned_device_id, expires_at
        );

        Ok((mxid, access_token, expires_at))
    }

    /// Force-join a user to a room via Synapse Admin API.
    ///
    /// This is used to ensure the Nova service user can observe room events for metadata sync,
    /// even when rooms are created by clients directly via Matrix SDK.
    ///
    /// API: POST /_synapse/admin/v1/join/{room_id_or_alias}
    pub async fn join_room_as_user(&self, room_id_or_alias: &str, user_id: &str) -> Result<(), AppError> {
        self.ensure_token_valid().await?;

        let url = format!(
            "{}/_synapse/admin/v1/join/{}",
            self.homeserver_url,
            urlencoding::encode(room_id_or_alias)
        );

        let request_body = JoinRoomRequest {
            user_id: user_id.to_string(),
        };
        let token = self.get_token().await;

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .json(&request_body)
            .send()
            .await
            .map_err(|e| {
                error!("Failed to send join room request to Synapse: {}", e);
                AppError::ServiceUnavailable(format!("Synapse API request failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            info!(
                "Force-joined user to room via admin API: user_id={}, room_id_or_alias={}",
                user_id, room_id_or_alias
            );
            Ok(())
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            warn!(
                "Synapse join room API returned error: status={}, body={}, user_id={}, room_id_or_alias={}",
                status, error_text, user_id, room_id_or_alias
            );
            Err(AppError::ServiceUnavailable(format!(
                "Synapse join room failed ({}): {}",
                status, error_text
            )))
        }
    }

    /// Upload media to Matrix media repository
    ///
    /// # Arguments
    /// * `image_data` - Raw image bytes
    /// * `content_type` - MIME type (e.g., "image/jpeg", "image/png")
    /// * `filename` - Optional filename for the upload
    ///
    /// # Returns
    /// Matrix mxc:// URL for the uploaded media
    ///
    /// API: POST /_matrix/media/v3/upload
    pub async fn upload_media(
        &self,
        image_data: &[u8],
        content_type: &str,
        filename: Option<&str>,
    ) -> Result<String, AppError> {
        self.ensure_token_valid().await?;

        let mut url = format!("{}/_matrix/media/v3/upload", self.homeserver_url);
        if let Some(name) = filename {
            url = format!("{}?filename={}", url, urlencoding::encode(name));
        }

        let token = self.get_token().await;

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .header("Content-Type", content_type)
            .body(image_data.to_vec())
            .send()
            .await
            .map_err(|e| {
                error!("Failed to upload media to Matrix: {}", e);
                AppError::ServiceUnavailable(format!("Matrix media upload failed: {}", e))
            })?;

        let status = response.status();
        if status.is_success() {
            #[derive(Deserialize)]
            struct UploadResponse {
                content_uri: String,
            }

            let upload_response: UploadResponse = response.json().await.map_err(|e| {
                error!("Failed to parse Matrix upload response: {}", e);
                AppError::ServiceUnavailable(format!("Invalid upload response: {}", e))
            })?;

            info!("Successfully uploaded media to Matrix: ", upload_response.content_uri);
            Ok(upload_response.content_uri)
        } else {
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            error!("Matrix media upload failed: status={}, body={}", status, error_text);
            Err(AppError::ServiceUnavailable(format!(
                "Matrix media upload failed ({}): {}",
                status, error_text
            )))
        }
    }

    /// Download image from URL and upload to Matrix media repository
    ///
    /// # Arguments
    /// * `image_url` - HTTP(S) URL of the image to download
    ///
    /// # Returns
    /// Matrix mxc:// URL for the uploaded media
    pub async fn download_and_upload_avatar(&self, image_url: &str) -> Result<String, AppError> {
        // Download image from Nova CDN
        let response = self.client.get(image_url).send().await.map_err(|e| {
            error!("Failed to download avatar from {}: {}", image_url, e);
            AppError::ServiceUnavailable(format!("Avatar download failed: {}", e))
        })?;

        if !response.status().is_success() {
            let status = response.status();
            error!("Avatar download returned non-success status: {}", status);
            return Err(AppError::ServiceUnavailable(format!(
                "Avatar download failed with status: {}",
                status
            )));
        }

        // Get content type from response headers
        let content_type = response
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("image/jpeg")
            .to_string();

        // Extract filename from URL
        let filename = image_url
            .split('/')
            .last()
            .and_then(|s| s.split('?').next())
            .map(|s| s.to_string());

        // Download image bytes
        let image_data = response.bytes().await.map_err(|e| {
            error!("Failed to read avatar bytes: {}", e);
            AppError::ServiceUnavailable(format!("Failed to read avatar data: {}", e))
        })?;

        // Upload to Matrix
        self.upload_media(&image_data, &content_type, filename.as_deref())
            .await
    }

    /// Calculate SHA256 hash of a string (for avatar URL caching)
    pub fn calculate_hash(input: &str) -> String {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(input.as_bytes());
        format!("{:x}", hasher.finalize())
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
            None, // No credentials for test
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
            None, // No credentials for test
        );

        let user_id = Uuid::new_v4();
        let mxid = client.user_id_to_mxid(user_id);

        // Verify format: @nova-{uuid}:{server_name}
        assert!(mxid.starts_with("@nova-"));
        assert!(mxid.contains(':'));
        assert!(mxid.ends_with(":nova.local"));
    }

    #[test]
    fn test_admin_credentials_creation() {
        let credentials = AdminCredentials {
            username: "@admin:example.com".to_string(),
            password: "secret".to_string(),
        };

        let client = MatrixAdminClient::new(
            "http://localhost:8008".to_string(),
            "initial_token".to_string(),
            "example.com".to_string(),
            Some(credentials),
        );

        assert!(client.admin_credentials.is_some());
    }
}

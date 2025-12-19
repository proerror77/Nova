//! Identity Service gRPC Client
//!
//! P0: dm_permission Single Source of Truth
//! Consolidates user settings operations to go through identity-service
//! instead of local PostgreSQL queries.

use crate::error::AppError;
use grpc_clients::nova::identity_service::v2::{GetUserSettingsRequest, UserSettings};
use grpc_clients::{config::GrpcConfig, GrpcClientPool};
use std::sync::Arc;
use tonic::Request;
use uuid::Uuid;

/// DM permission settings (read from identity-service)
#[derive(Debug, Clone)]
pub struct DmSettings {
    pub dm_permission: String,
    pub allow_messages: bool,
}

impl Default for DmSettings {
    fn default() -> Self {
        Self {
            // Default to 'mutuals' for safety (most restrictive reasonable default)
            dm_permission: "mutuals".to_string(),
            allow_messages: true,
        }
    }
}

impl From<UserSettings> for DmSettings {
    fn from(settings: UserSettings) -> Self {
        // dm_permission is an i32 enum: 0=none, 1=mutuals, 2=verified, 3=everyone
        // Convert to string representation
        let dm_permission_str = match settings.dm_permission {
            0 => "none",
            1 => "mutuals",
            2 => "verified",
            3 => "everyone",
            _ => "mutuals", // Default to mutuals for unknown values
        };
        // allow_messages is derived from dm_permission: 0 (none) means no messages allowed
        let allow_messages = settings.dm_permission != 0;
        Self {
            dm_permission: dm_permission_str.to_string(),
            allow_messages,
        }
    }
}

/// Cached gRPC client for identity-service (user settings)
/// Single source of truth for dm_permission and related settings
#[derive(Clone)]
pub struct IdentityClient {
    pool: Arc<GrpcClientPool>,
}

impl IdentityClient {
    /// Create a new identity client
    pub async fn new() -> Result<Self, AppError> {
        let cfg = GrpcConfig::from_env()
            .map_err(|e| AppError::StartServer(format!("Failed to load gRPC config: {}", e)))?;

        let pool = GrpcClientPool::new(&cfg)
            .await
            .map_err(|e| AppError::StartServer(format!("Failed to init gRPC pool: {}", e)))?;

        Ok(Self {
            pool: Arc::new(pool),
        })
    }

    /// Create from existing pool (preferred - avoids duplicate connections)
    pub fn from_pool(pool: Arc<GrpcClientPool>) -> Self {
        Self { pool }
    }

    /// Get DM settings for a user from identity-service
    /// 
    /// This is the SINGLE SOURCE OF TRUTH for dm_permission.
    /// Do NOT use local database queries for dm_permission.
    pub async fn get_dm_settings(&self, user_id: Uuid) -> Result<DmSettings, AppError> {
        let mut client = self.pool.auth();
        let request = Request::new(GetUserSettingsRequest {
            user_id: user_id.to_string(),
        });

        match client.get_user_settings(request).await {
            Ok(response) => {
                let resp = response.into_inner();
                
                // Check for error in response
                if let Some(error) = resp.error {
                    tracing::warn!(
                        user_id = %user_id,
                        error_code = %error.code,
                        error_message = %error.message,
                        "identity-service returned error for get_user_settings"
                    );
                    // Return default settings on error (fail-open for DMs)
                    return Ok(DmSettings::default());
                }

                match resp.settings {
                    Some(settings) => Ok(DmSettings::from(settings)),
                    None => {
                        // No settings found - user may not have configured yet
                        // Return default settings
                        tracing::debug!(
                            user_id = %user_id,
                            "No user settings found, using defaults"
                        );
                        Ok(DmSettings::default())
                    }
                }
            }
            Err(status) => {
                tracing::error!(
                    user_id = %user_id,
                    status = ?status.code(),
                    message = %status.message(),
                    "identity-service get_user_settings failed"
                );
                // Fail-open: return default settings to not block messaging
                // This allows chat to function even if identity-service is temporarily unavailable
                Ok(DmSettings::default())
            }
        }
    }

    /// Get full user settings from identity-service
    pub async fn get_user_settings(&self, user_id: Uuid) -> Result<Option<UserSettings>, AppError> {
        let mut client = self.pool.auth();
        let request = Request::new(GetUserSettingsRequest {
            user_id: user_id.to_string(),
        });

        match client.get_user_settings(request).await {
            Ok(response) => {
                let resp = response.into_inner();
                if resp.error.is_some() {
                    return Ok(None);
                }
                Ok(resp.settings)
            }
            Err(status) => {
                tracing::error!(
                    user_id = %user_id,
                    status = ?status.code(),
                    message = %status.message(),
                    "identity-service get_user_settings failed"
                );
                Err(AppError::GrpcClient(format!(
                    "identity-service error: {}",
                    status.message()
                )))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dm_settings_default() {
        let settings = DmSettings::default();
        assert_eq!(settings.dm_permission, "mutuals");
        assert!(settings.allow_messages);
    }
}

//! Auth Service gRPC Client
//!
//! Phase 1: Spec 007 - Users Consolidation
//! Consolidates user lookups to go through canonical auth-service instead of
//! the shadow users table in messaging-service.

use crate::auth_service::auth_service_client::AuthServiceClient;
use crate::auth_service::{CheckUserExistsRequest, GetUserRequest};
use crate::error::AppError;
use std::sync::Arc;
use tonic::transport::Channel;
use uuid::Uuid;

/// Cached gRPC client for auth-service
/// Implements connection pooling and reuse via tonic channel
#[derive(Clone)]
pub struct AuthClient {
    client: Arc<tokio::sync::Mutex<AuthServiceClient<Channel>>>,
}

impl AuthClient {
    /// Create a new auth client
    pub async fn new(auth_service_url: &str) -> Result<Self, AppError> {
        let channel = Channel::from_shared(auth_service_url.to_string())
            .map_err(|e| AppError::StartServer(format!("Invalid auth service URL: {}", e)))?
            .connect()
            .await
            .map_err(|e| {
                AppError::StartServer(format!("Failed to connect to auth-service: {}", e))
            })?;

        Ok(Self {
            client: Arc::new(tokio::sync::Mutex::new(AuthServiceClient::new(channel))),
        })
    }

    /// Check if a user exists by ID
    /// Replaces: SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)
    pub async fn user_exists(&self, user_id: Uuid) -> Result<bool, AppError> {
        let mut client = self.client.lock().await;
        let request = tonic::Request::new(CheckUserExistsRequest {
            user_id: user_id.to_string(),
        });

        match client.check_user_exists(request).await {
            Ok(response) => Ok(response.into_inner().exists),
            Err(status) => {
                // gRPC errors: rethrow as our AppError
                tracing::error!(
                    user_id = %user_id,
                    status = ?status.code(),
                    message = %status.message(),
                    "auth-service check_user_exists failed"
                );
                Err(AppError::StartServer(format!(
                    "auth-service error: {}",
                    status.message()
                )))
            }
        }
    }

    /// Get user by ID
    /// Replaces: SELECT username FROM users WHERE id = $1
    pub async fn get_user(&self, user_id: Uuid) -> Result<Option<String>, AppError> {
        let mut client = self.client.lock().await;
        let request = tonic::Request::new(GetUserRequest {
            user_id: user_id.to_string(),
        });

        match client.get_user(request).await {
            Ok(response) => {
                let user = response.into_inner().user;
                match user {
                    Some(u) => Ok(Some(u.username)),
                    None => Ok(None),
                }
            }
            Err(status) => {
                // If user not found, return None (NOT error)
                if status.code() == tonic::Code::NotFound {
                    Ok(None)
                } else {
                    tracing::error!(
                        user_id = %user_id,
                        status = ?status.code(),
                        message = %status.message(),
                        "auth-service get_user failed"
                    );
                    Err(AppError::StartServer(format!(
                        "auth-service error: {}",
                        status.message()
                    )))
                }
            }
        }
    }
}

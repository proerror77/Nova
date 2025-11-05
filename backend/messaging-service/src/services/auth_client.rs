//! Auth Service gRPC Client
//!
//! Phase 1: Spec 007 - Users Consolidation
//! Consolidates user lookups to go through canonical auth-service instead of
//! the shadow users table in messaging-service.

use grpc_clients::nova::auth_service::v1::{CheckUserExistsRequest, GetUserRequest};
use grpc_clients::{config::GrpcConfig, GrpcClientPool};
use crate::error::AppError;
use std::sync::Arc;
use tonic::Request;
use uuid::Uuid;

/// Cached gRPC client for auth-service
/// Implements connection pooling and reuse via tonic channel
#[derive(Clone)]
pub struct AuthClient { pool: Arc<GrpcClientPool> }

impl AuthClient {
    /// Create a new auth client
    pub async fn new(_auth_service_url: &str) -> Result<Self, AppError> {
        // Prefer centralized gRPC config from env (URL is ignored once centralized pool is used)
        let cfg = GrpcConfig::from_env().map_err(|e| {
            AppError::StartServer(format!("Failed to load gRPC config: {}", e))
        })?;

        let pool = GrpcClientPool::new(&cfg)
            .await
            .map_err(|e| AppError::StartServer(format!("Failed to init gRPC pool: {}", e)))?;

        Ok(Self { pool: Arc::new(pool) })
    }

    /// Check if a user exists by ID
    /// Replaces: SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)
    pub async fn user_exists(&self, user_id: Uuid) -> Result<bool, AppError> {
        let mut client = self.pool.auth();
        let request = Request::new(CheckUserExistsRequest {
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
        let mut client = self.pool.auth();
        let request = Request::new(GetUserRequest {
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

//! Graph Service gRPC Client
//!
//! P0: user-service Deletion Migration
//! Consolidates block/follow relationship operations to go through graph-service
//! instead of direct PostgreSQL queries.

use crate::error::AppError;
use grpc_clients::nova::graph_service::v2::{
    AreMutualFollowersRequest, HasBlockBetweenRequest, IsBlockedRequest, IsFollowingRequest,
};
use grpc_clients::{config::GrpcConfig, GrpcClientPool};
use std::sync::Arc;
use tonic::Request;
use uuid::Uuid;

/// Cached gRPC client for graph-service
/// Implements connection pooling and reuse via tonic channel
#[derive(Clone)]
pub struct GraphClient {
    pool: Arc<GrpcClientPool>,
}

impl GraphClient {
    /// Create a new graph client
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

    /// Check if user_a is blocked by user_b
    /// Replaces: SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2
    pub async fn is_blocked(&self, blocker_id: Uuid, blocked_id: Uuid) -> Result<bool, AppError> {
        let mut client = self.pool.graph();
        let request = Request::new(IsBlockedRequest {
            blocker_id: blocker_id.to_string(),
            blocked_id: blocked_id.to_string(),
        });

        match client.is_blocked(request).await {
            Ok(response) => Ok(response.into_inner().is_blocked),
            Err(status) => {
                tracing::error!(
                    blocker_id = %blocker_id,
                    blocked_id = %blocked_id,
                    status = ?status.code(),
                    message = %status.message(),
                    "graph-service is_blocked failed"
                );
                Err(AppError::GrpcClient(format!(
                    "graph-service error: {}",
                    status.message()
                )))
            }
        }
    }

    /// Check if either user has blocked the other (bidirectional)
    /// Replaces: SELECT 1 FROM blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)
    pub async fn has_block_between(
        &self,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<(bool, bool, bool), AppError> {
        let mut client = self.pool.graph();
        let request = Request::new(HasBlockBetweenRequest {
            user_a: user_a.to_string(),
            user_b: user_b.to_string(),
        });

        match client.has_block_between(request).await {
            Ok(response) => {
                let r = response.into_inner();
                Ok((r.has_block, r.a_blocked_b, r.b_blocked_a))
            }
            Err(status) => {
                tracing::error!(
                    user_a = %user_a,
                    user_b = %user_b,
                    status = ?status.code(),
                    message = %status.message(),
                    "graph-service has_block_between failed"
                );
                Err(AppError::GrpcClient(format!(
                    "graph-service error: {}",
                    status.message()
                )))
            }
        }
    }

    /// Check if follower_id follows following_id
    /// Replaces: SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2
    pub async fn is_following(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
    ) -> Result<bool, AppError> {
        let mut client = self.pool.graph();
        let request = Request::new(IsFollowingRequest {
            follower_id: follower_id.to_string(),
            followee_id: followee_id.to_string(),
        });

        match client.is_following(request).await {
            Ok(response) => Ok(response.into_inner().is_following),
            Err(status) => {
                tracing::error!(
                    follower_id = %follower_id,
                    followee_id = %followee_id,
                    status = ?status.code(),
                    message = %status.message(),
                    "graph-service is_following failed"
                );
                Err(AppError::GrpcClient(format!(
                    "graph-service error: {}",
                    status.message()
                )))
            }
        }
    }

    /// Check if two users follow each other (mutual follows)
    /// Replaces: SELECT COUNT(*) FROM follows WHERE (follower_id = $1 AND following_id = $2) OR (follower_id = $2 AND following_id = $1)
    pub async fn are_mutual_followers(
        &self,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<(bool, bool, bool), AppError> {
        let mut client = self.pool.graph();
        let request = Request::new(AreMutualFollowersRequest {
            user_a: user_a.to_string(),
            user_b: user_b.to_string(),
        });

        match client.are_mutual_followers(request).await {
            Ok(response) => {
                let r = response.into_inner();
                Ok((r.are_mutuals, r.a_follows_b, r.b_follows_a))
            }
            Err(status) => {
                tracing::error!(
                    user_a = %user_a,
                    user_b = %user_b,
                    status = ?status.code(),
                    message = %status.message(),
                    "graph-service are_mutual_followers failed"
                );
                Err(AppError::GrpcClient(format!(
                    "graph-service error: {}",
                    status.message()
                )))
            }
        }
    }
}

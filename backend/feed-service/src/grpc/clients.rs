use grpc_clients::nova::content_service::v1::{
    GetPostsByAuthorRequest, GetPostsByAuthorResponse, GetPostsByIdsRequest, GetPostsByIdsResponse,
};
use grpc_clients::nova::user_service::v1::{
    GetUserFollowingRequest, GetUserFollowingResponse, GetUserProfilesByIdsRequest,
    GetUserProfilesByIdsResponse,
};
/// gRPC clients for calling other services (centralized)
///
/// Feed Service orchestrates data from UserService and ContentService
/// to generate personalized feeds without direct database queries.
use grpc_clients::{config::GrpcConfig, GrpcClientPool};
use std::sync::Arc;
use tonic::Status;

/// Content Service gRPC Client
/// Provides access to posts, comments, and likes
#[derive(Clone)]
pub struct ContentServiceClient {
    pool: Arc<GrpcClientPool>,
}

impl ContentServiceClient {
    /// Create new ContentServiceClient
    pub async fn new(_addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        let cfg = GrpcConfig::from_env()?;
        let pool = GrpcClientPool::new(&cfg).await?;
        Ok(Self {
            pool: Arc::new(pool),
        })
    }

    /// Get posts by author
    pub async fn get_posts_by_author(
        &self,
        request: GetPostsByAuthorRequest,
    ) -> Result<GetPostsByAuthorResponse, Status> {
        let mut client = self.pool.content();
        client
            .get_posts_by_author(request)
            .await
            .map(|resp| resp.into_inner())
    }

    /// Get posts by IDs (batch operation to prevent N+1)
    pub async fn get_posts_by_ids(
        &self,
        request: GetPostsByIdsRequest,
    ) -> Result<GetPostsByIdsResponse, Status> {
        let mut client = self.pool.content();
        client
            .get_posts_by_ids(request)
            .await
            .map(|resp| resp.into_inner())
    }
}

/// User Service gRPC Client
/// Provides access to user profiles and relationships
#[derive(Clone)]
pub struct UserServiceClient {
    pool: Arc<GrpcClientPool>,
}

impl UserServiceClient {
    /// Create new UserServiceClient
    pub async fn new(_addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        let cfg = GrpcConfig::from_env()?;
        let pool = GrpcClientPool::new(&cfg).await?;
        Ok(Self {
            pool: Arc::new(pool),
        })
    }

    /// Get users this user is following
    pub async fn get_user_following(
        &self,
        request: GetUserFollowingRequest,
    ) -> Result<GetUserFollowingResponse, Status> {
        let mut client = self.pool.user();
        client
            .get_user_following(request)
            .await
            .map(|resp| resp.into_inner())
    }

    /// Get multiple user profiles by IDs (batch operation)
    pub async fn get_user_profiles_by_ids(
        &self,
        request: GetUserProfilesByIdsRequest,
    ) -> Result<GetUserProfilesByIdsResponse, Status> {
        let mut client = self.pool.user();
        client
            .get_user_profiles_by_ids(request)
            .await
            .map(|resp| resp.into_inner())
    }
}

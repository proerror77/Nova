/// gRPC clients for calling other services (centralized)
use grpc_clients::{config::GrpcConfig, GrpcClientPool};
use grpc_clients::nova::content_service::v1::{
    GetFeedRequest, GetFeedResponse, InvalidateFeedEventRequest, InvalidateFeedResponse,
};
use std::sync::Arc;

/// Content Service gRPC Client
#[derive(Clone)]
pub struct ContentServiceClient {
    pool: Arc<GrpcClientPool>,
}

impl ContentServiceClient {
    /// Create new ContentServiceClient
    pub async fn new(_addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        // Prefer centralized config from env; ignore addr once centralized pool is used
        let cfg = GrpcConfig::from_env()?;
        let pool = GrpcClientPool::new(&cfg).await?;
        Ok(Self { pool: Arc::new(pool) })
    }

    /// Get feed for user
    pub async fn get_feed(
        &self,
        request: GetFeedRequest,
    ) -> Result<GetFeedResponse, std::io::Error> {
        let mut client = self.pool.content();
        client
            .get_feed(request)
            .await
            .map(|resp| resp.into_inner())
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))
    }

    /// Invalidate feed event
    pub async fn invalidate_feed_event(
        &self,
        request: InvalidateFeedEventRequest,
    ) -> Result<InvalidateFeedResponse, std::io::Error> {
        let mut client = self.pool.content();
        client
            .invalidate_feed_event(request)
            .await
            .map(|resp| resp.into_inner())
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))
    }
}

/// User Service gRPC Client (for future use)
#[derive(Clone)]
pub struct UserServiceClient {
    // TODO: implement when proto is ready
}

impl UserServiceClient {
    pub async fn new(_addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {})
    }
}

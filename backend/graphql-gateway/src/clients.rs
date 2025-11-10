//! gRPC service clients for backend integration

use tonic::transport::Channel;
use std::error::Error;

// Common protos - must be at crate root so generated code can find it
pub mod common {
    pub mod v1 {
        tonic::include_proto!("nova.common.v1");
    }
    pub use v1::*;
}

// Proto module definitions from build.rs
pub mod proto {
    pub mod auth {
        tonic::include_proto!("nova.auth_service.v1");
    }

    pub mod user {
        tonic::include_proto!("nova.user_service.v1");
    }

    pub mod content {
        tonic::include_proto!("nova.content_service.v1");
    }

    pub mod feed {
        tonic::include_proto!("nova.feed_service.v1");
    }
}

use proto::auth::auth_service_client::AuthServiceClient;
use proto::user::user_service_client::UserServiceClient;
use proto::content::content_service_client::ContentServiceClient;
use proto::feed::recommendation_service_client::RecommendationServiceClient;

/// Service client manager for gRPC communication
#[derive(Clone)]
pub struct ServiceClients {
    pub auth_endpoint: String,
    pub user_endpoint: String,
    pub content_endpoint: String,
    pub feed_endpoint: String,
}

impl Default for ServiceClients {
    fn default() -> Self {
        Self {
            auth_endpoint: "http://auth-service.nova-backend.svc.cluster.local:9083".to_string(),
            user_endpoint: "http://user-service.nova-backend.svc.cluster.local:9080".to_string(),
            content_endpoint: "http://content-service.nova-backend.svc.cluster.local:9081".to_string(),
            feed_endpoint: "http://feed-service.nova-backend.svc.cluster.local:9084".to_string(),
        }
    }
}

impl ServiceClients {
    /// Create a new ServiceClients instance with custom endpoints
    pub fn new(
        auth_endpoint: String,
        user_endpoint: String,
        content_endpoint: String,
        feed_endpoint: String,
    ) -> Self {
        Self {
            auth_endpoint,
            user_endpoint,
            content_endpoint,
            feed_endpoint,
        }
    }

    /// Create auth service client
    pub async fn auth_client(
        &self,
    ) -> Result<AuthServiceClient<Channel>, Box<dyn Error + Send + Sync>> {
        let channel = Channel::from_shared(self.auth_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?;
        Ok(AuthServiceClient::new(channel))
    }

    /// Create user service client
    pub async fn user_client(
        &self,
    ) -> Result<UserServiceClient<Channel>, Box<dyn Error + Send + Sync>> {
        let channel = Channel::from_shared(self.user_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?;
        Ok(UserServiceClient::new(channel))
    }

    /// Create content service client
    pub async fn content_client(
        &self,
    ) -> Result<ContentServiceClient<Channel>, Box<dyn Error + Send + Sync>> {
        let channel = Channel::from_shared(self.content_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?;
        Ok(ContentServiceClient::new(channel))
    }

    /// Create recommendation service client (feed service)
    pub async fn recommendation_client(
        &self,
    ) -> Result<RecommendationServiceClient<Channel>, Box<dyn Error + Send + Sync>> {
        let channel = Channel::from_shared(self.feed_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn Error + Send + Sync>)?;
        Ok(RecommendationServiceClient::new(channel))
    }

    /// Alias for recommendation_client for backward compatibility
    pub async fn feed_client(
        &self,
    ) -> Result<RecommendationServiceClient<Channel>, Box<dyn Error + Send + Sync>> {
        self.recommendation_client().await
    }
}

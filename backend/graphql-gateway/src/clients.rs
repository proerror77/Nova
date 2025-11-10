//! gRPC Client connections for microservices

use crate::config::ServiceEndpoints;
use tonic::transport::Channel;

// Import generated gRPC clients (will be generated from proto files)
pub mod proto {
    pub mod common {
        tonic::include_proto!("nova.common.v1");
    }
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

/// Container for all gRPC service clients
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
            auth_endpoint: "http://localhost:50051".to_string(),
            user_endpoint: "http://localhost:50052".to_string(),
            content_endpoint: "http://localhost:50053".to_string(),
            feed_endpoint: "http://localhost:50056".to_string(),
        }
    }
}

impl ServiceClients {
    pub fn new(endpoints: ServiceEndpoints) -> Self {
        Self {
            auth_endpoint: endpoints.auth_service,
            user_endpoint: endpoints.user_service,
            content_endpoint: endpoints.content_service,
            feed_endpoint: endpoints.feed_service,
        }
    }

    /// Create auth service client
    pub async fn auth_client(&self) -> Result<AuthServiceClient<Channel>, Box<dyn std::error::Error + Send + Sync>> {
        let channel = Channel::from_shared(self.auth_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(AuthServiceClient::new(channel))
    }

    /// Create user service client
    pub async fn user_client(&self) -> Result<UserServiceClient<Channel>, Box<dyn std::error::Error + Send + Sync>> {
        let channel = Channel::from_shared(self.user_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(UserServiceClient::new(channel))
    }

    /// Create content service client
    pub async fn content_client(&self) -> Result<ContentServiceClient<Channel>, Box<dyn std::error::Error + Send + Sync>> {
        let channel = Channel::from_shared(self.content_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(ContentServiceClient::new(channel))
    }

    /// Create feed service client
    pub async fn feed_client(&self) -> Result<RecommendationServiceClient<Channel>, Box<dyn std::error::Error + Send + Sync>> {
        let channel = Channel::from_shared(self.feed_endpoint.clone())
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?
            .connect()
            .await
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;
        Ok(RecommendationServiceClient::new(channel))
    }
}

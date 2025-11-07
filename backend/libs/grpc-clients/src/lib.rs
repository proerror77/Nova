/// gRPC Clients Library
///
/// Centralizes gRPC client code generation and provides a unified interface
/// for all inter-service communication in the Nova architecture.
///
/// This library:
/// - Generates client stubs for all 12 services
/// - Provides connection pooling and management
/// - Handles common gRPC patterns (retries, timeouts, circuit breakers)
/// - Implements dependency injection for service clients
pub mod auth_client;
pub mod config;
pub mod middleware;
pub mod pool;

// Re-export AuthClient for easier access
pub use auth_client::AuthClient;

// Re-export generated proto client modules
pub mod nova {
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
    pub mod auth_service {
        pub mod v1 {
            tonic::include_proto!("nova.auth_service.v1");
        }
        pub use v1::*;
    }
    pub mod user_service {
        pub mod v1 {
            tonic::include_proto!("nova.user_service.v1");
        }
        pub use v1::*;
    }
    pub mod messaging_service {
        pub mod v1 {
            tonic::include_proto!("nova.messaging_service.v1");
        }
        pub use v1::*;
    }
    pub mod content_service {
        pub mod v1 {
            tonic::include_proto!("nova.content_service.v1");
        }
        pub use v1::*;
    }
    pub mod feed_service {
        pub mod v1 {
            tonic::include_proto!("nova.feed_service.v1");
        }
        pub use v1::*;
    }
    pub mod search_service {
        pub mod v1 {
            tonic::include_proto!("nova.search_service.v1");
        }
        pub use v1::*;
    }
    pub mod media_service {
        pub mod v1 {
            tonic::include_proto!("nova.media_service.v1");
        }
        pub use v1::*;
    }
    pub mod notification_service {
        pub mod v1 {
            tonic::include_proto!("nova.notification_service.v1");
        }
        pub use v1::*;
    }
    pub mod streaming_service {
        pub mod v1 {
            tonic::include_proto!("nova.streaming_service.v1");
        }
        pub use v1::*;
    }
    pub mod cdn_service {
        pub mod v1 {
            tonic::include_proto!("nova.cdn_service.v1");
        }
        pub use v1::*;
    }
    pub mod events_service {
        pub mod v1 {
            tonic::include_proto!("nova.events_service.v1");
        }
        pub use v1::*;
    }
    pub mod video_service {
        pub mod v1 {
            tonic::include_proto!("nova.video_service.v1");
        }
        pub use v1::*;
    }
}

use std::sync::Arc;
use tonic::transport::Channel;

/// Client types for all services
pub use nova::auth_service::auth_service_client::AuthServiceClient;
pub use nova::cdn_service::cdn_service_client::CdnServiceClient;
pub use nova::content_service::content_service_client::ContentServiceClient;
pub use nova::events_service::events_service_client::EventsServiceClient;
pub use nova::feed_service::recommendation_service_client::RecommendationServiceClient;
pub use nova::media_service::media_service_client::MediaServiceClient;
pub use nova::messaging_service::messaging_service_client::MessagingServiceClient;
pub use nova::notification_service::notification_service_client::NotificationServiceClient;
pub use nova::search_service::search_service_client::SearchServiceClient;
pub use nova::streaming_service::streaming_service_client::StreamingServiceClient;
pub use nova::user_service::user_service_client::UserServiceClient;
pub use nova::video_service::video_service_client::VideoServiceClient;

#[derive(Clone)]
pub struct GrpcClientPool {
    auth_client: Arc<AuthServiceClient<Channel>>,
    user_client: Arc<UserServiceClient<Channel>>,
    messaging_client: Arc<MessagingServiceClient<Channel>>,
    content_client: Arc<ContentServiceClient<Channel>>,
    feed_client: Arc<RecommendationServiceClient<Channel>>,
    search_client: Arc<SearchServiceClient<Channel>>,
    media_client: Arc<MediaServiceClient<Channel>>,
    notification_client: Arc<NotificationServiceClient<Channel>>,
    streaming_client: Arc<StreamingServiceClient<Channel>>,
    cdn_client: Arc<CdnServiceClient<Channel>>,
    events_client: Arc<EventsServiceClient<Channel>>,
    video_client: Arc<VideoServiceClient<Channel>>,
}

impl GrpcClientPool {
    /// Create a new gRPC client pool from configuration
    pub async fn new(config: &config::GrpcConfig) -> Result<Self, Box<dyn std::error::Error>> {
        let auth_client = Arc::new(AuthServiceClient::new(
            config.connect_channel(&config.auth_service_url).await?,
        ));
        let user_client = Arc::new(UserServiceClient::new(
            config.connect_channel(&config.user_service_url).await?,
        ));
        let messaging_client = Arc::new(MessagingServiceClient::new(
            config
                .connect_channel(&config.messaging_service_url)
                .await?,
        ));
        let content_client = Arc::new(ContentServiceClient::new(
            config.connect_channel(&config.content_service_url).await?,
        ));
        let feed_client = Arc::new(RecommendationServiceClient::new(
            config.connect_channel(&config.feed_service_url).await?,
        ));
        let search_client = Arc::new(SearchServiceClient::new(
            config.connect_channel(&config.search_service_url).await?,
        ));
        let media_client = Arc::new(MediaServiceClient::new(
            config.connect_channel(&config.media_service_url).await?,
        ));
        let notification_client = Arc::new(NotificationServiceClient::new(
            config
                .connect_channel(&config.notification_service_url)
                .await?,
        ));
        let streaming_client = Arc::new(StreamingServiceClient::new(
            config
                .connect_channel(&config.streaming_service_url)
                .await?,
        ));
        let cdn_client = Arc::new(CdnServiceClient::new(
            config.connect_channel(&config.cdn_service_url).await?,
        ));
        let events_client = Arc::new(EventsServiceClient::new(
            config.connect_channel(&config.events_service_url).await?,
        ));
        let video_client = Arc::new(VideoServiceClient::new(
            config.connect_channel(&config.video_service_url).await?,
        ));

        Ok(Self {
            auth_client,
            user_client,
            messaging_client,
            content_client,
            feed_client,
            search_client,
            media_client,
            notification_client,
            streaming_client,
            cdn_client,
            events_client,
            video_client,
        })
    }

    // Getters for each service client
    pub fn auth(&self) -> AuthServiceClient<Channel> {
        (*self.auth_client).clone()
    }

    pub fn user(&self) -> UserServiceClient<Channel> {
        (*self.user_client).clone()
    }

    pub fn messaging(&self) -> MessagingServiceClient<Channel> {
        (*self.messaging_client).clone()
    }

    pub fn content(&self) -> ContentServiceClient<Channel> {
        (*self.content_client).clone()
    }

    pub fn feed(&self) -> RecommendationServiceClient<Channel> {
        (*self.feed_client).clone()
    }

    pub fn search(&self) -> SearchServiceClient<Channel> {
        (*self.search_client).clone()
    }

    pub fn media(&self) -> MediaServiceClient<Channel> {
        (*self.media_client).clone()
    }

    pub fn notification(&self) -> NotificationServiceClient<Channel> {
        (*self.notification_client).clone()
    }

    pub fn streaming(&self) -> StreamingServiceClient<Channel> {
        (*self.streaming_client).clone()
    }

    pub fn cdn(&self) -> CdnServiceClient<Channel> {
        (*self.cdn_client).clone()
    }

    pub fn events(&self) -> EventsServiceClient<Channel> {
        (*self.events_client).clone()
    }

    pub fn video(&self) -> VideoServiceClient<Channel> {
        (*self.video_client).clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grpc_client_pool_creation() {
        // This is a placeholder test
        // Actual testing requires running gRPC services
    }
}

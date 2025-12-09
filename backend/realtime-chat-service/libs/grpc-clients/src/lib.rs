/// gRPC Clients Library
///
/// Centralizes gRPC client code generation and provides a unified interface
/// for all inter-service communication in the Nova architecture.
use std::sync::Arc;
use tonic::transport::Channel;

pub mod auth_client;
pub mod config;
pub mod middleware;
pub mod pool;

// Re-export connection pool for external use
pub use pool::GrpcConnectionPool;

// Re-export AuthClient for easier access
pub use auth_client::AuthClient;

// Re-export generated proto client modules
pub mod nova {
    pub mod common {
        pub mod v2 {
            tonic::include_proto!("nova.common.v2");
        }
        pub use v2::*;
    }
    pub mod identity_service {
        pub mod v2 {
            tonic::include_proto!("nova.identity_service.v2");
        }
        pub use v2::*;
    }
    pub mod content_service {
        pub mod v2 {
            tonic::include_proto!("nova.content_service.v2");
        }
        pub use v2::*;
    }
    // Backwards-compatible alias for legacy modules referring to `nova::content`
    pub mod content {
        pub use super::content_service::*;
    }
    pub mod feed_service {
        pub mod v2 {
            tonic::include_proto!("nova.feed_service.v2");
        }
        pub use v2::*;
    }
    pub mod search_service {
        pub mod v2 {
            tonic::include_proto!("nova.search_service.v2");
        }
        pub use v2::*;
    }
    pub mod media_service {
        pub mod v2 {
            tonic::include_proto!("nova.media_service.v2");
        }
        pub use v2::*;
    }
    pub mod notification_service {
        pub mod v2 {
            tonic::include_proto!("nova.notification_service.v2");
        }
        pub use v2::*;
    }
    pub mod events_service {
        pub mod v2 {
            tonic::include_proto!("nova.events_service.v2");
        }
        pub use v2::*;
    }
    pub mod graph_service {
        pub mod v2 {
            tonic::include_proto!("nova.graph_service.v2");
        }
        pub use v2::*;
    }
    pub mod social_service {
        pub mod v2 {
            tonic::include_proto!("nova.social_service.v2");
        }
        pub use v2::*;
    }
    pub mod ranking_service {
        pub mod v1 {
            tonic::include_proto!("ranking.v1");
        }
        pub use v1::*;
    }
    pub mod trust_safety {
        pub mod v2 {
            tonic::include_proto!("nova.trust_safety.v2");
        }
        pub use v2::*;
    }
}

// Feature Store proto module
pub mod feature_store {
    tonic::include_proto!("feature_store");
}

pub use feature_store::feature_store_client::FeatureStoreClient;
pub use nova::content_service::content_service_client::ContentServiceClient;
pub use nova::events_service::events_service_client::EventsServiceClient;
pub use nova::feed_service::recommendation_service_client::RecommendationServiceClient;
pub use nova::graph_service::graph_service_client::GraphServiceClient;
/// Client types for all services
pub use nova::identity_service::auth_service_client::AuthServiceClient;
pub use nova::media_service::media_service_client::MediaServiceClient;
pub use nova::notification_service::notification_service_client::NotificationServiceClient;
pub use nova::ranking_service::ranking_service_client::RankingServiceClient;
pub use nova::search_service::search_service_client::SearchServiceClient;
pub use nova::social_service::social_service_client::SocialServiceClient;
pub use nova::trust_safety::trust_safety_service_client::TrustSafetyServiceClient;

#[derive(Clone)]
pub struct GrpcClientPool {
    auth_client: Arc<AuthServiceClient<Channel>>,
    content_client: Arc<ContentServiceClient<Channel>>,
    feed_client: Arc<RecommendationServiceClient<Channel>>,
    search_client: Arc<SearchServiceClient<Channel>>,
    media_client: Arc<MediaServiceClient<Channel>>,
    notification_client: Arc<NotificationServiceClient<Channel>>,
    events_client: Arc<EventsServiceClient<Channel>>,
    graph_client: Arc<GraphServiceClient<Channel>>,
    social_client: Arc<SocialServiceClient<Channel>>,
    ranking_client: Arc<RankingServiceClient<Channel>>,
    feature_store_client: Arc<FeatureStoreClient<Channel>>,
    trust_safety_client: Arc<TrustSafetyServiceClient<Channel>>,
    degraded_services: Vec<String>,
}

impl GrpcClientPool {
    /// Create a new gRPC client pool from configuration
    ///
    /// **Graceful Degradation**: If a service endpoint is unavailable, creates a placeholder
    /// channel that will fail at call-time rather than blocking initialization.
    /// This allows services to start even when their gRPC dependencies are not yet deployed.
    pub async fn new(config: &config::GrpcConfig) -> Result<Self, Box<dyn std::error::Error>> {
        use crate::config::DependencyTier;

        // Helper to create channel with fallback to placeholder on failure
        async fn connect_or_placeholder(
            config: &config::GrpcConfig,
            endpoint: &config::ServiceEndpoint,
            service_name: &str,
            degraded: &mut Vec<String>,
        ) -> Result<Channel, Box<dyn std::error::Error>> {
            match config.connect_channel(&endpoint.url).await {
                Ok(channel) => {
                    tracing::debug!("✅ Connected to {}", service_name);
                    Ok(channel)
                }
                Err(e) => match endpoint.tier {
                    DependencyTier::Tier0 => Err(format!(
                        "{} is Tier0 and unreachable at {}: {}",
                        service_name, endpoint.url, e
                    )
                    .into()),
                    DependencyTier::Tier1 | DependencyTier::Tier2 => {
                        tracing::warn!(
                            target: "grpc_clients",
                            "⚠️  {} unavailable ({}): will start in degraded mode (tier={:?})",
                            service_name,
                            e,
                            endpoint.tier
                        );
                        degraded.push(service_name.to_string());
                        Ok(
                            tonic::transport::Endpoint::from_static("http://127.0.0.1:1")
                                .connect_lazy(),
                        )
                    }
                },
            }
        }

        let mut degraded = Vec::new();

        let auth_client = Arc::new(AuthServiceClient::new(
            connect_or_placeholder(
                config,
                &config.identity_service,
                "identity-service",
                &mut degraded,
            )
            .await?,
        ));
        let content_client = Arc::new(ContentServiceClient::new(
            connect_or_placeholder(
                config,
                &config.content_service,
                "content-service",
                &mut degraded,
            )
            .await?,
        ));
        let feed_client = Arc::new(RecommendationServiceClient::new(
            connect_or_placeholder(config, &config.feed_service, "feed-service", &mut degraded)
                .await?,
        ));
        let search_client = Arc::new(SearchServiceClient::new(
            connect_or_placeholder(
                config,
                &config.search_service,
                "search-service",
                &mut degraded,
            )
            .await?,
        ));
        let media_client = Arc::new(MediaServiceClient::new(
            connect_or_placeholder(
                config,
                &config.media_service,
                "media-service",
                &mut degraded,
            )
            .await?,
        ));
        let notification_client = Arc::new(NotificationServiceClient::new(
            connect_or_placeholder(
                config,
                &config.notification_service,
                "notification-service",
                &mut degraded,
            )
            .await?,
        ));
        let events_client = Arc::new(EventsServiceClient::new(
            connect_or_placeholder(
                config,
                &config.analytics_service,
                "analytics-service",
                &mut degraded,
            )
            .await?,
        ));
        let graph_client = Arc::new(GraphServiceClient::new(
            connect_or_placeholder(
                config,
                &config.graph_service,
                "graph-service",
                &mut degraded,
            )
            .await?,
        ));
        let social_client = Arc::new(SocialServiceClient::new(
            connect_or_placeholder(
                config,
                &config.social_service,
                "social-service",
                &mut degraded,
            )
            .await?,
        ));
        let ranking_client = Arc::new(RankingServiceClient::new(
            connect_or_placeholder(
                config,
                &config.ranking_service,
                "ranking-service",
                &mut degraded,
            )
            .await?,
        ));
        let feature_store_client = Arc::new(FeatureStoreClient::new(
            connect_or_placeholder(
                config,
                &config.feature_store,
                "feature-store",
                &mut degraded,
            )
            .await?,
        ));
        let trust_safety_client = Arc::new(TrustSafetyServiceClient::new(
            connect_or_placeholder(
                config,
                &config.trust_safety_service,
                "trust-safety-service",
                &mut degraded,
            )
            .await?,
        ));

        if !degraded.is_empty() {
            tracing::warn!(
                target: "grpc_clients",
                degraded = ?degraded,
                "gRPC client pool initialized in degraded mode"
            );
        }

        Ok(Self {
            auth_client,
            content_client,
            feed_client,
            search_client,
            media_client,
            notification_client,
            events_client,
            graph_client,
            social_client,
            ranking_client,
            feature_store_client,
            trust_safety_client,
            degraded_services: degraded,
        })
    }

    // Getters for each service client
    pub fn auth(&self) -> AuthServiceClient<Channel> {
        (*self.auth_client).clone()
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

    pub fn events(&self) -> EventsServiceClient<Channel> {
        (*self.events_client).clone()
    }

    pub fn graph(&self) -> GraphServiceClient<Channel> {
        (*self.graph_client).clone()
    }

    pub fn social(&self) -> SocialServiceClient<Channel> {
        (*self.social_client).clone()
    }

    pub fn ranking(&self) -> RankingServiceClient<Channel> {
        (*self.ranking_client).clone()
    }

    pub fn feature_store(&self) -> FeatureStoreClient<Channel> {
        (*self.feature_store_client).clone()
    }

    pub fn trust_safety(&self) -> TrustSafetyServiceClient<Channel> {
        (*self.trust_safety_client).clone()
    }

    /// Return list of services that were unavailable during initialization (Tier1/2 only).
    pub fn degraded_services(&self) -> &[String] {
        &self.degraded_services
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grpc_client_pool_creation() {
        // Placeholder test
    }
}

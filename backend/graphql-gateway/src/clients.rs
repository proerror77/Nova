//! gRPC service clients with connection pooling and production-ready configuration
//!
//! ## Key improvements:
//! - Connection pooling via `connect_lazy()` - HTTP/2 multiplexing handles concurrency
//! - Timeout configuration (connect + request)
//! - Keep-alive for long-lived connections
//! - ✅ P0: Circuit breaker protection for all gRPC clients
//! - Proper error types

// Some client methods and circuit breaker features are prepared for future REST API modules
#![allow(dead_code)]

use grpc_clients::config::GrpcConfig;
use resilience::circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};
use std::sync::Arc;
use std::time::Duration;
use tonic::transport::{Channel, Endpoint};
use tonic::Status;

// Common protos - must be at crate root so generated code can find it
pub mod common {
    pub mod v2 {
        tonic::include_proto!("nova.common.v2");
    }
}

// Proto module definitions from build.rs
pub mod proto {
    pub mod auth {
        tonic::include_proto!("nova.identity_service.v2");
    }

    // user module removed - user-service is deprecated
    // User profile data now comes from identity-service

    pub mod content {
        tonic::include_proto!("nova.content_service.v2");
    }

    pub mod feed {
        tonic::include_proto!("nova.feed_service.v2");
    }

    pub mod social {
        tonic::include_proto!("nova.social_service.v2");
    }

    pub mod chat {
        tonic::include_proto!("nova.realtime_chat.v1");
    }

    pub mod media {
        tonic::include_proto!("nova.media.v1");
    }

    pub mod search {
        tonic::include_proto!("nova.search.v1");
    }

    pub mod notification {
        tonic::include_proto!("nova.notification_service.v2");
    }

    pub mod graph {
        tonic::include_proto!("nova.graph_service.v2");
    }
}

use proto::auth::auth_service_client::AuthServiceClient;
use proto::chat::realtime_chat_service_client::RealtimeChatServiceClient;
use proto::content::content_service_client::ContentServiceClient;
use proto::feed::recommendation_service_client::RecommendationServiceClient;
use proto::graph::graph_service_client::GraphServiceClient;
use proto::media::media_service_client::MediaServiceClient;
use proto::notification::notification_service_client::NotificationServiceClient;
use proto::social::social_service_client::SocialServiceClient;
// UserServiceClient removed - user-service is deprecated

/// Service client manager with pooled gRPC connections and circuit breaker protection
///
/// # Performance characteristics:
/// - Each `Channel` uses HTTP/2 multiplexing (handles ~100 concurrent streams)
/// - Connection is lazy-initialized on first use
/// - Connection is reused across all requests
/// - ✅ P0: Circuit breaker for each service prevents cascading failures
///
/// # Circuit Breaker Protection:
/// - Tracks error rate and consecutive failures per service
/// - Opens circuit after 5 consecutive failures or 50% error rate
/// - Auto-recovery after 60s timeout
/// - Fast-fail when circuit is open (< 1ms vs 10s timeout)
///
/// # Example:
/// ```rust
/// let clients = ServiceClients::new();
/// let auth_client = clients.auth_client(); // First call: connects
/// let auth_client2 = clients.auth_client(); // Subsequent calls: reuses connection
/// ```
#[derive(Clone)]
pub struct ServiceClients {
    auth_channel: Arc<Channel>,
    // user_channel removed - user-service is deprecated
    content_channel: Arc<Channel>,
    feed_channel: Arc<Channel>,
    social_channel: Arc<Channel>,
    chat_channel: Arc<Channel>,
    media_channel: Arc<Channel>,
    search_channel: Arc<Channel>,
    notification_channel: Arc<Channel>,
    graph_channel: Arc<Channel>,
    // Circuit breakers (one per service)
    auth_cb: Arc<CircuitBreaker>,
    // user_cb removed - user-service is deprecated
    content_cb: Arc<CircuitBreaker>,
    feed_cb: Arc<CircuitBreaker>,
    social_cb: Arc<CircuitBreaker>,
    chat_cb: Arc<CircuitBreaker>,
    media_cb: Arc<CircuitBreaker>,
    search_cb: Arc<CircuitBreaker>,
    notification_cb: Arc<CircuitBreaker>,
    graph_cb: Arc<CircuitBreaker>,
}

impl Default for ServiceClients {
    fn default() -> Self {
        Self::new(
            "http://identity-service.nova-staging.svc.cluster.local:9083",
            // user-service removed - deprecated
            "http://content-service.nova-staging.svc.cluster.local:9081",
            "http://feed-service.nova-staging.svc.cluster.local:9084",
            "http://social-service.nova-staging.svc.cluster.local:9082",
            "http://realtime-chat-service.nova-staging.svc.cluster.local:9085",
            "http://media-service.nova-staging.svc.cluster.local:9086",
            "http://search-service.nova-staging.svc.cluster.local:9087",
            "http://notification-service.nova-staging.svc.cluster.local:50051",
            "http://graph-service.nova-staging.svc.cluster.local:50051",
        )
    }
}

impl ServiceClients {
    /// Build clients using the shared gRPC config (includes TLS/mTLS + timeouts).
    #[allow(clippy::result_large_err)]
    pub fn from_grpc_config(cfg: &GrpcConfig) -> Result<Self, ServiceError> {
        Ok(Self {
            auth_channel: Arc::new(Self::create_channel_from_endpoint(
                cfg.make_endpoint(&cfg.identity_service.url)
                    .map_err(|e| ServiceError::ConnectionError(e.to_string()))?,
            )),
            // user-service deprecated
            content_channel: Arc::new(Self::create_channel_from_endpoint(
                cfg.make_endpoint(&cfg.content_service.url)
                    .map_err(|e| ServiceError::ConnectionError(e.to_string()))?,
            )),
            feed_channel: Arc::new(Self::create_channel_from_endpoint(
                cfg.make_endpoint(&cfg.feed_service.url)
                    .map_err(|e| ServiceError::ConnectionError(e.to_string()))?,
            )),
            social_channel: Arc::new(Self::create_channel_from_endpoint(
                cfg.make_endpoint(&cfg.social_service.url)
                    .map_err(|e| ServiceError::ConnectionError(e.to_string()))?,
            )),
            chat_channel: Arc::new(Self::create_channel_from_endpoint(
                cfg.make_endpoint(&cfg.chat_service.url)
                    .map_err(|e| ServiceError::ConnectionError(e.to_string()))?,
            )),
            media_channel: Arc::new(Self::create_channel_from_endpoint(
                cfg.make_endpoint(&cfg.media_service.url)
                    .map_err(|e| ServiceError::ConnectionError(e.to_string()))?,
            )),
            search_channel: Arc::new(Self::create_channel_from_endpoint(
                cfg.make_endpoint(&cfg.search_service.url)
                    .map_err(|e| ServiceError::ConnectionError(e.to_string()))?,
            )),
            // notification and graph services use default endpoints (not yet in GrpcConfig)
            notification_channel: Arc::new(Self::create_channel(
                &std::env::var("NOTIFICATION_SERVICE_URL").unwrap_or_else(|_| {
                    "http://notification-service.nova-staging.svc.cluster.local:50051".to_string()
                }),
            )),
            graph_channel: Arc::new(Self::create_channel(
                &std::env::var("GRAPH_SERVICE_URL").unwrap_or_else(|_| {
                    "http://graph-service.nova-staging.svc.cluster.local:50051".to_string()
                }),
            )),
            auth_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            content_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            feed_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            social_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            chat_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            media_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            search_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            notification_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
            graph_cb: Arc::new(CircuitBreaker::new(Self::default_cb_config())),
        })
    }

    /// Create a new ServiceClients instance with custom endpoints and circuit breakers
    ///
    /// # Arguments:
    /// - `auth_endpoint`: Auth service URL (e.g., "http://auth-service:9083")
    /// - `content_endpoint`: Content service URL
    /// - `feed_endpoint`: Feed/recommendation service URL
    /// - `social_endpoint`: Social service URL
    /// - `chat_endpoint`: Realtime chat service URL
    /// - `media_endpoint`: Media service URL
    ///
    /// # Configuration:
    /// **Channel-level**:
    /// - **Connect timeout**: 5 seconds
    /// - **Request timeout**: 10 seconds
    /// - **Keep-alive**: 60 seconds (prevents connection drops by proxies/LBs)
    /// - **Keep-alive timeout**: 20 seconds
    /// - **Keep-alive while idle**: Enabled (sends pings even without traffic)
    /// - **Connection mode**: Lazy (connects on first use, not during construction)
    ///
    /// **Circuit Breaker** (per service):
    /// - **Failure threshold**: 5 consecutive failures
    /// - **Error rate threshold**: 50% (over 100-request window)
    /// - **Recovery timeout**: 60 seconds
    /// - **Success threshold**: 2 (HalfOpen → Closed)
    ///
    /// # Panics:
    /// Panics if any endpoint URL is malformed. In production, endpoints are
    /// hardcoded or validated at startup, so this is acceptable.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        auth_endpoint: &str,
        content_endpoint: &str,
        feed_endpoint: &str,
        social_endpoint: &str,
        chat_endpoint: &str,
        media_endpoint: &str,
        search_endpoint: &str,
        notification_endpoint: &str,
        graph_endpoint: &str,
    ) -> Self {
        // Circuit breaker configuration
        let cb_config = Self::default_cb_config();

        Self {
            auth_channel: Arc::new(Self::create_channel(auth_endpoint)),
            // user_channel removed - user-service is deprecated
            content_channel: Arc::new(Self::create_channel(content_endpoint)),
            feed_channel: Arc::new(Self::create_channel(feed_endpoint)),
            social_channel: Arc::new(Self::create_channel(social_endpoint)),
            chat_channel: Arc::new(Self::create_channel(chat_endpoint)),
            media_channel: Arc::new(Self::create_channel(media_endpoint)),
            search_channel: Arc::new(Self::create_channel(search_endpoint)),
            notification_channel: Arc::new(Self::create_channel(notification_endpoint)),
            graph_channel: Arc::new(Self::create_channel(graph_endpoint)),
            auth_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            // user_cb removed - user-service is deprecated
            content_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            feed_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            social_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            chat_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            media_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            search_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            notification_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            graph_cb: Arc::new(CircuitBreaker::new(cb_config)),
        }
    }

    fn default_cb_config() -> CircuitBreakerConfig {
        CircuitBreakerConfig {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(60),
            error_rate_threshold: 0.5,
            window_size: 100,
        }
    }

    /// Create a configured gRPC channel with production-ready settings
    ///
    /// # Configuration rationale:
    /// - **connect_lazy()**: Delays connection until first RPC. Faster startup,
    ///   allows services to start in any order.
    /// - **timeout(5s)**: Prevents hanging on unreachable services.
    /// - **http2_keep_alive_interval(60s)**: Prevents connection drops by
    ///   load balancers and proxies that close idle connections.
    /// - **keep_alive_while_idle(true)**: Sends pings even without traffic.
    ///   Critical for long-lived connections.
    /// - **keep_alive_timeout(20s)**: If no PING ACK in 20s, assume connection dead.
    ///
    /// # HTTP/2 Multiplexing:
    /// Each Channel handles ~100 concurrent streams. No need for connection pools
    /// in the traditional sense. One connection per service is sufficient for
    /// most workloads.
    ///
    /// # TLS/mTLS Support:
    /// Endpoints using https:// scheme will automatically use TLS.
    /// Service discovery and cert verification happen transparently.
    fn create_channel(endpoint: &str) -> Channel {
        Endpoint::from_shared(endpoint.to_string())
            .expect("Invalid endpoint URL")
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(10))
            .http2_keep_alive_interval(Duration::from_secs(60))
            .keep_alive_timeout(Duration::from_secs(20))
            .keep_alive_while_idle(true)
            .connect_lazy()
    }

    fn create_channel_from_endpoint(endpoint: Endpoint) -> Channel {
        endpoint.connect_lazy()
    }

    /// Get auth service client with circuit breaker protection
    ///
    /// # Performance:
    /// - First call: Establishes connection (5-10ms)
    /// - Subsequent calls: Reuses connection (<1ms)
    ///
    /// # Circuit Breaker:
    /// Wrap gRPC calls with `call_with_circuit_breaker()` to get protection:
    ///
    /// ```rust
    /// let mut client = clients.auth_client();
    /// let result = clients.call_auth(|| async move {
    ///     client.validate_token(request).await
    /// }).await?;
    /// ```
    ///
    /// # Returns:
    /// A lightweight client that shares the underlying connection.
    /// Creating multiple clients is cheap (just clones an Arc<Channel>).
    pub fn auth_client(&self) -> AuthServiceClient<Channel> {
        AuthServiceClient::new((*self.auth_channel).clone())
    }

    /// Execute auth service call with circuit breaker protection
    ///
    /// # Example:
    /// ```rust
    /// let mut client = clients.auth_client();
    /// let result = clients.call_auth(|| async move {
    ///     client.validate_token(request).await
    /// }).await?;
    /// ```
    pub async fn call_auth<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.auth_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "auth-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    // user_client() and call_user() removed - user-service is deprecated
    // User profile data now comes from identity-service

    /// Get content service client with circuit breaker protection
    ///
    /// # Circuit Breaker:
    /// Use `call_content()` to wrap gRPC calls with circuit breaker protection.
    pub fn content_client(&self) -> ContentServiceClient<Channel> {
        ContentServiceClient::new((*self.content_channel).clone())
    }

    /// Execute content service call with circuit breaker protection
    ///
    /// # Example:
    /// ```rust
    /// let mut client = clients.content_client();
    /// let result = clients.call_content(|| async move {
    ///     client.get_post(request).await
    /// }).await?;
    /// ```
    pub async fn call_content<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.content_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "content-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    /// Get recommendation service client (feed service) with circuit breaker protection
    ///
    /// # Circuit Breaker:
    /// Use `call_feed()` to wrap gRPC calls with circuit breaker protection.
    pub fn recommendation_client(&self) -> RecommendationServiceClient<Channel> {
        RecommendationServiceClient::new((*self.feed_channel).clone())
    }

    /// Execute feed service call with circuit breaker protection
    ///
    /// # Example:
    /// ```rust
    /// let mut client = clients.feed_client();
    /// let result = clients.call_feed(|| async move {
    ///     client.get_recommendations(request).await
    /// }).await?;
    /// ```
    pub async fn call_feed<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.feed_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "feed-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    /// Alias for recommendation_client for backward compatibility
    pub fn feed_client(&self) -> RecommendationServiceClient<Channel> {
        self.recommendation_client()
    }

    /// Get social service client with circuit breaker protection
    ///
    /// # Circuit Breaker:
    /// Use `call_social()` to wrap gRPC calls with circuit breaker protection.
    pub fn social_client(&self) -> SocialServiceClient<Channel> {
        SocialServiceClient::new((*self.social_channel).clone())
    }

    /// Execute social service call with circuit breaker protection
    ///
    /// # Example:
    /// ```rust
    /// let mut client = clients.social_client();
    /// let result = clients.call_social(|| async move {
    ///     client.follow_user(request).await
    /// }).await?;
    /// ```
    pub async fn call_social<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.social_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "social-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    /// Get realtime chat service client with circuit breaker protection
    ///
    /// # Circuit Breaker:
    /// Use `call_chat()` to wrap gRPC calls with circuit breaker protection.
    pub fn chat_client(&self) -> RealtimeChatServiceClient<Channel> {
        RealtimeChatServiceClient::new((*self.chat_channel).clone())
    }

    pub fn media_client(&self) -> MediaServiceClient<Channel> {
        MediaServiceClient::new((*self.media_channel).clone())
    }

    pub fn search_client(
        &self,
    ) -> proto::search::search_service_client::SearchServiceClient<Channel> {
        proto::search::search_service_client::SearchServiceClient::new(
            (*self.search_channel).clone(),
        )
    }

    /// Execute chat service call with circuit breaker protection
    ///
    /// # Example:
    /// ```rust
    /// let mut client = clients.chat_client();
    /// let result = clients.call_chat(|| async move {
    ///     client.send_message(request).await
    /// }).await?;
    /// ```
    pub async fn call_chat<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.chat_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "realtime-chat-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    /// Execute search service call with circuit breaker protection
    pub async fn call_search<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.search_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "search-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    /// Get notification service client
    pub fn notification_client(&self) -> NotificationServiceClient<Channel> {
        NotificationServiceClient::new((*self.notification_channel).clone())
    }

    /// Execute notification service call with circuit breaker protection
    pub async fn call_notification<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.notification_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "notification-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    /// Get graph service client
    pub fn graph_client(&self) -> GraphServiceClient<Channel> {
        GraphServiceClient::new((*self.graph_channel).clone())
    }

    /// Execute graph service call with circuit breaker protection
    pub async fn call_graph<F, Fut, T>(&self, f: F) -> Result<T, ServiceError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<tonic::Response<T>, Status>>,
    {
        self.graph_cb
            .call(f)
            .await
            .map(|response| response.into_inner())
            .map_err(|e| match e {
                resilience::circuit_breaker::CircuitBreakerError::Open => {
                    ServiceError::Unavailable {
                        service: "graph-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

    /// Get circuit breaker health status for monitoring
    ///
    /// Returns a list of (service_name, circuit_state) tuples for all services.
    /// Use this for health checks and observability.
    ///
    /// # Example:
    /// ```rust
    /// let status = clients.health_status();
    /// for (service, state) in status {
    ///     println!("{}: {:?}", service, state);
    /// }
    /// ```
    pub fn health_status(&self) -> Vec<(&'static str, CircuitState)> {
        vec![
            ("auth-service", self.auth_cb.state()),
            // user-service removed - deprecated
            ("content-service", self.content_cb.state()),
            ("feed-service", self.feed_cb.state()),
            ("social-service", self.social_cb.state()),
            ("realtime-chat-service", self.chat_cb.state()),
            ("media-service", self.media_cb.state()),
            ("notification-service", self.notification_cb.state()),
            ("graph-service", self.graph_cb.state()),
        ]
    }

    /// Get circuit breaker for a specific service (for direct access)
    pub fn get_circuit_breaker(&self, service: &str) -> Option<&CircuitBreaker> {
        match service {
            "auth" => Some(&self.auth_cb),
            // "user" removed - user-service is deprecated
            "content" => Some(&self.content_cb),
            "feed" => Some(&self.feed_cb),
            "social" => Some(&self.social_cb),
            "chat" | "realtime-chat" => Some(&self.chat_cb),
            "media" => Some(&self.media_cb),
            "notification" => Some(&self.notification_cb),
            "graph" => Some(&self.graph_cb),
            _ => None,
        }
    }
}

/// Custom error type for service communication
///
/// Provides better error context than `Box<dyn Error>`.
#[derive(Debug, thiserror::Error)]
#[allow(clippy::result_large_err)]
pub enum ServiceError {
    #[error("Service unavailable: {service}")]
    Unavailable { service: String },

    #[error("Request timeout after {timeout_secs}s")]
    Timeout { timeout_secs: u64 },

    #[error("gRPC error: {0}")]
    GrpcError(#[from] Status),

    #[error("Connection error: {0}")]
    ConnectionError(String),
}

impl ServiceError {
    pub fn unavailable(service: &str) -> Self {
        Self::Unavailable {
            service: service.to_string(),
        }
    }

    pub fn timeout(timeout_secs: u64) -> Self {
        Self::Timeout { timeout_secs }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_service_clients_creation() {
        let clients = ServiceClients::default();

        // Should be able to create clients without panicking
        let _auth = clients.auth_client();
        // user_client() removed - user-service is deprecated
        let _content = clients.content_client();
        let _feed = clients.feed_client();
        let _social = clients.social_client();
        let _chat = clients.chat_client();
        let _media = clients.media_client();
        let _search = clients.search_client();
        let _notification = clients.notification_client();
        let _graph = clients.graph_client();
    }

    #[test]
    fn test_service_clients_clone() {
        let clients = ServiceClients::default();
        let clients_clone = clients.clone();

        // Cloned instance should share the same channels (Arc count)
        assert_eq!(Arc::strong_count(&clients.auth_channel), 2);
        drop(clients_clone);
        assert_eq!(Arc::strong_count(&clients.auth_channel), 1);
    }

    #[test]
    fn test_custom_endpoints() {
        let clients = ServiceClients::new(
            "http://custom-auth:8080",
            // user endpoint removed - user-service is deprecated
            "http://custom-content:8082",
            "http://custom-feed:8083",
            "http://custom-social:8084",
            "http://custom-chat:8085",
            "http://custom-media:8086",
            "http://custom-search:8087",
            "http://custom-notification:8088",
            "http://custom-graph:8089",
        );

        // Should create without panicking
        let _auth = clients.auth_client();
        let _social = clients.social_client();
        let _chat = clients.chat_client();
        let _notification = clients.notification_client();
        let _graph = clients.graph_client();
    }

    #[test]
    #[should_panic(expected = "Invalid endpoint URL")]
    fn test_invalid_endpoint_panics() {
        let _ = ServiceClients::new(
            "not-a-url",
            // user endpoint removed - user-service is deprecated
            "http://content:8082",
            "http://feed:8083",
            "http://social:8084",
            "http://chat:8085",
            "http://media:8086",
            "http://search:8087",
            "http://notification:8088",
            "http://graph:8089",
        );
    }
}

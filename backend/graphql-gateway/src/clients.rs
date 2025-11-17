//! gRPC service clients with connection pooling and production-ready configuration
//!
//! ## Key improvements:
//! - Connection pooling via `connect_lazy()` - HTTP/2 multiplexing handles concurrency
//! - Timeout configuration (connect + request)
//! - Keep-alive for long-lived connections
//! - ✅ P0: Circuit breaker protection for all gRPC clients
//! - Proper error types

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

    pub mod content {
        tonic::include_proto!("nova.content_service.v2");
    }

    pub mod feed {
        tonic::include_proto!("nova.feed_service.v2");
    }

    pub mod graph {
        tonic::include_proto!("nova.graph_service.v2");
    }
}

use proto::auth::auth_service_client::AuthServiceClient;
use proto::content::content_service_client::ContentServiceClient;
use proto::feed::recommendation_service_client::RecommendationServiceClient;
use proto::graph::graph_service_client::GraphServiceClient;

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
    content_channel: Arc<Channel>,
    feed_channel: Arc<Channel>,
    graph_channel: Arc<Channel>,
    // Circuit breakers (one per service)
    auth_cb: Arc<CircuitBreaker>,
    content_cb: Arc<CircuitBreaker>,
    feed_cb: Arc<CircuitBreaker>,
    graph_cb: Arc<CircuitBreaker>,
}

impl Default for ServiceClients {
    fn default() -> Self {
        Self::new(
            "http://auth-service.nova-backend.svc.cluster.local:9083",
            "http://content-service.nova-backend.svc.cluster.local:9081",
            "http://feed-service.nova-backend.svc.cluster.local:9084",
            "http://graph-service.nova-backend.svc.cluster.local:9080",
        )
    }
}

impl ServiceClients {
    /// Create a new ServiceClients instance with custom endpoints and circuit breakers
    ///
    /// # Arguments:
    /// - `auth_endpoint`: Auth service URL (e.g., "http://auth-service:9083")
    /// - `user_endpoint`: User service URL
    /// - `content_endpoint`: Content service URL
    /// - `feed_endpoint`: Feed/recommendation service URL
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
    pub fn new(
        auth_endpoint: &str,
        content_endpoint: &str,
        feed_endpoint: &str,
        graph_endpoint: &str,
    ) -> Self {
        // Circuit breaker configuration
        let cb_config = CircuitBreakerConfig {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(60),
            error_rate_threshold: 0.5, // 50%
            window_size: 100,
        };

        Self {
            auth_channel: Arc::new(Self::create_channel(auth_endpoint)),
            content_channel: Arc::new(Self::create_channel(content_endpoint)),
            feed_channel: Arc::new(Self::create_channel(feed_endpoint)),
            graph_channel: Arc::new(Self::create_channel(graph_endpoint)),
            auth_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            content_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            feed_cb: Arc::new(CircuitBreaker::new(cb_config.clone())),
            graph_cb: Arc::new(CircuitBreaker::new(cb_config)),
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
                        service: "identity-service".to_string(),
                    }
                }
                resilience::circuit_breaker::CircuitBreakerError::CallFailed(msg) => {
                    ServiceError::ConnectionError(msg)
                }
            })
    }

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

    /// Get graph service client with circuit breaker protection
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
            ("identity-service", self.auth_cb.state()),
            ("content-service", self.content_cb.state()),
            ("feed-service", self.feed_cb.state()),
            ("graph-service", self.graph_cb.state()),
        ]
    }

    /// Get circuit breaker for a specific service (for direct access)
    pub fn get_circuit_breaker(&self, service: &str) -> Option<&CircuitBreaker> {
        match service {
            "auth" => Some(&self.auth_cb),
            "content" => Some(&self.content_cb),
            "feed" => Some(&self.feed_cb),
            "graph" => Some(&self.graph_cb),
            _ => None,
        }
    }
}

/// Custom error type for service communication
///
/// Provides better error context than `Box<dyn Error>`.
#[derive(Debug, thiserror::Error)]
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
        let _user = clients.user_client();
        let _content = clients.content_client();
        let _feed = clients.feed_client();
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
            "http://custom-user:8081",
            "http://custom-content:8082",
            "http://custom-feed:8083",
        );

        // Should create without panicking
        let _auth = clients.auth_client();
    }

    #[test]
    #[should_panic(expected = "Invalid endpoint URL")]
    fn test_invalid_endpoint_panics() {
        let _ = ServiceClients::new(
            "not-a-url",
            "http://user:8081",
            "http://content:8082",
            "http://feed:8083",
        );
    }
}

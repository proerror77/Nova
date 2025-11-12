/// Resilience patterns for microservices
///
/// This library provides production-ready resilience patterns including:
/// - **Circuit Breaker**: Prevents cascading failures by failing fast when error threshold is reached
/// - **Timeout**: Enforces time limits on all external calls
/// - **Retry**: Exponential backoff with jitter for transient failures
/// - **Tower Layer**: Composable middleware for Tower-based services
/// - **Preset Configurations**: Pre-tuned settings for gRPC, Database, Redis, etc.
///
/// # Example: gRPC Client with Circuit Breaker
///
/// ```rust,no_run
/// use resilience::{presets, CircuitBreaker};
///
/// #[tokio::main]
/// async fn main() {
///     let config = presets::grpc_config();
///     let circuit_breaker = CircuitBreaker::new(config.circuit_breaker);
///
///     let result = circuit_breaker.call(|| async {
///         // Your gRPC call here
///         Ok::<_, String>(())
///     }).await;
/// }
/// ```
///
/// # Example: Database Query with Timeout
///
/// ```rust,no_run
/// use resilience::{presets, timeout::with_timeout_result};
/// use std::time::Duration;
///
/// #[tokio::main]
/// async fn main() {
///     let config = presets::database_config();
///
///     let result = with_timeout_result(
///         config.timeout.duration,
///         async {
///             // Your database query
///             Ok::<_, String>(())
///         }
///     ).await;
/// }
/// ```

pub mod circuit_breaker;
pub mod layer;
pub mod metrics;
pub mod presets;
pub mod retry;
pub mod timeout;

// Re-export main types for convenience
pub use circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitBreakerError, CircuitState};
pub use layer::{CircuitBreakerLayer, CircuitBreakerService};
pub use presets::{ServiceConfig, grpc_config, database_config, redis_config, http_external_config, kafka_config, object_storage_config};
pub use retry::{RetryConfig, RetryError, with_retry};
pub use timeout::{TimeoutConfig, TimeoutError, with_timeout, with_timeout_result};

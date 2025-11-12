# Resilience Library - Usage Examples

Complete examples for integrating resilience patterns into Nova microservices.

---

## gRPC Service Client

### Example: User Service Client with Full Resilience Stack

```rust
use resilience::{presets, CircuitBreaker, with_timeout_result, with_retry};
use tonic::transport::Channel;
use std::sync::Arc;

pub struct UserServiceClient {
    client: user_service::UserServiceClient<Channel>,
    circuit_breaker: Arc<CircuitBreaker>,
}

impl UserServiceClient {
    pub async fn new(endpoint: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let config = presets::grpc_config();

        let channel = Channel::from_shared(endpoint.to_string())?
            .connect()
            .await?;

        Ok(Self {
            client: user_service::UserServiceClient::new(channel),
            circuit_breaker: Arc::new(CircuitBreaker::new(config.circuit_breaker)),
        })
    }

    pub async fn get_user(&self, user_id: i64) -> Result<User, ServiceError> {
        let config = presets::grpc_config();
        let cb = self.circuit_breaker.clone();
        let mut client = self.client.clone();

        cb.call(|| async {
            with_timeout_result(config.timeout.duration, async {
                let request = tonic::Request::new(GetUserRequest { user_id });
                client.get_user(request)
                    .await
                    .map(|r| r.into_inner())
                    .map_err(|e| e.to_string())
            }).await.map_err(|e| e.to_string())
        }).await.map_err(|e| ServiceError::CircuitBreakerError(e))
    }
}
```

---

## Database Service

### Example: User Repository with Timeout

```rust
use resilience::{presets, timeout::with_timeout_result};
use sqlx::{PgPool, FromRow};

pub struct UserRepository {
    pool: PgPool,
}

impl UserRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn find_by_id(&self, user_id: i64) -> Result<Option<User>, sqlx::Error> {
        let config = presets::database_config();

        with_timeout_result(config.timeout.duration, async {
            sqlx::query_as!(
                User,
                "SELECT id, username, email, created_at FROM users WHERE id = $1",
                user_id
            )
            .fetch_optional(&self.pool)
            .await
        })
        .await
        .map_err(|e| sqlx::Error::Io(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            e.to_string()
        )))
    }

    pub async fn list_users(&self, limit: i64, offset: i64) -> Result<Vec<User>, sqlx::Error> {
        let config = presets::database_config();

        with_timeout_result(config.timeout.duration, async {
            sqlx::query_as!(
                User,
                "SELECT id, username, email, created_at FROM users ORDER BY id LIMIT $1 OFFSET $2",
                limit,
                offset
            )
            .fetch_all(&self.pool)
            .await
        })
        .await
        .map_err(|e| sqlx::Error::Io(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            e.to_string()
        )))
    }
}
```

---

## Redis Cache Service

### Example: Cache Client with Retry

```rust
use resilience::{presets, CircuitBreaker, with_timeout_result, with_retry};
use redis::{aio::ConnectionManager, AsyncCommands};
use std::sync::Arc;

pub struct CacheService {
    conn: ConnectionManager,
    circuit_breaker: Arc<CircuitBreaker>,
}

impl CacheService {
    pub async fn new(redis_url: &str) -> Result<Self, redis::RedisError> {
        let config = presets::redis_config();
        let client = redis::Client::open(redis_url)?;
        let conn = ConnectionManager::new(client).await?;

        Ok(Self {
            conn,
            circuit_breaker: Arc::new(CircuitBreaker::new(config.circuit_breaker)),
        })
    }

    pub async fn get<T: serde::de::DeserializeOwned>(&self, key: &str) -> Result<Option<T>, CacheError> {
        let config = presets::redis_config();
        let cb = self.circuit_breaker.clone();
        let mut conn = self.conn.clone();
        let key = key.to_string();

        cb.call(|| async {
            with_retry(config.retry.unwrap(), || async {
                with_timeout_result(config.timeout.duration, async {
                    let value: Option<String> = conn.get(&key).await
                        .map_err(|e| e.to_string())?;

                    match value {
                        Some(v) => serde_json::from_str(&v).map(Some).map_err(|e| e.to_string()),
                        None => Ok(None),
                    }
                }).await.map_err(|e| e.to_string())
            }).await.map_err(|e| e.to_string())
        }).await.map_err(|e| CacheError::CircuitBreakerError(e.to_string()))
    }

    pub async fn set<T: serde::Serialize>(&self, key: &str, value: &T, ttl: u64) -> Result<(), CacheError> {
        let config = presets::redis_config();
        let cb = self.circuit_breaker.clone();
        let mut conn = self.conn.clone();
        let key = key.to_string();
        let value_str = serde_json::to_string(value)
            .map_err(|e| CacheError::SerializationError(e.to_string()))?;

        cb.call(|| async {
            with_timeout_result(config.timeout.duration, async {
                conn.set_ex(&key, value_str, ttl).await
                    .map_err(|e| e.to_string())
            }).await.map_err(|e| e.to_string())
        }).await.map_err(|e| CacheError::CircuitBreakerError(e.to_string()))
    }
}

#[derive(Debug, thiserror::Error)]
pub enum CacheError {
    #[error("Circuit breaker error: {0}")]
    CircuitBreakerError(String),
    #[error("Serialization error: {0}")]
    SerializationError(String),
}
```

---

## HTTP Client for External APIs

### Example: Payment Gateway Client

```rust
use resilience::{presets, CircuitBreaker, with_timeout_result, with_retry};
use reqwest::Client;
use std::sync::Arc;

pub struct PaymentGatewayClient {
    client: Client,
    base_url: String,
    api_key: String,
    circuit_breaker: Arc<CircuitBreaker>,
}

impl PaymentGatewayClient {
    pub fn new(base_url: String, api_key: String) -> Self {
        let config = presets::http_external_config();

        Self {
            client: Client::new(),
            base_url,
            api_key,
            circuit_breaker: Arc::new(CircuitBreaker::new(config.circuit_breaker)),
        }
    }

    pub async fn create_payment(&self, amount: i64, currency: &str) -> Result<PaymentResponse, PaymentError> {
        let config = presets::http_external_config();
        let cb = self.circuit_breaker.clone();

        cb.call(|| {
            let client = self.client.clone();
            let url = format!("{}/payments", self.base_url);
            let api_key = self.api_key.clone();
            let currency = currency.to_string();

            async move {
                with_retry(config.retry.unwrap(), || {
                    let client = client.clone();
                    let url = url.clone();
                    let api_key = api_key.clone();
                    let currency = currency.clone();

                    async move {
                        with_timeout_result(config.timeout.duration, async {
                            client
                                .post(&url)
                                .header("Authorization", format!("Bearer {}", api_key))
                                .json(&serde_json::json!({
                                    "amount": amount,
                                    "currency": currency,
                                }))
                                .send()
                                .await
                                .map_err(|e| e.to_string())?
                                .json::<PaymentResponse>()
                                .await
                                .map_err(|e| e.to_string())
                        }).await.map_err(|e| e.to_string())
                    }
                }).await.map_err(|e| e.to_string())
            }
        }).await.map_err(|e| PaymentError::CircuitBreakerError(e.to_string()))
    }
}

#[derive(Debug, thiserror::Error)]
pub enum PaymentError {
    #[error("Circuit breaker error: {0}")]
    CircuitBreakerError(String),
}

#[derive(Debug, serde::Deserialize)]
pub struct PaymentResponse {
    pub id: String,
    pub status: String,
}
```

---

## Kafka Producer

### Example: Event Publisher with Retry

```rust
use resilience::{presets, CircuitBreaker, with_timeout_result, with_retry};
use rdkafka::producer::{FutureProducer, FutureRecord};
use std::sync::Arc;
use std::time::Duration;

pub struct EventPublisher {
    producer: FutureProducer,
    circuit_breaker: Arc<CircuitBreaker>,
}

impl EventPublisher {
    pub fn new(brokers: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let config = presets::kafka_config();

        let producer: FutureProducer = rdkafka::config::ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("message.timeout.ms", "5000")
            .create()?;

        Ok(Self {
            producer,
            circuit_breaker: Arc::new(CircuitBreaker::new(config.circuit_breaker)),
        })
    }

    pub async fn publish<T: serde::Serialize>(
        &self,
        topic: &str,
        key: &str,
        event: &T,
    ) -> Result<(), PublishError> {
        let config = presets::kafka_config();
        let cb = self.circuit_breaker.clone();

        let payload = serde_json::to_string(event)
            .map_err(|e| PublishError::SerializationError(e.to_string()))?;

        cb.call(|| {
            let producer = self.producer.clone();
            let topic = topic.to_string();
            let key = key.to_string();
            let payload = payload.clone();

            async move {
                with_retry(config.retry.unwrap(), || {
                    let producer = producer.clone();
                    let topic = topic.clone();
                    let key = key.clone();
                    let payload = payload.clone();

                    async move {
                        with_timeout_result(config.timeout.duration, async {
                            let record = FutureRecord::to(&topic)
                                .key(&key)
                                .payload(&payload);

                            producer
                                .send(record, Duration::from_secs(0))
                                .await
                                .map(|_| ())
                                .map_err(|(e, _)| e.to_string())
                        }).await.map_err(|e| e.to_string())
                    }
                }).await.map_err(|e| e.to_string())
            }
        }).await.map_err(|e| PublishError::CircuitBreakerError(e.to_string()))
    }
}

#[derive(Debug, thiserror::Error)]
pub enum PublishError {
    #[error("Circuit breaker error: {0}")]
    CircuitBreakerError(String),
    #[error("Serialization error: {0}")]
    SerializationError(String),
}
```

---

## Application State (Shared Circuit Breakers)

### Example: Global Resilience State

```rust
use resilience::{presets, CircuitBreaker};
use std::sync::Arc;

/// Global resilience state shared across all handlers
pub struct AppState {
    pub user_service_cb: Arc<CircuitBreaker>,
    pub payment_service_cb: Arc<CircuitBreaker>,
    pub redis_cb: Arc<CircuitBreaker>,
    pub kafka_cb: Arc<CircuitBreaker>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            user_service_cb: Arc::new(CircuitBreaker::new(
                presets::grpc_config().circuit_breaker
            )),
            payment_service_cb: Arc::new(CircuitBreaker::new(
                presets::http_external_config().circuit_breaker
            )),
            redis_cb: Arc::new(CircuitBreaker::new(
                presets::redis_config().circuit_breaker
            )),
            kafka_cb: Arc::new(CircuitBreaker::new(
                presets::kafka_config().circuit_breaker
            )),
        }
    }
}

// Usage in Axum handler
async fn handle_request(
    State(state): State<Arc<AppState>>,
) -> Result<Json<Response>, StatusCode> {
    let user = state.user_service_cb.call(|| async {
        // Call user service
    }).await?;

    Ok(Json(Response { user }))
}
```

---

## Health Check Integration

### Example: Circuit Breaker Status in Health Check

```rust
use axum::{http::StatusCode, Json};
use resilience::CircuitState;
use serde::Serialize;
use std::sync::Arc;

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub services: ServiceStatus,
}

#[derive(Serialize)]
pub struct ServiceStatus {
    pub user_service: String,
    pub payment_service: String,
    pub redis: String,
}

pub async fn health_check(
    State(state): State<Arc<AppState>>,
) -> (StatusCode, Json<HealthResponse>) {
    let user_service_status = match state.user_service_cb.state() {
        CircuitState::Closed => "healthy",
        CircuitState::HalfOpen => "degraded",
        CircuitState::Open => "unhealthy",
    };

    let payment_service_status = match state.payment_service_cb.state() {
        CircuitState::Closed => "healthy",
        CircuitState::HalfOpen => "degraded",
        CircuitState::Open => "unhealthy",
    };

    let redis_status = match state.redis_cb.state() {
        CircuitState::Closed => "healthy",
        CircuitState::HalfOpen => "degraded",
        CircuitState::Open => "unhealthy",
    };

    let overall_status = if user_service_status == "unhealthy"
        || payment_service_status == "unhealthy"
    {
        "unhealthy"
    } else if user_service_status == "degraded"
        || payment_service_status == "degraded"
        || redis_status == "degraded"
    {
        "degraded"
    } else {
        "healthy"
    };

    let status_code = match overall_status {
        "healthy" => StatusCode::OK,
        "degraded" => StatusCode::OK,
        "unhealthy" => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    };

    (
        status_code,
        Json(HealthResponse {
            status: overall_status.to_string(),
            services: ServiceStatus {
                user_service: user_service_status.to_string(),
                payment_service: payment_service_status.to_string(),
                redis: redis_status.to_string(),
            },
        }),
    )
}
```

---

## Testing

### Example: Integration Test with Mock Service

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use resilience::{presets, CircuitBreaker};
    use std::sync::Arc;

    #[tokio::test]
    async fn test_circuit_breaker_opens_on_failures() {
        let config = presets::grpc_config();
        let cb = Arc::new(CircuitBreaker::new(config.circuit_breaker));

        // Simulate 5 consecutive failures
        for _ in 0..5 {
            let _ = cb.call(|| async {
                Err::<(), _>("service error")
            }).await;
        }

        // Circuit should be open
        assert_eq!(cb.state(), CircuitState::Open);

        // Next call should fail fast
        let result = cb.call(|| async {
            Ok::<_, String>(())
        }).await;

        assert!(result.is_err());
    }
}
```

---

## Monitoring with Prometheus

### Example: Exposing Metrics

```rust
// In Cargo.toml:
// resilience = { path = "../libs/resilience", features = ["metrics"] }

use axum::{routing::get, Router};
use prometheus::{Encoder, TextEncoder};

async fn metrics_handler() -> String {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    String::from_utf8(buffer).unwrap()
}

pub fn metrics_router() -> Router {
    Router::new().route("/metrics", get(metrics_handler))
}
```

---

## See Also

- [README.md](./README.md) - Quick start and API reference
- [PATTERNS.md](./PATTERNS.md) - Detailed pattern explanations

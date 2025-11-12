/// Preset configurations for common service types
use crate::circuit_breaker::CircuitBreakerConfig;
use crate::retry::RetryConfig;
use crate::timeout::TimeoutConfig;
use std::time::Duration;

/// Configuration bundle for a service type
#[derive(Debug, Clone)]
pub struct ServiceConfig {
    pub timeout: TimeoutConfig,
    pub circuit_breaker: CircuitBreakerConfig,
    pub retry: Option<RetryConfig>,
}

/// gRPC service calls (internal microservices)
///
/// - Timeout: 30s (long enough for complex operations)
/// - Circuit breaker: 5 failures, 60s cooldown
/// - Retry: 3 attempts with exponential backoff
pub fn grpc_config() -> ServiceConfig {
    ServiceConfig {
        timeout: TimeoutConfig {
            duration: Duration::from_secs(30),
        },
        circuit_breaker: CircuitBreakerConfig {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(60),
            error_rate_threshold: 0.5,
            window_size: 100,
        },
        retry: Some(RetryConfig {
            max_retries: 3,
            initial_backoff: Duration::from_millis(100),
            max_backoff: Duration::from_secs(5),
            backoff_multiplier: 2.0,
            jitter: true,
        }),
    }
}

/// Database queries (PostgreSQL, MySQL)
///
/// - Timeout: 10s (queries should be fast)
/// - Circuit breaker: 10 failures, 30s cooldown
/// - No retry (avoid duplicate writes)
pub fn database_config() -> ServiceConfig {
    ServiceConfig {
        timeout: TimeoutConfig {
            duration: Duration::from_secs(10),
        },
        circuit_breaker: CircuitBreakerConfig {
            failure_threshold: 10,
            success_threshold: 3,
            timeout: Duration::from_secs(30),
            error_rate_threshold: 0.6, // More tolerant
            window_size: 100,
        },
        retry: None, // Don't retry DB writes
    }
}

/// Redis/Cache operations
///
/// - Timeout: 5s (cache should be fast)
/// - Circuit breaker: 3 failures, 15s cooldown
/// - Retry: 2 attempts (idempotent reads)
pub fn redis_config() -> ServiceConfig {
    ServiceConfig {
        timeout: TimeoutConfig {
            duration: Duration::from_secs(5),
        },
        circuit_breaker: CircuitBreakerConfig {
            failure_threshold: 3,
            success_threshold: 2,
            timeout: Duration::from_secs(15),
            error_rate_threshold: 0.5,
            window_size: 50,
        },
        retry: Some(RetryConfig {
            max_retries: 2,
            initial_backoff: Duration::from_millis(50),
            max_backoff: Duration::from_secs(1),
            backoff_multiplier: 2.0,
            jitter: true,
        }),
    }
}

/// External HTTP APIs (third-party services)
///
/// - Timeout: 60s (external services can be slow)
/// - Circuit breaker: 5 failures, 120s cooldown
/// - Retry: 5 attempts with longer backoff
pub fn http_external_config() -> ServiceConfig {
    ServiceConfig {
        timeout: TimeoutConfig {
            duration: Duration::from_secs(60),
        },
        circuit_breaker: CircuitBreakerConfig {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(120),
            error_rate_threshold: 0.5,
            window_size: 100,
        },
        retry: Some(RetryConfig {
            max_retries: 5,
            initial_backoff: Duration::from_millis(500),
            max_backoff: Duration::from_secs(30),
            backoff_multiplier: 2.0,
            jitter: true,
        }),
    }
}

/// Kafka producer operations
///
/// - Timeout: 5s (produce should be fast)
/// - Circuit breaker: 5 failures, 30s cooldown
/// - Retry: 3 attempts (idempotent with keys)
pub fn kafka_config() -> ServiceConfig {
    ServiceConfig {
        timeout: TimeoutConfig {
            duration: Duration::from_secs(5),
        },
        circuit_breaker: CircuitBreakerConfig {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(30),
            error_rate_threshold: 0.5,
            window_size: 100,
        },
        retry: Some(RetryConfig {
            max_retries: 3,
            initial_backoff: Duration::from_millis(100),
            max_backoff: Duration::from_secs(5),
            backoff_multiplier: 2.0,
            jitter: true,
        }),
    }
}

/// S3/Object storage operations
///
/// - Timeout: 120s (large file uploads)
/// - Circuit breaker: 5 failures, 60s cooldown
/// - Retry: 5 attempts (idempotent with multipart)
pub fn object_storage_config() -> ServiceConfig {
    ServiceConfig {
        timeout: TimeoutConfig {
            duration: Duration::from_secs(120),
        },
        circuit_breaker: CircuitBreakerConfig {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(60),
            error_rate_threshold: 0.5,
            window_size: 50,
        },
        retry: Some(RetryConfig {
            max_retries: 5,
            initial_backoff: Duration::from_millis(500),
            max_backoff: Duration::from_secs(30),
            backoff_multiplier: 2.0,
            jitter: true,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grpc_config() {
        let config = grpc_config();
        assert_eq!(config.timeout.duration, Duration::from_secs(30));
        assert_eq!(config.circuit_breaker.failure_threshold, 5);
        assert!(config.retry.is_some());
    }

    #[test]
    fn test_database_config() {
        let config = database_config();
        assert_eq!(config.timeout.duration, Duration::from_secs(10));
        assert!(config.retry.is_none()); // No retry for DB
    }

    #[test]
    fn test_redis_config() {
        let config = redis_config();
        assert_eq!(config.timeout.duration, Duration::from_secs(5));
        assert!(config.retry.is_some());
    }

    #[test]
    fn test_http_external_config() {
        let config = http_external_config();
        assert_eq!(config.timeout.duration, Duration::from_secs(60));
        assert!(config.retry.is_some());
    }

    #[test]
    fn test_kafka_config() {
        let config = kafka_config();
        assert_eq!(config.timeout.duration, Duration::from_secs(5));
        assert!(config.retry.is_some());
    }

    #[test]
    fn test_object_storage_config() {
        let config = object_storage_config();
        assert_eq!(config.timeout.duration, Duration::from_secs(120));
        assert!(config.retry.is_some());
    }
}

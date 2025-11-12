/// Integration tests for resilience library
use resilience::{
    circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState},
    presets,
    retry::{with_retry, RetryConfig},
    timeout::{with_timeout, with_timeout_result},
};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;

// ==================== Circuit Breaker Tests ====================

#[tokio::test]
async fn test_circuit_breaker_full_lifecycle() {
    let config = CircuitBreakerConfig {
        failure_threshold: 3,
        success_threshold: 2,
        timeout: Duration::from_millis(100),
        ..Default::default()
    };
    let cb = CircuitBreaker::new(config);

    // Phase 1: Closed -> Open (3 failures)
    for _ in 0..3 {
        let _ = cb.call(|| async { Err::<(), _>("error") }).await;
    }
    assert_eq!(cb.state(), CircuitState::Open);

    // Phase 2: Open -> HalfOpen (wait for timeout)
    tokio::time::sleep(Duration::from_millis(150)).await;
    let _ = cb.call(|| async { Ok::<_, String>(()) }).await;
    assert_eq!(cb.state(), CircuitState::HalfOpen);

    // Phase 3: HalfOpen -> Closed (2 successes)
    for _ in 0..2 {
        let _ = cb.call(|| async { Ok::<_, String>(()) }).await;
    }
    assert_eq!(cb.state(), CircuitState::Closed);
}

#[tokio::test]
async fn test_circuit_breaker_error_rate_trigger() {
    let config = CircuitBreakerConfig {
        failure_threshold: 100, // High to avoid consecutive failure trigger
        error_rate_threshold: 0.6, // 60%
        window_size: 10,
        ..Default::default()
    };
    let cb = CircuitBreaker::new(config);

    // 7 failures out of 10 = 70% error rate
    for _ in 0..7 {
        let _ = cb.call(|| async { Err::<(), _>("error") }).await;
    }
    for _ in 0..3 {
        let _ = cb.call(|| async { Ok::<_, String>(()) }).await;
    }

    assert_eq!(cb.state(), CircuitState::Open);
}

#[tokio::test]
async fn test_circuit_breaker_halfopen_fails_back_to_open() {
    let config = CircuitBreakerConfig {
        failure_threshold: 2,
        timeout: Duration::from_millis(50),
        ..Default::default()
    };
    let cb = CircuitBreaker::new(config);

    // Open circuit
    for _ in 0..2 {
        let _ = cb.call(|| async { Err::<(), _>("error") }).await;
    }

    // Transition to HalfOpen
    tokio::time::sleep(Duration::from_millis(100)).await;
    let _ = cb.call(|| async { Ok::<_, String>(()) }).await;

    // Failure in HalfOpen -> back to Open
    let _ = cb.call(|| async { Err::<(), _>("error") }).await;
    assert_eq!(cb.state(), CircuitState::Open);
}

#[tokio::test]
async fn test_circuit_breaker_rejects_when_open() {
    let config = CircuitBreakerConfig {
        failure_threshold: 2,
        timeout: Duration::from_secs(10), // Long timeout
        ..Default::default()
    };
    let cb = CircuitBreaker::new(config);

    // Open circuit
    for _ in 0..2 {
        let _ = cb.call(|| async { Err::<(), _>("error") }).await;
    }

    // Should reject immediately
    let result = cb.call(|| async { Ok::<_, String>(()) }).await;
    assert!(result.is_err());
}

// ==================== Timeout Tests ====================

#[tokio::test]
async fn test_timeout_success() {
    let result = with_timeout(Duration::from_secs(1), async {
        tokio::time::sleep(Duration::from_millis(10)).await;
        42
    })
    .await;

    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 42);
}

#[tokio::test]
async fn test_timeout_elapsed() {
    let result = with_timeout(Duration::from_millis(50), async {
        tokio::time::sleep(Duration::from_secs(1)).await;
        42
    })
    .await;

    assert!(result.is_err());
}

#[tokio::test]
async fn test_timeout_result_operation_failed() {
    let result = with_timeout_result(Duration::from_secs(1), async {
        Err::<i32, _>("operation failed")
    })
    .await;

    assert!(result.is_err());
}

// ==================== Retry Tests ====================

#[tokio::test]
async fn test_retry_success_on_first_attempt() {
    let config = RetryConfig::default();
    let counter = Arc::new(AtomicU32::new(0));
    let counter_clone = counter.clone();

    let result = with_retry(config, move || {
        counter_clone.fetch_add(1, Ordering::SeqCst);
        async { Ok::<_, String>(42) }
    })
    .await;

    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 42);
    assert_eq!(counter.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn test_retry_success_after_transient_failures() {
    let config = RetryConfig {
        max_retries: 3,
        initial_backoff: Duration::from_millis(10),
        jitter: false,
        ..Default::default()
    };

    let counter = Arc::new(AtomicU32::new(0));
    let counter_clone = counter.clone();

    let result = with_retry(config, move || {
        let count = counter_clone.fetch_add(1, Ordering::SeqCst);
        async move {
            if count < 2 {
                Err("transient error")
            } else {
                Ok(42)
            }
        }
    })
    .await;

    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 42);
    assert_eq!(counter.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn test_retry_max_retries_exceeded() {
    let config = RetryConfig {
        max_retries: 2,
        initial_backoff: Duration::from_millis(10),
        jitter: false,
        ..Default::default()
    };

    let counter = Arc::new(AtomicU32::new(0));
    let counter_clone = counter.clone();

    let result = with_retry(config, move || {
        counter_clone.fetch_add(1, Ordering::SeqCst);
        async { Err::<i32, _>("persistent error") }
    })
    .await;

    assert!(result.is_err());
    assert_eq!(counter.load(Ordering::SeqCst), 3); // Initial + 2 retries
}

#[tokio::test]
async fn test_retry_exponential_backoff_timing() {
    let config = RetryConfig {
        max_retries: 3,
        initial_backoff: Duration::from_millis(50),
        backoff_multiplier: 2.0,
        jitter: false,
        ..Default::default()
    };

    let start = std::time::Instant::now();

    let _ = with_retry(config, || async { Err::<i32, _>("error") }).await;

    let elapsed = start.elapsed();

    // Expected: 50ms + 100ms + 200ms = 350ms minimum
    assert!(elapsed >= Duration::from_millis(350));
}

// ==================== Preset Configuration Tests ====================

#[test]
fn test_grpc_config_values() {
    let config = presets::grpc_config();
    assert_eq!(config.timeout.duration, Duration::from_secs(30));
    assert_eq!(config.circuit_breaker.failure_threshold, 5);
    assert!(config.retry.is_some());
    assert_eq!(config.retry.unwrap().max_retries, 3);
}

#[test]
fn test_database_config_no_retry() {
    let config = presets::database_config();
    assert_eq!(config.timeout.duration, Duration::from_secs(10));
    assert!(config.retry.is_none()); // DB should not retry
}

#[test]
fn test_redis_config_fast_timeout() {
    let config = presets::redis_config();
    assert_eq!(config.timeout.duration, Duration::from_secs(5));
    assert!(config.retry.is_some());
}

#[test]
fn test_http_external_config_long_timeout() {
    let config = presets::http_external_config();
    assert_eq!(config.timeout.duration, Duration::from_secs(60));
    assert!(config.retry.is_some());
}

// ==================== Combined Scenario Tests ====================

#[tokio::test]
async fn test_circuit_breaker_with_timeout() {
    let config = CircuitBreakerConfig {
        failure_threshold: 2,
        ..Default::default()
    };
    let cb = CircuitBreaker::new(config);

    // First call: timeout
    let _ = cb
        .call(|| async {
            with_timeout(Duration::from_millis(10), async {
                tokio::time::sleep(Duration::from_secs(1)).await;
                Ok::<(), String>(())
            })
            .await
            .map_err(|e| e.to_string())
        })
        .await;

    // Second call: timeout
    let _ = cb
        .call(|| async {
            with_timeout(Duration::from_millis(10), async {
                tokio::time::sleep(Duration::from_secs(1)).await;
                Ok::<(), String>(())
            })
            .await
            .map_err(|e| e.to_string())
        })
        .await;

    // Circuit should be open
    assert_eq!(cb.state(), CircuitState::Open);
}

#[tokio::test]
async fn test_retry_basic_functionality() {
    // Simple test: retry succeeds after transient failure
    let retry_config = RetryConfig {
        max_retries: 3,
        initial_backoff: Duration::from_millis(10),
        jitter: false,
        ..Default::default()
    };

    let counter = Arc::new(AtomicU32::new(0));
    let counter_clone = counter.clone();

    let result = with_retry(retry_config, move || {
        let count = counter_clone.fetch_add(1, Ordering::SeqCst);
        async move {
            if count < 2 {
                Err("temporary failure")
            } else {
                Ok(42)
            }
        }
    })
    .await;

    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 42);
}

#[tokio::test]
async fn test_grpc_preset_config_values() {
    // Verify gRPC preset configuration is correctly set
    let config = presets::grpc_config();
    let cb = CircuitBreaker::new(config.circuit_breaker);

    // Circuit breaker should start closed
    assert_eq!(cb.state(), CircuitState::Closed);

    // Should handle successful calls
    let result = cb.call(|| async { Ok::<_, String>(42) }).await;
    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 42);
}

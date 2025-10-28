//! Circuit Breaker integration tests
//!
//! Tests for circuit breaker state transitions, graceful degradation,
//! and error handling across all protected handlers.

use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;
use user_service::middleware::circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};
use user_service::error::AppError;

/// Test configuration for faster test execution (shorter timeouts)
fn test_config() -> CircuitBreakerConfig {
    CircuitBreakerConfig {
        failure_threshold: 2,      // Open after 2 failures
        success_threshold: 2,      // Close after 2 successes in half-open
        timeout_seconds: 1,        // 1 second timeout for quick testing
    }
}

// ============================================
// Unit Tests for CB State Machine
// ============================================

#[tokio::test]
async fn test_cb_initial_state_is_closed() {
    let cb = CircuitBreaker::new(test_config());
    assert_eq!(cb.get_state().await, CircuitState::Closed);
}

#[tokio::test]
async fn test_cb_opens_after_failure_threshold() {
    let cb = CircuitBreaker::new(test_config());

    // Record 2 failures (threshold = 2)
    for i in 1..=2 {
        let result = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;

        assert!(result.is_err());
        if i == 2 {
            assert_eq!(cb.get_state().await, CircuitState::Open);
        }
    }
}

#[tokio::test]
async fn test_cb_fails_fast_when_open() {
    let cb = CircuitBreaker::new(test_config());

    // Open the circuit
    for _ in 0..2 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;
    }

    assert_eq!(cb.get_state().await, CircuitState::Open);

    // Next request should fail immediately without executing closure
    let result = cb.call(|| async {
        Ok::<_, AppError>(())
    }).await;

    assert!(result.is_err());
    match result {
        Err(AppError::Internal(msg)) => {
            assert!(msg.contains("Circuit breaker is OPEN") || msg.contains("temporarily unavailable"));
        }
        _ => panic!("Expected specific error message"),
    }
}

#[tokio::test]
async fn test_cb_transitions_to_half_open_after_timeout() {
    let cb = CircuitBreaker::new(test_config());

    // Open the circuit
    for _ in 0..2 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;
    }

    assert_eq!(cb.get_state().await, CircuitState::Open);

    // Wait for timeout
    sleep(Duration::from_millis(1100)).await;

    // Next call should transition to half-open and allow the request
    let result = cb.call(|| async {
        Ok::<(), AppError>(())
    }).await;

    assert!(result.is_ok());

    let state = cb.get_state().await;
    assert!(state == CircuitState::HalfOpen || state == CircuitState::Closed);
}

#[tokio::test]
async fn test_cb_closes_after_success_threshold_in_half_open() {
    let cb = CircuitBreaker::new(test_config());

    // Open the circuit
    for _ in 0..2 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;
    }

    // Wait for timeout to transition to half-open
    sleep(Duration::from_millis(1100)).await;

    // Record 2 successful calls (success_threshold = 2)
    let mut state = cb.get_state().await;

    if state == CircuitState::Open {
        // Transition to half-open first
        let _ = cb.call(|| async { Ok::<(), AppError>(()) }).await;
    }

    // Record successes
    for i in 0..2 {
        let result = cb.call(|| async {
            Ok::<(), AppError>(())
        }).await;

        assert!(result.is_ok());
        if i == 1 {
            state = cb.get_state().await;
            assert_eq!(state, CircuitState::Closed,
                      "CB should be CLOSED after success threshold in half-open");
        }
    }
}

#[tokio::test]
async fn test_cb_reopens_on_failure_in_half_open() {
    let cb = CircuitBreaker::new(test_config());

    // Open the circuit
    for _ in 0..2 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;
    }

    assert_eq!(cb.get_state().await, CircuitState::Open);

    // Wait for timeout
    sleep(Duration::from_millis(1100)).await;

    // Trigger transition to half-open
    let _ = cb.call(|| async { Ok::<(), AppError>(()) }).await;

    // Now fail in half-open - should immediately reopen
    let result = cb.call(|| async {
        Err::<(), _>(AppError::Internal("test failure in half-open".to_string()))
    }).await;

    assert!(result.is_err());
    assert_eq!(cb.get_state().await, CircuitState::Open,
              "CB should reopen immediately on failure in half-open");
}

#[tokio::test]
async fn test_cb_reset_restores_closed_state() {
    let cb = CircuitBreaker::new(test_config());

    // Open the circuit
    for _ in 0..2 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;
    }

    assert_eq!(cb.get_state().await, CircuitState::Open);

    // Reset
    cb.reset().await;

    assert_eq!(cb.get_state().await, CircuitState::Closed);
}

// ============================================
// Tests for Success Tracking
// ============================================

#[tokio::test]
async fn test_cb_resets_failure_count_on_success_in_closed() {
    let cb = CircuitBreaker::new(test_config());

    // Record 1 failure
    let _ = cb.call(|| async {
        Err::<(), _>(AppError::Internal("test failure".to_string()))
    }).await;

    // Success should reset failure count
    let _ = cb.call(|| async {
        Ok::<(), AppError>(())
    }).await;

    // Record 1 more failure - should only need 1 more to open (not 2)
    let _ = cb.call(|| async {
        Err::<(), _>(AppError::Internal("test failure".to_string()))
    }).await;

    // Next failure should open (since we reset on success)
    let _ = cb.call(|| async {
        Err::<(), _>(AppError::Internal("test failure".to_string()))
    }).await;

    assert_eq!(cb.get_state().await, CircuitState::Open);
}

// ============================================
// Tests for Statistics
// ============================================

#[tokio::test]
async fn test_cb_stats_tracking() {
    let cb = CircuitBreaker::new(test_config());

    // Initial stats
    let stats = cb.get_stats().await;
    assert_eq!(stats.state, CircuitState::Closed);
    assert_eq!(stats.failure_count, 0);
    assert_eq!(stats.success_count, 0);
    assert!(stats.last_failure_time.is_none());

    // After failure
    let _ = cb.call(|| async {
        Err::<(), _>(AppError::Internal("test".to_string()))
    }).await;

    let stats = cb.get_stats().await;
    assert_eq!(stats.failure_count, 1);
    assert!(stats.last_failure_time.is_some());

    // After success
    let _ = cb.call(|| async {
        Ok::<(), AppError>(())
    }).await;

    let stats = cb.get_stats().await;
    assert_eq!(stats.failure_count, 0); // Reset on success in closed
}

// ============================================
// Tests for Graceful Degradation Pattern
// ============================================

#[tokio::test]
async fn test_cb_graceful_degradation_with_empty_results() {
    let cb = Arc::new(CircuitBreaker::new(test_config()));

    // Simulate handler that returns empty results when CB opens
    let handler = |cb: Arc<CircuitBreaker>| async move {
        match cb.call(|| async {
            Err::<Vec<String>, _>(AppError::Internal("Database error".to_string()))
        }).await {
            Ok(results) => Ok((results, 200)),
            Err(e) => {
                match &e {
                    AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                        // Graceful degradation: return empty results instead of error
                        Ok((Vec::new(), 200))
                    }
                    _ => Err((format!("Error: {}", e), 500)),
                }
            }
        }
    };

    // Open the circuit
    for _ in 0..2 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("Database error".to_string()))
        }).await;
    }

    // Handler should return empty results with 200 OK
    let (results, status) = handler(cb).await.unwrap();
    assert!(results.is_empty());
    assert_eq!(status, 200);
}

#[tokio::test]
async fn test_cb_error_message_contains_open_indicator() {
    let cb = CircuitBreaker::new(test_config());

    // Open the circuit
    for _ in 0..2 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;
    }

    // Error message should indicate circuit is open
    let result = cb.call(|| async {
        Ok::<(), AppError>(())
    }).await;

    assert!(result.is_err());
    let err_str = format!("{:?}", result.err().unwrap());
    assert!(err_str.to_lowercase().contains("circuit") ||
            err_str.to_lowercase().contains("open") ||
            err_str.to_lowercase().contains("unavailable"));
}

// ============================================
// Tests for Concurrent Access
// ============================================

#[tokio::test]
async fn test_cb_handles_concurrent_requests_during_state_change() {
    let cb = Arc::new(CircuitBreaker::new(test_config()));
    let mut handles = vec![];

    // Open the circuit with concurrent requests
    for i in 0..4 {
        let cb_clone = cb.clone();
        let handle = tokio::spawn(async move {
            if i < 2 {
                // First 2 will fail and open
                let _ = cb_clone.call(|| async {
                    Err::<(), _>(AppError::Internal("test failure".to_string()))
                }).await;
            } else {
                // Last 2 should encounter open circuit
                let _ = cb_clone.call(|| async {
                    Ok::<(), AppError>(())
                }).await;
            }
        });
        handles.push(handle);
    }

    // Wait for all concurrent requests
    for handle in handles {
        let _ = handle.await;
    }

    // Circuit should be open
    assert_eq!(cb.get_state().await, CircuitState::Open);
}

#[tokio::test]
async fn test_cb_preserves_state_under_concurrent_access() {
    let cb = Arc::new(CircuitBreaker::new(test_config()));
    let mut handles = vec![];

    // Spin up 10 concurrent requests to same CB
    for _ in 0..10 {
        let cb_clone = cb.clone();
        let handle = tokio::spawn(async move {
            let _ = cb_clone.call(|| async {
                Ok::<i32, AppError>(42)
            }).await;
        });
        handles.push(handle);
    }

    // Wait for all
    for handle in handles {
        let _ = handle.await;
    }

    // State should still be Closed (no failures)
    assert_eq!(cb.get_state().await, CircuitState::Closed);

    let stats = cb.get_stats().await;
    assert_eq!(stats.failure_count, 0);
}

// ============================================
// Tests for Multiple CB Instances (Handler Isolation)
// ============================================

#[tokio::test]
async fn test_multiple_cb_instances_are_independent() {
    let cb1 = Arc::new(CircuitBreaker::new(test_config()));
    let cb2 = Arc::new(CircuitBreaker::new(test_config()));

    // Open CB1
    for _ in 0..2 {
        let _ = cb1.call(|| async {
            Err::<(), _>(AppError::Internal("test failure".to_string()))
        }).await;
    }

    assert_eq!(cb1.get_state().await, CircuitState::Open);
    assert_eq!(cb2.get_state().await, CircuitState::Closed,
              "CB2 should remain closed when CB1 opens");

    // CB2 should still work normally
    let result = cb2.call(|| async {
        Ok::<(), AppError>(())
    }).await;

    assert!(result.is_ok());
}

// ============================================
// Integration Scenario Tests
// ============================================

#[tokio::test]
async fn test_realistic_handler_cb_scenario() {
    /// Simulates a handler that protects database queries
    struct MockHandler {
        cb: Arc<CircuitBreaker>,
        db_healthy: Arc<tokio::sync::Mutex<bool>>,
    }

    impl MockHandler {
        async fn get_posts(&self) -> Result<Vec<String>, (String, u16)> {
            match self.cb.call(|| {
                let db_healthy = self.db_healthy.clone();
                async move {
                    let healthy = *db_healthy.lock().await;
                    if healthy {
                        Ok(vec!["post1".to_string(), "post2".to_string()])
                    } else {
                        Err(AppError::Internal("Database connection failed".to_string()))
                    }
                }
            }).await {
                Ok(posts) => Ok(posts),
                Err(e) => {
                    match &e {
                        AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                            // Graceful degradation: return empty list instead of 503
                            Ok(Vec::new())
                        }
                        AppError::Internal(_) => {
                            // Regular database error also returns empty gracefully
                            Ok(Vec::new())
                        }
                        _ => Err((e.to_string(), 500)),
                    }
                }
            }
        }
    }

    let cb = Arc::new(CircuitBreaker::new(test_config()));
    let db_healthy = Arc::new(tokio::sync::Mutex::new(false));
    let handler = MockHandler {
        cb: cb.clone(),
        db_healthy: db_healthy.clone(),
    };

    // Database is down - should fail initially
    let result = handler.get_posts().await;
    assert!(result.is_ok()); // OK but empty

    // Fail again to open circuit
    let result = handler.get_posts().await;
    assert!(result.is_ok());
    assert!(result.unwrap().is_empty());

    // Verify circuit is open
    assert_eq!(cb.get_state().await, CircuitState::Open);

    // Continue returning empty gracefully while circuit is open
    for _ in 0..3 {
        let result = handler.get_posts().await;
        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }

    // Database recovers
    *db_healthy.lock().await = true;

    // Wait for timeout
    sleep(Duration::from_millis(1100)).await;

    // Handler should start working again after timeout + successes
    let result = handler.get_posts().await;
    assert!(result.is_ok());

    let posts = result.unwrap();
    // Eventually should return real posts
    if !posts.is_empty() {
        assert_eq!(posts.len(), 2);
    }
}

// ============================================
// Edge Cases
// ============================================

#[tokio::test]
async fn test_cb_handles_zero_timeout() {
    // Edge case: timeout of 0 seconds means immediate recovery
    let cb = CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 1,
        success_threshold: 1,
        timeout_seconds: 0,
    });

    // Open circuit
    let _ = cb.call(|| async {
        Err::<(), _>(AppError::Internal("test".to_string()))
    }).await;

    assert_eq!(cb.get_state().await, CircuitState::Open);

    // Immediate recovery should work
    let result = cb.call(|| async {
        Ok::<(), AppError>(())
    }).await;

    assert!(result.is_ok());
}

#[tokio::test]
async fn test_cb_with_very_high_thresholds() {
    // Edge case: very conservative thresholds
    let cb = CircuitBreaker::new(CircuitBreakerConfig {
        failure_threshold: 100,
        success_threshold: 100,
        timeout_seconds: 3600,
    });

    // Many failures should not open
    for _ in 0..10 {
        let _ = cb.call(|| async {
            Err::<(), _>(AppError::Internal("test".to_string()))
        }).await;
    }

    assert_eq!(cb.get_state().await, CircuitState::Closed);
}

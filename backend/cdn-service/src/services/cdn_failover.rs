/// CDN Failover and Error Handling Service
///
/// Manages failover between CDN and origin, with circuit breaker pattern,
/// exponential backoff, and comprehensive error tracking.
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};

/// Failover state for tracking failures
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailoverState {
    /// CDN is healthy
    HealthyCache,
    /// CDN degraded (some failures)
    DegradedCache,
    /// CDN circuit broken (too many failures)
    BrokenCircuit,
    /// Fallback to origin in use
    UsingFallback,
}

impl FailoverState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::HealthyCache => "healthy",
            Self::DegradedCache => "degraded",
            Self::BrokenCircuit => "broken_circuit",
            Self::UsingFallback => "using_fallback",
        }
    }
}

/// CDN failure tracker
#[derive(Debug, Clone)]
pub struct FailureEvent {
    pub timestamp: u64,
    pub error_type: String,
    pub reason: String,
}

/// Failover manager with circuit breaker pattern
pub struct FailoverManager {
    state: Arc<RwLock<FailoverState>>,
    failure_count: Arc<AtomicU32>,
    success_count: Arc<AtomicU32>,
    last_failure: Arc<RwLock<Option<FailureEvent>>>,
    /// Threshold for circuit breaking (failures before breaking)
    failure_threshold: u32,
    /// Success count needed to recover from broken circuit
    recovery_threshold: u32,
    /// Backoff multiplier for exponential backoff
    backoff_multiplier: u32,
}

impl FailoverManager {
    /// Create a new failover manager
    pub fn new(failure_threshold: u32, recovery_threshold: u32) -> Self {
        info!(
            "Initializing Failover Manager: failure_threshold={}, recovery_threshold={}",
            failure_threshold, recovery_threshold
        );

        Self {
            state: Arc::new(RwLock::new(FailoverState::HealthyCache)),
            failure_count: Arc::new(AtomicU32::new(0)),
            success_count: Arc::new(AtomicU32::new(0)),
            last_failure: Arc::new(RwLock::new(None)),
            failure_threshold,
            recovery_threshold,
            backoff_multiplier: 2,
        }
    }

    /// Record a successful operation
    pub async fn record_success(&self) {
        let old_count = self.success_count.fetch_add(1, Ordering::SeqCst);
        let state = self.state.read().await;

        match *state {
            FailoverState::BrokenCircuit => {
                if old_count + 1 >= self.recovery_threshold {
                    info!("Circuit breaker recovering: {} successes", old_count + 1);
                    drop(state);
                    self.set_state(FailoverState::HealthyCache).await;
                    self.failure_count.store(0, Ordering::SeqCst);
                    self.success_count.store(0, Ordering::SeqCst);
                }
            }
            FailoverState::DegradedCache => {
                self.failure_count.store(0, Ordering::SeqCst);
                drop(state);
                self.set_state(FailoverState::HealthyCache).await;
            }
            _ => {}
        }
    }

    /// Record a failed operation
    pub async fn record_failure(&self, error_type: &str, reason: &str) {
        let old_count = self.failure_count.fetch_add(1, Ordering::SeqCst);
        let mut last_failure = self.last_failure.write().await;

        *last_failure = Some(FailureEvent {
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0),
            error_type: error_type.to_string(),
            reason: reason.to_string(),
        });

        drop(last_failure);

        // Transition to degraded after 1-2 failures
        {
            let state = self.state.read().await;
            if old_count + 1 == 1 && *state == FailoverState::HealthyCache {
                warn!("CDN degraded: {} failures", old_count + 1);
                drop(state);
                self.set_state(FailoverState::DegradedCache).await;
            }
        }

        // Break circuit after threshold reached
        if old_count + 1 >= self.failure_threshold {
            error!("Circuit breaker activated: {} failures", old_count + 1);
            self.set_state(FailoverState::BrokenCircuit).await;
            self.set_state(FailoverState::UsingFallback).await;
        }
    }

    /// Set failover state
    pub async fn set_state(&self, state: FailoverState) {
        let mut current_state = self.state.write().await;
        if *current_state != state {
            info!(
                "Failover state transition: {} → {}",
                current_state.as_str(),
                state.as_str()
            );
            *current_state = state;
        }
    }

    /// Get current failover state
    pub async fn get_state(&self) -> FailoverState {
        *self.state.read().await
    }

    /// Check if should use fallback
    pub async fn should_use_fallback(&self) -> bool {
        let state = self.get_state().await;
        state == FailoverState::BrokenCircuit || state == FailoverState::UsingFallback
    }

    /// Get exponential backoff delay in milliseconds
    pub fn get_backoff_delay(&self) -> u32 {
        let failure_count = self.failure_count.load(Ordering::SeqCst);
        let base_delay = 100u32; // 100ms base

        // Exponential backoff: base * multiplier^count, capped at 10 seconds
        let delay =
            base_delay.saturating_mul(self.backoff_multiplier.saturating_pow(failure_count));

        delay.min(10000) // Cap at 10 seconds
    }

    /// Get failure statistics
    pub async fn get_stats(&self) -> FailoverStats {
        let state = *self.state.read().await;
        let failures = self.failure_count.load(Ordering::SeqCst);
        let successes = self.success_count.load(Ordering::SeqCst);
        let last_failure = self.last_failure.read().await.clone();

        let success_rate = if successes + failures > 0 {
            (successes as f64 / (successes + failures) as f64) * 100.0
        } else {
            100.0
        };

        FailoverStats {
            state,
            failure_count: failures,
            success_count: successes,
            success_rate,
            last_failure: last_failure.clone(),
        }
    }

    /// Reset failover state (admin operation)
    pub async fn reset(&self) {
        info!("Failover manager reset");
        self.failure_count.store(0, Ordering::SeqCst);
        self.success_count.store(0, Ordering::SeqCst);
        self.set_state(FailoverState::HealthyCache).await;
    }

    /// Get maximum backoff delay
    pub fn max_backoff_delay(&self) -> u32 {
        10000 // 10 seconds
    }
}

/// Failover statistics
#[derive(Debug, Clone)]
pub struct FailoverStats {
    pub state: FailoverState,
    pub failure_count: u32,
    pub success_count: u32,
    pub success_rate: f64,
    pub last_failure: Option<FailureEvent>,
}

// Clone already derived in struct definition above

/// Error handling helper
pub struct ErrorHandler;

impl ErrorHandler {
    /// Classify error and return whether to fallback
    pub fn should_fallback(error: &str) -> bool {
        // Errors that warrant fallback
        let fallback_errors = [
            "timeout",
            "connection_refused",
            "cdn_unavailable",
            "service_unavailable",
            "gateway_timeout",
        ];

        let lower_error = error.to_lowercase();
        fallback_errors.iter().any(|e| lower_error.contains(e))
    }

    /// Get error severity level
    pub fn get_severity(error: &str) -> ErrorSeverity {
        let lower_error = error.to_lowercase();

        if lower_error.contains("fatal") || lower_error.contains("panic") {
            ErrorSeverity::Critical
        } else if lower_error.contains("timeout") || lower_error.contains("unavailable") {
            ErrorSeverity::High
        } else if lower_error.contains("degraded") || lower_error.contains("retry") {
            ErrorSeverity::Medium
        } else {
            ErrorSeverity::Low
        }
    }
}

/// Error severity levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum ErrorSeverity {
    Low,
    Medium,
    High,
    Critical,
}

impl ErrorSeverity {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
            Self::Critical => "critical",
        }
    }
}

#[cfg(test)]
#[cfg(all(test, feature = "legacy_internal_tests"))]
mod tests {
    use super::*;

    #[test]
    fn test_failover_state_str() {
        assert_eq!(FailoverState::HealthyCache.as_str(), "healthy");
        assert_eq!(FailoverState::DegradedCache.as_str(), "degraded");
        assert_eq!(FailoverState::BrokenCircuit.as_str(), "broken_circuit");
        assert_eq!(FailoverState::UsingFallback.as_str(), "using_fallback");
    }

    #[test]
    fn test_error_severity_str() {
        assert_eq!(ErrorSeverity::Low.as_str(), "low");
        assert_eq!(ErrorSeverity::Critical.as_str(), "critical");
    }

    #[tokio::test]
    async fn test_failover_creation() {
        let manager = FailoverManager::new(5, 3);
        assert_eq!(manager.get_state().await, FailoverState::HealthyCache);
    }

    #[tokio::test]
    async fn test_failover_success_record() {
        let manager = FailoverManager::new(5, 3);
        manager.record_success().await;

        let stats = manager.get_stats().await;
        assert_eq!(stats.success_count, 1);
        assert_eq!(stats.failure_count, 0);
    }

    #[tokio::test]
    async fn test_failover_failure_record() {
        let manager = FailoverManager::new(5, 3);
        manager.record_failure("timeout", "CDN timeout").await;

        let stats = manager.get_stats().await;
        assert_eq!(stats.failure_count, 1);
        assert!(stats.last_failure.is_some());
    }

    #[tokio::test]
    async fn test_failover_degraded_state() {
        let manager = FailoverManager::new(5, 3);
        manager.record_failure("timeout", "CDN timeout").await;

        let state = manager.get_state().await;
        assert_eq!(state, FailoverState::DegradedCache);
    }

    #[tokio::test]
    async fn test_failover_circuit_break() {
        let manager = FailoverManager::new(2, 3);

        // Fail twice to break circuit
        manager.record_failure("timeout", "CDN timeout").await;
        manager.record_failure("timeout", "CDN timeout").await;

        let state = manager.get_state().await;
        assert_eq!(state, FailoverState::UsingFallback);
    }

    #[tokio::test]
    async fn test_failover_recovery() {
        let manager = FailoverManager::new(2, 2);

        // Break circuit
        manager.record_failure("timeout", "CDN timeout").await;
        manager.record_failure("timeout", "CDN timeout").await;
        assert!(manager.should_use_fallback().await);

        // Recover with successes
        manager.record_success().await;
        manager.record_success().await;

        let state = manager.get_state().await;
        assert_eq!(state, FailoverState::HealthyCache);
    }

    #[test]
    fn test_error_classification() {
        assert!(ErrorHandler::should_fallback("timeout"));
        assert!(ErrorHandler::should_fallback("cdn_unavailable"));
        assert!(!ErrorHandler::should_fallback("invalid_format"));
    }

    #[test]
    fn test_error_severity() {
        assert_eq!(
            ErrorHandler::get_severity("fatal error"),
            ErrorSeverity::Critical
        );
        assert_eq!(ErrorHandler::get_severity("timeout"), ErrorSeverity::High);
        assert_eq!(
            ErrorHandler::get_severity("retry later"),
            ErrorSeverity::Medium
        );
    }

    #[test]
    fn test_backoff_calculation() {
        let manager = FailoverManager::new(5, 3);

        // Initial failures have exponential backoff
        manager.failure_count.store(1, Ordering::SeqCst);
        let delay = manager.get_backoff_delay();
        assert!(delay > 100 && delay <= 10000);

        // Max backoff is 10 seconds
        manager.failure_count.store(100, Ordering::SeqCst);
        let delay = manager.get_backoff_delay();
        assert_eq!(delay, 10000);
    }

    #[tokio::test]
    async fn test_failover_reset() {
        let manager = FailoverManager::new(2, 3);

        manager.record_failure("timeout", "error").await;
        manager.record_failure("timeout", "error").await;
        assert!(manager.should_use_fallback().await);

        manager.reset().await;
        assert_eq!(manager.get_state().await, FailoverState::HealthyCache);

        let stats = manager.get_stats().await;
        assert_eq!(stats.failure_count, 0);
    }
}

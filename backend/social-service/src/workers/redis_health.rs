//! Redis Connection Health Check Background Job
//!
//! Periodically pings Redis to keep connections alive and detect stale connections
//! before they cause "broken pipe" errors during actual counter operations.
//!
//! The Redis server has a tcp-keepalive of 300 seconds, but connections can still
//! become stale during periods of low traffic. This health check runs every 60 seconds
//! to ensure connections remain active.

use crate::services::CounterService;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;

/// How often to ping Redis (every 60 seconds)
const HEALTH_CHECK_INTERVAL: Duration = Duration::from_secs(60);

/// Configuration for Redis health checks
#[derive(Clone)]
pub struct RedisHealthConfig {
    pub enabled: bool,
    pub check_interval: Duration,
}

impl Default for RedisHealthConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            check_interval: HEALTH_CHECK_INTERVAL,
        }
    }
}

/// Start the Redis health check background job
///
/// This job periodically pings Redis to:
/// 1. Keep TCP connections alive (prevents broken pipe errors)
/// 2. Detect connection issues early (before user-facing operations fail)
/// 3. Trigger ConnectionManager's automatic reconnection if needed
pub async fn start_redis_health_check(counter_service: Arc<CounterService>, config: RedisHealthConfig) {
    if !config.enabled {
        tracing::info!("Redis health check disabled by configuration");
        return;
    }

    tracing::info!(
        interval_secs = config.check_interval.as_secs(),
        "Starting Redis health check background job for social-service"
    );

    // Initial delay to let services start up
    sleep(Duration::from_secs(10)).await;

    let mut consecutive_failures = 0;
    let max_consecutive_failures = 5;

    loop {
        match counter_service.ping().await {
            Ok(()) => {
                if consecutive_failures > 0 {
                    tracing::info!(
                        previous_failures = consecutive_failures,
                        "Redis connection recovered"
                    );
                }
                consecutive_failures = 0;
                tracing::debug!("Redis health check: OK");
            }
            Err(e) => {
                consecutive_failures += 1;
                if consecutive_failures >= max_consecutive_failures {
                    tracing::error!(
                        consecutive_failures = consecutive_failures,
                        error = %e,
                        "Redis health check: CRITICAL - multiple consecutive failures"
                    );
                } else {
                    tracing::warn!(
                        consecutive_failures = consecutive_failures,
                        error = %e,
                        "Redis health check: FAILED"
                    );
                }
            }
        }

        sleep(config.check_interval).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = RedisHealthConfig::default();
        assert!(config.enabled);
        assert_eq!(config.check_interval, Duration::from_secs(60));
    }
}

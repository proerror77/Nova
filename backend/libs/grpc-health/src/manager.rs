//! Health check manager and background monitoring

use crate::checks::HealthCheck;
use crate::error::Result;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tonic_health::pb::health_server::{Health, HealthServer};
use tonic_health::server::HealthReporter;

/// Health check manager
///
/// Coordinates health checks for multiple dependencies and reports status
/// to the gRPC health service.
pub struct HealthManager {
    reporter: HealthReporter,
    checks: Arc<RwLock<Vec<Box<dyn HealthCheck>>>>,
}

impl HealthManager {
    /// Create a new health manager
    ///
    /// Returns a tuple of (manager, health_server) where health_server
    /// should be added to your gRPC server.
    pub fn new() -> (Self, HealthServer<impl Health>) {
        let (reporter, service) = tonic_health::server::health_reporter();

        let manager = Self {
            reporter,
            checks: Arc::new(RwLock::new(Vec::new())),
        };

        (manager, service)
    }

    /// Register a health check
    ///
    /// All registered checks will be executed during health check runs.
    pub async fn register_check(&self, check: Box<dyn HealthCheck>) {
        self.checks.write().await.push(check);
    }

    /// Execute all registered health checks
    ///
    /// Returns `Ok(())` if all checks pass, or the first error encountered.
    pub async fn execute_checks(&self) -> Result<()> {
        let checks = self.checks.read().await;

        for check in checks.iter() {
            check.check().await?;
        }

        Ok(())
    }

    /// Run health check and update service status
    ///
    /// Executes all registered health checks and updates the overall health status
    /// to SERVING or NOT_SERVING based on the results.
    pub async fn check_and_update(&mut self) {
        match self.execute_checks().await {
            Ok(()) => {
                tracing::debug!("All health checks passed, setting status to SERVING");
                // Set overall server health to serving (empty string = overall health)
                self.reporter
                    .set_service_status("", tonic_health::ServingStatus::Serving)
                    .await;
            }
            Err(e) => {
                tracing::error!(
                    error = ?e,
                    "Health check failed, setting status to NOT_SERVING"
                );
                // Set overall server health to not serving (empty string = overall health)
                self.reporter
                    .set_service_status("", tonic_health::ServingStatus::NotServing)
                    .await;
            }
        }
    }

    /// Start background health check task
    ///
    /// Spawns a background task that periodically executes health checks
    /// and updates the service status.
    ///
    /// # Arguments
    ///
    /// * `interval` - How often to run health checks
    ///
    /// # Returns
    ///
    /// A JoinHandle for the background task. You can use this to cancel
    /// the task if needed.
    ///
    /// # Example
    ///
    /// ```rust,no_run
    /// use grpc_health::HealthManager;
    /// use std::sync::Arc;
    /// use std::time::Duration;
    ///
    /// # async fn example() {
    /// let (health_manager, _) = HealthManager::new();
    /// let health_manager = Arc::new(tokio::sync::Mutex::new(health_manager));
    ///
    /// let handle = HealthManager::start_background_check(
    ///     health_manager.clone(),
    ///     Duration::from_secs(10),
    /// );
    ///
    /// // Later, if you want to stop the background checks:
    /// // handle.abort();
    /// # }
    /// ```
    pub fn start_background_check(
        manager: Arc<tokio::sync::Mutex<Self>>,
        interval: Duration,
    ) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            let mut interval_timer = tokio::time::interval(interval);

            loop {
                interval_timer.tick().await;

                let mut mgr = manager.lock().await;
                mgr.check_and_update().await;
            }
        })
    }
}

impl Default for HealthManager {
    fn default() -> Self {
        Self::new().0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::HealthCheckError;
    use async_trait::async_trait;

    struct AlwaysHealthyCheck;

    #[async_trait]
    impl HealthCheck for AlwaysHealthyCheck {
        async fn check(&self) -> Result<()> {
            Ok(())
        }
    }

    struct AlwaysUnhealthyCheck;

    #[async_trait]
    impl HealthCheck for AlwaysUnhealthyCheck {
        async fn check(&self) -> Result<()> {
            Err(HealthCheckError::generic("Always fails"))
        }
    }

    #[tokio::test]
    async fn test_health_manager_creation() {
        let (_manager, _service) = HealthManager::new();
        // If we got here, creation succeeded
    }

    #[tokio::test]
    async fn test_register_and_execute_healthy_check() {
        let (manager, _service) = HealthManager::new();

        manager.register_check(Box::new(AlwaysHealthyCheck)).await;

        let result = manager.execute_checks().await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_register_and_execute_unhealthy_check() {
        let (manager, _service) = HealthManager::new();

        manager.register_check(Box::new(AlwaysUnhealthyCheck)).await;

        let result = manager.execute_checks().await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_multiple_checks_all_healthy() {
        let (manager, _service) = HealthManager::new();

        manager.register_check(Box::new(AlwaysHealthyCheck)).await;
        manager.register_check(Box::new(AlwaysHealthyCheck)).await;

        let result = manager.execute_checks().await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_multiple_checks_one_unhealthy() {
        let (manager, _service) = HealthManager::new();

        manager.register_check(Box::new(AlwaysHealthyCheck)).await;
        manager.register_check(Box::new(AlwaysUnhealthyCheck)).await;

        let result = manager.execute_checks().await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_check_and_update() {
        let (mut manager, _service) = HealthManager::new();

        manager.register_check(Box::new(AlwaysHealthyCheck)).await;
        manager.check_and_update().await;

        // If we got here without panic, the status update succeeded
    }

    #[tokio::test]
    async fn test_background_check_starts() {
        let (manager, _service) = HealthManager::new();
        let manager = Arc::new(tokio::sync::Mutex::new(manager));

        {
            let mgr = manager.lock().await;
            mgr.register_check(Box::new(AlwaysHealthyCheck)).await;
        }

        let handle =
            HealthManager::start_background_check(manager.clone(), Duration::from_millis(100));

        // Let it run for a short time
        tokio::time::sleep(Duration::from_millis(250)).await;

        // Cancel the background task
        handle.abort();
    }
}

//! gRPC health checking for inter-service communication

use std::sync::Arc;
use tokio::sync::RwLock;

/// Health status of a gRPC service
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HealthStatus {
    /// Service is healthy and reachable
    Healthy,
    /// Service is temporarily unavailable
    Unavailable,
    /// Service connection failed
    Unreachable,
}

impl std::fmt::Display for HealthStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HealthStatus::Healthy => write!(f, "healthy"),
            HealthStatus::Unavailable => write!(f, "unavailable"),
            HealthStatus::Unreachable => write!(f, "unreachable"),
        }
    }
}

/// Service health information
#[derive(Debug, Clone)]
pub struct ServiceHealth {
    /// Service name
    pub name: String,
    /// Current health status
    pub status: HealthStatus,
    /// Last check timestamp
    pub last_check: std::time::SystemTime,
}

/// Health checker for gRPC services
pub struct HealthChecker {
    /// Health status for content service
    content_service_health: Arc<RwLock<ServiceHealth>>,
    /// Health status for media service
    media_service_health: Arc<RwLock<ServiceHealth>>,
    /// Health status for auth service
    auth_service_health: Arc<RwLock<ServiceHealth>>,
    /// Health status for feed service
    feed_service_health: Arc<RwLock<ServiceHealth>>,
}

impl HealthChecker {
    /// Create a new health checker
    pub fn new() -> Self {
        Self {
            content_service_health: Arc::new(RwLock::new(ServiceHealth {
                name: "content-service".to_string(),
                status: HealthStatus::Unreachable,
                last_check: std::time::SystemTime::now(),
            })),
            media_service_health: Arc::new(RwLock::new(ServiceHealth {
                name: "media-service".to_string(),
                status: HealthStatus::Unreachable,
                last_check: std::time::SystemTime::now(),
            })),
            auth_service_health: Arc::new(RwLock::new(ServiceHealth {
                name: "auth-service".to_string(),
                status: HealthStatus::Unreachable,
                last_check: std::time::SystemTime::now(),
            })),
            feed_service_health: Arc::new(RwLock::new(ServiceHealth {
                name: "feed-service".to_string(),
                status: HealthStatus::Unreachable,
                last_check: std::time::SystemTime::now(),
            })),
        }
    }

    /// Get content service health status
    pub async fn content_service_health(&self) -> ServiceHealth {
        self.content_service_health.read().await.clone()
    }

    /// Get media service health status
    pub async fn media_service_health(&self) -> ServiceHealth {
        self.media_service_health.read().await.clone()
    }

    /// Update content service health status
    pub async fn set_content_service_health(&self, status: HealthStatus) {
        let mut health = self.content_service_health.write().await;
        health.status = status;
        health.last_check = std::time::SystemTime::now();
        tracing::info!("Content service health updated: {}", status);
    }

    /// Update media service health status
    pub async fn set_media_service_health(&self, status: HealthStatus) {
        let mut health = self.media_service_health.write().await;
        health.status = status;
        health.last_check = std::time::SystemTime::now();
        tracing::info!("Media service health updated: {}", status);
    }

    /// Get auth service health status
    pub async fn auth_service_health(&self) -> ServiceHealth {
        self.auth_service_health.read().await.clone()
    }

    /// Update auth service health status
    pub async fn set_auth_service_health(&self, status: HealthStatus) {
        let mut health = self.auth_service_health.write().await;
        health.status = status;
        health.last_check = std::time::SystemTime::now();
        tracing::info!("Auth service health updated: {}", status);
    }

    /// Get feed service health status
    pub async fn feed_service_health(&self) -> ServiceHealth {
        self.feed_service_health.read().await.clone()
    }

    /// Update feed service health status
    pub async fn set_feed_service_health(&self, status: HealthStatus) {
        let mut health = self.feed_service_health.write().await;
        health.status = status;
        health.last_check = std::time::SystemTime::now();
        tracing::info!("Feed service health updated: {}", status);
    }

    /// Check if all services are healthy
    pub async fn all_healthy(&self) -> bool {
        let content_health = self.content_service_health.read().await;
        let media_health = self.media_service_health.read().await;
        let auth_health = self.auth_service_health.read().await;
        let feed_health = self.feed_service_health.read().await;

        content_health.status == HealthStatus::Healthy
            && media_health.status == HealthStatus::Healthy
            && auth_health.status == HealthStatus::Healthy
            && feed_health.status == HealthStatus::Healthy
    }

    /// Get overall health status string
    pub async fn overall_status(&self) -> String {
        let content_health = self.content_service_health.read().await;
        let media_health = self.media_service_health.read().await;
        let auth_health = self.auth_service_health.read().await;
        let feed_health = self.feed_service_health.read().await;

        format!(
            "{{\"content_service\": \"{}\", \"media_service\": \"{}\", \"auth_service\": \"{}\", \"feed_service\": \"{}\"}}",
            content_health.status, media_health.status, auth_health.status, feed_health.status
        )
    }
}

impl Default for HealthChecker {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_health_checker_creation() {
        let checker = HealthChecker::new();
        let content_health = checker.content_service_health().await;
        assert_eq!(content_health.status, HealthStatus::Unreachable);
        let auth_health = checker.auth_service_health().await;
        assert_eq!(auth_health.status, HealthStatus::Unreachable);
    }

    #[tokio::test]
    async fn test_health_status_update() {
        let checker = HealthChecker::new();
        checker
            .set_content_service_health(HealthStatus::Healthy)
            .await;
        checker.set_auth_service_health(HealthStatus::Healthy).await;
        let health = checker.content_service_health().await;
        assert_eq!(health.status, HealthStatus::Healthy);
    }

    #[tokio::test]
    async fn test_all_healthy() {
        let checker = HealthChecker::new();
        assert!(!checker.all_healthy().await);

        checker
            .set_content_service_health(HealthStatus::Healthy)
            .await;
        checker
            .set_media_service_health(HealthStatus::Healthy)
            .await;
        checker.set_auth_service_health(HealthStatus::Healthy).await;
        checker.set_feed_service_health(HealthStatus::Healthy).await;
        assert!(checker.all_healthy().await);
    }
}

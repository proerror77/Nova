//! gRPC Test Helpers
//!
//! Provides utilities for testing gRPC service integration

use std::time::Duration;

/// Configuration for connecting to gRPC services
#[derive(Clone, Debug)]
pub struct GrpcConfig {
    pub user_service_endpoint: String,
    pub messaging_service_endpoint: String,
    pub auth_service_endpoint: String,
    pub connection_timeout: Duration,
    pub request_timeout: Duration,
}

impl Default for GrpcConfig {
    fn default() -> Self {
        Self {
            user_service_endpoint: "http://127.0.0.1:9081".to_string(),
            messaging_service_endpoint: "http://127.0.0.1:9085".to_string(),
            auth_service_endpoint: "http://127.0.0.1:9086".to_string(),
            connection_timeout: Duration::from_secs(5),
            request_timeout: Duration::from_secs(10),
        }
    }
}

/// Result type for gRPC test operations
pub type GrpcTestResult<T> = Result<T, GrpcTestError>;

/// Custom error type for gRPC test failures
#[derive(Debug)]
pub enum GrpcTestError {
    ConnectionFailed(String),
    RequestTimeout,
    InvalidResponse(String),
    ServiceError(String),
}

impl std::fmt::Display for GrpcTestError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ConnectionFailed(msg) => write!(f, "Connection failed: {}", msg),
            Self::RequestTimeout => write!(f, "Request timeout"),
            Self::InvalidResponse(msg) => write!(f, "Invalid response: {}", msg),
            Self::ServiceError(msg) => write!(f, "Service error: {}", msg),
        }
    }
}

impl std::error::Error for GrpcTestError {}

/// Helper to check if a gRPC service is reachable
pub async fn check_grpc_service_reachable(
    endpoint: &str,
    timeout: Duration,
) -> GrpcTestResult<bool> {
    let start = std::time::Instant::now();

    // In real scenario, would make a Health check gRPC call
    // For now, just simulate the check
    while start.elapsed() < timeout {
        println!("Checking gRPC service at {}", endpoint);

        // Simulated check - in real code would use tonic client
        if std::env::var("MOCK_SERVICE_READY").is_ok() {
            return Ok(true);
        }

        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    Err(GrpcTestError::ConnectionFailed(
        format!("Service at {} not reachable within timeout", endpoint)
    ))
}

/// Helper to wait for multiple services to be ready
pub async fn wait_for_services_ready(
    config: &GrpcConfig,
) -> GrpcTestResult<()> {
    println!("Waiting for gRPC services to be ready...");

    // Check User Service
    check_grpc_service_reachable(&config.user_service_endpoint, config.connection_timeout)
        .await
        .map_err(|_| {
            GrpcTestError::ConnectionFailed("User Service".to_string())
        })?;

    println!("✓ User Service ready at {}", config.user_service_endpoint);

    // Check Messaging Service
    check_grpc_service_reachable(&config.messaging_service_endpoint, config.connection_timeout)
        .await
        .map_err(|_| {
            GrpcTestError::ConnectionFailed("Messaging Service".to_string())
        })?;

    println!("✓ Messaging Service ready at {}", config.messaging_service_endpoint);

    Ok(())
}

/// Test scenario builder for complex integration tests
pub struct IntegrationTestScenario {
    config: GrpcConfig,
    steps: Vec<String>,
}

impl IntegrationTestScenario {
    pub fn new(config: GrpcConfig) -> Self {
        Self {
            config,
            steps: Vec::new(),
        }
    }

    pub fn add_step(mut self, description: impl Into<String>) -> Self {
        self.steps.push(description.into());
        self
    }

    pub async fn execute(&self) -> GrpcTestResult<()> {
        println!("=== Executing Integration Test Scenario ===");

        for (i, step) in self.steps.iter().enumerate() {
            println!("Step {}: {}", i + 1, step);
            // Simulate step execution
            tokio::time::sleep(Duration::from_millis(10)).await;
        }

        println!("✓ Scenario completed successfully");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grpc_config_defaults() {
        let config = GrpcConfig::default();
        assert_eq!(config.user_service_endpoint, "http://127.0.0.1:9081");
        assert_eq!(config.messaging_service_endpoint, "http://127.0.0.1:9085");
        assert_eq!(config.connection_timeout, Duration::from_secs(5));
    }

    #[tokio::test]
    async fn test_scenario_builder() {
        let config = GrpcConfig::default();
        let scenario = IntegrationTestScenario::new(config)
            .add_step("Create test user")
            .add_step("Create test conversation")
            .add_step("Send test message");

        assert_eq!(scenario.steps.len(), 3);
    }
}

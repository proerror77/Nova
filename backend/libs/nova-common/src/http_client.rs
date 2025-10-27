//! HTTP client utilities for inter-service communication
//!
//! Provides convenient methods for services to call each other over HTTP

use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::error::{Result, ServiceError};
use crate::models::{CommandRequest, CommandResponse};

/// Inter-service HTTP client
pub struct ServiceClient {
    client: Client,
    base_url: String,
    service_name: String,
}

impl ServiceClient {
    /// Create a new service client
    pub fn new(service_name: &str, base_url: &str) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.to_string(),
            service_name: service_name.to_string(),
        }
    }

    /// Call another service with a command
    pub async fn call<Req, Res>(
        &self,
        target_service: &str,
        endpoint: &str,
        command: Req,
    ) -> Result<Res>
    where
        Req: Serialize,
        Res: for<'de> Deserialize<'de>,
    {
        let request = CommandRequest::new(&self.service_name, target_service, command);

        let url = format!("{}/api/v1/{}/{}", self.base_url, target_service, endpoint);

        info!(
            "Calling {}: {} (request_id: {})",
            target_service, endpoint, request.request_id
        );

        let response = self
            .client
            .post(&url)
            .json(&request)
            .send()
            .await
            .map_err(|e| ServiceError::ExternalService(format!("Request failed: {}", e)))?;

        if !response.status().is_success() {
            let error_text = response
                .text()
                .await
                .unwrap_or_else(|_| "Unknown error".to_string());
            return Err(ServiceError::ExternalService(error_text));
        }

        response
            .json::<CommandResponse<Res>>()
            .await
            .map_err(|e| ServiceError::ExternalService(format!("Parse failed: {}", e)))
            .and_then(|cmd_response| {
                if cmd_response.success {
                    cmd_response
                        .data
                        .ok_or_else(|| ServiceError::Internal("No data in response".to_string()))
                } else {
                    Err(ServiceError::Internal(
                        cmd_response
                            .error
                            .unwrap_or_else(|| "Unknown error".to_string()),
                    ))
                }
            })
    }

    /// Get health status of another service
    pub async fn health_check(&self, target_service: &str) -> Result<bool> {
        let url = format!("{}/api/v1/{}/health", self.base_url, target_service);

        match self.client.get(&url).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_service_client_creation() {
        let client = ServiceClient::new("user-service", "http://localhost:8080");
        assert_eq!(client.service_name, "user-service");
        assert_eq!(client.base_url, "http://localhost:8080");
    }
}

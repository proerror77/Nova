use hyper::{Body, Client as HyperClient, Method, Request};
use hyper_rustls::HttpsConnectorBuilder;
use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
/// T202: Apple Push Notification Service (APNs) Integration
///
/// This module implements APNs support for iOS/macOS push notifications
/// Part of Phase 7A notifications system
use serde::{Deserialize, Serialize};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// APNs Send Result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct APNsSendResult {
    pub message_id: String,
    pub success: bool,
    pub error: Option<String>,
}

/// APNs Notification Priority
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum APNsPriority {
    /// Immediate delivery
    High,
    /// Background delivery
    Low,
}

impl APNsPriority {
    pub fn as_str(&self) -> &str {
        match self {
            APNsPriority::High => "10",
            APNsPriority::Low => "5",
        }
    }
}

/// Apple Push Notification Service Client
pub struct APNsClient {
    pub certificate_path: String,
    pub key_path: String,
    pub is_production: bool,
    pub team_id: String,
    pub key_id: String,
    pub bundle_id: String,
    http_client: HyperClient<hyper_rustls::HttpsConnector<hyper::client::HttpConnector>>,
}

impl APNsClient {
    /// Create new APNs client
    pub fn new(
        certificate_path: String,
        key_path: String,
        team_id: String,
        key_id: String,
        bundle_id: String,
        is_production: bool,
    ) -> Self {
        let https = HttpsConnectorBuilder::new()
            .with_native_roots()
            .https_or_http()
            .enable_http2()
            .build();

        let client = HyperClient::builder().build::<_, Body>(https);

        Self {
            certificate_path,
            key_path,
            is_production,
            team_id,
            key_id,
            bundle_id,
            http_client: client,
        }
    }

    /// Get APNs API endpoint based on environment
    pub fn get_endpoint(&self) -> String {
        if self.is_production {
            "api.push.apple.com".to_string()
        } else {
            "api.sandbox.push.apple.com".to_string()
        }
    }

    /// Send notification to single device
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        priority: APNsPriority,
    ) -> Result<APNsSendResult, String> {
        // Validate token first
        self.validate_token(device_token)?;

        // Build payload
        let payload = self.build_alert_payload(title, body, None)?;

        // Generate JWT token for authentication
        let auth_token = self.generate_auth_token()?;

        // Build request
        let endpoint = self.get_endpoint();
        let url = format!("https://{}/3/device/{}", endpoint, device_token);

        let request = Request::builder()
            .method(Method::POST)
            .uri(&url)
            .header("authorization", format!("bearer {}", auth_token))
            .header("apns-topic", &self.bundle_id)
            .header("apns-priority", priority.as_str())
            .header("apns-push-type", "alert")
            .header("content-type", "application/json")
            .body(Body::from(payload))
            .map_err(|e| format!("Failed to build request: {}", e))?;

        // Send request
        let response = self
            .http_client
            .request(request)
            .await
            .map_err(|e| format!("APNs request failed: {}", e))?;

        let status = response.status();
        let apns_id = response
            .headers()
            .get("apns-id")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("unknown")
            .to_string();

        if status.is_success() {
            Ok(APNsSendResult {
                message_id: apns_id,
                success: true,
                error: None,
            })
        } else {
            let body_bytes = hyper::body::to_bytes(response.into_body())
                .await
                .unwrap_or_default();
            let error_msg = String::from_utf8_lossy(&body_bytes).to_string();

            Ok(APNsSendResult {
                message_id: apns_id,
                success: false,
                error: Some(format!("APNs error {}: {}", status, error_msg)),
            })
        }
    }

    /// Send notification to multiple devices
    pub async fn send_multicast(
        &self,
        device_tokens: &[String],
        title: &str,
        body: &str,
        priority: APNsPriority,
    ) -> Result<APNsMulticastResult, String> {
        // Send to each device sequentially
        // In production, use tokio::join! or FuturesUnordered for parallel sends
        let mut results = Vec::new();
        let mut success_count = 0;
        let mut failure_count = 0;

        for token in device_tokens {
            match self.send(token, title, body, priority).await {
                Ok(result) => {
                    if result.success {
                        success_count += 1;
                    } else {
                        failure_count += 1;
                    }
                    results.push(result);
                }
                Err(e) => {
                    failure_count += 1;
                    results.push(APNsSendResult {
                        message_id: String::new(),
                        success: false,
                        error: Some(e),
                    });
                }
            }
        }

        Ok(APNsMulticastResult {
            success_count,
            failure_count,
            results,
        })
    }

    /// Update notification with badge count
    pub async fn send_with_badge(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        badge: i32,
    ) -> Result<APNsSendResult, String> {
        self.validate_token(device_token)?;

        let payload = self.build_alert_payload(title, body, Some(badge))?;
        let auth_token = self.generate_auth_token()?;
        let endpoint = self.get_endpoint();
        let url = format!("https://{}/3/device/{}", endpoint, device_token);

        let request = Request::builder()
            .method(Method::POST)
            .uri(&url)
            .header("authorization", format!("bearer {}", auth_token))
            .header("apns-topic", &self.bundle_id)
            .header("apns-priority", "10")
            .header("apns-push-type", "alert")
            .header("content-type", "application/json")
            .body(Body::from(payload))
            .map_err(|e| format!("Failed to build request: {}", e))?;

        let response = self
            .http_client
            .request(request)
            .await
            .map_err(|e| format!("APNs request failed: {}", e))?;

        let status = response.status();
        let apns_id = response
            .headers()
            .get("apns-id")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("unknown")
            .to_string();

        if status.is_success() {
            Ok(APNsSendResult {
                message_id: apns_id,
                success: true,
                error: None,
            })
        } else {
            Ok(APNsSendResult {
                message_id: apns_id,
                success: false,
                error: Some(format!("APNs error {}", status)),
            })
        }
    }

    /// Send silent notification (background update)
    pub async fn send_silent(
        &self,
        device_token: &str,
        data: serde_json::Value,
    ) -> Result<APNsSendResult, String> {
        self.validate_token(device_token)?;

        // Silent notification payload
        let payload = serde_json::json!({
            "aps": {
                "content-available": 1
            },
            "data": data
        });

        let auth_token = self.generate_auth_token()?;
        let endpoint = self.get_endpoint();
        let url = format!("https://{}/3/device/{}", endpoint, device_token);

        let request = Request::builder()
            .method(Method::POST)
            .uri(&url)
            .header("authorization", format!("bearer {}", auth_token))
            .header("apns-topic", &self.bundle_id)
            .header("apns-priority", "5")
            .header("apns-push-type", "background")
            .header("content-type", "application/json")
            .body(Body::from(payload.to_string()))
            .map_err(|e| format!("Failed to build request: {}", e))?;

        let response = self
            .http_client
            .request(request)
            .await
            .map_err(|e| format!("APNs request failed: {}", e))?;

        let status = response.status();
        let apns_id = response
            .headers()
            .get("apns-id")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("unknown")
            .to_string();

        if status.is_success() {
            Ok(APNsSendResult {
                message_id: apns_id,
                success: true,
                error: None,
            })
        } else {
            Ok(APNsSendResult {
                message_id: apns_id,
                success: false,
                error: Some(format!("APNs error {}", status)),
            })
        }
    }

    /// Validate device token format
    pub fn validate_token(&self, device_token: &str) -> Result<bool, String> {
        // APNs tokens should be 64 hex characters
        if device_token.len() != 64 {
            return Err(format!(
                "Invalid APNs token length: expected 64 chars, got {}",
                device_token.len()
            ));
        }

        if !device_token.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err("Invalid APNs token format: token must be hexadecimal".to_string());
        }

        Ok(true)
    }

    /// Build APNs alert payload
    fn build_alert_payload(
        &self,
        title: &str,
        body: &str,
        badge: Option<i32>,
    ) -> Result<String, String> {
        let mut payload = serde_json::json!({
            "aps": {
                "alert": {
                    "title": title,
                    "body": body
                },
                "sound": "default"
            }
        });

        if let Some(badge_count) = badge {
            payload["aps"]["badge"] = serde_json::json!(badge_count);
        }

        serde_json::to_string(&payload).map_err(|e| format!("Failed to serialize payload: {}", e))
    }

    /// Generate JWT authentication token for APNs
    fn generate_auth_token(&self) -> Result<String, String> {
        use std::fs;

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        #[derive(Debug, Serialize, Deserialize)]
        struct Claims {
            iss: String,
            iat: u64,
        }

        let claims = Claims {
            iss: self.team_id.clone(),
            iat: now,
        };

        // Read private key from file
        let key_content = fs::read_to_string(&self.key_path)
            .map_err(|e| format!("Failed to read key file: {}", e))?;

        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());

        let encoding_key = EncodingKey::from_ec_pem(key_content.as_bytes())
            .map_err(|e| format!("Failed to parse EC key: {}", e))?;

        encode(&header, &claims, &encoding_key).map_err(|e| format!("Failed to encode JWT: {}", e))
    }
}

/// APNs multicast result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct APNsMulticastResult {
    pub success_count: usize,
    pub failure_count: usize,
    pub results: Vec<APNsSendResult>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apns_client_creation() {
        let client = APNsClient::new(
            "/path/to/cert.p8".to_string(),
            "/path/to/key.p8".to_string(),
            "TEAM123".to_string(),
            "KEY123".to_string(),
            "com.example.app".to_string(),
            true,
        );

        assert_eq!(client.team_id, "TEAM123");
        assert!(client.is_production);
        assert_eq!(client.bundle_id, "com.example.app");
    }

    #[test]
    fn test_apns_endpoint_production() {
        let client = APNsClient::new(
            "/path/to/cert.p8".to_string(),
            "/path/to/key.p8".to_string(),
            "TEAM123".to_string(),
            "KEY123".to_string(),
            "com.example.app".to_string(),
            true,
        );

        assert_eq!(client.get_endpoint(), "api.push.apple.com");
    }

    #[test]
    fn test_apns_endpoint_sandbox() {
        let client = APNsClient::new(
            "/path/to/cert.p8".to_string(),
            "/path/to/key.p8".to_string(),
            "TEAM123".to_string(),
            "KEY123".to_string(),
            "com.example.app".to_string(),
            false,
        );

        assert_eq!(client.get_endpoint(), "api.sandbox.push.apple.com");
    }

    #[test]
    fn test_valid_token_format() {
        let client = APNsClient::new(
            "/path/to/cert.p8".to_string(),
            "/path/to/key.p8".to_string(),
            "TEAM123".to_string(),
            "KEY123".to_string(),
            "com.example.app".to_string(),
            true,
        );

        let valid_token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        assert!(client.validate_token(valid_token).is_ok());
    }

    #[test]
    fn test_invalid_token_too_short() {
        let client = APNsClient::new(
            "/path/to/cert.p8".to_string(),
            "/path/to/key.p8".to_string(),
            "TEAM123".to_string(),
            "KEY123".to_string(),
            "com.example.app".to_string(),
            true,
        );

        let invalid_token = "0123456789abcdef";
        assert!(client.validate_token(invalid_token).is_err());
    }

    #[test]
    fn test_invalid_token_non_hex() {
        let client = APNsClient::new(
            "/path/to/cert.p8".to_string(),
            "/path/to/key.p8".to_string(),
            "TEAM123".to_string(),
            "KEY123".to_string(),
            "com.example.app".to_string(),
            true,
        );

        let invalid_token = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";
        assert!(client.validate_token(invalid_token).is_err());
    }

    #[test]
    fn test_apns_priority_high() {
        assert_eq!(APNsPriority::High.as_str(), "10");
    }

    #[test]
    fn test_apns_priority_low() {
        assert_eq!(APNsPriority::Low.as_str(), "5");
    }

    // Note: async tests removed as they require actual APNs credentials
    // Integration tests will cover async behavior with mocked APIs

    #[test]
    fn test_multicast_result() {
        let result = APNsMulticastResult {
            success_count: 50,
            failure_count: 5,
            results: vec![],
        };

        assert_eq!(result.success_count, 50);
        assert_eq!(result.failure_count, 5);
    }
}

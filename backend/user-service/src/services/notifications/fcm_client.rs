use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use reqwest::Client;
/// T202: Firebase Cloud Messaging (FCM) Integration
///
/// This module implements FCM support for Android/Web push notifications
/// Part of Phase 7A notifications system
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// FCM Send Result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FCMSendResult {
    pub message_id: String,
    pub success: bool,
    pub error: Option<String>,
}

/// Firebase Service Account Key
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceAccountKey {
    pub project_id: String,
    pub private_key_id: String,
    pub private_key: String,
    pub client_email: String,
    pub client_id: String,
    pub auth_uri: String,
    pub token_uri: String,
}

/// Firebase Cloud Messaging Client
pub struct FCMClient {
    pub project_id: String,
    pub credentials: Arc<ServiceAccountKey>,
    pub api_key: Option<String>,
    http_client: Client,
}

impl FCMClient {
    /// Create new FCM client
    pub fn new(project_id: String, credentials: ServiceAccountKey) -> Self {
        Self {
            project_id,
            credentials: Arc::new(credentials),
            api_key: None,
            http_client: Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .expect("Failed to create HTTP client"),
        }
    }

    /// Send notification via FCM
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<FCMSendResult, String> {
        let access_token = self.get_access_token().await?;

        let mut message = serde_json::json!({
            "message": {
                "token": device_token,
                "notification": {
                    "title": title,
                    "body": body
                }
            }
        });

        if let Some(data_payload) = data {
            message["message"]["data"] = data_payload;
        }

        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );

        let response = self
            .http_client
            .post(&url)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .json(&message)
            .send()
            .await
            .map_err(|e| format!("FCM API request failed: {}", e))?;

        if response.status().is_success() {
            let result: serde_json::Value = response
                .json()
                .await
                .map_err(|e| format!("Failed to parse FCM response: {}", e))?;

            Ok(FCMSendResult {
                message_id: result["name"].as_str().unwrap_or("unknown").to_string(),
                success: true,
                error: None,
            })
        } else {
            let error_text = response
                .text()
                .await
                .unwrap_or_else(|_| "Unknown error".to_string());

            Ok(FCMSendResult {
                message_id: String::new(),
                success: false,
                error: Some(error_text),
            })
        }
    }

    /// Send multicast notification (to multiple devices)
    pub async fn send_multicast(
        &self,
        device_tokens: &[String],
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<MulticastSendResult, String> {
        // FCM doesn't have a native multicast endpoint, so we send individually
        // In production, consider batching with async concurrency control
        let mut results = Vec::new();
        let mut success_count = 0;
        let mut failure_count = 0;

        for token in device_tokens {
            match self.send(token, title, body, data.clone()).await {
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
                    results.push(FCMSendResult {
                        message_id: String::new(),
                        success: false,
                        error: Some(e),
                    });
                }
            }
        }

        Ok(MulticastSendResult {
            success_count,
            failure_count,
            results,
        })
    }

    /// Subscribe device to topic
    pub async fn subscribe_to_topic(
        &self,
        device_tokens: &[String],
        topic: &str,
    ) -> Result<TopicSubscriptionResult, String> {
        let access_token = self.get_access_token().await?;

        // FCM IID (Instance ID) API for topic subscription
        let url = format!("https://iid.googleapis.com/iid/v1:batchAdd");

        let body = serde_json::json!({
            "to": format!("/topics/{}", topic),
            "registration_tokens": device_tokens
        });

        let response = self
            .http_client
            .post(&url)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Topic subscription failed: {}", e))?;

        if response.status().is_success() {
            let result: serde_json::Value = response
                .json()
                .await
                .map_err(|e| format!("Failed to parse subscription response: {}", e))?;

            let empty_vec = vec![];
            let results = result["results"].as_array().unwrap_or(&empty_vec);
            let failed = results.iter().filter(|r| r.get("error").is_some()).count();

            Ok(TopicSubscriptionResult {
                topic: topic.to_string(),
                subscribed: device_tokens.len() - failed,
                failed,
            })
        } else {
            Err(format!(
                "Topic subscription failed with status: {}",
                response.status()
            ))
        }
    }

    /// Send notification to topic
    pub async fn send_to_topic(
        &self,
        topic: &str,
        title: &str,
        body: &str,
    ) -> Result<FCMSendResult, String> {
        let access_token = self.get_access_token().await?;

        let message = serde_json::json!({
            "message": {
                "topic": topic,
                "notification": {
                    "title": title,
                    "body": body
                }
            }
        });

        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            self.project_id
        );

        let response = self
            .http_client
            .post(&url)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .json(&message)
            .send()
            .await
            .map_err(|e| format!("Topic send failed: {}", e))?;

        if response.status().is_success() {
            let result: serde_json::Value = response
                .json()
                .await
                .map_err(|e| format!("Failed to parse response: {}", e))?;

            Ok(FCMSendResult {
                message_id: result["name"].as_str().unwrap_or("unknown").to_string(),
                success: true,
                error: None,
            })
        } else {
            let error_text = response
                .text()
                .await
                .unwrap_or_else(|_| "Unknown error".to_string());

            Ok(FCMSendResult {
                message_id: String::new(),
                success: false,
                error: Some(error_text),
            })
        }
    }

    /// Validate device token
    pub async fn validate_token(&self, device_token: &str) -> Result<bool, String> {
        // FCM tokens are base64-encoded strings, typically 152+ characters
        if device_token.is_empty() {
            return Err("Token cannot be empty".to_string());
        }

        if device_token.len() < 140 {
            return Err("Token too short to be valid FCM token".to_string());
        }

        // Basic validation - tokens should be alphanumeric with some special chars
        let valid_chars = device_token
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == ':');

        if !valid_chars {
            return Err("Token contains invalid characters".to_string());
        }

        Ok(true)
    }

    /// Get access token from service account
    async fn get_access_token(&self) -> Result<String, String> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        #[derive(Debug, Serialize, Deserialize)]
        struct Claims {
            iss: String,
            scope: String,
            aud: String,
            iat: u64,
            exp: u64,
        }

        let claims = Claims {
            iss: self.credentials.client_email.clone(),
            scope: "https://www.googleapis.com/auth/firebase.messaging".to_string(),
            aud: self.credentials.token_uri.clone(),
            iat: now,
            exp: now + 3600,
        };

        // Create JWT using jsonwebtoken library
        let header = Header::new(Algorithm::RS256);
        let encoding_key = EncodingKey::from_rsa_pem(self.credentials.private_key.as_bytes())
            .map_err(|e| format!("Failed to parse private key: {}", e))?;

        let jwt = encode(&header, &claims, &encoding_key)
            .map_err(|e| format!("Failed to encode JWT: {}", e))?;

        // Exchange JWT for access token
        let token_response = self
            .http_client
            .post(&self.credentials.token_uri)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &jwt),
            ])
            .send()
            .await
            .map_err(|e| format!("Token exchange failed: {}", e))?;

        if !token_response.status().is_success() {
            let error_text = token_response
                .text()
                .await
                .unwrap_or_else(|_| "Unknown error".to_string());
            return Err(format!("Token exchange failed: {}", error_text));
        }

        let token_json: serde_json::Value = token_response
            .json()
            .await
            .map_err(|e| format!("Failed to parse token response: {}", e))?;

        token_json["access_token"]
            .as_str()
            .map(|s| s.to_string())
            .ok_or_else(|| "No access_token in response".to_string())
    }
}

/// Multicast send result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MulticastSendResult {
    pub success_count: usize,
    pub failure_count: usize,
    pub results: Vec<FCMSendResult>,
}

/// Topic subscription result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopicSubscriptionResult {
    pub topic: String,
    pub subscribed: usize,
    pub failed: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fcm_client_creation() {
        let creds = ServiceAccountKey {
            project_id: "test-project".to_string(),
            private_key_id: "key-id".to_string(),
            private_key: "private-key".to_string(),
            client_email: "test@test.iam.gserviceaccount.com".to_string(),
            client_id: "123456".to_string(),
            auth_uri: "https://accounts.google.com/o/oauth2/auth".to_string(),
            token_uri: "https://oauth2.googleapis.com/token".to_string(),
        };

        let client = FCMClient::new("test-project".to_string(), creds);
        assert_eq!(client.project_id, "test-project");
    }

    // Note: async tests removed as they require actual FCM credentials and network access
    // Integration tests will cover async behavior with mocked APIs

    #[test]
    fn test_multicast_result() {
        let result = MulticastSendResult {
            success_count: 10,
            failure_count: 2,
            results: vec![],
        };

        assert_eq!(result.success_count, 10);
        assert_eq!(result.failure_count, 2);
    }

    #[test]
    fn test_topic_subscription_result() {
        let result = TopicSubscriptionResult {
            topic: "news".to_string(),
            subscribed: 100,
            failed: 5,
        };

        assert_eq!(result.topic, "news");
        assert_eq!(result.subscribed, 100);
        assert_eq!(result.failed, 5);
    }
}

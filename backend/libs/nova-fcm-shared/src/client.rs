use chrono::{Duration, Utc};
use jsonwebtoken::{encode, EncodingKey, Header};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

use crate::models::*;

/// Firebase Cloud Messaging Client
///
/// Handles Firebase Cloud Messaging (FCM) for Android and Web push notifications.
/// Manages OAuth2 token generation, caching, and message delivery.
pub struct FCMClient {
    pub project_id: String,
    pub credentials: Arc<ServiceAccountKey>,
    pub api_key: Option<String>,
    token_cache: Arc<Mutex<Option<TokenCache>>>,
    http_client: reqwest::Client,
}

impl FCMClient {
    /// Create new FCM client
    ///
    /// # Arguments
    /// * `project_id` - Firebase project ID
    /// * `credentials` - Service account key with OAuth2 credentials
    pub fn new(project_id: String, credentials: ServiceAccountKey) -> Self {
        Self {
            project_id,
            credentials: Arc::new(credentials),
            api_key: None,
            token_cache: Arc::new(Mutex::new(None)),
            http_client: reqwest::Client::new(),
        }
    }

    /// Send notification via FCM to a single device
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<FCMSendResult, String> {
        let access_token = self.get_access_token().await?;

        let message = FcmMessage {
            message: FcmMessageContent {
                token: Some(device_token.to_string()),
                topic: None,
                notification: FcmNotification {
                    title: title.to_string(),
                    body: body.to_string(),
                },
                data,
                android: None,
                webpush: None,
            },
        };

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
            .map_err(|e| format!("FCM send request failed: {}", e))?;

        match response.status() {
            reqwest::StatusCode::OK => {
                let fcm_response: FcmApiResponse = response
                    .json()
                    .await
                    .map_err(|e| format!("Failed to parse FCM response: {}", e))?;

                Ok(FCMSendResult {
                    message_id: fcm_response
                        .name
                        .unwrap_or_else(|| Uuid::new_v4().to_string()),
                    success: true,
                    error: None,
                })
            }
            status => {
                let error_text = response
                    .text()
                    .await
                    .unwrap_or_else(|_| "Unknown error".to_string());

                Err(format!("FCM API error: {} - {}", status, error_text))
            }
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
        let mut results = Vec::new();
        let mut success_count = 0;
        let mut failure_count = 0;

        for device_token in device_tokens {
            match self.send(device_token, title, body, data.clone()).await {
                Ok(result) => {
                    results.push(result);
                    success_count += 1;
                }
                Err(e) => {
                    results.push(FCMSendResult {
                        message_id: Uuid::new_v4().to_string(),
                        success: false,
                        error: Some(e),
                    });
                    failure_count += 1;
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
        let _access_token = self.get_access_token().await?;

        let url = "https://iid.googleapis.com/iid/v1:batchAdd";

        let mut subscribed = 0;
        let mut failed = 0;

        for device_token in device_tokens {
            let body = serde_json::json!({
                "to": format!("/topics/{}", topic),
                "registration_tokens": [device_token]
            });

            match self
                .http_client
                .post(url)
                .header(
                    "Authorization",
                    format!("key={}", self.credentials.client_id),
                )
                .json(&body)
                .send()
                .await
            {
                Ok(response) if response.status().is_success() => {
                    subscribed += 1;
                }
                _ => {
                    failed += 1;
                }
            }
        }

        Ok(TopicSubscriptionResult {
            topic: topic.to_string(),
            subscribed,
            failed,
        })
    }

    /// Send notification to topic
    pub async fn send_to_topic(
        &self,
        topic: &str,
        title: &str,
        body: &str,
    ) -> Result<FCMSendResult, String> {
        let access_token = self.get_access_token().await?;

        let message = FcmMessage {
            message: FcmMessageContent {
                token: None,
                topic: Some(topic.to_string()),
                notification: FcmNotification {
                    title: title.to_string(),
                    body: body.to_string(),
                },
                data: None,
                android: None,
                webpush: None,
            },
        };

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
            .map_err(|e| format!("FCM topic send request failed: {}", e))?;

        match response.status() {
            reqwest::StatusCode::OK => {
                let fcm_response: FcmApiResponse = response
                    .json()
                    .await
                    .map_err(|e| format!("Failed to parse FCM response: {}", e))?;

                Ok(FCMSendResult {
                    message_id: fcm_response
                        .name
                        .unwrap_or_else(|| Uuid::new_v4().to_string()),
                    success: true,
                    error: None,
                })
            }
            status => {
                let error_text = response
                    .text()
                    .await
                    .unwrap_or_else(|_| "Unknown error".to_string());

                Err(format!("FCM API error: {} - {}", status, error_text))
            }
        }
    }

    /// Validate device token format
    pub async fn validate_token(&self, device_token: &str) -> Result<bool, String> {
        // Basic validation: token should be non-empty and reasonably long
        if device_token.is_empty() || device_token.len() < 10 {
            return Ok(false);
        }

        // FCM tokens are typically 100-200 characters
        if device_token.len() > 1000 {
            return Ok(false);
        }

        Ok(true)
    }

    /// Get access token from service account (with caching)
    pub async fn get_access_token(&self) -> Result<String, String> {
        // Check if we have a cached token that's still valid
        {
            let cache = self.token_cache.lock().expect("Token cache lock poisoned");
            if let Some(cached) = cache.as_ref() {
                let now = Utc::now().timestamp();
                if cached.expires_at > now + 60 {
                    // Token is still valid for at least 60 more seconds
                    return Ok(cached.access_token.clone());
                }
            }
        }

        // Generate new JWT and exchange for access token
        let now = Utc::now();
        let exp = (now + Duration::hours(1)).timestamp();
        let iat = now.timestamp();

        let claims = JwtClaims {
            iss: self.credentials.client_email.clone(),
            sub: self.credentials.client_email.clone(),
            scope: "https://www.googleapis.com/auth/cloud-platform".to_string(),
            aud: self.credentials.token_uri.clone(),
            exp,
            iat,
        };

        // Sign JWT with private key
        let encoding_key = EncodingKey::from_rsa_pem(self.credentials.private_key.as_bytes())
            .map_err(|e| format!("Failed to parse private key: {}", e))?;

        let token = encode(&Header::default(), &claims, &encoding_key)
            .map_err(|e| format!("Failed to encode JWT: {}", e))?;

        // Exchange JWT for access token
        let params = [
            ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            ("assertion", &token),
        ];

        let response = self
            .http_client
            .post(&self.credentials.token_uri)
            .form(&params)
            .send()
            .await
            .map_err(|e| format!("Failed to get access token: {}", e))?;

        if !response.status().is_success() {
            return Err(format!(
                "Token request failed with status: {}",
                response.status()
            ));
        }

        let token_response: GoogleTokenResponse = response
            .json()
            .await
            .map_err(|e| format!("Failed to parse token response: {}", e))?;

        // Cache the token
        let expires_at = Utc::now().timestamp() + token_response.expires_in;
        {
            let mut cache = self.token_cache.lock().expect("Token cache lock poisoned");
            *cache = Some(TokenCache {
                access_token: token_response.access_token.clone(),
                expires_at,
            });
        }

        Ok(token_response.access_token)
    }
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

    #[test]
    fn test_validate_token_valid() {
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

        // Test valid token
        let result = futures::executor::block_on(
            client.validate_token("valid_token_with_reasonable_length_12345678"),
        );
        assert!(result.is_ok());
        assert!(result.unwrap());
    }

    #[test]
    fn test_validate_token_invalid() {
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

        // Test empty token
        let result = futures::executor::block_on(client.validate_token(""));
        assert!(result.is_ok());
        assert!(!result.unwrap());

        // Test too short token
        let result = futures::executor::block_on(client.validate_token("short"));
        assert!(result.is_ok());
        assert!(!result.unwrap());
    }

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

    #[test]
    fn test_fcm_send_result_serialization() {
        let result = FCMSendResult {
            message_id: "test-msg-123".to_string(),
            success: true,
            error: None,
        };

        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("test-msg-123"));
        assert!(json.contains("true"));
    }
}

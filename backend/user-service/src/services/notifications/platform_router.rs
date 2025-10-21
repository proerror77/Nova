/// Platform Router for Push Notifications
///
/// Automatically routes notifications to the correct platform (FCM or APNs)
/// based on device token format and metadata

use super::{FCMClient, APNsClient, FCMSendResult, APNsSendResult, APNsPriority};
use serde::{Deserialize, Serialize};

/// Platform type for routing
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Platform {
    iOS,
    Android,
    Web,
}

/// Device information for routing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub token: String,
    pub platform: Platform,
}

/// Unified send result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnifiedSendResult {
    pub platform: Platform,
    pub message_id: String,
    pub success: bool,
    pub error: Option<String>,
}

/// Platform router
pub struct PlatformRouter {
    fcm_client: FCMClient,
    apns_client: APNsClient,
}

impl PlatformRouter {
    /// Create new platform router
    pub fn new(fcm_client: FCMClient, apns_client: APNsClient) -> Self {
        Self {
            fcm_client,
            apns_client,
        }
    }

    /// Detect platform from token format
    ///
    /// APNs tokens: 64 hex characters
    /// FCM tokens: 152+ base64-encoded characters with special chars
    pub fn detect_platform(&self, token: &str) -> Platform {
        // APNs tokens are exactly 64 hex characters
        if token.len() == 64 && token.chars().all(|c| c.is_ascii_hexdigit()) {
            return Platform::iOS;
        }

        // FCM tokens are longer and contain special characters
        if token.len() >= 140 && (token.contains(':') || token.contains('-') || token.contains('_')) {
            return Platform::Android;
        }

        // Default to Android/FCM
        Platform::Android
    }

    /// Send notification to appropriate platform
    pub async fn send(
        &self,
        device: &DeviceInfo,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<UnifiedSendResult, String> {
        match device.platform {
            Platform::iOS => {
                let result = self
                    .apns_client
                    .send(&device.token, title, body, APNsPriority::High)
                    .await?;

                Ok(UnifiedSendResult {
                    platform: Platform::iOS,
                    message_id: result.message_id,
                    success: result.success,
                    error: result.error,
                })
            }
            Platform::Android | Platform::Web => {
                let result = self
                    .fcm_client
                    .send(&device.token, title, body, data)
                    .await?;

                Ok(UnifiedSendResult {
                    platform: device.platform,
                    message_id: result.message_id,
                    success: result.success,
                    error: result.error,
                })
            }
        }
    }

    /// Send notification with auto-detection
    pub async fn send_auto(
        &self,
        token: &str,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<UnifiedSendResult, String> {
        let platform = self.detect_platform(token);
        let device = DeviceInfo {
            token: token.to_string(),
            platform,
        };

        self.send(&device, title, body, data).await
    }

    /// Send to multiple devices (mixed platforms)
    pub async fn send_multicast(
        &self,
        devices: &[DeviceInfo],
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<Vec<UnifiedSendResult>, String> {
        let mut results = Vec::new();

        for device in devices {
            match self.send(device, title, body, data.clone()).await {
                Ok(result) => results.push(result),
                Err(e) => {
                    results.push(UnifiedSendResult {
                        platform: device.platform,
                        message_id: String::new(),
                        success: false,
                        error: Some(e),
                    });
                }
            }
        }

        Ok(results)
    }

    /// Get FCM client reference
    pub fn fcm(&self) -> &FCMClient {
        &self.fcm_client
    }

    /// Get APNs client reference
    pub fn apns(&self) -> &APNsClient {
        &self.apns_client
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::services::notifications::{ServiceAccountKey};

    fn create_test_fcm_client() -> FCMClient {
        let creds = ServiceAccountKey {
            project_id: "test-project".to_string(),
            private_key_id: "key-id".to_string(),
            private_key: "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----".to_string(),
            client_email: "test@test.iam.gserviceaccount.com".to_string(),
            client_id: "123456".to_string(),
            auth_uri: "https://accounts.google.com/o/oauth2/auth".to_string(),
            token_uri: "https://oauth2.googleapis.com/token".to_string(),
        };

        FCMClient::new("test-project".to_string(), creds)
    }

    fn create_test_apns_client() -> APNsClient {
        APNsClient::new(
            "/path/to/cert.p8".to_string(),
            "/path/to/key.p8".to_string(),
            "TEAM123".to_string(),
            "KEY123".to_string(),
            "com.example.app".to_string(),
            false,
        )
    }

    #[test]
    fn test_detect_ios_platform() {
        let fcm = create_test_fcm_client();
        let apns = create_test_apns_client();
        let router = PlatformRouter::new(fcm, apns);

        let ios_token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        assert_eq!(router.detect_platform(ios_token), Platform::iOS);
    }

    #[test]
    fn test_detect_android_platform() {
        let fcm = create_test_fcm_client();
        let apns = create_test_apns_client();
        let router = PlatformRouter::new(fcm, apns);

        let android_token = "eJwNyEEKgCAUBdC7_K0t6B4iWrRo1SJE_CRi-mOmSHh3gbe6wUvtCXXHN5rMNr0hxA4TqLWN-9cA0a9eZg:APA91bHun4MxP5egoKMwt00IHzKqfxBL";
        assert_eq!(router.detect_platform(android_token), Platform::Android);
    }

    #[test]
    fn test_platform_enum() {
        assert_eq!(Platform::iOS, Platform::iOS);
        assert_ne!(Platform::iOS, Platform::Android);
    }

    #[test]
    fn test_device_info_creation() {
        let device = DeviceInfo {
            token: "test-token".to_string(),
            platform: Platform::iOS,
        };

        assert_eq!(device.platform, Platform::iOS);
        assert_eq!(device.token, "test-token");
    }
}

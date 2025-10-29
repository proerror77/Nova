use serde::{Deserialize, Serialize};

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

/// OAuth2 Token Cache
#[derive(Debug, Clone)]
pub struct TokenCache {
    pub access_token: String,
    pub expires_at: i64,
}

/// JWT Claims for Google OAuth2
#[derive(Debug, Serialize)]
pub struct JwtClaims {
    pub iss: String,
    pub sub: String,
    pub scope: String,
    pub aud: String,
    pub exp: i64,
    pub iat: i64,
}

/// Google OAuth2 Token Response
#[derive(Debug, Deserialize)]
pub struct GoogleTokenResponse {
    pub access_token: String,
    pub expires_in: i64,
    pub token_type: String,
}

/// FCM Message Request
#[derive(Debug, Serialize)]
pub struct FcmMessage {
    pub message: FcmMessageContent,
}

/// FCM Message Content
#[derive(Debug, Serialize)]
pub struct FcmMessageContent {
    pub token: Option<String>,
    pub topic: Option<String>,
    pub notification: FcmNotification,
    pub data: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub android: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub webpush: Option<serde_json::Value>,
}

/// FCM Notification Payload
#[derive(Debug, Serialize)]
pub struct FcmNotification {
    pub title: String,
    pub body: String,
}

/// FCM API Response
#[derive(Debug, Deserialize)]
pub struct FcmApiResponse {
    pub name: Option<String>,
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

/// Multicast response entry
#[derive(Debug, Deserialize)]
pub struct FcmMulticastEntry {
    pub success: bool,
    pub error: Option<FcmErrorResponse>,
}

#[derive(Debug, Deserialize)]
pub struct FcmErrorResponse {
    pub code: Option<String>,
    pub message: Option<String>,
}

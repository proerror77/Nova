use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::error::AppError;

use super::fcm::FcmPush;
use super::push::{ApnsPush, PushProvider};

/// Maximum retry attempts for failed notifications
const MAX_RETRIES: u32 = 3;

/// Notification job representing a queued push notification
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct NotificationJob {
    pub id: Uuid,
    pub device_token: String,
    pub platform: String, // 'ios' or 'android'
    pub title: String,
    pub body: String,
    pub badge: Option<i32>,
    pub status: String, // 'pending', 'sent', 'failed'
    pub retry_count: i32,
    pub max_retries: i32,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
}

impl NotificationJob {
    /// Creates a new notification job
    pub fn new(device_token: String, platform: String, title: String, body: String, badge: Option<i32>) -> Self {
        Self {
            id: Uuid::new_v4(),
            device_token,
            platform,
            title,
            body,
            badge,
            status: "pending".to_string(),
            retry_count: 0,
            max_retries: MAX_RETRIES as i32,
            created_at: Utc::now(),
            sent_at: None,
            last_error: None,
        }
    }
}

/// Trait for notification queue operations
#[async_trait::async_trait]
pub trait NotificationQueue: Send + Sync {
    /// Queues a new notification for delivery
    async fn queue_notification(&self, job: NotificationJob) -> Result<(), AppError>;

    /// Processes pending notifications and returns count of processed jobs
    async fn process_pending(&self) -> Result<usize, AppError>;

    /// Gets notification status by job ID
    async fn get_status(&self, job_id: Uuid) -> Result<Option<NotificationJob>, AppError>;

    /// Cancels a pending notification
    async fn cancel_notification(&self, job_id: Uuid) -> Result<(), AppError>;
}

/// PostgreSQL-based notification queue implementation
pub struct PostgresNotificationQueue {
    db: Arc<PgPool>,
    apns_provider: Option<Arc<ApnsPush>>,
    fcm_provider: Option<Arc<FcmPush>>,
}

impl PostgresNotificationQueue {
    /// Creates a new PostgreSQL notification queue
    pub fn new(db: Arc<PgPool>, apns_provider: Option<Arc<ApnsPush>>, fcm_provider: Option<Arc<FcmPush>>) -> Self {
        Self {
            db,
            apns_provider,
            fcm_provider,
        }
    }

    /// Sends notification using appropriate provider
    async fn send_with_provider(&self, job: &NotificationJob) -> Result<(), AppError> {
        match job.platform.as_str() {
            "ios" => {
                let provider = self
                    .apns_provider
                    .as_ref()
                    .ok_or_else(|| AppError::Config("APNs provider not configured".to_string()))?;

                provider
                    .send(
                        job.device_token.clone(),
                        job.title.clone(),
                        job.body.clone(),
                        job.badge.map(|b| b as u32),
                    )
                    .await
            }
            "android" => {
                let provider = self
                    .fcm_provider
                    .as_ref()
                    .ok_or_else(|| AppError::Config("FCM provider not configured".to_string()))?;

                provider
                    .send(
                        job.device_token.clone(),
                        job.title.clone(),
                        job.body.clone(),
                        job.badge.map(|b| b as u32),
                    )
                    .await
            }
            platform => Err(AppError::BadRequest(format!("Unsupported platform: {}", platform))),
        }
    }

    /// Marks job as sent
    async fn mark_sent(&self, job_id: Uuid) -> Result<(), AppError> {
        sqlx::query(
            r#"
            UPDATE notification_jobs
            SET status = 'sent', sent_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(job_id)
        .execute(&*self.db)
        .await?;

        Ok(())
    }

    /// Marks job as failed and increments retry count
    async fn mark_failed(&self, job_id: Uuid, error_msg: String) -> Result<(), AppError> {
        sqlx::query(
            r#"
            UPDATE notification_jobs
            SET retry_count = retry_count + 1,
                last_error = $2,
                status = CASE
                    WHEN retry_count + 1 >= max_retries THEN 'failed'
                    ELSE 'pending'
                END
            WHERE id = $1
            "#,
        )
        .bind(job_id)
        .bind(error_msg)
        .execute(&*self.db)
        .await?;

        Ok(())
    }
}

#[async_trait::async_trait]
impl NotificationQueue for PostgresNotificationQueue {
    async fn queue_notification(&self, job: NotificationJob) -> Result<(), AppError> {
        sqlx::query(
            r#"
            INSERT INTO notification_jobs
            (id, device_token, platform, title, body, badge, status, retry_count, max_retries, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            "#,
        )
        .bind(job.id)
        .bind(&job.device_token)
        .bind(&job.platform)
        .bind(&job.title)
        .bind(&job.body)
        .bind(job.badge)
        .bind(&job.status)
        .bind(job.retry_count)
        .bind(job.max_retries)
        .bind(job.created_at)
        .execute(&*self.db)
        .await?;

        info!("Queued notification job {} for {} device", job.id, job.platform);
        Ok(())
    }

    async fn process_pending(&self) -> Result<usize, AppError> {
        // Fetch pending jobs that haven't exceeded retry limit
        let jobs = sqlx::query_as::<_, NotificationJob>(
            r#"
            SELECT id, device_token, platform, title, body, badge, status,
                   retry_count, max_retries, created_at, sent_at, last_error
            FROM notification_jobs
            WHERE status = 'pending'
              AND retry_count < max_retries
            ORDER BY created_at ASC
            LIMIT 100
            "#
        )
        .fetch_all(&*self.db)
        .await?;

        let total = jobs.len();
        let mut processed = 0;

        for job in jobs {
            match self.send_with_provider(&job).await {
                Ok(_) => {
                    if let Err(e) = self.mark_sent(job.id).await {
                        error!("Failed to mark job {} as sent: {}", job.id, e);
                    } else {
                        info!("Successfully sent notification job {}", job.id);
                        processed += 1;
                    }
                }
                Err(e) => {
                    let error_msg = e.to_string();
                    warn!(
                        "Failed to send notification job {} (attempt {}/{}): {}",
                        job.id,
                        job.retry_count + 1,
                        job.max_retries,
                        error_msg
                    );

                    if let Err(mark_err) = self.mark_failed(job.id, error_msg).await {
                        error!("Failed to mark job {} as failed: {}", job.id, mark_err);
                    }
                }
            }
        }

        if total > 0 {
            info!("Processed {}/{} pending notification jobs", processed, total);
        }

        Ok(processed)
    }

    async fn get_status(&self, job_id: Uuid) -> Result<Option<NotificationJob>, AppError> {
        let job = sqlx::query_as::<_, NotificationJob>(
            r#"
            SELECT id, device_token, platform, title, body, badge, status,
                   retry_count, max_retries, created_at, sent_at, last_error
            FROM notification_jobs
            WHERE id = $1
            "#,
        )
        .bind(job_id)
        .fetch_optional(&*self.db)
        .await?;

        Ok(job)
    }

    async fn cancel_notification(&self, job_id: Uuid) -> Result<(), AppError> {
        let result = sqlx::query(
            r#"
            UPDATE notification_jobs
            SET status = 'failed', last_error = 'Cancelled by user'
            WHERE id = $1 AND status = 'pending'
            "#,
        )
        .bind(job_id)
        .execute(&*self.db)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound);
        }

        info!("Cancelled notification job {}", job_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_notification_job() {
        let job = NotificationJob::new(
            "test_token".to_string(),
            "ios".to_string(),
            "Test Title".to_string(),
            "Test Body".to_string(),
            Some(1),
        );

        assert_eq!(job.device_token, "test_token");
        assert_eq!(job.platform, "ios");
        assert_eq!(job.status, "pending");
        assert_eq!(job.retry_count, 0);
        assert_eq!(job.max_retries, MAX_RETRIES as i32);
        assert!(job.sent_at.is_none());
        assert!(job.last_error.is_none());
    }
}

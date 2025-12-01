//! Database operations for user warnings (strike system)

use crate::error::{Result, TrustSafetyError};
use crate::models::enforcement::{CreateWarningInput, UserWarning};
use chrono::{Duration, Utc};
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

/// Database operations for user warnings
pub struct WarningsDb {
    pool: Arc<PgPool>,
}

impl WarningsDb {
    pub fn new(pool: Arc<PgPool>) -> Self {
        Self { pool }
    }

    /// Issue a new warning to a user
    pub async fn create_warning(&self, input: CreateWarningInput) -> Result<UserWarning> {
        let expires_at = input
            .expires_in_days
            .filter(|&days| days > 0)
            .map(|days| Utc::now() + Duration::days(days));

        let warning = sqlx::query_as::<_, UserWarning>(
            r#"
            INSERT INTO user_warnings (
                user_id,
                warning_type,
                severity,
                strike_points,
                reason,
                moderation_log_id,
                report_id,
                issued_by,
                acknowledged,
                expires_at,
                created_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9, NOW())
            RETURNING id, user_id, warning_type, severity, strike_points, reason,
                      moderation_log_id, report_id, issued_by, acknowledged,
                      acknowledged_at, expires_at, created_at
            "#,
        )
        .bind(input.user_id)
        .bind(&input.warning_type)
        .bind(&input.severity)
        .bind(input.strike_points)
        .bind(&input.reason)
        .bind(input.moderation_log_id)
        .bind(input.report_id)
        .bind(input.issued_by)
        .bind(expires_at)
        .fetch_one(&*self.pool)
        .await?;

        tracing::info!(
            warning_id = %warning.id,
            user_id = %input.user_id,
            warning_type = %input.warning_type,
            severity = %input.severity,
            strike_points = %input.strike_points,
            "Warning issued"
        );

        Ok(warning)
    }

    /// Get warning by ID
    pub async fn get_warning(&self, warning_id: Uuid) -> Result<UserWarning> {
        let warning = sqlx::query_as::<_, UserWarning>(
            r#"
            SELECT id, user_id, warning_type, severity, strike_points, reason,
                   moderation_log_id, report_id, issued_by, acknowledged,
                   acknowledged_at, expires_at, created_at
            FROM user_warnings
            WHERE id = $1
            "#,
        )
        .bind(warning_id)
        .fetch_optional(&*self.pool)
        .await?
        .ok_or_else(|| TrustSafetyError::NotFound(format!("Warning {} not found", warning_id)))?;

        Ok(warning)
    }

    /// Get warnings for a user
    pub async fn get_user_warnings(
        &self,
        user_id: Uuid,
        active_only: bool,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<UserWarning>> {
        let warnings = if active_only {
            sqlx::query_as::<_, UserWarning>(
                r#"
                SELECT id, user_id, warning_type, severity, strike_points, reason,
                       moderation_log_id, report_id, issued_by, acknowledged,
                       acknowledged_at, expires_at, created_at
                FROM user_warnings
                WHERE user_id = $1
                  AND (expires_at IS NULL OR expires_at > NOW())
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(user_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&*self.pool)
            .await?
        } else {
            sqlx::query_as::<_, UserWarning>(
                r#"
                SELECT id, user_id, warning_type, severity, strike_points, reason,
                       moderation_log_id, report_id, issued_by, acknowledged,
                       acknowledged_at, expires_at, created_at
                FROM user_warnings
                WHERE user_id = $1
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(user_id)
            .bind(limit)
            .bind(offset)
            .fetch_all(&*self.pool)
            .await?
        };

        Ok(warnings)
    }

    /// Count user warnings
    pub async fn count_user_warnings(&self, user_id: Uuid, active_only: bool) -> Result<i64> {
        let count: i64 = if active_only {
            sqlx::query_scalar(
                r#"
                SELECT COUNT(*) FROM user_warnings
                WHERE user_id = $1
                  AND (expires_at IS NULL OR expires_at > NOW())
                "#,
            )
            .bind(user_id)
            .fetch_one(&*self.pool)
            .await?
        } else {
            sqlx::query_scalar("SELECT COUNT(*) FROM user_warnings WHERE user_id = $1")
                .bind(user_id)
                .fetch_one(&*self.pool)
                .await?
        };

        Ok(count)
    }

    /// Get total active strike points for a user
    pub async fn get_total_strike_points(&self, user_id: Uuid) -> Result<i32> {
        let points: Option<i64> = sqlx::query_scalar(
            r#"
            SELECT SUM(strike_points)::BIGINT
            FROM user_warnings
            WHERE user_id = $1
              AND (expires_at IS NULL OR expires_at > NOW())
            "#,
        )
        .bind(user_id)
        .fetch_one(&*self.pool)
        .await?;

        Ok(points.unwrap_or(0) as i32)
    }

    /// Acknowledge a warning
    pub async fn acknowledge_warning(&self, warning_id: Uuid, user_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"
            UPDATE user_warnings
            SET acknowledged = true,
                acknowledged_at = NOW()
            WHERE id = $1 AND user_id = $2 AND acknowledged = false
            "#,
        )
        .bind(warning_id)
        .bind(user_id)
        .execute(&*self.pool)
        .await?;

        let acknowledged = result.rows_affected() > 0;

        if acknowledged {
            tracing::info!(
                warning_id = %warning_id,
                user_id = %user_id,
                "Warning acknowledged"
            );
        }

        Ok(acknowledged)
    }

    /// Check if auto-ban should be triggered based on strike points
    /// Default threshold: 10 points
    pub async fn should_auto_ban(&self, user_id: Uuid, threshold: i32) -> Result<bool> {
        let points = self.get_total_strike_points(user_id).await?;
        Ok(points >= threshold)
    }
}

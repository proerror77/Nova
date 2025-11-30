//! Database operations for user reports

use crate::error::{Result, TrustSafetyError};
use crate::models::enforcement::{CreateReportInput, UserReport};
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

/// Database operations for user reports
pub struct ReportsDb {
    pool: Arc<PgPool>,
}

impl ReportsDb {
    pub fn new(pool: Arc<PgPool>) -> Self {
        Self { pool }
    }

    /// Create a new user report
    pub async fn create_report(&self, input: CreateReportInput) -> Result<UserReport> {
        let report = sqlx::query_as::<_, UserReport>(
            r#"
            INSERT INTO user_reports (
                reporter_user_id,
                reported_user_id,
                reported_content_id,
                reported_content_type,
                report_type,
                description,
                status,
                created_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, 'pending', NOW())
            RETURNING id, reporter_user_id, reported_user_id, reported_content_id,
                      reported_content_type, report_type, description, status,
                      reviewed_by, reviewed_at, resolution, created_at
            "#,
        )
        .bind(input.reporter_user_id)
        .bind(input.reported_user_id)
        .bind(&input.reported_content_id)
        .bind(&input.reported_content_type)
        .bind(&input.report_type)
        .bind(&input.description)
        .fetch_one(&*self.pool)
        .await?;

        tracing::info!(
            report_id = %report.id,
            reporter = %input.reporter_user_id,
            report_type = %input.report_type,
            "User report created"
        );

        Ok(report)
    }

    /// Get report by ID
    pub async fn get_report(&self, report_id: Uuid) -> Result<UserReport> {
        let report = sqlx::query_as::<_, UserReport>(
            r#"
            SELECT id, reporter_user_id, reported_user_id, reported_content_id,
                   reported_content_type, report_type, description, status,
                   reviewed_by, reviewed_at, resolution, created_at
            FROM user_reports
            WHERE id = $1
            "#,
        )
        .bind(report_id)
        .fetch_optional(&*self.pool)
        .await?
        .ok_or_else(|| TrustSafetyError::NotFound(format!("Report {} not found", report_id)))?;

        Ok(report)
    }

    /// Get reports filed by a user
    pub async fn get_reports_by_reporter(
        &self,
        user_id: Uuid,
        status: Option<&str>,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<UserReport>> {
        let reports = if let Some(status) = status {
            sqlx::query_as::<_, UserReport>(
                r#"
                SELECT id, reporter_user_id, reported_user_id, reported_content_id,
                       reported_content_type, report_type, description, status,
                       reviewed_by, reviewed_at, resolution, created_at
                FROM user_reports
                WHERE reporter_user_id = $1 AND status = $2
                ORDER BY created_at DESC
                LIMIT $3 OFFSET $4
                "#,
            )
            .bind(user_id)
            .bind(status)
            .bind(limit)
            .bind(offset)
            .fetch_all(&*self.pool)
            .await?
        } else {
            sqlx::query_as::<_, UserReport>(
                r#"
                SELECT id, reporter_user_id, reported_user_id, reported_content_id,
                       reported_content_type, report_type, description, status,
                       reviewed_by, reviewed_at, resolution, created_at
                FROM user_reports
                WHERE reporter_user_id = $1
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

        Ok(reports)
    }

    /// Count reports by reporter
    pub async fn count_reports_by_reporter(
        &self,
        user_id: Uuid,
        status: Option<&str>,
    ) -> Result<i64> {
        let count: i64 = if let Some(status) = status {
            sqlx::query_scalar(
                "SELECT COUNT(*) FROM user_reports WHERE reporter_user_id = $1 AND status = $2",
            )
            .bind(user_id)
            .bind(status)
            .fetch_one(&*self.pool)
            .await?
        } else {
            sqlx::query_scalar("SELECT COUNT(*) FROM user_reports WHERE reporter_user_id = $1")
                .bind(user_id)
                .fetch_one(&*self.pool)
                .await?
        };

        Ok(count)
    }

    /// Review a report (admin action)
    pub async fn review_report(
        &self,
        report_id: Uuid,
        admin_id: Uuid,
        resolution: &str,
        status: &str,
    ) -> Result<UserReport> {
        let report = sqlx::query_as::<_, UserReport>(
            r#"
            UPDATE user_reports
            SET status = $2,
                reviewed_by = $3,
                reviewed_at = NOW(),
                resolution = $4
            WHERE id = $1
            RETURNING id, reporter_user_id, reported_user_id, reported_content_id,
                      reported_content_type, report_type, description, status,
                      reviewed_by, reviewed_at, resolution, created_at
            "#,
        )
        .bind(report_id)
        .bind(status)
        .bind(admin_id)
        .bind(resolution)
        .fetch_optional(&*self.pool)
        .await?
        .ok_or_else(|| TrustSafetyError::NotFound(format!("Report {} not found", report_id)))?;

        tracing::info!(
            report_id = %report_id,
            admin_id = %admin_id,
            resolution = %resolution,
            status = %status,
            "Report reviewed"
        );

        Ok(report)
    }

    /// Get pending reports (for admin queue)
    pub async fn get_pending_reports(&self, limit: i64, offset: i64) -> Result<Vec<UserReport>> {
        let reports = sqlx::query_as::<_, UserReport>(
            r#"
            SELECT id, reporter_user_id, reported_user_id, reported_content_id,
                   reported_content_type, report_type, description, status,
                   reviewed_by, reviewed_at, resolution, created_at
            FROM user_reports
            WHERE status = 'pending'
            ORDER BY created_at ASC
            LIMIT $1 OFFSET $2
            "#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(&*self.pool)
        .await?;

        Ok(reports)
    }
}

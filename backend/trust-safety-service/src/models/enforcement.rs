//! P0: User enforcement models (Reports, Warnings, Bans)
//! Migrated from user-service to trust-safety-service

use chrono::{DateTime, Utc};
use sqlx::FromRow;
use uuid::Uuid;

/// User report record from database
#[derive(Debug, Clone, FromRow)]
pub struct UserReport {
    pub id: Uuid,
    pub reporter_user_id: Uuid,
    pub reported_user_id: Option<Uuid>,
    pub reported_content_id: Option<String>,
    pub reported_content_type: Option<String>,
    pub report_type: String,
    pub description: Option<String>,
    pub status: String,
    pub reviewed_by: Option<Uuid>,
    pub reviewed_at: Option<DateTime<Utc>>,
    pub resolution: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// User warning record from database
#[derive(Debug, Clone, FromRow)]
pub struct UserWarning {
    pub id: Uuid,
    pub user_id: Uuid,
    pub warning_type: String,
    pub severity: String,
    pub strike_points: i32,
    pub reason: String,
    pub moderation_log_id: Option<Uuid>,
    pub report_id: Option<Uuid>,
    pub issued_by: Uuid,
    pub acknowledged: bool,
    pub acknowledged_at: Option<DateTime<Utc>>,
    pub expires_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// User ban record from database
#[derive(Debug, Clone, FromRow)]
pub struct UserBan {
    pub id: Uuid,
    pub user_id: Uuid,
    pub ban_type: String,
    pub reason: String,
    pub banned_by: Uuid,
    pub warning_id: Option<Uuid>,
    pub report_id: Option<Uuid>,
    pub starts_at: DateTime<Utc>,
    pub ends_at: Option<DateTime<Utc>>,
    pub lifted_at: Option<DateTime<Utc>>,
    pub lifted_by: Option<Uuid>,
    pub lift_reason: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Input for creating a new report
#[derive(Debug)]
pub struct CreateReportInput {
    pub reporter_user_id: Uuid,
    pub reported_user_id: Option<Uuid>,
    pub reported_content_id: Option<String>,
    pub reported_content_type: Option<String>,
    pub report_type: String,
    pub description: Option<String>,
}

/// Input for creating a new warning
#[derive(Debug)]
pub struct CreateWarningInput {
    pub user_id: Uuid,
    pub warning_type: String,
    pub severity: String,
    pub strike_points: i32,
    pub reason: String,
    pub moderation_log_id: Option<Uuid>,
    pub report_id: Option<Uuid>,
    pub issued_by: Uuid,
    pub expires_in_days: Option<i64>,
}

/// Input for creating a new ban
#[derive(Debug)]
pub struct CreateBanInput {
    pub user_id: Uuid,
    pub ban_type: String,
    pub reason: String,
    pub banned_by: Uuid,
    pub warning_id: Option<Uuid>,
    pub report_id: Option<Uuid>,
    pub duration_hours: Option<i64>,
}

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres, Row};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Report {
    pub id: Uuid,
    pub reporter_id: Uuid,
    pub reported_user_id: Option<Uuid>,
    pub reason_id: Uuid,
    pub reason_code: String,
    pub target_type: String, // 'user', 'post', 'message', 'comment'
    pub target_id: Uuid,
    pub description: Option<String>,
    pub status: String,   // 'open', 'investigating', 'resolved', 'dismissed'
    pub severity: String, // 'low', 'medium', 'high', 'critical'
    pub priority: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub resolved_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ModerationAction {
    pub id: Uuid,
    pub report_id: Option<Uuid>,
    pub moderator_id: Uuid,
    pub action_type: String, // 'warn', 'mute', 'suspend', 'ban', 'delete_content'
    pub target_type: Option<String>,
    pub target_id: Option<Uuid>,
    pub duration_days: Option<i32>,
    pub reason: Option<String>,
    pub notes: Option<String>,
    pub status: String, // 'active', 'appealed', 'reversed'
    pub created_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateReportRequest {
    pub reporter_id: Uuid,
    pub reported_user_id: Option<Uuid>,
    pub reason_code: String,
    pub target_type: String,
    pub target_id: Uuid,
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateModerationActionRequest {
    pub report_id: Option<Uuid>,
    pub moderator_id: Uuid,
    pub action_type: String,
    pub target_type: String,
    pub target_id: Uuid,
    pub duration_days: Option<i32>,
    pub reason: Option<String>,
    pub notes: Option<String>,
}

pub struct ModerationService;

impl ModerationService {
    /// Create a new report
    pub async fn create_report(
        db: &Pool<Postgres>,
        request: CreateReportRequest,
    ) -> Result<Report, String> {
        // Get reason ID from reason code
        let reason_id: Uuid =
            sqlx::query_scalar("SELECT id FROM report_reasons WHERE reason_code = $1")
                .bind(&request.reason_code)
                .fetch_optional(db)
                .await
                .map_err(|e| format!("Failed to fetch reason: {}", e))?
                .ok_or_else(|| "Invalid reason code".to_string())?;

        let report = sqlx::query_as::<_, Report>(
            r#"
            INSERT INTO reports (
                reporter_id, reported_user_id, reason_id, reason_code,
                target_type, target_id, description
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING *
            "#,
        )
        .bind(request.reporter_id)
        .bind(request.reported_user_id)
        .bind(reason_id)
        .bind(request.reason_code)
        .bind(request.target_type)
        .bind(request.target_id)
        .bind(request.description)
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to create report: {}", e))?;

        // Add to moderation queue
        let _ = sqlx::query("INSERT INTO moderation_queue (report_id, priority) VALUES ($1, $2)")
            .bind(report.id)
            .bind(calculate_priority(&report.severity))
            .execute(db)
            .await;

        Ok(report)
    }

    /// Get reports with filtering
    pub async fn get_reports(
        db: &Pool<Postgres>,
        status: Option<&str>,
        limit: i64,
        offset: i64,
    ) -> Result<(Vec<Report>, i64), String> {
        let limit = limit.min(100);

        let mut query_str = "SELECT * FROM reports WHERE 1=1".to_string();
        let mut count_query = "SELECT COUNT(*) FROM reports WHERE 1=1".to_string();

        if let Some(s) = status {
            query_str.push_str(&format!(" AND status = '{}'", s));
            count_query.push_str(&format!(" AND status = '{}'", s));
        }

        query_str.push_str(" ORDER BY priority DESC, created_at DESC LIMIT $1 OFFSET $2");

        let reports = sqlx::query_as::<_, Report>(&query_str)
            .bind(limit)
            .bind(offset)
            .fetch_all(db)
            .await
            .map_err(|e| format!("Failed to fetch reports: {}", e))?;

        let total: i64 = sqlx::query_scalar(&count_query)
            .fetch_one(db)
            .await
            .map_err(|e| format!("Failed to count reports: {}", e))?;

        Ok((reports, total))
    }

    /// Update report status
    pub async fn update_report_status(
        db: &Pool<Postgres>,
        report_id: Uuid,
        new_status: &str,
    ) -> Result<Report, String> {
        let resolved_at = if new_status == "resolved" {
            Some(Utc::now())
        } else {
            None
        };

        let report = sqlx::query_as::<_, Report>(
            r#"
            UPDATE reports
            SET status = $1, updated_at = NOW(), resolved_at = COALESCE($2, resolved_at)
            WHERE id = $3
            RETURNING *
            "#,
        )
        .bind(new_status)
        .bind(resolved_at)
        .bind(report_id)
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to update report: {}", e))?;

        Ok(report)
    }

    /// Create a moderation action
    pub async fn create_action(
        db: &Pool<Postgres>,
        request: CreateModerationActionRequest,
    ) -> Result<ModerationAction, String> {
        let expires_at = request
            .duration_days
            .map(|days| Utc::now() + chrono::Duration::days(days as i64));

        let action = sqlx::query_as::<_, ModerationAction>(
            r#"
            INSERT INTO moderation_actions (
                report_id, moderator_id, action_type, target_type,
                target_id, duration_days, reason, notes, expires_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING *
            "#,
        )
        .bind(request.report_id)
        .bind(request.moderator_id)
        .bind(&request.action_type)
        .bind(&request.target_type)
        .bind(request.target_id)
        .bind(request.duration_days)
        .bind(request.reason)
        .bind(request.notes)
        .bind(expires_at)
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to create action: {}", e))?;

        // Update report if it's linked
        if let Some(report_id) = request.report_id {
            let _ = sqlx::query("UPDATE reports SET status = 'resolved' WHERE id = $1")
                .bind(report_id)
                .execute(db)
                .await;
        }

        Ok(action)
    }

    /// Get active actions for a user
    pub async fn get_active_actions_for_user(
        db: &Pool<Postgres>,
        user_id: Uuid,
    ) -> Result<Vec<ModerationAction>, String> {
        let actions = sqlx::query_as::<_, ModerationAction>(
            r#"
            SELECT *
            FROM moderation_actions
            WHERE target_id = $1 AND target_type = 'user' AND status = 'active'
              AND (expires_at IS NULL OR expires_at > NOW())
            ORDER BY created_at DESC
            "#,
        )
        .bind(user_id)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch actions: {}", e))?;

        Ok(actions)
    }

    /// Check if a user is banned
    pub async fn is_user_banned(db: &Pool<Postgres>, user_id: Uuid) -> Result<bool, String> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM moderation_actions
            WHERE target_id = $1 AND action_type = 'ban' AND status = 'active'
              AND (expires_at IS NULL OR expires_at > NOW())
            "#,
        )
        .bind(user_id)
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to check ban status: {}", e))?;

        Ok(count > 0)
    }

    /// Check if a user is muted/suspended
    pub async fn get_user_restrictions(
        db: &Pool<Postgres>,
        user_id: Uuid,
    ) -> Result<Vec<ModerationAction>, String> {
        let actions = sqlx::query_as::<_, ModerationAction>(
            r#"
            SELECT *
            FROM moderation_actions
            WHERE target_id = $1 AND action_type IN ('mute', 'suspend')
              AND status = 'active' AND (expires_at IS NULL OR expires_at > NOW())
            "#,
        )
        .bind(user_id)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch restrictions: {}", e))?;

        Ok(actions)
    }

    /// Appeal a moderation action
    pub async fn appeal_action(
        db: &Pool<Postgres>,
        action_id: Uuid,
        user_id: Uuid,
        reason: &str,
    ) -> Result<(), String> {
        sqlx::query(
            r#"
            INSERT INTO moderation_appeals (action_id, user_id, reason, status)
            VALUES ($1, $2, $3, 'pending')
            "#,
        )
        .bind(action_id)
        .bind(user_id)
        .bind(reason)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to create appeal: {}", e))?;

        // Update action status to 'appealed'
        sqlx::query("UPDATE moderation_actions SET status = 'appealed' WHERE id = $1")
            .bind(action_id)
            .execute(db)
            .await
            .map_err(|e| format!("Failed to update action: {}", e))?;

        Ok(())
    }

    /// Clean up expired actions
    pub async fn cleanup_expired_actions(db: &Pool<Postgres>) -> Result<u64, String> {
        let result = sqlx::query(
            r#"
            UPDATE moderation_actions
            SET status = 'expired', updated_at = NOW()
            WHERE expires_at IS NOT NULL AND expires_at < NOW() AND status = 'active'
            "#,
        )
        .execute(db)
        .await
        .map_err(|e| format!("Failed to cleanup actions: {}", e))?;

        Ok(result.rows_affected())
    }

    /// Get moderation queue stats
    pub async fn get_queue_stats(db: &Pool<Postgres>) -> Result<serde_json::Value, String> {
        let pending: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM moderation_queue WHERE queue_status = 'pending'",
        )
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to count pending: {}", e))?;

        let assigned: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM moderation_queue WHERE queue_status = 'assigned'",
        )
        .fetch_one(db)
        .await
        .map_err(|e| format!("Failed to count assigned: {}", e))?;

        Ok(serde_json::json!({
            "pending": pending,
            "assigned": assigned,
            "total": pending + assigned
        }))
    }
}

/// Calculate priority based on severity
fn calculate_priority(severity: &str) -> i32 {
    match severity {
        "critical" => 1000,
        "high" => 100,
        "medium" => 10,
        "low" => 1,
        _ => 0,
    }
}

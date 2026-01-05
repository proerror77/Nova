// Dashboard service - provides statistics and chart data
use chrono::{DateTime, Duration, Utc};
use serde::Serialize;

use crate::db::Database;
use crate::error::Result;

pub struct DashboardService {
    db: Database,
}

#[derive(Debug, Serialize)]
pub struct DashboardStats {
    pub total_users: i64,
    pub active_users_today: i64,
    pub new_users_today: i64,
    pub banned_users: i64,
    pub total_warnings: i64,
    pub pending_reviews: i64,
    pub admin_actions_today: i64,
}

#[derive(Debug, Serialize)]
pub struct ChartDataPoint {
    pub date: String,
    pub value: i64,
}

#[derive(Debug, Serialize)]
pub struct RiskAlert {
    pub id: String,
    pub level: String,
    pub title: String,
    pub description: String,
    pub user_id: Option<String>,
    pub created_at: DateTime<Utc>,
}

impl DashboardService {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    /// Get dashboard statistics
    pub async fn get_stats(&self) -> Result<DashboardStats> {
        let today_start = Utc::now().date_naive().and_hms_opt(0, 0, 0).unwrap();

        // Total users
        let total_users: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users")
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

        // Active users today (users with last_active_at today)
        let active_users_today: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM users WHERE last_active_at >= $1"
        )
        .bind(today_start)
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        // New users today
        let new_users_today: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM users WHERE created_at >= $1"
        )
        .bind(today_start)
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        // Banned users (active bans)
        let banned_users: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(DISTINCT user_id) FROM user_bans
            WHERE is_active = true
            AND (expires_at IS NULL OR expires_at > NOW())
            "#
        )
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        // Total warnings (last 30 days)
        let total_warnings: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_warnings WHERE created_at >= NOW() - INTERVAL '30 days'"
        )
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        // Pending reviews (placeholder - would need content_reports table)
        let pending_reviews: i64 = 0;

        // Admin actions today
        let admin_actions_today: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM audit_logs WHERE created_at >= $1"
        )
        .bind(today_start)
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        Ok(DashboardStats {
            total_users,
            active_users_today,
            new_users_today,
            banned_users,
            total_warnings,
            pending_reviews,
            admin_actions_today,
        })
    }

    /// Get user growth chart data for the last N days
    pub async fn get_user_chart(&self, days: i32) -> Result<Vec<ChartDataPoint>> {
        let mut data = Vec::new();
        let today = Utc::now().date_naive();

        for i in (0..days).rev() {
            let date = today - Duration::days(i as i64);
            let next_date = date + Duration::days(1);

            let count: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM users WHERE created_at >= $1 AND created_at < $2"
            )
            .bind(date.and_hms_opt(0, 0, 0).unwrap())
            .bind(next_date.and_hms_opt(0, 0, 0).unwrap())
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

            data.push(ChartDataPoint {
                date: date.format("%Y-%m-%d").to_string(),
                value: count,
            });
        }

        Ok(data)
    }

    /// Get admin activity chart data
    pub async fn get_activity_chart(&self, days: i32) -> Result<Vec<ChartDataPoint>> {
        let mut data = Vec::new();
        let today = Utc::now().date_naive();

        for i in (0..days).rev() {
            let date = today - Duration::days(i as i64);
            let next_date = date + Duration::days(1);

            let count: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM audit_logs WHERE created_at >= $1 AND created_at < $2"
            )
            .bind(date.and_hms_opt(0, 0, 0).unwrap())
            .bind(next_date.and_hms_opt(0, 0, 0).unwrap())
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

            data.push(ChartDataPoint {
                date: date.format("%Y-%m-%d").to_string(),
                value: count,
            });
        }

        Ok(data)
    }

    /// Get recent audit logs for admin activity feed
    pub async fn get_recent_activity(&self, limit: i64) -> Result<Vec<RecentActivity>> {
        let activities: Vec<RecentActivity> = sqlx::query_as(
            r#"
            SELECT
                al.id,
                al.action,
                al.resource_type,
                al.resource_id,
                al.created_at,
                a.name as admin_name,
                a.email as admin_email
            FROM audit_logs al
            JOIN admin_users a ON al.admin_id = a.id
            ORDER BY al.created_at DESC
            LIMIT $1
            "#
        )
        .bind(limit)
        .fetch_all(&self.db.pg)
        .await
        .unwrap_or_default();

        Ok(activities)
    }

    /// Get risk alerts based on patterns
    pub async fn get_risk_alerts(&self) -> Result<Vec<RiskAlert>> {
        let mut alerts = Vec::new();

        // Check for users with multiple warnings
        let high_warning_users: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(DISTINCT user_id) FROM user_warnings
            GROUP BY user_id
            HAVING COUNT(*) >= 3
            "#
        )
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        if high_warning_users > 0 {
            alerts.push(RiskAlert {
                id: uuid::Uuid::new_v4().to_string(),
                level: "medium".to_string(),
                title: "多次警告用户".to_string(),
                description: format!("有 {} 个用户收到3次以上警告", high_warning_users),
                user_id: None,
                created_at: Utc::now(),
            });
        }

        // Check for recent ban surge
        let recent_bans: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_bans WHERE banned_at >= NOW() - INTERVAL '1 hour'"
        )
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        if recent_bans > 5 {
            alerts.push(RiskAlert {
                id: uuid::Uuid::new_v4().to_string(),
                level: "high".to_string(),
                title: "封禁数量激增".to_string(),
                description: format!("过去1小时内封禁了 {} 个用户", recent_bans),
                user_id: None,
                created_at: Utc::now(),
            });
        }

        Ok(alerts)
    }
}

#[derive(Debug, sqlx::FromRow, Serialize)]
pub struct RecentActivity {
    pub id: uuid::Uuid,
    pub action: String,
    pub resource_type: String,
    pub resource_id: Option<String>,
    pub created_at: DateTime<Utc>,
    pub admin_name: String,
    pub admin_email: String,
}

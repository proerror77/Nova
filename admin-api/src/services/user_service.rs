// User service - handles user queries and management operations
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::db::Database;
use crate::error::{AppError, Result};

pub struct UserService {
    db: Database,
}

/// User summary for list views
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct UserSummary {
    pub id: Uuid,
    pub nickname: String,
    pub email: String,
    pub avatar: Option<String>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub last_active_at: Option<DateTime<Utc>>,
}

/// Full user details
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct UserDetail {
    pub id: Uuid,
    pub nickname: String,
    pub email: String,
    pub phone: Option<String>,
    pub avatar: Option<String>,
    pub bio: Option<String>,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// User ban record
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct UserBan {
    pub id: Uuid,
    pub user_id: Uuid,
    pub admin_id: Uuid,
    pub reason: String,
    pub duration_days: Option<i32>,
    pub banned_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
    pub is_active: bool,
}

/// User warning record
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct UserWarning {
    pub id: Uuid,
    pub user_id: Uuid,
    pub admin_id: Uuid,
    pub reason: String,
    pub severity: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct ListUsersParams {
    pub page: u32,
    pub limit: u32,
    pub status: Option<String>,
    pub search: Option<String>,
}

impl UserService {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    /// List users with pagination and filters
    /// Note: This queries the main Nova users table (requires read access)
    pub async fn list_users(&self, params: ListUsersParams) -> Result<(Vec<UserSummary>, i64)> {
        let offset = ((params.page - 1) * params.limit) as i64;
        let limit = params.limit as i64;

        // Build dynamic query based on filters
        let mut where_clauses = vec!["1=1".to_string()];

        if let Some(ref status) = params.status {
            where_clauses.push(format!("status = '{}'", status));
        }

        if let Some(ref search) = params.search {
            where_clauses.push(format!(
                "(nickname ILIKE '%{}%' OR email ILIKE '%{}%')",
                search, search
            ));
        }

        let where_clause = where_clauses.join(" AND ");

        // Query users from main users table
        // Note: In production, this would connect to the main Nova database
        let query = format!(
            r#"
            SELECT
                id,
                COALESCE(nickname, 'Unknown') as nickname,
                COALESCE(email, '') as email,
                avatar,
                COALESCE(status, 'active') as status,
                created_at,
                last_active_at
            FROM users
            WHERE {}
            ORDER BY created_at DESC
            LIMIT $1 OFFSET $2
            "#,
            where_clause
        );

        let users: Vec<UserSummary> = sqlx::query_as(&query)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db.pg)
            .await
            .unwrap_or_default();

        // Get total count
        let count_query = format!(
            "SELECT COUNT(*) as count FROM users WHERE {}",
            where_clause
        );

        let total: i64 = sqlx::query_scalar(&count_query)
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

        Ok((users, total))
    }

    /// Get user details by ID
    pub async fn get_user(&self, user_id: Uuid) -> Result<UserDetail> {
        let user: UserDetail = sqlx::query_as(
            r#"
            SELECT
                id,
                COALESCE(nickname, 'Unknown') as nickname,
                COALESCE(email, '') as email,
                phone,
                avatar,
                bio,
                COALESCE(status, 'active') as status,
                created_at,
                updated_at
            FROM users
            WHERE id = $1
            "#
        )
        .bind(user_id)
        .fetch_optional(&self.db.pg)
        .await?
        .ok_or(AppError::NotFound(format!("User {} not found", user_id)))?;

        Ok(user)
    }

    /// Ban a user
    pub async fn ban_user(
        &self,
        user_id: Uuid,
        admin_id: Uuid,
        reason: &str,
        duration_days: Option<i32>,
    ) -> Result<UserBan> {
        let expires_at = duration_days.map(|days| Utc::now() + Duration::days(days as i64));

        // Create ban record
        let ban: UserBan = sqlx::query_as(
            r#"
            INSERT INTO user_bans (user_id, admin_id, reason, duration_days, expires_at)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            "#
        )
        .bind(user_id)
        .bind(admin_id)
        .bind(reason)
        .bind(duration_days)
        .bind(expires_at)
        .fetch_one(&self.db.pg)
        .await?;

        // Update user status in main table (if we have write access)
        let _ = sqlx::query("UPDATE users SET status = 'banned' WHERE id = $1")
            .bind(user_id)
            .execute(&self.db.pg)
            .await;

        Ok(ban)
    }

    /// Unban a user
    pub async fn unban_user(&self, user_id: Uuid, admin_id: Uuid) -> Result<()> {
        // Mark all active bans as inactive
        sqlx::query(
            r#"
            UPDATE user_bans
            SET is_active = false, unbanned_at = NOW(), unbanned_by = $2
            WHERE user_id = $1 AND is_active = true
            "#
        )
        .bind(user_id)
        .bind(admin_id)
        .execute(&self.db.pg)
        .await?;

        // Update user status in main table
        let _ = sqlx::query("UPDATE users SET status = 'active' WHERE id = $1")
            .bind(user_id)
            .execute(&self.db.pg)
            .await;

        Ok(())
    }

    /// Warn a user
    pub async fn warn_user(
        &self,
        user_id: Uuid,
        admin_id: Uuid,
        reason: &str,
        severity: &str,
    ) -> Result<UserWarning> {
        let warning: UserWarning = sqlx::query_as(
            r#"
            INSERT INTO user_warnings (user_id, admin_id, reason, severity)
            VALUES ($1, $2, $3, $4)
            RETURNING *
            "#
        )
        .bind(user_id)
        .bind(admin_id)
        .bind(reason)
        .bind(severity)
        .fetch_one(&self.db.pg)
        .await?;

        Ok(warning)
    }

    /// Get user's ban history
    pub async fn get_user_bans(&self, user_id: Uuid) -> Result<Vec<UserBan>> {
        let bans: Vec<UserBan> = sqlx::query_as(
            "SELECT * FROM user_bans WHERE user_id = $1 ORDER BY banned_at DESC"
        )
        .bind(user_id)
        .fetch_all(&self.db.pg)
        .await?;

        Ok(bans)
    }

    /// Get user's warning history
    pub async fn get_user_warnings(&self, user_id: Uuid) -> Result<Vec<UserWarning>> {
        let warnings: Vec<UserWarning> = sqlx::query_as(
            "SELECT * FROM user_warnings WHERE user_id = $1 ORDER BY created_at DESC"
        )
        .bind(user_id)
        .fetch_all(&self.db.pg)
        .await?;

        Ok(warnings)
    }

    /// Get warning count for a user
    pub async fn get_warning_count(&self, user_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM user_warnings WHERE user_id = $1"
        )
        .bind(user_id)
        .fetch_one(&self.db.pg)
        .await?;

        Ok(count)
    }

    /// Check if user is currently banned
    pub async fn is_user_banned(&self, user_id: Uuid) -> Result<bool> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM user_bans
            WHERE user_id = $1
            AND is_active = true
            AND (expires_at IS NULL OR expires_at > NOW())
            "#
        )
        .bind(user_id)
        .fetch_one(&self.db.pg)
        .await?;

        Ok(count > 0)
    }
}

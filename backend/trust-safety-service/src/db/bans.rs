//! Database operations for user bans

use crate::error::{Result, TrustSafetyError};
use crate::models::enforcement::{CreateBanInput, UserBan};
use chrono::{Duration, Utc};
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

/// Database operations for user bans
pub struct BansDb {
    pool: Arc<PgPool>,
}

impl BansDb {
    pub fn new(pool: Arc<PgPool>) -> Self {
        Self { pool }
    }

    /// Ban a user
    pub async fn create_ban(&self, input: CreateBanInput) -> Result<UserBan> {
        let ends_at = input
            .duration_hours
            .filter(|&hours| hours > 0)
            .map(|hours| Utc::now() + Duration::hours(hours));

        let ban = sqlx::query_as::<_, UserBan>(
            r#"
            INSERT INTO user_bans (
                user_id,
                ban_type,
                reason,
                banned_by,
                warning_id,
                report_id,
                starts_at,
                ends_at,
                created_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7, NOW())
            RETURNING id, user_id, ban_type, reason, banned_by, warning_id,
                      report_id, starts_at, ends_at, lifted_at, lifted_by,
                      lift_reason, created_at
            "#,
        )
        .bind(input.user_id)
        .bind(&input.ban_type)
        .bind(&input.reason)
        .bind(input.banned_by)
        .bind(input.warning_id)
        .bind(input.report_id)
        .bind(ends_at)
        .fetch_one(&*self.pool)
        .await?;

        tracing::warn!(
            ban_id = %ban.id,
            user_id = %input.user_id,
            ban_type = %input.ban_type,
            banned_by = %input.banned_by,
            ends_at = ?ends_at,
            "User banned"
        );

        Ok(ban)
    }

    /// Get ban by ID
    pub async fn get_ban(&self, ban_id: Uuid) -> Result<UserBan> {
        let ban = sqlx::query_as::<_, UserBan>(
            r#"
            SELECT id, user_id, ban_type, reason, banned_by, warning_id,
                   report_id, starts_at, ends_at, lifted_at, lifted_by,
                   lift_reason, created_at
            FROM user_bans
            WHERE id = $1
            "#,
        )
        .bind(ban_id)
        .fetch_optional(&*self.pool)
        .await?
        .ok_or_else(|| TrustSafetyError::NotFound(format!("Ban {} not found", ban_id)))?;

        Ok(ban)
    }

    /// Check if a user is currently banned (returns active ban if exists)
    pub async fn get_active_ban(&self, user_id: Uuid) -> Result<Option<UserBan>> {
        let ban = sqlx::query_as::<_, UserBan>(
            r#"
            SELECT id, user_id, ban_type, reason, banned_by, warning_id,
                   report_id, starts_at, ends_at, lifted_at, lifted_by,
                   lift_reason, created_at
            FROM user_bans
            WHERE user_id = $1
              AND lifted_at IS NULL
              AND (ends_at IS NULL OR ends_at > NOW())
            ORDER BY created_at DESC
            LIMIT 1
            "#,
        )
        .bind(user_id)
        .fetch_optional(&*self.pool)
        .await?;

        Ok(ban)
    }

    /// Check if user is banned (simple boolean check)
    pub async fn is_user_banned(&self, user_id: Uuid) -> Result<bool> {
        let is_banned: bool = sqlx::query_scalar(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM user_bans
                WHERE user_id = $1
                  AND lifted_at IS NULL
                  AND (ends_at IS NULL OR ends_at > NOW())
            )
            "#,
        )
        .bind(user_id)
        .fetch_one(&*self.pool)
        .await?;

        Ok(is_banned)
    }

    /// Get ban history for a user
    pub async fn get_user_bans(
        &self,
        user_id: Uuid,
        active_only: bool,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<UserBan>> {
        let bans = if active_only {
            sqlx::query_as::<_, UserBan>(
                r#"
                SELECT id, user_id, ban_type, reason, banned_by, warning_id,
                       report_id, starts_at, ends_at, lifted_at, lifted_by,
                       lift_reason, created_at
                FROM user_bans
                WHERE user_id = $1
                  AND lifted_at IS NULL
                  AND (ends_at IS NULL OR ends_at > NOW())
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
            sqlx::query_as::<_, UserBan>(
                r#"
                SELECT id, user_id, ban_type, reason, banned_by, warning_id,
                       report_id, starts_at, ends_at, lifted_at, lifted_by,
                       lift_reason, created_at
                FROM user_bans
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

        Ok(bans)
    }

    /// Count user bans
    pub async fn count_user_bans(&self, user_id: Uuid, active_only: bool) -> Result<i64> {
        let count: i64 = if active_only {
            sqlx::query_scalar(
                r#"
                SELECT COUNT(*) FROM user_bans
                WHERE user_id = $1
                  AND lifted_at IS NULL
                  AND (ends_at IS NULL OR ends_at > NOW())
                "#,
            )
            .bind(user_id)
            .fetch_one(&*self.pool)
            .await?
        } else {
            sqlx::query_scalar("SELECT COUNT(*) FROM user_bans WHERE user_id = $1")
                .bind(user_id)
                .fetch_one(&*self.pool)
                .await?
        };

        Ok(count)
    }

    /// Lift a ban (early release)
    pub async fn lift_ban(
        &self,
        ban_id: Uuid,
        lifted_by: Uuid,
        lift_reason: &str,
    ) -> Result<UserBan> {
        let ban = sqlx::query_as::<_, UserBan>(
            r#"
            UPDATE user_bans
            SET lifted_at = NOW(),
                lifted_by = $2,
                lift_reason = $3
            WHERE id = $1 AND lifted_at IS NULL
            RETURNING id, user_id, ban_type, reason, banned_by, warning_id,
                      report_id, starts_at, ends_at, lifted_at, lifted_by,
                      lift_reason, created_at
            "#,
        )
        .bind(ban_id)
        .bind(lifted_by)
        .bind(lift_reason)
        .fetch_optional(&*self.pool)
        .await?
        .ok_or_else(|| {
            TrustSafetyError::NotFound(format!("Ban {} not found or already lifted", ban_id))
        })?;

        tracing::info!(
            ban_id = %ban_id,
            user_id = %ban.user_id,
            lifted_by = %lifted_by,
            lift_reason = %lift_reason,
            "Ban lifted"
        );

        Ok(ban)
    }
}

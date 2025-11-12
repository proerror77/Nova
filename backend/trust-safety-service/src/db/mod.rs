use crate::error::{Result, TrustSafetyError};
use crate::models::ModerationLog;
use chrono::Utc;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

/// Database operations for moderation logs
pub struct ModerationDb {
    pool: Arc<PgPool>,
}

impl ModerationDb {
    pub fn new(pool: Arc<PgPool>) -> Self {
        Self { pool }
    }

    /// Save moderation log
    pub async fn save_moderation_log(
        &self,
        content_id: &str,
        content_type: &str,
        user_id: Uuid,
        nsfw_score: f32,
        toxicity_score: f32,
        spam_score: f32,
        overall_score: f32,
        approved: bool,
        violations: Vec<String>,
    ) -> Result<Uuid> {
        let moderation_id = sqlx::query_scalar::<_, Uuid>(
            r#"
            INSERT INTO moderation_logs (
                content_id,
                content_type,
                user_id,
                nsfw_score,
                toxicity_score,
                spam_score,
                overall_score,
                approved,
                violations,
                created_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            RETURNING id
            "#,
        )
        .bind(content_id)
        .bind(content_type)
        .bind(user_id)
        .bind(nsfw_score)
        .bind(toxicity_score)
        .bind(spam_score)
        .bind(overall_score)
        .bind(approved)
        .bind(&violations)
        .bind(Utc::now())
        .fetch_one(&*self.pool)
        .await?;

        tracing::info!(
            moderation_id = %moderation_id,
            content_id = %content_id,
            approved = %approved,
            overall_score = %overall_score,
            "Moderation log saved"
        );

        Ok(moderation_id)
    }

    /// Get moderation log by ID
    pub async fn get_moderation_log(&self, moderation_id: Uuid) -> Result<ModerationLog> {
        let log = sqlx::query_as::<_, ModerationLog>(
            r#"
            SELECT id, content_id, content_type, user_id,
                   nsfw_score, toxicity_score, spam_score, overall_score,
                   approved, violations, created_at
            FROM moderation_logs
            WHERE id = $1
            "#,
        )
        .bind(moderation_id)
        .fetch_optional(&*self.pool)
        .await?
        .ok_or_else(|| {
            TrustSafetyError::ModerationLogNotFound(moderation_id.to_string())
        })?;

        Ok(log)
    }

    /// Get moderation history for user
    pub async fn get_user_moderation_history(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<ModerationLog>> {
        let logs = sqlx::query_as::<_, ModerationLog>(
            r#"
            SELECT id, content_id, content_type, user_id,
                   nsfw_score, toxicity_score, spam_score, overall_score,
                   approved, violations, created_at
            FROM moderation_logs
            WHERE user_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&*self.pool)
        .await?;

        Ok(logs)
    }

    /// Get moderation history for content
    pub async fn get_content_moderation_history(
        &self,
        content_id: &str,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<ModerationLog>> {
        let logs = sqlx::query_as::<_, ModerationLog>(
            r#"
            SELECT id, content_id, content_type, user_id,
                   nsfw_score, toxicity_score, spam_score, overall_score,
                   approved, violations, created_at
            FROM moderation_logs
            WHERE content_id = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(content_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&*self.pool)
        .await?;

        Ok(logs)
    }

    /// Count total moderation logs
    pub async fn count_moderation_logs(
        &self,
        user_id: Option<Uuid>,
        content_id: Option<&str>,
    ) -> Result<i64> {
        let count = if let Some(user_id) = user_id {
            sqlx::query_scalar("SELECT COUNT(*) FROM moderation_logs WHERE user_id = $1")
                .bind(user_id)
                .fetch_one(&*self.pool)
                .await?
        } else if let Some(content_id) = content_id {
            sqlx::query_scalar("SELECT COUNT(*) FROM moderation_logs WHERE content_id = $1")
                .bind(content_id)
                .fetch_one(&*self.pool)
                .await?
        } else {
            sqlx::query_scalar("SELECT COUNT(*) FROM moderation_logs")
                .fetch_one(&*self.pool)
                .await?
        };

        Ok(count)
    }

    /// Get recent content for duplicate detection
    pub async fn get_recent_user_content(
        &self,
        user_id: Uuid,
        limit: i64,
    ) -> Result<Vec<String>> {
        let content_ids = sqlx::query_scalar::<_, String>(
            r#"
            SELECT content_id
            FROM moderation_logs
            WHERE user_id = $1
            ORDER BY created_at DESC
            LIMIT $2
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(&*self.pool)
        .await?;

        Ok(content_ids)
    }

    /// Get user's post statistics for spam detection
    pub async fn get_user_post_stats(
        &self,
        user_id: Uuid,
    ) -> Result<(i64, Option<i64>)> {
        // Count posts in last hour and get seconds since last post
        let stats = sqlx::query_as::<_, (i64, Option<i64>)>(
            r#"
            SELECT
                COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour') as recent_count,
                EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))::BIGINT as seconds_since_last
            FROM moderation_logs
            WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_one(&*self.pool)
        .await?;

        Ok(stats)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: Integration tests require a test database
    // These are placeholder unit tests

    #[test]
    fn test_database_module_exists() {
        // Placeholder test
        assert!(true);
    }
}

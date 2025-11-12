use crate::error::{Result, TrustSafetyError};
use crate::models::{Appeal, AppealStatus};
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

/// Appeal service for handling content appeal workflows
pub struct AppealService {
    db: Arc<PgPool>,
}

impl AppealService {
    pub fn new(db: Arc<PgPool>) -> Self {
        Self { db }
    }

    /// Submit a new appeal for rejected content
    pub async fn submit_appeal(
        &self,
        moderation_id: Uuid,
        user_id: Uuid,
        reason: &str,
    ) -> Result<Appeal> {
        // Validate moderation exists
        let moderation_exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM moderation_logs WHERE id = $1 AND user_id = $2)",
        )
        .bind(moderation_id)
        .bind(user_id)
        .fetch_one(&*self.db)
        .await?;

        if !moderation_exists {
            return Err(TrustSafetyError::ModerationLogNotFound(
                moderation_id.to_string(),
            ));
        }

        // Check if appeal already exists
        let existing_appeal = sqlx::query_as::<_, Appeal>(
            r#"
            SELECT id, moderation_id, user_id, reason,
                   status as "status: AppealStatus",
                   admin_id, admin_note, created_at, reviewed_at
            FROM appeals
            WHERE moderation_id = $1
            "#,
        )
        .bind(moderation_id)
        .fetch_optional(&*self.db)
        .await?;

        if let Some(appeal) = existing_appeal {
            return Err(TrustSafetyError::InvalidInput(format!(
                "Appeal already exists: {}",
                appeal.id
            )));
        }

        // Create new appeal
        let appeal = sqlx::query_as::<_, Appeal>(
            r#"
            INSERT INTO appeals (moderation_id, user_id, reason, status, created_at)
            VALUES ($1, $2, $3, 'pending', NOW())
            RETURNING id, moderation_id, user_id, reason,
                      status as "status: AppealStatus",
                      admin_id, admin_note, created_at, reviewed_at
            "#,
        )
        .bind(moderation_id)
        .bind(user_id)
        .bind(reason)
        .fetch_one(&*self.db)
        .await?;

        tracing::info!(
            appeal_id = %appeal.id,
            moderation_id = %moderation_id,
            user_id = %user_id,
            "Appeal submitted"
        );

        Ok(appeal)
    }

    /// Review an appeal (admin action)
    pub async fn review_appeal(
        &self,
        appeal_id: Uuid,
        admin_id: Uuid,
        decision: AppealStatus,
        admin_note: Option<&str>,
    ) -> Result<Appeal> {
        // Fetch current appeal
        let current_appeal = sqlx::query_as::<_, Appeal>(
            r#"
            SELECT id, moderation_id, user_id, reason,
                   status as "status: AppealStatus",
                   admin_id, admin_note, created_at, reviewed_at
            FROM appeals
            WHERE id = $1
            "#,
        )
        .bind(appeal_id)
        .fetch_optional(&*self.db)
        .await?
        .ok_or_else(|| TrustSafetyError::AppealNotFound(appeal_id.to_string()))?;

        // Validate state transition
        if !current_appeal.status.can_transition_to(decision) {
            return Err(TrustSafetyError::InvalidAppealStatusTransition {
                from: current_appeal.status.as_str().to_string(),
                to: decision.as_str().to_string(),
            });
        }

        // Update appeal
        let updated_appeal = sqlx::query_as::<_, Appeal>(
            r#"
            UPDATE appeals
            SET status = $1,
                reviewed_at = NOW(),
                admin_id = $2,
                admin_note = $3
            WHERE id = $4
            RETURNING id, moderation_id, user_id, reason,
                      status as "status: AppealStatus",
                      admin_id, admin_note, created_at, reviewed_at
            "#,
        )
        .bind(decision)
        .bind(admin_id)
        .bind(admin_note)
        .bind(appeal_id)
        .fetch_one(&*self.db)
        .await?;

        tracing::info!(
            appeal_id = %appeal_id,
            admin_id = %admin_id,
            decision = %decision.as_str(),
            "Appeal reviewed"
        );

        // If approved, update moderation log
        if decision == AppealStatus::Approved {
            sqlx::query("UPDATE moderation_logs SET approved = true WHERE id = $1")
                .bind(updated_appeal.moderation_id)
                .execute(&*self.db)
                .await?;

            tracing::info!(
                moderation_id = %updated_appeal.moderation_id,
                "Moderation decision overturned"
            );
        }

        Ok(updated_appeal)
    }

    /// Get appeal by ID
    pub async fn get_appeal(&self, appeal_id: Uuid) -> Result<Appeal> {
        let appeal = sqlx::query_as::<_, Appeal>(
            r#"
            SELECT id, moderation_id, user_id, reason,
                   status as "status: AppealStatus",
                   admin_id, admin_note, created_at, reviewed_at
            FROM appeals
            WHERE id = $1
            "#,
        )
        .bind(appeal_id)
        .fetch_optional(&*self.db)
        .await?
        .ok_or_else(|| TrustSafetyError::AppealNotFound(appeal_id.to_string()))?;

        Ok(appeal)
    }

    /// List appeals (with pagination)
    pub async fn list_appeals(
        &self,
        status: Option<AppealStatus>,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Appeal>> {
        let appeals = if let Some(status) = status {
            sqlx::query_as::<_, Appeal>(
                r#"
                SELECT id, moderation_id, user_id, reason,
                       status as "status: AppealStatus",
                       admin_id, admin_note, created_at, reviewed_at
                FROM appeals
                WHERE status = $1
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(status)
            .bind(limit)
            .bind(offset)
            .fetch_all(&*self.db)
            .await?
        } else {
            sqlx::query_as::<_, Appeal>(
                r#"
                SELECT id, moderation_id, user_id, reason,
                       status as "status: AppealStatus",
                       admin_id, admin_note, created_at, reviewed_at
                FROM appeals
                ORDER BY created_at DESC
                LIMIT $1 OFFSET $2
                "#,
            )
            .bind(limit)
            .bind(offset)
            .fetch_all(&*self.db)
            .await?
        };

        Ok(appeals)
    }

    /// Count total appeals
    pub async fn count_appeals(&self, status: Option<AppealStatus>) -> Result<i64> {
        let count = if let Some(status) = status {
            sqlx::query_scalar("SELECT COUNT(*) FROM appeals WHERE status = $1")
                .bind(status)
                .fetch_one(&*self.db)
                .await?
        } else {
            sqlx::query_scalar("SELECT COUNT(*) FROM appeals")
                .fetch_one(&*self.db)
                .await?
        };

        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: Integration tests would require a test database
    // These are placeholder unit tests

    #[test]
    fn test_appeal_status_validation() {
        assert!(AppealStatus::Pending.can_transition_to(AppealStatus::Approved));
        assert!(AppealStatus::Pending.can_transition_to(AppealStatus::Rejected));
        assert!(!AppealStatus::Approved.can_transition_to(AppealStatus::Pending));
    }
}

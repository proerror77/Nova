use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// Appeal status enum with state machine
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "appeal_status", rename_all = "lowercase")]
pub enum AppealStatus {
    Pending,
    Approved,
    Rejected,
}

impl AppealStatus {
    /// Validate state transition (pending -> approved/rejected only)
    pub fn can_transition_to(&self, new_status: AppealStatus) -> bool {
        matches!(
            (self, new_status),
            (AppealStatus::Pending, AppealStatus::Approved)
                | (AppealStatus::Pending, AppealStatus::Rejected)
        )
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            AppealStatus::Pending => "pending",
            AppealStatus::Approved => "approved",
            AppealStatus::Rejected => "rejected",
        }
    }
}

impl From<i32> for AppealStatus {
    fn from(value: i32) -> Self {
        match value {
            1 => AppealStatus::Pending,
            2 => AppealStatus::Approved,
            3 => AppealStatus::Rejected,
            _ => AppealStatus::Pending, // Default
        }
    }
}

/// Appeal record
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Appeal {
    pub id: Uuid,
    pub moderation_id: Uuid,
    pub user_id: Uuid,
    pub reason: String,
    pub status: AppealStatus,
    pub admin_id: Option<Uuid>,
    pub admin_note: Option<String>,
    pub created_at: DateTime<Utc>,
    pub reviewed_at: Option<DateTime<Utc>>,
}

impl Appeal {
    /// Create new pending appeal
    pub fn new(moderation_id: Uuid, user_id: Uuid, reason: String) -> Self {
        Self {
            id: Uuid::new_v4(),
            moderation_id,
            user_id,
            reason,
            status: AppealStatus::Pending,
            admin_id: None,
            admin_note: None,
            created_at: Utc::now(),
            reviewed_at: None,
        }
    }

    /// Review appeal (state transition)
    pub fn review(
        &mut self,
        admin_id: Uuid,
        decision: AppealStatus,
        admin_note: Option<String>,
    ) -> Result<(), String> {
        if !self.status.can_transition_to(decision) {
            return Err(format!(
                "Invalid transition: {} -> {}",
                self.status.as_str(),
                decision.as_str()
            ));
        }

        self.status = decision;
        self.admin_id = Some(admin_id);
        self.admin_note = admin_note;
        self.reviewed_at = Some(Utc::now());

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_appeal_status_transitions() {
        assert!(AppealStatus::Pending.can_transition_to(AppealStatus::Approved));
        assert!(AppealStatus::Pending.can_transition_to(AppealStatus::Rejected));
        assert!(!AppealStatus::Approved.can_transition_to(AppealStatus::Pending));
        assert!(!AppealStatus::Approved.can_transition_to(AppealStatus::Rejected));
        assert!(!AppealStatus::Rejected.can_transition_to(AppealStatus::Pending));
    }

    #[test]
    fn test_appeal_creation() {
        let appeal = Appeal::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            "I believe this was flagged incorrectly".to_string(),
        );
        assert_eq!(appeal.status, AppealStatus::Pending);
        assert!(appeal.admin_id.is_none());
    }

    #[test]
    fn test_appeal_review() {
        let mut appeal = Appeal::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            "Test reason".to_string(),
        );
        let admin_id = Uuid::new_v4();

        let result = appeal.review(
            admin_id,
            AppealStatus::Approved,
            Some("Approved after review".to_string()),
        );

        assert!(result.is_ok());
        assert_eq!(appeal.status, AppealStatus::Approved);
        assert_eq!(appeal.admin_id, Some(admin_id));
        assert!(appeal.reviewed_at.is_some());
    }

    #[test]
    fn test_invalid_appeal_transition() {
        let mut appeal = Appeal::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            "Test reason".to_string(),
        );
        appeal.status = AppealStatus::Approved;

        let result = appeal.review(
            Uuid::new_v4(),
            AppealStatus::Rejected,
            None,
        );

        assert!(result.is_err());
    }
}

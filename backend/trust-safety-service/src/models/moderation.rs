use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// Moderation result from text/image checks
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModerationResult {
    pub is_flagged: bool,
    pub violations: Vec<String>,
    pub reason: Option<String>,
}

impl ModerationResult {
    pub fn safe() -> Self {
        Self {
            is_flagged: false,
            violations: Vec::new(),
            reason: None,
        }
    }

    pub fn flagged(violation: &str, reason: impl Into<String>) -> Self {
        Self {
            is_flagged: true,
            violations: vec![violation.to_string()],
            reason: Some(reason.into()),
        }
    }

    pub fn with_violations(violations: Vec<String>, reason: impl Into<String>) -> Self {
        Self {
            is_flagged: !violations.is_empty(),
            violations,
            reason: Some(reason.into()),
        }
    }
}

/// Risk scores from moderation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskScore {
    pub nsfw_score: f32,
    pub toxicity_score: f32,
    pub spam_score: f32,
    pub overall_score: f32,
}

impl RiskScore {
    pub fn new(nsfw: f32, toxicity: f32, spam: f32) -> Self {
        let overall = (nsfw + toxicity + spam) / 3.0;
        Self {
            nsfw_score: nsfw,
            toxicity_score: toxicity,
            spam_score: spam,
            overall_score: overall,
        }
    }

    pub fn zero() -> Self {
        Self {
            nsfw_score: 0.0,
            toxicity_score: 0.0,
            spam_score: 0.0,
            overall_score: 0.0,
        }
    }
}

/// Moderation log stored in database
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ModerationLog {
    pub id: Uuid,
    pub content_id: String,
    pub content_type: String,
    pub user_id: Uuid,
    pub nsfw_score: f32,
    pub toxicity_score: f32,
    pub spam_score: f32,
    pub overall_score: f32,
    pub approved: bool,
    pub violations: Vec<String>,
    pub created_at: DateTime<Utc>,
}

/// Content type enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContentType {
    Post,
    Comment,
    Message,
    ProfileBio,
    ProfileName,
}

impl ContentType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ContentType::Post => "post",
            ContentType::Comment => "comment",
            ContentType::Message => "message",
            ContentType::ProfileBio => "profile_bio",
            ContentType::ProfileName => "profile_name",
        }
    }
}

impl From<i32> for ContentType {
    fn from(value: i32) -> Self {
        match value {
            1 => ContentType::Post,
            2 => ContentType::Comment,
            3 => ContentType::Message,
            4 => ContentType::ProfileBio,
            5 => ContentType::ProfileName,
            _ => ContentType::Post, // Default
        }
    }
}

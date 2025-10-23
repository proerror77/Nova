use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConversationType { Direct, Group }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PrivacyMode { StrictE2E, SearchEnabled }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: Uuid,
    pub kind: ConversationType,
    pub name: Option<String>,
    pub member_count: i32,
    pub privacy_mode: PrivacyMode,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}


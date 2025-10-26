pub mod conversation;
pub mod member;
pub mod message;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// Re-export for convenience
pub use member::MemberRole;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: Uuid,
    pub username: String,
    pub public_key: Option<String>,
    pub created_at: DateTime<Utc>,
}

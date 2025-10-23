pub mod conversation;
pub mod message;

use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: Uuid,
    pub username: String,
    pub public_key: Option<String>,
    pub created_at: DateTime<Utc>,
}

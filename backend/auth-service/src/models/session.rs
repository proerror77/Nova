/// Session model
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use sqlx::FromRow;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Session {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: String,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub os_name: Option<String>,
    pub os_version: Option<String>,
    pub browser_name: Option<String>,
    pub browser_version: Option<String>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub location_country: Option<String>,
    pub location_city: Option<String>,
    pub access_token_jti: Option<String>,
    pub refresh_token_jti: Option<String>,
    pub last_activity_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub revoked_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Session {
    /// Check if session is still valid
    pub fn is_valid(&self) -> bool {
        self.revoked_at.is_none() && self.expires_at > Utc::now()
    }

    /// Check if session has expired
    pub fn is_expired(&self) -> bool {
        self.expires_at < Utc::now()
    }

    /// Check if session has been revoked
    pub fn is_revoked(&self) -> bool {
        self.revoked_at.is_some()
    }
}

#[derive(Debug, Deserialize)]
pub struct CreateSessionRequest {
    pub user_id: Option<Uuid>,
    pub device_id: String,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
}

// Admin model - used by AuthService when implementing real auth
#![allow(dead_code)]

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::middleware::AdminRole;

#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct Admin {
    pub id: Uuid,
    pub email: String,
    pub password_hash: String,
    pub name: String,
    pub role: String,
    pub avatar: Option<String>,
    pub status: String,
    pub login_attempts: i32,
    pub locked_until: Option<DateTime<Utc>>,
    pub permissions: serde_json::Value,
    pub last_login_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Admin {
    pub fn role(&self) -> AdminRole {
        match self.role.as_str() {
            "super_admin" => AdminRole::SuperAdmin,
            "admin" => AdminRole::Admin,
            _ => AdminRole::Moderator,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct CreateAdmin {
    pub email: String,
    pub password: String,
    pub name: String,
    pub role: String,
}

#[derive(Debug, Deserialize)]
pub struct UpdateAdmin {
    pub name: Option<String>,
    pub role: Option<String>,
    pub status: Option<String>,
    pub permissions: Option<serde_json::Value>,
}

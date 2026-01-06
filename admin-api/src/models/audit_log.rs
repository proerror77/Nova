// Audit log model - used by AuditService for operation logging
#![allow(dead_code)]

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct AuditLog {
    pub id: Uuid,
    pub admin_id: Uuid,
    pub action: String,
    pub resource_type: String,
    pub resource_id: Option<String>,
    pub details: Option<serde_json::Value>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug)]
pub struct CreateAuditLog {
    pub admin_id: Uuid,
    pub action: AuditAction,
    pub resource_type: ResourceType,
    pub resource_id: Option<String>,
    pub details: Option<serde_json::Value>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AuditAction {
    // Auth
    Login,
    Logout,
    // User management
    ViewUser,
    BanUser,
    UnbanUser,
    WarnUser,
    // Content moderation
    ViewContent,
    ApproveContent,
    RejectContent,
    RemoveContent,
    RestoreContent,
    ApprovePost,
    RejectPost,
    ApproveComment,
    RejectComment,
    // Admin management
    CreateAdmin,
    UpdateAdmin,
    DeleteAdmin,
}

impl AuditAction {
    pub fn as_str(&self) -> &'static str {
        match self {
            AuditAction::Login => "login",
            AuditAction::Logout => "logout",
            AuditAction::ViewUser => "view_user",
            AuditAction::BanUser => "ban_user",
            AuditAction::UnbanUser => "unban_user",
            AuditAction::WarnUser => "warn_user",
            AuditAction::ViewContent => "view_content",
            AuditAction::ApproveContent => "approve_content",
            AuditAction::RejectContent => "reject_content",
            AuditAction::RemoveContent => "remove_content",
            AuditAction::RestoreContent => "restore_content",
            AuditAction::ApprovePost => "approve_post",
            AuditAction::RejectPost => "reject_post",
            AuditAction::ApproveComment => "approve_comment",
            AuditAction::RejectComment => "reject_comment",
            AuditAction::CreateAdmin => "create_admin",
            AuditAction::UpdateAdmin => "update_admin",
            AuditAction::DeleteAdmin => "delete_admin",
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceType {
    Admin,
    User,
    Post,
    Comment,
    Session,
}

impl ResourceType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ResourceType::Admin => "admin",
            ResourceType::User => "user",
            ResourceType::Post => "post",
            ResourceType::Comment => "comment",
            ResourceType::Session => "session",
        }
    }
}

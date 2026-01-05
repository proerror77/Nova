// Audit service - will be wired into API handlers for operation logging
#![allow(dead_code)]

use uuid::Uuid;

use crate::db::Database;
use crate::error::Result;
use crate::models::{AuditLog, CreateAuditLog, ResourceType};

pub struct AuditService {
    db: Database,
}

impl AuditService {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    pub async fn log(&self, entry: CreateAuditLog) -> Result<AuditLog> {
        let log: AuditLog = sqlx::query_as(
            r#"
            INSERT INTO audit_logs (id, admin_id, action, resource_type, resource_id, details, ip_address, user_agent, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
            RETURNING *
            "#
        )
        .bind(Uuid::new_v4())
        .bind(entry.admin_id)
        .bind(entry.action.as_str())
        .bind(entry.resource_type.as_str())
        .bind(entry.resource_id)
        .bind(entry.details)
        .bind(entry.ip_address)
        .bind(entry.user_agent)
        .fetch_one(&self.db.pg)
        .await?;

        Ok(log)
    }

    pub async fn list_by_admin(&self, admin_id: Uuid, limit: i64, offset: i64) -> Result<Vec<AuditLog>> {
        let logs: Vec<AuditLog> = sqlx::query_as(
            "SELECT * FROM audit_logs WHERE admin_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3"
        )
        .bind(admin_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.db.pg)
        .await?;

        Ok(logs)
    }

    pub async fn list_by_resource(&self, resource_type: ResourceType, resource_id: &str, limit: i64) -> Result<Vec<AuditLog>> {
        let logs: Vec<AuditLog> = sqlx::query_as(
            "SELECT * FROM audit_logs WHERE resource_type = $1 AND resource_id = $2 ORDER BY created_at DESC LIMIT $3"
        )
        .bind(resource_type.as_str())
        .bind(resource_id)
        .bind(limit)
        .fetch_all(&self.db.pg)
        .await?;

        Ok(logs)
    }

    pub async fn list_recent(&self, limit: i64) -> Result<Vec<AuditLog>> {
        let logs: Vec<AuditLog> = sqlx::query_as(
            "SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT $1"
        )
        .bind(limit)
        .fetch_all(&self.db.pg)
        .await?;

        Ok(logs)
    }
}

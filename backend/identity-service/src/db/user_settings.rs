//! Database operations for user settings (P0: user-service migration)

use crate::error::IdentityError;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// User settings record from database
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct UserSettingsRecord {
    pub user_id: Uuid,
    pub dm_permission: String,
    pub email_notifications: bool,
    pub push_notifications: bool,
    pub marketing_emails: bool,
    pub timezone: String,
    pub language: String,
    pub dark_mode: bool,
    pub privacy_level: String,
    pub allow_messages: bool,
    pub show_online_status: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Fields that can be updated in user settings
#[derive(Debug, Default)]
pub struct UpdateUserSettingsFields {
    pub dm_permission: Option<String>,
    pub email_notifications: Option<bool>,
    pub push_notifications: Option<bool>,
    pub marketing_emails: Option<bool>,
    pub timezone: Option<String>,
    pub language: Option<String>,
    pub dark_mode: Option<bool>,
    pub privacy_level: Option<String>,
    pub allow_messages: Option<bool>,
    pub show_online_status: Option<bool>,
}

/// Get user settings by user ID (creates default if not exists)
pub async fn get_user_settings(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<UserSettingsRecord, IdentityError> {
    // Try to get existing settings
    let existing = sqlx::query_as::<_, UserSettingsRecord>(
        r#"
        SELECT user_id, dm_permission, email_notifications, push_notifications,
               marketing_emails, timezone, language, dark_mode, privacy_level,
               allow_messages, show_online_status, created_at, updated_at
        FROM user_settings
        WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    if let Some(settings) = existing {
        return Ok(settings);
    }

    // Create default settings if not exists (handles race condition)
    sqlx::query(
        r#"
        INSERT INTO user_settings (user_id)
        VALUES ($1)
        ON CONFLICT (user_id) DO NOTHING
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    // Fetch the newly created (or existing) settings
    sqlx::query_as::<_, UserSettingsRecord>(
        r#"
        SELECT user_id, dm_permission, email_notifications, push_notifications,
               marketing_emails, timezone, language, dark_mode, privacy_level,
               allow_messages, show_online_status, created_at, updated_at
        FROM user_settings
        WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))
}

/// Update user settings (partial update - only specified fields)
pub async fn update_user_settings(
    pool: &PgPool,
    user_id: Uuid,
    fields: UpdateUserSettingsFields,
) -> Result<UserSettingsRecord, IdentityError> {
    // Ensure settings exist first (creates default if not)
    ensure_settings_exist(pool, user_id).await?;

    // Build dynamic update query
    let mut set_clauses = Vec::new();
    let mut param_idx = 2; // $1 is user_id

    if fields.dm_permission.is_some() {
        set_clauses.push(format!("dm_permission = ${}", param_idx));
        param_idx += 1;
    }
    if fields.email_notifications.is_some() {
        set_clauses.push(format!("email_notifications = ${}", param_idx));
        param_idx += 1;
    }
    if fields.push_notifications.is_some() {
        set_clauses.push(format!("push_notifications = ${}", param_idx));
        param_idx += 1;
    }
    if fields.marketing_emails.is_some() {
        set_clauses.push(format!("marketing_emails = ${}", param_idx));
        param_idx += 1;
    }
    if fields.timezone.is_some() {
        set_clauses.push(format!("timezone = ${}", param_idx));
        param_idx += 1;
    }
    if fields.language.is_some() {
        set_clauses.push(format!("language = ${}", param_idx));
        param_idx += 1;
    }
    if fields.dark_mode.is_some() {
        set_clauses.push(format!("dark_mode = ${}", param_idx));
        param_idx += 1;
    }
    if fields.privacy_level.is_some() {
        set_clauses.push(format!("privacy_level = ${}", param_idx));
        param_idx += 1;
    }
    if fields.allow_messages.is_some() {
        set_clauses.push(format!("allow_messages = ${}", param_idx));
        param_idx += 1;
    }
    if fields.show_online_status.is_some() {
        set_clauses.push(format!("show_online_status = ${}", param_idx));
        // param_idx += 1; // Last one, not needed
    }

    // If no fields to update, just return current settings
    if set_clauses.is_empty() {
        return get_user_settings(pool, user_id).await;
    }

    // Always update updated_at
    set_clauses.push("updated_at = NOW()".to_string());

    let query = format!(
        r#"
        UPDATE user_settings
        SET {}
        WHERE user_id = $1
        RETURNING user_id, dm_permission, email_notifications, push_notifications,
                  marketing_emails, timezone, language, dark_mode, privacy_level,
                  allow_messages, show_online_status, created_at, updated_at
        "#,
        set_clauses.join(", ")
    );

    // Build query with parameters
    let mut query_builder = sqlx::query_as::<_, UserSettingsRecord>(&query).bind(user_id);

    if let Some(v) = &fields.dm_permission {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = fields.email_notifications {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = fields.push_notifications {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = fields.marketing_emails {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = &fields.timezone {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = &fields.language {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = fields.dark_mode {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = &fields.privacy_level {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = fields.allow_messages {
        query_builder = query_builder.bind(v);
    }
    if let Some(v) = fields.show_online_status {
        query_builder = query_builder.bind(v);
    }

    query_builder
        .fetch_one(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))
}

/// Ensure user settings exist (creates default if not)
async fn ensure_settings_exist(pool: &PgPool, user_id: Uuid) -> Result<(), IdentityError> {
    sqlx::query(
        r#"
        INSERT INTO user_settings (user_id)
        VALUES ($1)
        ON CONFLICT (user_id) DO NOTHING
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;
    Ok(())
}

/// Get DM permission for a user (helper for messaging checks)
pub async fn get_dm_permission(pool: &PgPool, user_id: Uuid) -> Result<String, IdentityError> {
    let result = sqlx::query_scalar::<_, String>(
        r#"
        SELECT dm_permission
        FROM user_settings
        WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    // Return default if not found
    // P1: Default to "mutuals" (more restrictive) for security
    Ok(result.unwrap_or_else(|| "mutuals".to_string()))
}

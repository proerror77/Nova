use crate::error::{IdentityError, Result};
use crate::models::session::Session;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct DeviceRecord {
    pub device_id: String,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub os_name: Option<String>,
    pub os_version: Option<String>,
    pub last_activity_at: DateTime<Utc>,
}

fn map_session_to_device(session: &Session) -> DeviceRecord {
    DeviceRecord {
        device_id: session.device_id.clone(),
        device_name: session.device_name.clone(),
        device_type: session.device_type.clone(),
        os_name: session.os_name.clone(),
        os_version: session.os_version.clone(),
        last_activity_at: session.last_activity_at,
    }
}

/// List active devices for a user ordered by last activity
pub async fn list_devices(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<(Vec<DeviceRecord>, i64)> {
    let sessions = sqlx::query_as::<_, Session>(
        r#"
        SELECT id, user_id, device_id, device_name, device_type,
               os_name, os_version, browser_name, browser_version,
               ip_address, user_agent, location_country, location_city,
               access_token_jti, refresh_token_jti, last_activity_at,
               expires_at, revoked_at, created_at, updated_at
        FROM sessions
        WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > NOW()
        ORDER BY last_activity_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(user_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    let total = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM sessions WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > NOW()",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok((sessions.iter().map(map_session_to_device).collect(), total))
}

/// Revoke sessions for a user by device_id or all
pub async fn logout_device(
    pool: &PgPool,
    user_id: Uuid,
    device_id: Option<&str>,
    all: bool,
) -> Result<u64> {
    let now = Utc::now();
    let rows = if all {
        sqlx::query(
            "UPDATE sessions SET revoked_at = $2, updated_at = $2 WHERE user_id = $1 AND revoked_at IS NULL",
        )
        .bind(user_id)
        .bind(now)
        .execute(pool)
        .await
    } else if let Some(id) = device_id {
        sqlx::query(
            "UPDATE sessions SET revoked_at = $3, updated_at = $3 WHERE user_id = $1 AND device_id = $2 AND revoked_at IS NULL",
        )
        .bind(user_id)
        .bind(id)
        .bind(now)
        .execute(pool)
        .await
    } else {
        // nothing to do
        return Ok(0);
    }
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(rows.rows_affected())
}

/// Get the most recent active device or a specific device
pub async fn get_current_device(
    pool: &PgPool,
    user_id: Uuid,
    device_id: Option<&str>,
) -> Result<Option<DeviceRecord>> {
    let session_opt = if let Some(id) = device_id {
        sqlx::query_as::<_, Session>(
            r#"
            SELECT id, user_id, device_id, device_name, device_type,
                   os_name, os_version, browser_name, browser_version,
                   ip_address, user_agent, location_country, location_city,
                   access_token_jti, refresh_token_jti, last_activity_at,
                   expires_at, revoked_at, created_at, updated_at
            FROM sessions
            WHERE user_id = $1 AND device_id = $2 AND revoked_at IS NULL AND expires_at > NOW()
            ORDER BY last_activity_at DESC
            LIMIT 1
            "#,
        )
        .bind(user_id)
        .bind(id)
        .fetch_optional(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?
    } else {
        sqlx::query_as::<_, Session>(
            r#"
            SELECT id, user_id, device_id, device_name, device_type,
                   os_name, os_version, browser_name, browser_version,
                   ip_address, user_agent, location_country, location_city,
                   access_token_jti, refresh_token_jti, last_activity_at,
                   expires_at, revoked_at, created_at, updated_at
            FROM sessions
            WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > NOW()
            ORDER BY last_activity_at DESC
            LIMIT 1
            "#,
        )
        .bind(user_id)
        .fetch_optional(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?
    };

    Ok(session_opt.map(|s| map_session_to_device(&s)))
}

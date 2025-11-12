/// Session database operations
use crate::error::{IdentityError, Result};
use crate::models::session::Session;
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

/// Create a new session
pub async fn create_session(
    pool: &PgPool,
    user_id: Uuid,
    device_id: &str,
    device_name: Option<&str>,
    device_type: Option<&str>,
    os_name: Option<&str>,
    os_version: Option<&str>,
    browser_name: Option<&str>,
    browser_version: Option<&str>,
    ip_address: Option<&str>,
    user_agent: Option<&str>,
    location_country: Option<&str>,
    location_city: Option<&str>,
) -> Result<Session> {
    let session_id = Uuid::new_v4();
    let now = Utc::now();
    let expires_at = now + chrono::Duration::days(30);

    let session = sqlx::query_as::<_, Session>(
        r#"
        INSERT INTO sessions (
            id, user_id, device_id, device_name, device_type,
            os_name, os_version, browser_name, browser_version,
            ip_address, user_agent, location_country, location_city,
            last_activity_at, expires_at, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
        RETURNING id, user_id, device_id, device_name, device_type,
                  os_name, os_version, browser_name, browser_version,
                  ip_address, user_agent, location_country, location_city,
                  access_token_jti, refresh_token_jti, last_activity_at,
                  expires_at, revoked_at, created_at, updated_at
        "#,
    )
    .bind(session_id)
    .bind(user_id)
    .bind(device_id)
    .bind(device_name)
    .bind(device_type)
    .bind(os_name)
    .bind(os_version)
    .bind(browser_name)
    .bind(browser_version)
    .bind(ip_address)
    .bind(user_agent)
    .bind(location_country)
    .bind(location_city)
    .bind(now)
    .bind(expires_at)
    .bind(now)
    .bind(now)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(session)
}

/// Get session by ID
pub async fn get_session(pool: &PgPool, session_id: Uuid) -> Result<Option<Session>> {
    let session = sqlx::query_as::<_, Session>(
        r#"
        SELECT id, user_id, device_id, device_name, device_type,
               os_name, os_version, browser_name, browser_version,
               ip_address, user_agent, location_country, location_city,
               access_token_jti, refresh_token_jti, last_activity_at,
               expires_at, revoked_at, created_at, updated_at
        FROM sessions
        WHERE id = $1
        "#,
    )
    .bind(session_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(session)
}

/// Revoke a session
pub async fn revoke_session(pool: &PgPool, session_id: Uuid) -> Result<()> {
    let now = Utc::now();

    sqlx::query(
        r#"
        UPDATE sessions
        SET revoked_at = $1, updated_at = $2
        WHERE id = $3
        "#,
    )
    .bind(now)
    .bind(now)
    .bind(session_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(())
}

/// List all valid sessions for a user
pub async fn list_sessions(pool: &PgPool, user_id: Uuid) -> Result<Vec<Session>> {
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
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(sessions)
}

/// Update session last activity timestamp
pub async fn update_last_activity(pool: &PgPool, session_id: Uuid) -> Result<()> {
    let now = Utc::now();

    sqlx::query(
        r#"
        UPDATE sessions
        SET last_activity_at = $1, updated_at = $2
        WHERE id = $3
        "#,
    )
    .bind(now)
    .bind(now)
    .bind(session_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(())
}

/// Store JWT ID tokens for a session
pub async fn store_jwt_ids(
    pool: &PgPool,
    session_id: Uuid,
    access_token_jti: &str,
    refresh_token_jti: &str,
) -> Result<()> {
    let now = Utc::now();

    sqlx::query(
        r#"
        UPDATE sessions
        SET access_token_jti = $1, refresh_token_jti = $2, updated_at = $3
        WHERE id = $4
        "#,
    )
    .bind(access_token_jti)
    .bind(refresh_token_jti)
    .bind(now)
    .bind(session_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(())
}

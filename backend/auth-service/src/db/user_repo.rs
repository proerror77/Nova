use crate::error::{AuthError, Result};
use crate::models::User;
use sqlx::PgPool;
use uuid::Uuid;

/// Create a new user
pub async fn create_user(
    pool: &PgPool,
    email: &str,
    username: &str,
    password_hash: &str,
) -> Result<User> {
    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, email, username, password_hash, email_verified, is_active, failed_login_attempts, created_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, $3, false, true, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        RETURNING *
        "#,
    )
    .bind(email)
    .bind(username)
    .bind(password_hash)
    .fetch_one(pool)
    .await
    .map_err(|e| {
        if e.to_string().contains("unique constraint") {
            AuthError::EmailAlreadyExists
        } else {
            AuthError::Database(e.to_string())
        }
    })?;

    Ok(user)
}

/// Get user by email
pub async fn get_user_by_email(pool: &PgPool, email: &str) -> Result<User> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT * FROM users WHERE email = $1
        "#,
    )
    .bind(email)
    .fetch_one(pool)
    .await
    .map_err(|_| AuthError::UserNotFound)
}

/// Get user by ID
pub async fn get_user_by_id(pool: &PgPool, user_id: Uuid) -> Result<User> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT * FROM users WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|_| AuthError::UserNotFound)
}

/// Get user by username
pub async fn get_user_by_username(pool: &PgPool, username: &str) -> Result<User> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT * FROM users WHERE username = $1
        "#,
    )
    .bind(username)
    .fetch_one(pool)
    .await
    .map_err(|_| AuthError::UserNotFound)
}

/// Verify user's email
pub async fn verify_user_email(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users SET email_verified = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Update last login timestamp
pub async fn update_last_login(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users SET last_login_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Update password hash
pub async fn update_password(pool: &PgPool, user_id: Uuid, password_hash: &str) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2
        "#,
    )
    .bind(password_hash)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Increment failed login attempts
pub async fn increment_failed_attempts(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users SET failed_login_attempts = failed_login_attempts + 1, updated_at = CURRENT_TIMESTAMP WHERE id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Reset failed login attempts
pub async fn reset_failed_attempts(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users SET failed_login_attempts = 0, locked_until = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Lock user account until specified time
pub async fn lock_user_account(
    pool: &PgPool,
    user_id: Uuid,
    locked_until: chrono::DateTime<chrono::Utc>,
) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users SET locked_until = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2
        "#,
    )
    .bind(locked_until)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

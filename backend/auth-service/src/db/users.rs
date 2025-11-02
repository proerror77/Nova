/// User database operations
use crate::error::AuthResult;
use crate::models::User;
use sqlx::PgPool;
use uuid::Uuid;

/// Find user by email (excluding soft-deleted users)
pub async fn find_by_email(pool: &PgPool, email: &str) -> AuthResult<Option<User>> {
    let user =
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL")
            .bind(email)
            .fetch_optional(pool)
            .await
            .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(user)
}

/// Find user by ID (excluding soft-deleted users)
pub async fn find_by_id(pool: &PgPool, user_id: Uuid) -> AuthResult<Option<User>> {
    let user =
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL")
            .bind(user_id)
            .fetch_optional(pool)
            .await
            .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(user)
}

/// Create a new user
pub async fn create_user(
    pool: &PgPool,
    email: &str,
    username: &str,
    password_hash: &str,
) -> AuthResult<User> {
    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, email, username, password_hash, email_verified, totp_enabled, totp_verified, created_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, $3, false, false, false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        RETURNING *
        "#
    )
    .bind(email)
    .bind(username)
    .bind(password_hash)
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(user)
}

/// Check if email exists (excluding soft-deleted users)
pub async fn email_exists(pool: &PgPool, email: &str) -> AuthResult<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND deleted_at IS NULL)",
    )
    .bind(email)
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(exists)
}

/// Check if username exists (excluding soft-deleted users)
pub async fn username_exists(pool: &PgPool, username: &str) -> AuthResult<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND deleted_at IS NULL)",
    )
    .bind(username)
    .fetch_one(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(exists)
}

/// Verify email for user
pub async fn verify_email(pool: &PgPool, user_id: Uuid) -> AuthResult<()> {
    sqlx::query(
        "UPDATE users SET email_verified = true, email_verified_at = CURRENT_TIMESTAMP WHERE id = $1"
    )
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Record successful login
pub async fn record_successful_login(pool: &PgPool, user_id: Uuid) -> AuthResult<()> {
    sqlx::query(
        "UPDATE users SET last_login_at = CURRENT_TIMESTAMP, failed_login_attempts = 0 WHERE id = $1"
    )
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Record failed login attempt and lock account if needed
pub async fn record_failed_login(
    pool: &PgPool,
    user_id: Uuid,
    max_attempts: i32,
    lock_duration_secs: i64,
) -> AuthResult<()> {
    let lock_until = if max_attempts > 0 {
        format!(
            "CURRENT_TIMESTAMP + INTERVAL '{} seconds'",
            lock_duration_secs
        )
    } else {
        "NULL".to_string()
    };

    let query = format!(
        r#"
        UPDATE users
        SET failed_login_attempts = failed_login_attempts + 1,
            locked_until = CASE
                WHEN failed_login_attempts + 1 >= $2 THEN {}
                ELSE locked_until
            END
        WHERE id = $1
        "#,
        lock_until
    );

    sqlx::query(&query)
        .bind(user_id)
        .bind(max_attempts)
        .execute(pool)
        .await
        .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Enable TOTP 2FA
pub async fn enable_totp(pool: &PgPool, user_id: Uuid, secret: &str) -> AuthResult<()> {
    sqlx::query("UPDATE users SET totp_enabled = true, totp_secret = $1 WHERE id = $2")
        .bind(secret)
        .bind(user_id)
        .execute(pool)
        .await
        .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Verify TOTP secret
pub async fn verify_totp(pool: &PgPool, user_id: Uuid) -> AuthResult<()> {
    sqlx::query("UPDATE users SET totp_verified = true WHERE id = $1")
        .bind(user_id)
        .execute(pool)
        .await
        .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

/// Update password hash and clear failed login attempts
pub async fn update_password(pool: &PgPool, user_id: Uuid, password_hash: &str) -> AuthResult<()> {
    sqlx::query(
        r#"
        UPDATE users
        SET password_hash = $1,
            last_password_change_at = CURRENT_TIMESTAMP,
            failed_login_attempts = 0,
            locked_until = NULL
        WHERE id = $2
        "#,
    )
    .bind(password_hash)
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| crate::error::AuthError::Database(e.to_string()))?;

    Ok(())
}

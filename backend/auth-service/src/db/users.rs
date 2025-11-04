/// User database operations
use crate::error::{AuthError, AuthResult};
use crate::models::User;
use chrono::{DateTime, Utc};
use serde_json::json;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

/// Lightweight projection for profile-centric views
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct UserProfileRecord {
    pub id: Uuid,
    pub username: String,
    pub email: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_photo_url: Option<String>,
    pub location: Option<String>,
    pub private_account: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Optional fields for profile updates (single writer via auth-service)
#[derive(Debug, Default)]
pub struct UpdateUserProfileFields {
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_photo_url: Option<String>,
    pub location: Option<String>,
    pub private_account: Option<bool>,
}

/// Find user by email (excluding soft-deleted users)
pub async fn find_by_email(pool: &PgPool, email: &str) -> AuthResult<Option<User>> {
    let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL")
        .bind(email)
        .fetch_optional(pool)
        .await?;

    Ok(user)
}

/// Find user by ID (excluding soft-deleted users)
pub async fn find_by_id(pool: &PgPool, user_id: Uuid) -> AuthResult<Option<User>> {
    let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL")
        .bind(user_id)
        .fetch_optional(pool)
        .await?;

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
    .await?;

    Ok(user)
}

/// Retrieve profile snapshot for a given user
pub async fn get_user_profile(
    pool: &PgPool,
    user_id: Uuid,
) -> AuthResult<Option<UserProfileRecord>> {
    let profile = sqlx::query_as::<_, UserProfileRecord>(
        r#"
        SELECT
            id,
            username,
            email,
            display_name,
            bio,
            avatar_url,
            cover_photo_url,
            location,
            COALESCE(private_account, FALSE) AS private_account,
            created_at,
            updated_at
        FROM users
        WHERE id = $1 AND deleted_at IS NULL
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    Ok(profile)
}

/// Update profile fields in a single writer service (auth-service)
pub async fn update_user_profile(
    pool: &PgPool,
    user_id: Uuid,
    fields: UpdateUserProfileFields,
) -> AuthResult<UserProfileRecord> {
    let now = Utc::now();

    let profile = sqlx::query_as::<_, UserProfileRecord>(
        r#"
        UPDATE users
        SET
            display_name = COALESCE($2, display_name),
            bio = COALESCE($3, bio),
            avatar_url = COALESCE($4, avatar_url),
            cover_photo_url = COALESCE($5, cover_photo_url),
            location = COALESCE($6, location),
            private_account = COALESCE($7, private_account),
            updated_at = $8
        WHERE id = $1
        RETURNING
            id,
            username,
            email,
            display_name,
            bio,
            avatar_url,
            cover_photo_url,
            location,
            COALESCE(private_account, FALSE) AS private_account,
            created_at,
            updated_at
        "#,
    )
    .bind(user_id)
    .bind(fields.display_name)
    .bind(fields.bio)
    .bind(fields.avatar_url)
    .bind(fields.cover_photo_url)
    .bind(fields.location)
    .bind(fields.private_account)
    .bind(now)
    .fetch_one(pool)
    .await
    .map_err(|e| {
        tracing::error!(user_id=%user_id, error=%e, "Failed to update user profile");
        e.into()
    })?;

    Ok(profile)
}

/// Upsert a user's public key used for end-to-end encryption flows
pub async fn upsert_user_public_key(
    pool: &PgPool,
    user_id: Uuid,
    public_key_b64: &str,
) -> AuthResult<()> {
    sqlx::query(
        r#"
        UPDATE users
        SET public_key = $2, updated_at = CURRENT_TIMESTAMP
        WHERE id = $1 AND deleted_at IS NULL
        "#,
    )
    .bind(user_id)
    .bind(public_key_b64)
    .execute(pool)
    .await?;

    Ok(())
}

/// Fetch a user's public key if present
pub async fn get_user_public_key(pool: &PgPool, user_id: Uuid) -> AuthResult<Option<String>> {
    let public_key = sqlx::query_scalar::<_, Option<String>>(
        "SELECT public_key FROM users WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    Ok(public_key)
}

async fn insert_outbox_event(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    deleted_at: DateTime<Utc>,
    deleted_by: Option<Uuid>,
) -> AuthResult<()> {
    let payload = json!({
        "user_id": user_id,
        "deleted_at": deleted_at,
        "deleted_by": deleted_by,
    });

    sqlx::query(
        r#"
        INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind("User")
    .bind(user_id)
    .bind("UserDeleted")
    .bind(payload)
    .execute(tx.as_mut())
    .await?;

    Ok(())
}

/// Soft delete user (GDPR) and enqueue outbox event for downstream services
pub async fn soft_delete_user(
    pool: &PgPool,
    user_id: Uuid,
    deleted_by: Option<Uuid>,
) -> AuthResult<DateTime<Utc>> {
    let deleted_at = Utc::now();
    let mut tx = pool.begin().await?;

    let result = sqlx::query(
        r#"
        UPDATE users
        SET deleted_at = $2,
            deleted_by = $3,
            is_active = FALSE,
            updated_at = $2
        WHERE id = $1 AND (deleted_at IS NULL OR deleted_at > $2)
        "#,
    )
    .bind(user_id)
    .bind(deleted_at)
    .bind(deleted_by)
    .execute(tx.as_mut())
    .await?;

    if result.rows_affected() == 0 {
        tx.rollback().await?;
        return Err(AuthError::UserNotFound);
    }

    // Emit outbox event for messaging-service to handle message deletion asynchronously
    // This maintains service boundary: auth-service only manages users, messaging-service manages messages
    insert_outbox_event(&mut tx, user_id, deleted_at, deleted_by).await?;

    tx.commit()
        .await?;

    Ok(deleted_at)
}

/// Check if email exists (excluding soft-deleted users)
pub async fn email_exists(pool: &PgPool, email: &str) -> AuthResult<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND deleted_at IS NULL)",
    )
    .bind(email)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

/// Check if username exists (excluding soft-deleted users)
pub async fn username_exists(pool: &PgPool, username: &str) -> AuthResult<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND deleted_at IS NULL)",
    )
    .bind(username)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

/// Verify email for user
pub async fn verify_email(pool: &PgPool, user_id: Uuid) -> AuthResult<()> {
    sqlx::query(
        "UPDATE users SET email_verified = true, email_verified_at = CURRENT_TIMESTAMP WHERE id = $1"
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Record successful login
pub async fn record_successful_login(pool: &PgPool, user_id: Uuid) -> AuthResult<()> {
    sqlx::query(
        "UPDATE users SET last_login_at = CURRENT_TIMESTAMP, failed_login_attempts = 0 WHERE id = $1"
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Record failed login attempt and lock account if needed
pub async fn record_failed_login(
    pool: &PgPool,
    user_id: Uuid,
    max_attempts: i32,
    lock_duration_secs: i64,
) -> AuthResult<()> {
    // Use parameterized query to prevent SQL injection
    // The lock_until is calculated using PostgreSQL interval arithmetic
    sqlx::query(
        r#"
        UPDATE users
        SET failed_login_attempts = failed_login_attempts + 1,
            locked_until = CASE
                WHEN $2 > 0 AND failed_login_attempts + 1 >= $2
                THEN CURRENT_TIMESTAMP + ($3 || ' seconds')::interval
                ELSE locked_until
            END
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .bind(max_attempts)
    .bind(lock_duration_secs.to_string())
    .execute(pool)
    .await?;

    Ok(())
}

/// Enable TOTP 2FA
pub async fn enable_totp(pool: &PgPool, user_id: Uuid, secret: &str) -> AuthResult<()> {
    sqlx::query("UPDATE users SET totp_enabled = true, totp_secret = $1 WHERE id = $2")
        .bind(secret)
        .bind(user_id)
        .execute(pool)
        .await?;

    Ok(())
}

/// Verify TOTP secret
pub async fn verify_totp(pool: &PgPool, user_id: Uuid) -> AuthResult<()> {
    sqlx::query("UPDATE users SET totp_verified = true WHERE id = $1")
        .bind(user_id)
        .execute(pool)
        .await?;

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
    .await?;

    Ok(())
}

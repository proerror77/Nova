/// User database operations for identity-service
use crate::error::{IdentityError, Result};
use crate::models::user::Gender;
use crate::models::User;
use chrono::{DateTime, NaiveDate, Utc};
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
    // Extended profile fields
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub gender: Option<Gender>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Optional fields for profile updates (single writer via identity-service)
#[derive(Debug, Default)]
pub struct UpdateUserProfileFields {
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_photo_url: Option<String>,
    pub location: Option<String>,
    pub private_account: Option<bool>,
    // Extended profile fields
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub gender: Option<Gender>,
}

async fn insert_identity_outbox_event(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    event_type: &str,
    payload: serde_json::Value,
) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
        VALUES ($1, $2, $3, $4)
        "#,
    )
    .bind("identity")
    .bind(user_id.to_string())
    .bind(event_type)
    .bind(payload)
    .execute(tx.as_mut())
    .await?;

    Ok(())
}

/// Find user by email (excluding soft-deleted users)
pub async fn find_by_email(pool: &PgPool, email: &str) -> Result<Option<User>> {
    let user =
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL")
            .bind(email)
            .fetch_optional(pool)
            .await?;

    Ok(user)
}

/// Find user by username (excluding soft-deleted users)
pub async fn find_by_username(pool: &PgPool, username: &str) -> Result<Option<User>> {
    let user =
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE username = $1 AND deleted_at IS NULL")
            .bind(username)
            .fetch_optional(pool)
            .await?;

    Ok(user)
}

/// Find user by email or username (excluding soft-deleted users)
/// This function supports login with either email or username
pub async fn find_by_email_or_username(pool: &PgPool, identifier: &str) -> Result<Option<User>> {
    let user = sqlx::query_as::<_, User>(
        "SELECT * FROM users WHERE (email = $1 OR username = $1) AND deleted_at IS NULL",
    )
    .bind(identifier)
    .fetch_optional(pool)
    .await?;

    Ok(user)
}

/// Find user by ID (excluding soft-deleted users)
pub async fn find_by_id(pool: &PgPool, user_id: Uuid) -> Result<Option<User>> {
    let user =
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL")
            .bind(user_id)
            .fetch_optional(pool)
            .await?;

    Ok(user)
}

/// Batch find users by IDs (for gRPC GetUsersByIds RPC)
pub async fn find_by_ids(pool: &PgPool, user_ids: &[Uuid]) -> Result<Vec<User>> {
    let users =
        sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = ANY($1) AND deleted_at IS NULL")
            .bind(user_ids)
            .fetch_all(pool)
            .await?;

    Ok(users)
}

/// Batch find users by usernames (for @mention resolution)
/// Returns a map of username -> user_id for found users
pub async fn find_by_usernames(
    pool: &PgPool,
    usernames: &[String],
) -> Result<std::collections::HashMap<String, Uuid>> {
    if usernames.is_empty() {
        return Ok(std::collections::HashMap::new());
    }

    // Limit to 100 usernames to prevent abuse
    let usernames_to_query: Vec<&str> = usernames
        .iter()
        .take(100)
        .map(|s| s.as_str())
        .collect();

    let rows: Vec<(String, Uuid)> = sqlx::query_as(
        "SELECT LOWER(username), id FROM users WHERE LOWER(username) = ANY($1) AND deleted_at IS NULL",
    )
    .bind(&usernames_to_query)
    .fetch_all(pool)
    .await?;

    let result: std::collections::HashMap<String, Uuid> = rows.into_iter().collect();
    Ok(result)
}

/// Create a new user
pub async fn create_user(
    pool: &PgPool,
    email: &str,
    username: &str,
    password_hash: &str,
    display_name: Option<&str>,
) -> Result<User> {
    let mut tx = pool.begin().await?;

    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, email, username, password_hash, display_name, email_verified, totp_enabled, totp_verified, created_at, updated_at)
        VALUES (uuid_generate_v4(), $1, $2, $3, $4, false, false, false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        RETURNING *
        "#
    )
    .bind(email)
    .bind(username)
    .bind(password_hash)
    .bind(display_name)
    .fetch_one(&mut *tx)
    .await?;

    let payload = json!({
        "user_id": user.id,
        "email": user.email,
        "username": user.username,
        "created_at": user.created_at,
    });

    insert_identity_outbox_event(&mut tx, user.id, "identity.user.created", payload).await?;

    tx.commit().await?;

    Ok(user)
}

/// Retrieve profile snapshot for a given user
pub async fn get_user_profile(pool: &PgPool, user_id: Uuid) -> Result<Option<UserProfileRecord>> {
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
            first_name,
            last_name,
            date_of_birth,
            gender,
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

/// Update profile fields (single writer via identity-service)
pub async fn update_user_profile(
    pool: &PgPool,
    user_id: Uuid,
    fields: UpdateUserProfileFields,
) -> Result<UserProfileRecord> {
    let now = Utc::now();
    let mut tx = pool.begin().await?;

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
            first_name = COALESCE($8, first_name),
            last_name = COALESCE($9, last_name),
            date_of_birth = COALESCE($10, date_of_birth),
            gender = COALESCE($11, gender),
            updated_at = $12
        WHERE id = $1 AND deleted_at IS NULL
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
            first_name,
            last_name,
            date_of_birth,
            gender,
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
    .bind(fields.first_name)
    .bind(fields.last_name)
    .bind(fields.date_of_birth)
    .bind(fields.gender)
    .bind(now)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(user_id=%user_id, error=%e, "Failed to update user profile");
        IdentityError::from(e)
    })?;

    let payload = json!({
        "user_id": profile.id,
        "username": profile.username,
        "display_name": profile.display_name,
        "bio": profile.bio,
        "avatar_url": profile.avatar_url,
        "is_verified": false,
        "follower_count": 0,
        "updated_at": profile.updated_at,
    });

    insert_identity_outbox_event(
        &mut tx,
        profile.id,
        "identity.user.profile_updated",
        payload,
    )
    .await?;

    tx.commit().await?;

    Ok(profile)
}

/// Upsert a user's public key used for end-to-end encryption flows
pub async fn upsert_user_public_key(
    pool: &PgPool,
    user_id: Uuid,
    public_key_b64: &str,
) -> Result<()> {
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
pub async fn get_user_public_key(pool: &PgPool, user_id: Uuid) -> Result<Option<String>> {
    let public_key = sqlx::query_scalar::<_, Option<String>>(
        "SELECT public_key FROM users WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    Ok(public_key)
}

/// Soft delete user (GDPR) and enqueue outbox event for downstream services
pub async fn soft_delete_user(
    pool: &PgPool,
    user_id: Uuid,
    deleted_by: Option<Uuid>,
) -> Result<DateTime<Utc>> {
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
        return Err(IdentityError::UserNotFound);
    }

    let payload = json!({
        "user_id": user_id,
        "deleted_at": deleted_at,
        "soft_delete": true,
        "deleted_by": deleted_by,
    });

    insert_identity_outbox_event(&mut tx, user_id, "identity.user.deleted", payload).await?;

    tx.commit().await?;

    Ok(deleted_at)
}

/// Check if email exists (excluding soft-deleted users)
pub async fn email_exists(pool: &PgPool, email: &str) -> Result<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND deleted_at IS NULL)",
    )
    .bind(email)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

/// Check if username exists (excluding soft-deleted users)
pub async fn username_exists(pool: &PgPool, username: &str) -> Result<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND deleted_at IS NULL)",
    )
    .bind(username)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

/// Verify email for user
pub async fn verify_email(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        "UPDATE users SET email_verified = true, email_verified_at = CURRENT_TIMESTAMP WHERE id = $1"
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Record successful login
pub async fn record_successful_login(pool: &PgPool, user_id: Uuid) -> Result<()> {
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
) -> Result<User> {
    // Use parameterized query to prevent SQL injection
    // The lock_until is calculated using PostgreSQL interval arithmetic
    let user = sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET failed_login_attempts = failed_login_attempts + 1,
            locked_until = CASE
                WHEN $2 > 0 AND failed_login_attempts + 1 >= $2
                THEN CURRENT_TIMESTAMP + ($3 || ' seconds')::interval
                ELSE locked_until
            END
        WHERE id = $1
        RETURNING *
        "#,
    )
    .bind(user_id)
    .bind(max_attempts)
    .bind(lock_duration_secs.to_string())
    .fetch_one(pool)
    .await?;

    Ok(user)
}

/// Enable TOTP 2FA
pub async fn enable_totp(pool: &PgPool, user_id: Uuid, secret: &str) -> Result<()> {
    sqlx::query(
        "UPDATE users SET totp_enabled = true, totp_verified = false, totp_secret = $1 WHERE id = $2",
    )
    .bind(secret)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Verify TOTP secret
pub async fn verify_totp(pool: &PgPool, user_id: Uuid) -> Result<()> {
    let mut tx = pool.begin().await?;

    sqlx::query("UPDATE users SET totp_verified = true WHERE id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

    let payload = json!({
        "user_id": user_id,
        "enabled_at": Utc::now(),
        "method": "totp",
    });

    insert_identity_outbox_event(
        &mut tx,
        user_id,
        "identity.user.two_fa_enabled",
        payload,
    )
    .await?;

    tx.commit().await?;

    Ok(())
}

/// Disable TOTP and clear stored secret
pub async fn disable_totp(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        "UPDATE users SET totp_enabled = false, totp_verified = false, totp_secret = NULL WHERE id = $1",
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Update password hash and clear failed login attempts
pub async fn update_password(pool: &PgPool, user_id: Uuid, password_hash: &str) -> Result<()> {
    let mut tx = pool.begin().await?;

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
    .execute(&mut *tx)
    .await?;

    let payload = json!({
        "user_id": user_id,
        "changed_at": Utc::now(),
        "invalidate_all_sessions": true,
    });

    insert_identity_outbox_event(
        &mut tx,
        user_id,
        "identity.user.password_changed",
        payload,
    )
    .await?;

    tx.commit().await?;

    Ok(())
}

/// Reset failed login attempts after successful login or password reset
pub async fn reset_failed_login(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users
        SET failed_login_attempts = 0,
            locked_until = NULL
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// List users with pagination
pub async fn list_users(pool: &PgPool, limit: i64, offset: i64) -> Result<Vec<User>> {
    let users = sqlx::query_as::<_, User>(
        r#"
        SELECT *
        FROM users
        WHERE deleted_at IS NULL
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
        "#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(users)
}

/// Search users by email or username
pub async fn search_users(pool: &PgPool, query: &str, limit: i64) -> Result<Vec<User>> {
    let search_pattern = format!("%{}%", query);

    let users = sqlx::query_as::<_, User>(
        r#"
        SELECT *
        FROM users
        WHERE deleted_at IS NULL
          AND (email ILIKE $1 OR username ILIKE $1)
        ORDER BY created_at DESC
        LIMIT $2
        "#,
    )
    .bind(&search_pattern)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(users)
}

/// Find user by phone number (excluding soft-deleted users)
pub async fn find_by_phone(pool: &PgPool, phone_number: &str) -> Result<Option<User>> {
    let user = sqlx::query_as::<_, User>(
        "SELECT * FROM users WHERE phone_number = $1 AND deleted_at IS NULL",
    )
    .bind(phone_number)
    .fetch_optional(pool)
    .await?;

    Ok(user)
}

/// Check if phone number exists (excluding soft-deleted users)
pub async fn phone_exists(pool: &PgPool, phone_number: &str) -> Result<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE phone_number = $1 AND deleted_at IS NULL)",
    )
    .bind(phone_number)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

/// Create a new user with phone number (phone-based registration)
pub async fn create_user_with_phone(
    pool: &PgPool,
    phone_number: &str,
    username: &str,
    password_hash: &str,
    display_name: Option<&str>,
) -> Result<User> {
    // Generate a placeholder email for phone-registered users
    // This maintains database constraint compatibility while allowing phone-only registration
    let placeholder_email = format!("phone+{}@nova.local", phone_number.replace('+', ""));

    let mut tx = pool.begin().await?;

    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (
            id, email, username, password_hash, display_name,
            phone_number, phone_verified, email_verified,
            totp_enabled, totp_verified, private_account,
            failed_login_attempts, created_at, updated_at
        )
        VALUES (
            uuid_generate_v4(), $1, $2, $3, $4,
            $5, true, false,
            false, false, false,
            0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        RETURNING *
        "#,
    )
    .bind(&placeholder_email)
    .bind(username)
    .bind(password_hash)
    .bind(display_name)
    .bind(phone_number)
    .fetch_one(&mut *tx)
    .await?;

    let payload = json!({
        "user_id": user.id,
        "email": user.email,
        "username": user.username,
        "created_at": user.created_at,
    });

    insert_identity_outbox_event(&mut tx, user.id, "identity.user.created", payload).await?;

    tx.commit().await?;

    Ok(user)
}

/// Verify phone number for user
pub async fn verify_phone(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query("UPDATE users SET phone_verified = true WHERE id = $1")
        .bind(user_id)
        .execute(pool)
        .await?;

    Ok(())
}

/// Update user's phone number
pub async fn update_phone_number(
    pool: &PgPool,
    user_id: Uuid,
    phone_number: &str,
    verified: bool,
) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE users
        SET phone_number = $2, phone_verified = $3, updated_at = CURRENT_TIMESTAMP
        WHERE id = $1 AND deleted_at IS NULL
        "#,
    )
    .bind(user_id)
    .bind(phone_number)
    .bind(verified)
    .execute(pool)
    .await?;

    Ok(())
}

/// Create a new user via OAuth (social login)
pub async fn create_oauth_user(
    pool: &PgPool,
    email: &str,
    username: &str,
    oauth_provider: &str,
    oauth_provider_id: &str,
) -> Result<User> {
    let mut tx = pool.begin().await?;

    // Create user with empty password (OAuth users don't have passwords)
    let user = sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (email, username, password_hash, is_email_verified)
        VALUES ($1, $2, '', true)
        RETURNING *
        "#,
    )
    .bind(email)
    .bind(username)
    .fetch_one(&mut *tx)
    .await?;

    // Create OAuth connection record
    sqlx::query(
        r#"
        INSERT INTO oauth_connections (user_id, provider, provider_user_id, created_at)
        VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
        "#,
    )
    .bind(user.id)
    .bind(oauth_provider)
    .bind(oauth_provider_id)
    .execute(&mut *tx)
    .await?;

    let payload = json!({
        "user_id": user.id,
        "email": user.email,
        "username": user.username,
        "created_at": user.created_at,
    });

    insert_identity_outbox_event(&mut tx, user.id, "identity.user.created", payload).await?;

    tx.commit().await?;

    Ok(user)
}

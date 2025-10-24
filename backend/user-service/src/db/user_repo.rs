/// User repository - handles all database operations for users
use crate::models::User;
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

/// Create a new user in the database
pub async fn create_user(
    pool: &PgPool,
    email: &str,
    username: &str,
    password_hash: &str,
) -> Result<User, sqlx::Error> {
    let id = Uuid::new_v4();
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        INSERT INTO users (id, email, username, password_hash, email_verified, is_active, failed_login_attempts, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#
    )
    .bind(id)
    .bind(email.to_lowercase())
    .bind(username)
    .bind(password_hash)
    .bind(false)  // email_verified
    .bind(true)   // is_active
    .bind(0)      // failed_login_attempts
    .bind(now)    // created_at
    .bind(now)    // updated_at
    .fetch_one(pool)
    .await
}

/// Find a user by email
pub async fn find_by_email(pool: &PgPool, email: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        FROM users
        WHERE email = $1 AND deleted_at IS NULL
        "#
    )
    .bind(email.to_lowercase())
    .fetch_optional(pool)
    .await
}

/// Find a user by username
pub async fn find_by_username(pool: &PgPool, username: &str) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        FROM users
        WHERE username = $1 AND deleted_at IS NULL
        "#
    )
    .bind(username)
    .fetch_optional(pool)
    .await
}

/// Find a user by ID
pub async fn find_by_id(pool: &PgPool, id: Uuid) -> Result<Option<User>, sqlx::Error> {
    sqlx::query_as::<_, User>(
        r#"
        SELECT id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        FROM users
        WHERE id = $1 AND deleted_at IS NULL
        "#
    )
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// Update a user's public key for E2E messaging
pub async fn update_public_key(
    pool: &PgPool,
    user_id: Uuid,
    public_key_b64: &str,
) -> Result<(), sqlx::Error> {
    let now = Utc::now();
    sqlx::query(
        r#"
        UPDATE users
        SET public_key = $1, updated_at = $2
        WHERE id = $3
        "#,
    )
    .bind(public_key_b64)
    .bind(now)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Fetch a user's public key (if any)
pub async fn get_public_key(pool: &PgPool, user_id: Uuid) -> Result<Option<String>, sqlx::Error> {
    let row = sqlx::query_scalar::<_, Option<String>>(
        r#"
        SELECT public_key FROM users WHERE id = $1 AND deleted_at IS NULL
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;
    Ok(row)
}

/// Update a user's email verification status
pub async fn verify_email(pool: &PgPool, user_id: Uuid) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET email_verified = true, updated_at = $1
        WHERE id = $2
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#
    )
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Update a user's password
pub async fn update_password(
    pool: &PgPool,
    user_id: Uuid,
    new_password_hash: &str,
) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET password_hash = $1, updated_at = $2, failed_login_attempts = 0
        WHERE id = $3
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#
    )
    .bind(new_password_hash)
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Record a successful login
pub async fn record_successful_login(pool: &PgPool, user_id: Uuid) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET last_login_at = $1, failed_login_attempts = 0, locked_until = NULL, updated_at = $1
        WHERE id = $2
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#
    )
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Record a failed login attempt and lock account if threshold reached
///
/// # Arguments
/// * `max_allowed_attempts` - Maximum failed attempts before locking
/// * `lock_duration_secs` - Lock duration in seconds
pub async fn record_failed_login(
    pool: &PgPool,
    user_id: Uuid,
    max_allowed_attempts: i32,
    lock_duration_secs: i64,
) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    // Get current attempt count
    let current_attempts: i32 = sqlx::query_scalar(
        r#"
        SELECT failed_login_attempts FROM users WHERE id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    // Calculate new attempt count
    let new_attempts = current_attempts + 1;

    // Lock account if new_attempts >= max_attempts
    let lock_until = if max_allowed_attempts > 0 && new_attempts >= max_allowed_attempts {
        Some(now + chrono::Duration::seconds(lock_duration_secs))
    } else {
        None
    };

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET failed_login_attempts = $1, locked_until = $2, updated_at = $3
        WHERE id = $4
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#
    )
    .bind(new_attempts)
    .bind(lock_until)
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Soft delete a user (GDPR compliance)
/// Sets deleted_at timestamp and deactivates account
/// Note: email and username are NOT nullified to maintain referential integrity
pub async fn soft_delete(pool: &PgPool, user_id: Uuid) -> Result<(), sqlx::Error> {
    let now = Utc::now();

    sqlx::query(
        r#"
        UPDATE users
        SET deleted_at = $1, is_active = FALSE, updated_at = $1
        WHERE id = $2
        "#,
    )
    .bind(now)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Check if email is already taken
pub async fn email_exists(pool: &PgPool, email: &str) -> Result<bool, sqlx::Error> {
    let result = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(SELECT 1 FROM users WHERE email = $1 AND deleted_at IS NULL)
        "#,
    )
    .bind(email.to_lowercase())
    .fetch_one(pool)
    .await?;

    Ok(result)
}

/// Check if username is already taken
pub async fn username_exists(pool: &PgPool, username: &str) -> Result<bool, sqlx::Error> {
    let result = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND deleted_at IS NULL)
        "#,
    )
    .bind(username)
    .fetch_one(pool)
    .await?;

    Ok(result)
}

/// Enable TOTP-based 2FA for a user
pub async fn enable_totp(
    pool: &PgPool,
    user_id: Uuid,
    totp_secret: &str,
) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET totp_secret = $1, totp_enabled = true, two_fa_enabled_at = $2, updated_at = $2
        WHERE id = $3
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#,
    )
    .bind(totp_secret)
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Disable TOTP-based 2FA for a user
pub async fn disable_totp(pool: &PgPool, user_id: Uuid) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET totp_secret = NULL, totp_enabled = false, updated_at = $1
        WHERE id = $2
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#,
    )
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Update user profile fields
pub async fn update_profile(
    pool: &PgPool,
    user_id: Uuid,
    display_name: Option<&str>,
    bio: Option<&str>,
    avatar_url: Option<&str>,
    cover_photo_url: Option<&str>,
    location: Option<&str>,
    private_account: Option<bool>,
) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET
            display_name = COALESCE($1, display_name),
            bio = COALESCE($2, bio),
            avatar_url = COALESCE($3, avatar_url),
            cover_photo_url = COALESCE($4, cover_photo_url),
            location = COALESCE($5, location),
            private_account = COALESCE($6, private_account),
            updated_at = $7
        WHERE id = $8
        RETURNING id, email, username, password_hash, email_verified, is_active, totp_secret, totp_enabled, two_fa_enabled_at, failed_login_attempts, locked_until, created_at, updated_at, last_login_at, display_name, bio, avatar_url, cover_photo_url, location, private_account
        "#,
    )
    .bind(display_name)
    .bind(bio)
    .bind(avatar_url)
    .bind(cover_photo_url)
    .bind(location)
    .bind(private_account)
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Check if a user has blocked another user
/// Check if two users are blocked in either direction (bidirectional)
/// OPTIMIZED: Single query instead of two separate is_blocked calls
pub async fn are_blocked(
    pool: &PgPool,
    user_a: Uuid,
    user_b: Uuid,
) -> Result<bool, sqlx::Error> {
    let result = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM blocked_users
            WHERE (blocker_id = $1 AND blocked_user_id = $2)
               OR (blocker_id = $2 AND blocked_user_id = $1)
        )
        "#,
    )
    .bind(user_a)
    .bind(user_b)
    .fetch_one(pool)
    .await?;

    Ok(result)
}

pub async fn is_blocked(
    pool: &PgPool,
    blocker_id: Uuid,
    blocked_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let result = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM blocked_users
            WHERE blocker_id = $1 AND blocked_user_id = $2
        )
        "#,
    )
    .bind(blocker_id)
    .bind(blocked_id)
    .fetch_one(pool)
    .await?;

    Ok(result)
}

/// Block a user
pub async fn block_user(
    pool: &PgPool,
    blocker_id: Uuid,
    blocked_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO blocked_users (blocker_id, blocked_user_id)
        VALUES ($1, $2)
        ON CONFLICT (blocker_id, blocked_user_id) DO NOTHING
        "#,
    )
    .bind(blocker_id)
    .bind(blocked_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Unblock a user
pub async fn unblock_user(
    pool: &PgPool,
    blocker_id: Uuid,
    blocked_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        DELETE FROM blocked_users
        WHERE blocker_id = $1 AND blocked_user_id = $2
        "#,
    )
    .bind(blocker_id)
    .bind(blocked_id)
    .execute(pool)
    .await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    // Database tests would require a test database setup
    // These are placeholders for integration tests
    #[test]
    fn test_user_repository_compile() {
        // Ensures the module compiles correctly
        assert!(true);
    }
}

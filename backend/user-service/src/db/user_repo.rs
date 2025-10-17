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
        RETURNING id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
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
        SELECT id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
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
        SELECT id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
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
        SELECT id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        FROM users
        WHERE id = $1 AND deleted_at IS NULL
        "#
    )
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// Update a user's email verification status
pub async fn verify_email(pool: &PgPool, user_id: Uuid) -> Result<User, sqlx::Error> {
    let now = Utc::now();

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET email_verified = true, updated_at = $1
        WHERE id = $2
        RETURNING id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
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
        RETURNING id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
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
        RETURNING id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#
    )
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Record a failed login attempt
pub async fn record_failed_login(
    pool: &PgPool,
    user_id: Uuid,
    max_attempts: i32,
    lock_duration_secs: i64,
) -> Result<User, sqlx::Error> {
    let now = Utc::now();
    let lock_until = if max_attempts <= 1 {
        Some(now + chrono::Duration::seconds(lock_duration_secs))
    } else {
        None
    };

    sqlx::query_as::<_, User>(
        r#"
        UPDATE users
        SET failed_login_attempts = failed_login_attempts + 1, locked_until = $1, updated_at = $2
        WHERE id = $3
        RETURNING id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
        "#
    )
    .bind(lock_until)
    .bind(now)
    .bind(user_id)
    .fetch_one(pool)
    .await
}

/// Soft delete a user (GDPR compliance)
pub async fn soft_delete(pool: &PgPool, user_id: Uuid) -> Result<(), sqlx::Error> {
    let now = Utc::now();

    sqlx::query(
        r#"
        UPDATE users
        SET deleted_at = $1, email = NULL, username = NULL, updated_at = $1
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

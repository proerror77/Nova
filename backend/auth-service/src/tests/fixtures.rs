/// Test fixtures and helpers for auth-service tests
///
/// Provides reusable test data and utility functions following the DRY principle.

use crate::models::user::{LoginRequest, RegisterRequest};
use sqlx::PgPool;
use uuid::Uuid;

/// Standard test user email
pub const TEST_EMAIL: &str = "test@example.com";
pub const TEST_USERNAME: &str = "testuser";
pub const TEST_PASSWORD: &str = "SecurePass123!";

/// Alternative test users for duplicate checks
pub const TEST_EMAIL_2: &str = "test2@example.com";
pub const TEST_USERNAME_2: &str = "testuser2";

/// Create a valid RegisterRequest for testing
pub fn valid_register_request() -> RegisterRequest {
    RegisterRequest {
        email: TEST_EMAIL.to_string(),
        username: TEST_USERNAME.to_string(),
        password: TEST_PASSWORD.to_string(),
    }
}

/// Create a valid LoginRequest for testing
pub fn valid_login_request() -> LoginRequest {
    LoginRequest {
        email: TEST_EMAIL.to_string(),
        password: TEST_PASSWORD.to_string(),
    }
}

/// Create a RegisterRequest with custom values
pub fn custom_register_request(email: &str, username: &str, password: &str) -> RegisterRequest {
    RegisterRequest {
        email: email.to_string(),
        username: username.to_string(),
        password: password.to_string(),
    }
}

/// Create a LoginRequest with custom values
pub fn custom_login_request(email: &str, password: &str) -> LoginRequest {
    LoginRequest {
        email: email.to_string(),
        password: password.to_string(),
    }
}

/// Weak passwords for testing validation
pub fn weak_passwords() -> Vec<&'static str> {
    vec![
        "short",                 // Too short
        "nouppercase123!",       // No uppercase
        "NOLOWERCASE123!",       // No lowercase
        "NoDigitsHere!",         // No digits
        "NoSpecialChars123",     // No special characters
        "12345678",              // Only digits
    ]
}

/// Invalid email formats for testing
/// Note: These are formats that validator::validate_email actually rejects
pub fn invalid_emails() -> Vec<&'static str> {
    vec![
        "not-an-email",      // Missing @
        "@example.com",      // Missing local part
        "test@",             // Missing domain
        "test @example.com", // Space in email
        "test@.com",         // Domain starts with dot
    ]
}

/// Test helper to create a user directly in the database
pub async fn create_test_user(pool: &PgPool, email: &str, username: &str, password_hash: &str) -> Uuid {
    let user_id = Uuid::new_v4();

    sqlx::query(
        r#"
        INSERT INTO users (id, email, username, password_hash, is_email_verified, created_at, updated_at)
        VALUES ($1, $2, $3, $4, FALSE, NOW(), NOW())
        "#,
    )
    .bind(user_id)
    .bind(email)
    .bind(username)
    .bind(password_hash)
    .execute(pool)
    .await
    .expect("Failed to create test user");

    user_id
}

/// Test helper to clean up a user by email
pub async fn delete_test_user_by_email(pool: &PgPool, email: &str) {
    let _ = sqlx::query("DELETE FROM users WHERE email = $1")
        .bind(email)
        .execute(pool)
        .await;
}

/// Test helper to clean up a user by ID
pub async fn delete_test_user_by_id(pool: &PgPool, user_id: Uuid) {
    let _ = sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(user_id)
        .execute(pool)
        .await;
}

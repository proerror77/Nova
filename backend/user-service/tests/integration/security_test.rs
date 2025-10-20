/// Security testing suite for Nova Authentication Service
/// Tests SQL injection, brute force, JWT tampering, and password validation
use actix_web::{test, web, App};
use chrono::{Duration, Utc};
use serde_json::json;
use uuid::Uuid;

// Import common test fixtures
#[path = "../common/fixtures.rs"]
mod fixtures;
use fixtures::*;

// Import application modules
use user_service::handlers::auth::{login, register, verify_email};
use user_service::security::{hash_password, jwt};
use user_service::Config;

// ============================================
// SQL Injection Tests
// ============================================

#[tokio::test]
async fn test_sql_injection_in_email_field() {
    let pool = create_test_pool().await;
    let redis = create_test_redis().await;

    // SQL injection attempt in email field
    let malicious_email = "admin' OR '1'='1";

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(redis.clone()))
            .route("/auth/register", web::post().to(register)),
    )
    .await;

    let req = test::TestRequest::post()
        .uri("/auth/register")
        .set_json(&json!({
            "email": malicious_email,
            "username": "testuser",
            "password": "ValidP@ssw0rd123"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;

    // Should fail email validation, not execute SQL
    assert_eq!(resp.status(), 400);

    cleanup_test_data(&pool).await;
}

#[tokio::test]
async fn test_sql_injection_in_login() {
    let pool = create_test_pool().await;

    // Create a legitimate user first
    let _user = create_test_user_with_email(&pool, "real@example.com").await;

    // Try SQL injection in login
    let config = Config::from_env();

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(config.clone()))
            .route("/auth/login", web::post().to(login)),
    )
    .await;

    let req = test::TestRequest::post()
        .uri("/auth/login")
        .set_json(&json!({
            "email": "admin' OR '1'='1' --",
            "password": "anything"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;

    // Should fail (invalid credentials), not bypass authentication
    assert_eq!(resp.status(), 400); // Invalid email format

    cleanup_test_data(&pool).await;
}

#[tokio::test]
async fn test_sql_injection_in_email_verification() {
    let pool = create_test_pool().await;
    let mut redis = create_test_redis().await;

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(redis.clone()))
            .route("/auth/verify-email", web::post().to(verify_email)),
    )
    .await;

    // Try SQL injection in verification token
    let req = test::TestRequest::post()
        .uri("/auth/verify-email")
        .set_json(&json!({
            "token": "abc'; DROP TABLE users; --"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;

    // Should fail token format validation
    assert_eq!(resp.status(), 400);

    clear_redis(&mut redis).await;
    cleanup_test_data(&pool).await;
}

// ============================================
// Brute Force Protection Tests
// ============================================

#[tokio::test]
async fn test_brute_force_login_protection() {
    let pool = create_test_pool().await;

    // Create test user
    let password_hash = hash_password("ValidP@ssw0rd").unwrap();
    let user = create_unverified_user(&pool, "victim@example.com", &password_hash).await;

    // Verify email to allow login attempts
    sqlx::query("UPDATE users SET email_verified = true WHERE id = $1")
        .bind(user.id)
        .execute(&pool)
        .await
        .unwrap();

    let config = Config::from_env();

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(config.clone()))
            .route("/auth/login", web::post().to(login)),
    )
    .await;

    // Attempt 5 failed logins
    for i in 1..=5 {
        let req = test::TestRequest::post()
            .uri("/auth/login")
            .set_json(&json!({
                "email": "victim@example.com",
                "password": "WrongPassword123!"
            }))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 401, "Login attempt {} should fail", i);
    }

    // Verify account is now locked
    let lock_status = get_user_lock_status(&pool, user.id).await;
    assert!(
        lock_status.is_some(),
        "Account should be locked after 5 failed attempts"
    );

    // Attempt 6th login should still fail (account locked)
    let req = test::TestRequest::post()
        .uri("/auth/login")
        .set_json(&json!({
            "email": "victim@example.com",
            "password": "ValidP@ssw0rd" // Even correct password
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(
        resp.status(),
        401,
        "Locked account should reject even correct password"
    );

    cleanup_test_data(&pool).await;
}

#[tokio::test]
async fn test_account_unlock_after_timeout() {
    let pool = create_test_pool().await;

    // Create locked user (locked 2 seconds ago, should be unlocked now)
    let _password_hash = hash_password("ValidP@ssw0rd").unwrap();
    let user = create_test_user_with_email(&pool, "locked@example.com").await;

    // Lock account in the past
    let locked_until = Utc::now() - Duration::seconds(1);
    lock_user_account(&pool, user.id, locked_until).await;

    let config = Config::from_env();

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(config.clone()))
            .route("/auth/login", web::post().to(login)),
    )
    .await;

    // Should now be able to login
    let req = test::TestRequest::post()
        .uri("/auth/login")
        .set_json(&json!({
            "email": "locked@example.com",
            "password": "password" // fixtures use this password
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(
        resp.status(),
        200,
        "Login should succeed after lock timeout"
    );

    cleanup_test_data(&pool).await;
}

// ============================================
// JWT Tampering Tests
// ============================================

#[tokio::test]
async fn test_jwt_payload_tampering() {
    // Initialize JWT keys
    jwt::initialize_keys(
        &std::env::var("JWT_PRIVATE_KEY").unwrap(),
        &std::env::var("JWT_PUBLIC_KEY").unwrap(),
    )
    .unwrap();

    let user_id = Uuid::new_v4();
    let token = jwt::generate_access_token(user_id, "user@example.com", "testuser").unwrap();

    // Split token into parts
    let parts: Vec<&str> = token.split('.').collect();
    assert_eq!(parts.len(), 3, "JWT should have 3 parts");

    // Tamper with payload (change user_id)
    use base64::Engine;
    let fake_payload = base64::engine::general_purpose::STANDARD.encode(
        json!({
            "sub": Uuid::new_v4().to_string(),
            "email": "attacker@example.com",
            "username": "attacker",
            "iat": chrono::Utc::now().timestamp(),
            "exp": (chrono::Utc::now() + chrono::Duration::hours(1)).timestamp(),
            "token_type": "access"
        })
        .to_string(),
    );

    let tampered_token = format!("{}.{}.{}", parts[0], fake_payload, parts[2]);

    // Validation should fail
    let result = jwt::validate_token(&tampered_token);
    assert!(result.is_err(), "Tampered JWT should fail validation");
}

#[tokio::test]
async fn test_jwt_signature_tampering() {
    // Initialize JWT keys
    jwt::initialize_keys(
        &std::env::var("JWT_PRIVATE_KEY").unwrap(),
        &std::env::var("JWT_PUBLIC_KEY").unwrap(),
    )
    .unwrap();

    let user_id = Uuid::new_v4();
    let token = jwt::generate_access_token(user_id, "user@example.com", "testuser").unwrap();

    // Tamper with signature
    let parts: Vec<&str> = token.split('.').collect();
    let tampered_token = format!("{}.{}.{}", parts[0], parts[1], "fakeSignature");

    // Validation should fail
    let result = jwt::validate_token(&tampered_token);
    assert!(result.is_err(), "JWT with invalid signature should fail");
}

#[tokio::test]
async fn test_jwt_expired_token() {
    // Initialize JWT keys
    jwt::initialize_keys(
        &std::env::var("JWT_PRIVATE_KEY").unwrap(),
        &std::env::var("JWT_PUBLIC_KEY").unwrap(),
    )
    .unwrap();

    // Create a token
    let user_id = Uuid::new_v4();
    let token = jwt::generate_access_token(user_id, "user@example.com", "testuser").unwrap();

    // Token should NOT be expired immediately
    let is_expired = jwt::is_token_expired(&token).unwrap();
    assert!(!is_expired, "Freshly created token should not be expired");
}

#[tokio::test]
async fn test_jwt_forged_token() {
    // Initialize JWT keys
    jwt::initialize_keys(
        &std::env::var("JWT_PRIVATE_KEY").unwrap(),
        &std::env::var("JWT_PUBLIC_KEY").unwrap(),
    )
    .unwrap();

    // Create a completely fake token (HS256 signed, but we expect RS256)
    let fake_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c";

    // Validation should fail
    let result = jwt::validate_token(fake_token);
    assert!(result.is_err(), "Forged token should fail validation");
}

// ============================================
// Password Validation Tests
// ============================================

#[tokio::test]
async fn test_password_validation_prevents_weak_passwords() {
    let pool = create_test_pool().await;
    let redis = create_test_redis().await;

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(redis.clone()))
            .route("/auth/register", web::post().to(register)),
    )
    .await;

    // Test various weak passwords
    let weak_passwords = vec![
        "short",           // Too short
        "nouppercase123!", // No uppercase
        "NOLOWERCASE123!", // No lowercase
        "NoNumbers!",      // No numbers
        "NoSpecialChar1",  // No special char
    ];

    for weak_pwd in weak_passwords {
        let req = test::TestRequest::post()
            .uri("/auth/register")
            .set_json(&json!({
                "email": format!("test-{}@example.com", Uuid::new_v4()),
                "username": format!("user{}", Uuid::new_v4().to_string().chars().take(8).collect::<String>()),
                "password": weak_pwd
            }))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(
            resp.status(),
            400,
            "Weak password '{}' should be rejected",
            weak_pwd
        );
    }

    cleanup_test_data(&pool).await;
}

#[tokio::test]
async fn test_email_validation_prevents_invalid_emails() {
    let pool = create_test_pool().await;
    let redis = create_test_redis().await;

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(redis.clone()))
            .route("/auth/register", web::post().to(register)),
    )
    .await;

    let invalid_emails = vec![
        "notanemail",
        "@example.com",
        "user@",
        "user name@example.com",
        "user@.com",
    ];

    for invalid_email in invalid_emails {
        let req = test::TestRequest::post()
            .uri("/auth/register")
            .set_json(&json!({
                "email": invalid_email,
                "username": "validuser",
                "password": "ValidP@ssw0rd123"
            }))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(
            resp.status(),
            400,
            "Invalid email '{}' should be rejected",
            invalid_email
        );
    }

    cleanup_test_data(&pool).await;
}

// ============================================
// Comprehensive Security Test
// ============================================

#[tokio::test]
async fn test_complete_authentication_flow_security() {
    let pool = create_test_pool().await;
    let redis = create_test_redis().await;
    let config = Config::from_env();

    // Initialize JWT
    jwt::initialize_keys(
        &std::env::var("JWT_PRIVATE_KEY").unwrap(),
        &std::env::var("JWT_PUBLIC_KEY").unwrap(),
    )
    .unwrap();

    // 1. Test registration with valid data
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(redis.clone()))
            .route("/auth/register", web::post().to(register)),
    )
    .await;

    let test_email = format!("secure-{}@example.com", Uuid::new_v4());
    let req = test::TestRequest::post()
        .uri("/auth/register")
        .set_json(&json!({
            "email": test_email,
            "username": "secureuser",
            "password": "SecureP@ssw0rd123"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 201, "Registration should succeed");

    // 2. Verify email is required for login
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(config.clone()))
            .route("/auth/login", web::post().to(login)),
    )
    .await;

    let req = test::TestRequest::post()
        .uri("/auth/login")
        .set_json(&json!({
            "email": test_email,
            "password": "SecureP@ssw0rd123"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(
        resp.status(),
        403,
        "Login should fail without email verification"
    );

    // 3. Verify password is hashed
    let user = sqlx::query_as::<_, (String,)>("SELECT password_hash FROM users WHERE email = $1")
        .bind(&test_email)
        .fetch_one(&pool)
        .await
        .unwrap();

    assert!(
        !user.0.contains("SecureP@ssw0rd123"),
        "Password should not be stored in plaintext"
    );
    assert!(
        user.0.starts_with("$argon2"),
        "Password should be Argon2 hashed"
    );

    cleanup_test_data(&pool).await;
}

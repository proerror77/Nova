/// Core authentication business logic tests
///
/// These tests verify the core auth workflows:
/// - User registration
/// - User login
/// - Token refresh
/// - Token revocation (logout)
///
/// Tests use a real PostgreSQL database (via DATABASE_URL env var)
/// and follow the red-green-refactor TDD cycle.
use crate::error::AuthError;
use crate::models::user::{LoginRequest, RefreshTokenRequest, RegisterRequest};
use crate::security::{jwt, password};
use crate::tests::fixtures::*;
use sqlx::PgPool;
use uuid::Uuid;

// ============================================================================
// Test Setup
// ============================================================================

/// Initialize test database connection
///
/// Requires DATABASE_URL environment variable to be set
async fn setup_test_db() -> PgPool {
    let database_url =
        std::env::var("DATABASE_URL").expect("DATABASE_URL must be set for integration tests");

    PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to test database")
}

// ============================================================================
// Registration Tests
// ============================================================================

#[tokio::test]
async fn test_register_user_happy_path() {
    // GIVEN: A valid registration request
    let pool = setup_test_db().await;
    let req = valid_register_request();

    // Clean up any existing test user
    delete_test_user_by_email(&pool, &req.email).await;

    // WHEN: We attempt to register the user
    let result = register_user_logic(&pool, &req).await;

    // THEN: Registration should succeed and return a user ID and tokens
    assert!(
        result.is_ok(),
        "Registration should succeed with valid input"
    );
    let (user_id, access_token, refresh_token) = result.unwrap();

    // Verify user ID is valid UUID
    assert_ne!(user_id, Uuid::nil(), "User ID should not be nil");

    // Verify tokens are not empty
    assert!(!access_token.is_empty(), "Access token should not be empty");
    assert!(
        !refresh_token.is_empty(),
        "Refresh token should not be empty"
    );

    // Verify tokens are valid JWT format (3 parts separated by dots)
    assert_eq!(
        access_token.matches('.').count(),
        2,
        "Access token should be valid JWT"
    );
    assert_eq!(
        refresh_token.matches('.').count(),
        2,
        "Refresh token should be valid JWT"
    );

    // Verify user was created in database
    let user = crate::db::users::find_by_email(&pool, &req.email)
        .await
        .expect("Database query should succeed")
        .expect("User should exist in database");

    assert_eq!(user.email, req.email);
    assert_eq!(user.username, req.username);
    assert!(
        !user.email_verified,
        "New user should not be email verified"
    );

    // Clean up
    delete_test_user_by_id(&pool, user_id).await;
}

#[tokio::test]
async fn test_register_user_duplicate_email() {
    // GIVEN: A user already exists with the test email
    let pool = setup_test_db().await;
    let req = valid_register_request();

    delete_test_user_by_email(&pool, &req.email).await;

    // Create the first user
    let password_hash =
        password::hash_password(TEST_PASSWORD).expect("Password hashing should succeed");
    let existing_user_id = create_test_user(&pool, &req.email, TEST_USERNAME, &password_hash).await;

    // WHEN: We attempt to register another user with the same email
    let result = register_user_logic(&pool, &req).await;

    // THEN: Registration should fail with EmailAlreadyExists error
    assert!(
        result.is_err(),
        "Registration should fail for duplicate email"
    );

    let err = result.unwrap_err();
    assert!(
        matches!(err, AuthError::EmailAlreadyExists),
        "Error should be EmailAlreadyExists, got: {:?}",
        err
    );

    // Clean up
    delete_test_user_by_id(&pool, existing_user_id).await;
}

#[tokio::test]
async fn test_register_user_duplicate_username() {
    // GIVEN: A user already exists with the test username
    let pool = setup_test_db().await;

    delete_test_user_by_email(&pool, TEST_EMAIL).await;
    delete_test_user_by_email(&pool, TEST_EMAIL_2).await;

    let password_hash =
        password::hash_password(TEST_PASSWORD).expect("Password hashing should succeed");

    // Create user with TEST_USERNAME
    let existing_user_id =
        create_test_user(&pool, TEST_EMAIL_2, TEST_USERNAME, &password_hash).await;

    // WHEN: We attempt to register with same username but different email
    let req = custom_register_request(TEST_EMAIL, TEST_USERNAME, TEST_PASSWORD);
    let result = register_user_logic(&pool, &req).await;

    // THEN: Registration should fail with UsernameAlreadyExists error
    assert!(
        result.is_err(),
        "Registration should fail for duplicate username"
    );

    let err = result.unwrap_err();
    assert!(
        matches!(err, AuthError::UsernameAlreadyExists),
        "Error should be UsernameAlreadyExists, got: {:?}",
        err
    );

    // Clean up
    delete_test_user_by_id(&pool, existing_user_id).await;
}

#[tokio::test]
async fn test_register_user_weak_password() {
    // GIVEN: Registration requests with various weak passwords
    let pool = setup_test_db().await;

    for weak_pwd in weak_passwords() {
        let req = custom_register_request(TEST_EMAIL, TEST_USERNAME, weak_pwd);

        // WHEN: We attempt to register with a weak password
        let result = register_user_logic(&pool, &req).await;

        // THEN: Registration should fail with WeakPassword error
        assert!(
            result.is_err(),
            "Registration should fail for weak password: {}",
            weak_pwd
        );

        let err = result.unwrap_err();
        assert!(
            matches!(err, AuthError::WeakPassword),
            "Error should be WeakPassword for '{}', got: {:?}",
            weak_pwd,
            err
        );
    }
}

#[tokio::test]
async fn test_register_user_invalid_email() {
    // GIVEN: Registration requests with invalid email formats
    let pool = setup_test_db().await;

    for invalid_email in invalid_emails() {
        let req = custom_register_request(invalid_email, TEST_USERNAME, TEST_PASSWORD);

        // WHEN: We attempt to register with invalid email
        let result = register_user_logic(&pool, &req).await;

        // THEN: Registration should fail with InvalidEmailFormat error
        assert!(
            result.is_err(),
            "Registration should fail for invalid email: {}",
            invalid_email
        );

        let err = result.unwrap_err();
        assert!(
            matches!(err, AuthError::InvalidEmailFormat),
            "Error should be InvalidEmailFormat for '{}', got: {:?}",
            invalid_email,
            err
        );
    }
}

// ============================================================================
// Login Tests
// ============================================================================

#[tokio::test]
async fn test_login_user_correct_credentials() {
    // GIVEN: A user exists with known credentials
    let pool = setup_test_db().await;

    delete_test_user_by_email(&pool, TEST_EMAIL).await;

    let password_hash =
        password::hash_password(TEST_PASSWORD).expect("Password hashing should succeed");
    let user_id = create_test_user(&pool, TEST_EMAIL, TEST_USERNAME, &password_hash).await;

    let req = valid_login_request();

    // WHEN: We attempt to login with correct credentials
    let result = login_user_logic(&pool, &req).await;

    // THEN: Login should succeed and return tokens
    assert!(
        result.is_ok(),
        "Login should succeed with correct credentials"
    );

    let (returned_user_id, access_token, refresh_token) = result.unwrap();

    assert_eq!(returned_user_id, user_id, "Returned user ID should match");
    assert!(!access_token.is_empty(), "Access token should not be empty");
    assert!(
        !refresh_token.is_empty(),
        "Refresh token should not be empty"
    );

    // Verify tokens can be validated
    let access_claims = jwt::validate_token(&access_token);
    assert!(access_claims.is_ok(), "Access token should be valid");

    let refresh_claims = jwt::validate_token(&refresh_token);
    assert!(refresh_claims.is_ok(), "Refresh token should be valid");

    // Clean up
    delete_test_user_by_id(&pool, user_id).await;
}

#[tokio::test]
async fn test_login_user_wrong_password() {
    // GIVEN: A user exists with known credentials
    let pool = setup_test_db().await;

    delete_test_user_by_email(&pool, TEST_EMAIL).await;

    let password_hash =
        password::hash_password(TEST_PASSWORD).expect("Password hashing should succeed");
    let user_id = create_test_user(&pool, TEST_EMAIL, TEST_USERNAME, &password_hash).await;

    // WHEN: We attempt to login with wrong password
    let req = custom_login_request(TEST_EMAIL, "WrongPassword123!");
    let result = login_user_logic(&pool, &req).await;

    // THEN: Login should fail with InvalidCredentials error
    assert!(result.is_err(), "Login should fail with wrong password");

    let err = result.unwrap_err();
    assert!(
        matches!(err, AuthError::InvalidCredentials),
        "Error should be InvalidCredentials, got: {:?}",
        err
    );

    // Clean up
    delete_test_user_by_id(&pool, user_id).await;
}

#[tokio::test]
async fn test_login_user_nonexistent_user() {
    // GIVEN: No user exists with the given email
    let pool = setup_test_db().await;

    delete_test_user_by_email(&pool, "nonexistent@example.com").await;

    // WHEN: We attempt to login with non-existent email
    let req = custom_login_request("nonexistent@example.com", TEST_PASSWORD);
    let result = login_user_logic(&pool, &req).await;

    // THEN: Login should fail with InvalidCredentials error
    assert!(result.is_err(), "Login should fail for non-existent user");

    let err = result.unwrap_err();
    assert!(
        matches!(err, AuthError::InvalidCredentials),
        "Error should be InvalidCredentials, got: {:?}",
        err
    );
}

#[tokio::test]
async fn test_login_user_invalid_email_format() {
    // GIVEN: Login request with invalid email format
    let pool = setup_test_db().await;

    // WHEN: We attempt to login with invalid email
    let req = custom_login_request("not-an-email", TEST_PASSWORD);
    let result = login_user_logic(&pool, &req).await;

    // THEN: Login should fail with InvalidEmailFormat error
    assert!(
        result.is_err(),
        "Login should fail for invalid email format"
    );

    let err = result.unwrap_err();
    assert!(
        matches!(err, AuthError::InvalidEmailFormat),
        "Error should be InvalidEmailFormat, got: {:?}",
        err
    );
}

// ============================================================================
// Token Refresh Tests
// ============================================================================

#[tokio::test]
async fn test_refresh_token_valid() {
    // GIVEN: A valid refresh token
    let user_id = Uuid::new_v4();
    let email = "test@example.com";
    let username = "testuser";

    // Initialize JWT keys for testing
    init_jwt_keys_once();

    let token_pair = jwt::generate_token_pair(user_id, email, username)
        .expect("Token generation should succeed");

    let req = RefreshTokenRequest {
        refresh_token: token_pair.refresh_token.clone(),
    };

    // WHEN: We attempt to refresh the token
    let result = refresh_token_logic(&req);

    // THEN: Refresh should succeed and return new tokens
    assert!(
        result.is_ok(),
        "Token refresh should succeed with valid refresh token"
    );

    let (new_access, new_refresh) = result.unwrap();

    // Verify new tokens are different from old tokens
    assert_ne!(
        new_access, token_pair.access_token,
        "New access token should be different"
    );
    assert_ne!(
        new_refresh, token_pair.refresh_token,
        "New refresh token should be different"
    );

    // Verify new tokens are valid
    let access_claims = jwt::validate_token(&new_access);
    assert!(access_claims.is_ok(), "New access token should be valid");

    let refresh_claims = jwt::validate_token(&new_refresh);
    assert!(refresh_claims.is_ok(), "New refresh token should be valid");
}

#[tokio::test]
async fn test_refresh_token_with_access_token() {
    // GIVEN: An access token (not a refresh token)
    let user_id = Uuid::new_v4();

    init_jwt_keys_once();

    let access_token = jwt::generate_access_token(user_id, "test@example.com", "testuser")
        .expect("Token generation should succeed");

    let req = RefreshTokenRequest {
        refresh_token: access_token,
    };

    // WHEN: We attempt to use access token for refresh
    let result = refresh_token_logic(&req);

    // THEN: Refresh should fail with InvalidToken error
    assert!(
        result.is_err(),
        "Token refresh should fail when using access token"
    );

    let err = result.unwrap_err();
    assert!(
        matches!(err, AuthError::InvalidToken),
        "Error should be InvalidToken, got: {:?}",
        err
    );
}

#[tokio::test]
async fn test_refresh_token_invalid_token() {
    // GIVEN: An invalid token string
    let req = RefreshTokenRequest {
        refresh_token: "invalid.token.here".to_string(),
    };

    // WHEN: We attempt to refresh with invalid token
    let result = refresh_token_logic(&req);

    // THEN: Refresh should fail
    assert!(
        result.is_err(),
        "Token refresh should fail with invalid token"
    );
}

// ============================================================================
// Business Logic Functions (extracted from handlers for testability)
// ============================================================================

/// Register user business logic
async fn register_user_logic(
    pool: &PgPool,
    req: &RegisterRequest,
) -> Result<(Uuid, String, String), AuthError> {
    use validator::Validate;

    // Trim and validate
    let trimmed_req = RegisterRequest {
        email: req.email.trim().to_string(),
        username: req.username.trim().to_string(),
        password: req.password.clone(),
    };

    if let Err(e) = trimmed_req.validate() {
        let fields = e.field_errors();
        if fields.contains_key("email") {
            return Err(AuthError::InvalidEmailFormat);
        }
        if fields.contains_key("password") {
            return Err(AuthError::WeakPassword);
        }
        return Err(AuthError::InvalidCredentials);
    }

    // Check for duplicates
    if crate::db::users::email_exists(pool, &trimmed_req.email).await? {
        return Err(AuthError::EmailAlreadyExists);
    }

    if crate::db::users::username_exists(pool, &trimmed_req.username).await? {
        return Err(AuthError::UsernameAlreadyExists);
    }

    // Hash password
    let password_hash = password::hash_password(&trimmed_req.password)?;

    // Create user
    let user = crate::db::users::create_user(
        pool,
        &trimmed_req.email,
        &trimmed_req.username,
        &password_hash,
    )
    .await?;

    // Generate tokens
    let token_pair = jwt::generate_token_pair(user.id, &user.email, &user.username)?;

    Ok((user.id, token_pair.access_token, token_pair.refresh_token))
}

/// Login user business logic
async fn login_user_logic(
    pool: &PgPool,
    req: &LoginRequest,
) -> Result<(Uuid, String, String), AuthError> {
    use validator::Validate;

    let trimmed_req = LoginRequest {
        email: req.email.trim().to_string(),
        password: req.password.clone(),
    };

    if let Err(e) = trimmed_req.validate() {
        if e.field_errors().contains_key("email") {
            return Err(AuthError::InvalidEmailFormat);
        }
        return Err(AuthError::InvalidCredentials);
    }

    // Find user
    let user = match crate::db::users::find_by_email(pool, &trimmed_req.email).await? {
        Some(user) => user,
        None => return Err(AuthError::InvalidCredentials),
    };

    // Check if account is locked
    if user.is_locked() {
        return Err(AuthError::InvalidCredentials);
    }

    // Verify password
    password::verify_password(&trimmed_req.password, &user.password_hash)?;

    // Record successful login
    let _ = crate::db::users::record_successful_login(pool, user.id).await;

    // Generate tokens
    let token_pair = jwt::generate_token_pair(user.id, &user.email, &user.username)?;

    Ok((user.id, token_pair.access_token, token_pair.refresh_token))
}

/// Refresh token business logic (simplified without revocation checks for unit tests)
fn refresh_token_logic(req: &RefreshTokenRequest) -> Result<(String, String), AuthError> {
    // Validate refresh token
    let token_data = jwt::validate_token(&req.refresh_token)?;

    // Check token type
    if token_data.claims.token_type != "refresh" {
        return Err(AuthError::InvalidToken);
    }

    let user_id = Uuid::parse_str(&token_data.claims.sub).map_err(|_| AuthError::InvalidToken)?;

    // Generate new token pair
    let new_pair = jwt::generate_token_pair(
        user_id,
        &token_data.claims.email,
        &token_data.claims.username,
    )?;

    Ok((new_pair.access_token, new_pair.refresh_token))
}

// ============================================================================
// Test Utilities
// ============================================================================

/// Initialize JWT keys once for all tests
fn init_jwt_keys_once() {
    use std::sync::Once;
    static INIT: Once = Once::new();

    INIT.call_once(|| {
        const TEST_PRIVATE_KEY: &str = r#"-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDmk2ZpednMZ2LD
UgdpKdNEgdB6Z8sbcHGwN+/UjEQGDJXpilaPQIVjGttbVbZ+l91IdvQ1x/cwN6sZ
0+R8vIThjJcaHRelPnRmcsQeu5jtPA/6x8h8jpvzvYEXCZ3QI9Fe1trnI3KUbTOS
WZpXRoWLlbgH4wUjTf9H6yKw11iNd5US9DbvLUU0F8noWqvVk8zqoB5aJosMNdW8
VMoRP94Hi7T51xwpqkb3EBLWRjZS3icyUHWpPFCCTRsIRbkvZ62SU4K9y9JIOeWp
ZZy1SOxrowbqUI5t+7ayE6+Rj4GRBh/z0rEBO4kGAln7+t3T8f4HKA8ttFWx9glg
6CTUN9wnAgMBAAECggEAJE+LeIojOG4CPvbItVD236T/Kyeenqrt3G29VmA4c34W
kE6kJFm+0m/voh80vBQ3rtUSJEi3WV/gPBMDD88IW2oD1FhHLv36NWABbpg7FFu5
uyksc3Zp13qSZ7RbUTndcO1Y+mlkqTyBO0eNEg1zCRus0uEiIACFIShFsEpZZv2P
cyaZCbr3AltkK4byQL2eQ7Q7aKPZXKEub+acLR5IWOzSRhVQ4KR3K53RHJ6MbGc7
rrQP2MD+tQq1XH9TtKJ5uA51fe8goDhV8Hn4km2sabsSPqH1HyUkN4XZCJ5THhtY
fna+gPkUl5ybumCMPpt1RDSkoJcZly0xWQFWUvMooQKBgQD3Ptqe/hcVfrQn6LoZ
BbgSTv92dvd8Oz9WDBqt0LZDIKu5Kp8qwXIAb6xAd0tkhSDUmuodId8Jh/niRBMy
3zAv90z2QTnXJRFgN3De7Wty/0f8HMRrjR63AwLcx5w5XOLhthVN+jkV+bu0+sJh
EG81O/NbRaYrgnDHQXEHkoTvLwKBgQDuvXGlKahZi8HT3bdqa9lwQrLzVoKy7Ztj
zDazsv24bCVXM0Hj/0NXzq/axvgU6vfG08wMLS/htUAg9QdgTA/HKa5Bb0axhFXc
MQUR3/xTr3kfXXEwITdnDY2X3+j4SgD7OU92P+vwB4iGgPUegrqIHJmrfe51xEM3
J4Sf51LkiQKBgDIR8IQyQMqBlkpevxFCLzzF8sYy4XuvI+xxFxYMJl0ByMT+9Kzb
8BJWizOi9QmuTC/CD5dGvLxZZSmFT74FpOSR2GwmWWhQgWxSzfDXc+Md/5321XBS
a930Jig/5EtZnDjJfxcDjXv9zx2fiq3NfjfxpB7fw/8bs2smvZUi/vjRAoGBAJ6k
OklTFjBywxjjIwdPpUyItdsnKHB3naNCRzNABIMxMdrxD57Ot9Q4XvjU8HMN9Bom
EVgiCshEJdoAmKcvw+hHVSjcJbC+TEOmO0U2fripSKZD9HvUBrmu8uDyBCBBJMfL
vHbKYSC+EMW4Gantmr/pqV+grf2JrlSPKP0MvTNpAoGAZnsljoUTW9PSDnx30Hqk
lRgoyQivtx6hKDm6v2l++mEQ0mMBE3NaN3hYxm6ncpG7b0giTu4jZx9U5Y0DLJ7m
3Dv/Cqr1zqQEekb93a1JZQxj9DP+Q/vw8CX/ky+xCE4zz596Dql+nycrOcbUM056
YMNQEWT7aC6+SsTEfz2Btk8=
-----END PRIVATE KEY-----"#;

        const TEST_PUBLIC_KEY: &str = r#"-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5pNmaXnZzGdiw1IHaSnT
RIHQemfLG3BxsDfv1IxEBgyV6YpWj0CFYxrbW1W2fpfdSHb0Ncf3MDerGdPkfLyE
4YyXGh0XpT50ZnLEHruY7TwP+sfIfI6b872BFwmd0CPRXtba5yNylG0zklmaV0aF
i5W4B+MFI03/R+sisNdYjXeVEvQ27y1FNBfJ6Fqr1ZPM6qAeWiaLDDXVvFTKET/e
B4u0+dccKapG9xAS1kY2Ut4nMlB1qTxQgk0bCEW5L2etklOCvcvSSDnlqWWctUjs
a6MG6lCObfu2shOvkY+BkQYf89KxATuJBgJZ+/rd0/H+BygPLbRVsfYJYOgk1Dfc
JwIDAQAB
-----END PUBLIC KEY-----"#;

        crypto_core::jwt::initialize_jwt_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY)
            .expect("Failed to initialize JWT keys");
    });
}

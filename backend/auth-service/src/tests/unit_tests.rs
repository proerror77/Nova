/// Pure unit tests for auth-service core logic (no database required)
///
/// These tests verify password validation, email validation, and token operations
/// without requiring database connectivity.

use crate::error::AuthError;
use crate::models::user::RefreshTokenRequest;
use crate::security::{jwt, password};
use crate::tests::fixtures::*;
use uuid::Uuid;
use validator::Validate;

// ============================================================================
// Password Validation Tests
// ============================================================================

#[test]
fn test_password_hash_and_verify() {
    // GIVEN: A strong password
    let password = TEST_PASSWORD;

    // WHEN: We hash it
    let hash = password::hash_password(password);

    // THEN: Hashing should succeed
    assert!(hash.is_ok(), "Password hashing should succeed with strong password");

    let hash_str = hash.unwrap();

    // AND: Verification with correct password should succeed
    let verify_result = password::verify_password(password, &hash_str);
    assert!(verify_result.is_ok(), "Password verification should succeed with correct password");
}

#[test]
fn test_password_verify_wrong_password() {
    // GIVEN: A password hash
    let password = TEST_PASSWORD;
    let hash = password::hash_password(password).expect("Hash should succeed");

    // WHEN: We verify with wrong password
    let result = password::verify_password("WrongPassword123!", &hash);

    // THEN: Verification should fail
    assert!(result.is_err(), "Password verification should fail with wrong password");
    assert!(
        matches!(result.unwrap_err(), AuthError::InvalidCredentials),
        "Error should be InvalidCredentials"
    );
}

#[test]
fn test_weak_password_too_short() {
    // GIVEN: Password shorter than 8 characters
    let weak_password = "Pass1!";

    // WHEN: We attempt to hash it
    let result = password::hash_password(weak_password);

    // THEN: Should fail with WeakPassword
    assert!(result.is_err(), "Short password should be rejected");
    assert!(
        matches!(result.unwrap_err(), AuthError::WeakPassword),
        "Error should be WeakPassword"
    );
}

#[test]
fn test_weak_password_no_uppercase() {
    // GIVEN: Password without uppercase
    let weak_password = "securepass123!";

    // WHEN: We attempt to hash it
    let result = password::hash_password(weak_password);

    // THEN: Should fail with WeakPassword
    assert!(result.is_err(), "Password without uppercase should be rejected");
}

#[test]
fn test_weak_password_no_lowercase() {
    // GIVEN: Password without lowercase
    let weak_password = "SECUREPASS123!";

    // WHEN: We attempt to hash it
    let result = password::hash_password(weak_password);

    // THEN: Should fail with WeakPassword
    assert!(result.is_err(), "Password without lowercase should be rejected");
}

#[test]
fn test_weak_password_no_digit() {
    // GIVEN: Password without digit
    let weak_password = "SecurePass!";

    // WHEN: We attempt to hash it
    let result = password::hash_password(weak_password);

    // THEN: Should fail with WeakPassword
    assert!(result.is_err(), "Password without digit should be rejected");
}

#[test]
fn test_weak_password_no_special() {
    // GIVEN: Password without special character
    let weak_password = "SecurePass123";

    // WHEN: We attempt to hash it
    let result = password::hash_password(weak_password);

    // THEN: Should fail with WeakPassword
    assert!(result.is_err(), "Password without special character should be rejected");
}

#[test]
fn test_all_weak_passwords() {
    // GIVEN: Various weak passwords
    for weak_pwd in weak_passwords() {
        // WHEN: We attempt to hash each
        let result = password::hash_password(weak_pwd);

        // THEN: All should fail
        assert!(
            result.is_err(),
            "Weak password '{}' should be rejected",
            weak_pwd
        );
        assert!(
            matches!(result.unwrap_err(), AuthError::WeakPassword),
            "Error should be WeakPassword for '{}'",
            weak_pwd
        );
    }
}

// ============================================================================
// Email Validation Tests
// ============================================================================

#[test]
fn test_valid_email_format() {
    // GIVEN: A valid RegisterRequest
    let req = valid_register_request();

    // WHEN: We validate it
    let result = req.validate();

    // THEN: Validation should succeed
    assert!(result.is_ok(), "Valid email should pass validation");
}

#[test]
fn test_invalid_email_formats() {
    // GIVEN: Various invalid email formats
    for invalid_email in invalid_emails() {
        let req = custom_register_request(invalid_email, TEST_USERNAME, TEST_PASSWORD);

        // WHEN: We validate
        let result = req.validate();

        // THEN: Should fail validation
        assert!(
            result.is_err(),
            "Invalid email '{}' should fail validation",
            invalid_email
        );

        let errors = result.unwrap_err();
        assert!(
            errors.field_errors().contains_key("email"),
            "Should have email validation error for '{}'",
            invalid_email
        );
    }
}

#[test]
fn test_login_request_invalid_email() {
    // GIVEN: LoginRequest with invalid email
    for invalid_email in invalid_emails() {
        let req = custom_login_request(invalid_email, TEST_PASSWORD);

        // WHEN: We validate
        let result = req.validate();

        // THEN: Should fail
        assert!(
            result.is_err(),
            "Invalid email '{}' should fail validation",
            invalid_email
        );
    }
}

// ============================================================================
// JWT Token Tests (already covered in crypto-core, but testing integration)
// ============================================================================

#[test]
fn test_generate_access_token() {
    // GIVEN: Valid user credentials
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();
    let email = "test@example.com";
    let username = "testuser";

    // WHEN: We generate access token
    let result = jwt::generate_access_token(user_id, email, username);

    // THEN: Should succeed
    assert!(result.is_ok(), "Access token generation should succeed");

    let token = result.unwrap();

    // AND: Token should be valid JWT format
    assert_eq!(token.matches('.').count(), 2, "Token should have JWT format (3 parts)");
}

#[test]
fn test_generate_refresh_token() {
    // GIVEN: Valid user credentials
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();

    // WHEN: We generate refresh token
    let result = jwt::generate_refresh_token(user_id, "test@example.com", "testuser");

    // THEN: Should succeed
    assert!(result.is_ok(), "Refresh token generation should succeed");
}

#[test]
fn test_generate_token_pair() {
    // GIVEN: Valid user credentials
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();

    // WHEN: We generate token pair
    let result = jwt::generate_token_pair(user_id, "test@example.com", "testuser");

    // THEN: Should succeed with both tokens
    assert!(result.is_ok(), "Token pair generation should succeed");

    let pair = result.unwrap();
    assert!(!pair.access_token.is_empty(), "Access token should not be empty");
    assert!(!pair.refresh_token.is_empty(), "Refresh token should not be empty");
    assert_eq!(pair.token_type, "Bearer", "Token type should be Bearer");
}

#[test]
fn test_validate_valid_token() {
    // GIVEN: A freshly generated token
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();
    let token = jwt::generate_access_token(user_id, "test@example.com", "testuser")
        .expect("Token generation should succeed");

    // WHEN: We validate it
    let result = jwt::validate_token(&token);

    // THEN: Should succeed
    assert!(result.is_ok(), "Valid token should pass validation");

    let token_data = result.unwrap();
    assert_eq!(token_data.claims.sub, user_id.to_string());
    assert_eq!(token_data.claims.email, "test@example.com");
    assert_eq!(token_data.claims.username, "testuser");
    assert_eq!(token_data.claims.token_type, "access");
}

#[test]
fn test_validate_invalid_token() {
    // GIVEN: An invalid token string
    init_jwt_keys_once();

    let invalid_token = "invalid.token.here";

    // WHEN: We validate it
    let result = jwt::validate_token(invalid_token);

    // THEN: Should fail
    assert!(result.is_err(), "Invalid token should fail validation");
}

#[test]
fn test_validate_tampered_token() {
    // GIVEN: A valid token that we tamper with
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();
    let token = jwt::generate_access_token(user_id, "test@example.com", "testuser")
        .expect("Token generation should succeed");

    // Tamper by replacing a character
    let tampered = token.replace("a", "b");

    // WHEN: We validate the tampered token
    let result = jwt::validate_token(&tampered);

    // THEN: Should fail
    assert!(result.is_err(), "Tampered token should fail validation");
}

#[test]
fn test_refresh_token_validation_happy_path() {
    // GIVEN: A valid refresh token
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();
    let token_pair = jwt::generate_token_pair(user_id, "test@example.com", "testuser")
        .expect("Token generation should succeed");

    // WHEN: We validate the refresh token
    let result = jwt::validate_token(&token_pair.refresh_token);

    // THEN: Should succeed
    assert!(result.is_ok(), "Valid refresh token should pass validation");

    let token_data = result.unwrap();
    assert_eq!(token_data.claims.token_type, "refresh");
}

#[test]
fn test_refresh_token_wrong_type_rejected() {
    // GIVEN: An access token (not refresh)
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();
    let access_token = jwt::generate_access_token(user_id, "test@example.com", "testuser")
        .expect("Token generation should succeed");

    let req = RefreshTokenRequest {
        refresh_token: access_token,
    };

    // WHEN: We attempt to use it for refresh (business logic)
    let result = validate_refresh_token_type(&req);

    // THEN: Should fail
    assert!(result.is_err(), "Access token should not be accepted for refresh");
    assert!(
        matches!(result.unwrap_err(), AuthError::InvalidToken),
        "Error should be InvalidToken"
    );
}

#[test]
fn test_extract_user_id_from_token() {
    // GIVEN: A valid token
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();
    let token = jwt::generate_access_token(user_id, "test@example.com", "testuser")
        .expect("Token generation should succeed");

    // WHEN: We extract user ID
    let result = jwt::get_user_id_from_token(&token);

    // THEN: Should succeed and match original
    assert!(result.is_ok(), "User ID extraction should succeed");
    assert_eq!(result.unwrap(), user_id);
}

#[test]
fn test_extract_email_from_token() {
    // GIVEN: A valid token
    init_jwt_keys_once();

    let user_id = Uuid::new_v4();
    let email = "test@example.com";
    let token = jwt::generate_access_token(user_id, email, "testuser")
        .expect("Token generation should succeed");

    // WHEN: We extract email
    let result = jwt::get_email_from_token(&token);

    // THEN: Should succeed and match
    assert!(result.is_ok(), "Email extraction should succeed");
    assert_eq!(result.unwrap(), email);
}

// ============================================================================
// Test Utilities
// ============================================================================

/// Validate refresh token type (business logic helper)
fn validate_refresh_token_type(req: &RefreshTokenRequest) -> Result<(), AuthError> {
    let token_data = jwt::validate_token(&req.refresh_token)?;

    if token_data.claims.token_type != "refresh" {
        return Err(AuthError::InvalidToken);
    }

    Ok(())
}

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

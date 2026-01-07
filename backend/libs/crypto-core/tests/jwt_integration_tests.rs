/// Integration tests for crypto-core JWT functionality
///
/// This test module covers:
/// - JWT token generation and validation
/// - Token expiration handling
/// - Claims extraction
/// - Error handling for invalid tokens
use crypto_core::jwt::{
    generate_access_token, generate_refresh_token, generate_token_pair, initialize_jwt_keys,
    is_token_expired, validate_token,
};
use std::sync::Once;
use uuid::Uuid;

// Test RSA key pair - FOR TESTING ONLY
// NEVER use these keys in production
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

fn init_test_keys() {
    // Use a static flag to prevent re-initialization in tests
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        initialize_jwt_keys(TEST_PRIVATE_KEY, TEST_PUBLIC_KEY)
            .expect("Failed to initialize test keys");
    });
}

// ============================================================================
// Token Generation Tests
// ============================================================================

#[test]
fn test_generate_access_token_success() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let result = generate_access_token(user_id, "test@example.com", "testuser", None, None);

    assert!(result.is_ok(), "Should generate access token successfully");
    let token = result.unwrap();
    assert!(!token.is_empty(), "Token should not be empty");
    assert_eq!(
        token.matches('.').count(),
        2,
        "JWT should have 3 parts separated by dots"
    );
}

#[test]
fn test_generate_refresh_token_success() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let result = generate_refresh_token(user_id, "test@example.com", "testuser", None, None);

    assert!(result.is_ok(), "Should generate refresh token successfully");
    let token = result.unwrap();
    assert!(!token.is_empty(), "Token should not be empty");
    assert_eq!(
        token.matches('.').count(),
        2,
        "JWT should have 3 parts separated by dots"
    );
}

#[test]
fn test_generate_token_pair_success() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let result = generate_token_pair(user_id, "test@example.com", "testuser", None, None);

    assert!(result.is_ok(), "Should generate token pair successfully");
    let tokens = result.unwrap();
    assert!(
        !tokens.access_token.is_empty(),
        "Access token should not be empty"
    );
    assert!(
        !tokens.refresh_token.is_empty(),
        "Refresh token should not be empty"
    );
    assert_eq!(tokens.token_type, "Bearer", "Token type should be Bearer");
}

// ============================================================================
// Token Validation Tests
// ============================================================================

#[test]
fn test_validate_valid_token() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = generate_access_token(user_id, "test@example.com", "testuser", None, None)
        .expect("Failed to generate token");

    let validation = validate_token(&token);
    assert!(
        validation.is_ok(),
        "Should validate valid token successfully"
    );

    let token_data = validation.unwrap();
    assert_eq!(token_data.claims.sub, user_id.to_string());
    assert_eq!(token_data.claims.email, "test@example.com");
    assert_eq!(token_data.claims.username, "testuser");
    assert_eq!(token_data.claims.token_type, "access");
}

#[test]
fn test_validate_invalid_token_format() {
    init_test_keys();

    let result = validate_token("invalid.token.here");
    assert!(result.is_err(), "Should reject token with invalid format");
}

#[test]
fn test_validate_tampered_token() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = generate_access_token(user_id, "test@example.com", "testuser", None, None)
        .expect("Failed to generate token");

    // Tamper with the token by replacing a character in the signature
    let tampered = token.replace("a", "b");
    let result = validate_token(&tampered);
    assert!(result.is_err(), "Should reject tampered token");
}

#[test]
fn test_validate_malformed_token() {
    init_test_keys();

    let malformed_tokens = vec!["invalid", "two.parts", "", "...", "invalid!@#$.token"];

    for malformed in malformed_tokens {
        let result = validate_token(malformed);
        assert!(
            result.is_err(),
            "Should reject malformed token: {}",
            malformed
        );
    }
}

// ============================================================================
// Token Expiration Tests
// ============================================================================

#[test]
fn test_newly_generated_token_not_expired() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = generate_access_token(user_id, "test@example.com", "testuser", None, None)
        .expect("Failed to generate token");

    let is_expired = is_token_expired(&token);
    assert!(is_expired.is_ok(), "Should successfully check expiration");
    assert!(
        !is_expired.unwrap(),
        "Newly generated token should not be expired"
    );
}

// ============================================================================
// Claims Extraction Tests
// ============================================================================

#[test]
fn test_extract_claims_from_valid_token() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let email = "user@example.com";
    let username = "john_doe";

    let token = generate_access_token(user_id, email, username, None, None).expect("Failed to generate token");

    let token_data = validate_token(&token).expect("Failed to validate token");

    assert_eq!(token_data.claims.sub, user_id.to_string());
    assert_eq!(token_data.claims.email, email);
    assert_eq!(token_data.claims.username, username);
}

#[test]
fn test_refresh_token_has_longer_expiry() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let email = "test@example.com";
    let username = "testuser";

    let access =
        generate_access_token(user_id, email, username, None, None).expect("Failed to generate access token");
    let refresh =
        generate_refresh_token(user_id, email, username, None, None).expect("Failed to generate refresh token");

    let access_claims = validate_token(&access).unwrap().claims;
    let refresh_claims = validate_token(&refresh).unwrap().claims;

    assert!(
        refresh_claims.exp > access_claims.exp,
        "Refresh token should have longer expiry than access token"
    );
}

#[test]
fn test_access_token_type() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = generate_access_token(user_id, "test@example.com", "testuser", None, None)
        .expect("Failed to generate token");

    let token_data = validate_token(&token).expect("Failed to validate token");
    assert_eq!(token_data.claims.token_type, "access");
}

#[test]
fn test_refresh_token_type() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let token = generate_refresh_token(user_id, "test@example.com", "testuser", None, None)
        .expect("Failed to generate token");

    let token_data = validate_token(&token).expect("Failed to validate token");
    assert_eq!(token_data.claims.token_type, "refresh");
}

// ============================================================================
// Integration Tests
// ============================================================================

#[test]
fn test_complete_token_lifecycle() {
    init_test_keys();

    let user_id = Uuid::new_v4();
    let email = "integration@example.com";
    let username = "integration_user";

    // 1. Generate token pair
    let token_pair =
        generate_token_pair(user_id, email, username, None, None).expect("Failed to generate token pair");

    // 2. Validate access token
    let access_data =
        validate_token(&token_pair.access_token).expect("Failed to validate access token");
    assert_eq!(access_data.claims.sub, user_id.to_string());
    assert_eq!(access_data.claims.email, email);

    // 3. Validate refresh token
    let refresh_data =
        validate_token(&token_pair.refresh_token).expect("Failed to validate refresh token");
    assert_eq!(refresh_data.claims.sub, user_id.to_string());

    // 4. Check neither is expired
    assert!(
        !is_token_expired(&token_pair.access_token).unwrap(),
        "Access token should not be expired"
    );
    assert!(
        !is_token_expired(&token_pair.refresh_token).unwrap(),
        "Refresh token should not be expired"
    );
}

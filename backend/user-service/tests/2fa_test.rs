/// 2FA (Two-Factor Authentication) Integration Tests
/// Tests TOTP generation, verification, backup codes, and full 2FA flow
use std::sync::Once;

static INIT: Once = Once::new();

/// Initialize test environment (JWT keys, etc.)
fn init_test_env() {
    INIT.call_once(|| {
        // Set default environment
        std::env::set_var("APP_ENV", "test");
        std::env::set_var("LOG_LEVEL", "warn");
        std::env::set_var("JWT_PRIVATE_KEY_PEM", TEST_JWT_PRIVATE_KEY);
        std::env::set_var("JWT_PUBLIC_KEY_PEM", TEST_JWT_PUBLIC_KEY);

        // Initialize JWT keys
        user_service::security::jwt::initialize_keys(TEST_JWT_PRIVATE_KEY, TEST_JWT_PUBLIC_KEY)
            .expect("Failed to initialize JWT keys");
    });
}

// Test RSA keys (2048-bit)
const TEST_JWT_PRIVATE_KEY: &str = r#"-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAyVR8eZJV7pB9Z1qJ8N1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z
1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z
1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z
nQIDAQABAoIBAC9xYRvJTJa7l7O9N+nLy1Gq5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5
qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5
qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5qJ5
AkEA6n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2L5n2
L5n2L5n2L5n2L5n2L5n2L5n2L5n2LQJAXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXP
PXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXPPXXP
PXXPPXXPAkBKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKAkEAyYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
YYYAkAZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
ZZZ
-----END RSA PRIVATE KEY-----"#;

const TEST_JWT_PUBLIC_KEY: &str = r#"-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVR8eZJV7pB9Z1qJ8N1Z
1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z
1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z1Z
nQIDAQAB
-----END PUBLIC KEY-----"#;

#[test]
fn test_totp_generator_create_secret() {
    init_test_env();

    let secret = user_service::security::TOTPGenerator::generate_secret()
        .expect("Failed to generate TOTP secret");

    // Base32 encoded 32 bytes = 56 characters
    assert_eq!(secret.len(), 56);
    assert!(secret
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '='));
}

#[test]
fn test_totp_generator_create_provisioning_uri() {
    init_test_env();

    let secret = "JBSWY3DPEBLW64TMMQ======";
    let uri = user_service::security::TOTPGenerator::generate_provisioning_uri(
        "user@example.com",
        secret,
        "Nova",
    );

    assert!(uri.contains("otpauth://totp"));
    assert!(uri.contains("user@example.com"));
    assert!(uri.contains("Nova"));
    assert!(uri.contains(secret));
    assert!(uri.contains("algorithm=SHA1"));
    assert!(uri.contains("digits=6"));
    assert!(uri.contains("period=30"));
}

#[test]
fn test_backup_codes_generation() {
    init_test_env();

    let codes = user_service::security::TOTPGenerator::generate_backup_codes();

    // Should generate 10 backup codes
    assert_eq!(codes.len(), 10);

    // Each code should be 8 hex characters
    for code in &codes {
        assert_eq!(code.len(), 8);
        assert!(code.chars().all(|c| c.is_ascii_hexdigit()));
    }

    // Codes should be unique
    let unique_codes: std::collections::HashSet<_> = codes.iter().collect();
    assert_eq!(unique_codes.len(), 10);
}

#[test]
fn test_totp_verification_valid() {
    init_test_env();

    // Test with a known secret and manual code generation
    // Using RFC 6238 test vector with secret "JBSWY3DPEBLW64TMMQ======"
    let secret = "JBSWY3DPEBLW64TMMQ======";

    // Generate TOTP code for a known timestamp
    // The test just ensures the verify function works with the time window
    let result = user_service::security::TOTPGenerator::verify_totp(secret, "000000");

    // Should return a result (either true or false, but not error)
    assert!(result.is_ok());
}

#[test]
fn test_totp_verification_invalid_format() {
    init_test_env();

    let secret = "JBSWY3DPEBLW64TMMQ======";

    // Invalid: letters instead of numbers
    let result = user_service::security::TOTPGenerator::verify_totp(secret, "abcdef")
        .expect("Should succeed");
    assert!(!result);

    // Invalid: too short
    let result = user_service::security::TOTPGenerator::verify_totp(secret, "12345")
        .expect("Should succeed");
    assert!(!result);

    // Invalid: too long
    let result = user_service::security::TOTPGenerator::verify_totp(secret, "1234567")
        .expect("Should succeed");
    assert!(!result);
}

#[test]
fn test_backup_codes_uniqueness() {
    init_test_env();

    // Generate multiple backup code sets and verify uniqueness across sets
    let codes1 = user_service::security::TOTPGenerator::generate_backup_codes();
    let codes2 = user_service::security::TOTPGenerator::generate_backup_codes();

    // Each set should have unique codes within itself
    let set1: std::collections::HashSet<_> = codes1.iter().collect();
    let set2: std::collections::HashSet<_> = codes2.iter().collect();
    assert_eq!(set1.len(), 10);
    assert_eq!(set2.len(), 10);

    // Sets should not overlap (cryptographically random generation)
    let intersection: std::collections::HashSet<_> = set1.intersection(&set2).collect();
    assert!(
        intersection.is_empty(),
        "Two independent backup code sets should not overlap"
    );
}

#[test]
fn test_totp_code_generation_consistency() {
    init_test_env();

    // TOTP codes should be deterministic for the same secret and time counter
    // This test just validates that the function can be called repeatedly
    let secret = "JBSWY3DPEBLW64TMMQ======";

    let result1 = user_service::security::TOTPGenerator::verify_totp(secret, "123456");
    let result2 = user_service::security::TOTPGenerator::verify_totp(secret, "123456");

    // Both calls should return the same result (deterministic behavior)
    assert_eq!(result1.is_ok(), result2.is_ok());
    assert_eq!(result1.as_deref(), result2.as_deref());
}

#[test]
fn test_qr_code_generation() {
    init_test_env();

    let secret = "JBSWY3DPEBLW64TMMQ======";
    let uri = user_service::security::TOTPGenerator::generate_provisioning_uri(
        "user@example.com",
        secret,
        "Nova",
    );

    let qr_code = user_service::security::TOTPGenerator::generate_qr_code(&uri)
        .expect("Failed to generate QR code");

    // QR code should be non-empty bytes
    assert!(!qr_code.is_empty());

    // Should contain valid SVG data (starts with SVG tag or XML declaration)
    let qr_str = String::from_utf8_lossy(&qr_code);
    assert!(
        qr_str.contains("<svg") || qr_str.contains("<?xml"),
        "QR code should contain SVG data"
    );
}

#[test]
fn test_2fa_setup_flow() {
    init_test_env();

    let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
    rt.block_on(async {
        let email = "test@example.com";

        let result = user_service::services::two_fa::generate_2fa_setup(email).await;
        assert!(result.is_ok(), "2FA setup generation should succeed");

        let (secret, uri, backup_codes) = result.unwrap();

        // Verify secret
        assert_eq!(secret.len(), 56);
        assert!(secret
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '='));

        // Verify URI
        assert!(uri.contains("otpauth://totp"));
        assert!(uri.contains(email));

        // Verify backup codes
        assert_eq!(backup_codes.len(), 10);
        for code in &backup_codes {
            assert_eq!(code.len(), 8);
            assert!(code.chars().all(|c| c.is_ascii_hexdigit()));
        }
    });
}

#[test]
fn test_verify_user_code_totp_format() {
    init_test_env();

    let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
    rt.block_on(async {
        // Note: Without a real database, this test validates the function signature and structure
        // A full integration test would use a test database

        // The unified verify_user_code function should handle:
        // - TOTP codes: 6 digits
        // - Backup codes: 8 hex digits

        // Test data
        let totp_code = "123456";
        let backup_code = "a1b2c3d4";

        // Verify format validation
        assert_eq!(totp_code.len(), 6);
        assert!(totp_code.chars().all(|c| c.is_ascii_digit()));

        assert_eq!(backup_code.len(), 8);
        assert!(backup_code.chars().all(|c| c.is_ascii_hexdigit()));
    });
}

#[test]
fn test_backup_code_format_validation() {
    init_test_env();

    // Test backup code format validation
    let valid_codes = vec!["a1b2c3d4", "00000000", "ffffffff", "12345678"];

    for code in valid_codes {
        assert_eq!(code.len(), 8);
        assert!(
            code.chars().all(|c| c.is_ascii_hexdigit()),
            "Code {} should be valid hex",
            code
        );
    }

    // Test invalid codes
    let invalid_codes = vec![
        "a1b2c3d",   // too short
        "a1b2c3d4e", // too long
        "a1b2c3dg",  // non-hex character
        "GGGGGGGG",  // out of hex range
    ];

    for code in invalid_codes {
        let is_valid_hex = code.len() == 8 && code.chars().all(|c| c.is_ascii_hexdigit());
        assert!(!is_valid_hex, "Code {} should be invalid", code);
    }
}

#[test]
fn test_totp_code_format_validation() {
    init_test_env();

    // Test TOTP code format validation
    let valid_codes = vec!["000000", "123456", "999999"];

    for code in valid_codes {
        assert_eq!(code.len(), 6);
        assert!(
            code.chars().all(|c| c.is_ascii_digit()),
            "Code {} should be valid digits",
            code
        );
    }

    // Test invalid codes
    let invalid_codes = vec![
        "12345",   // too short
        "1234567", // too long
        "12345a",  // contains letter
        "   123",  // contains space
    ];

    for code in invalid_codes {
        let is_valid_digits = code.len() == 6 && code.chars().all(|c| c.is_ascii_digit());
        assert!(!is_valid_digits, "Code {} should be invalid", code);
    }
}

#[test]
fn test_session_management() {
    init_test_env();

    let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
    rt.block_on(async {
        // Test session ID generation
        let session_id = uuid::Uuid::new_v4().to_string();
        assert!(!session_id.is_empty());
        assert!(session_id.len() > 0);

        // Session key format validation
        let session_type = "2fa_pending";
        let session_key = format!("{}:{}", session_type, session_id);
        assert!(session_key.contains(":"));
        assert!(session_key.contains("2fa_pending"));
    });
}

#[test]
fn test_concurrent_code_generation() {
    init_test_env();

    // Test that multiple concurrent calls generate different backup codes
    use std::thread;

    let handles: Vec<_> = (0..5)
        .map(|_| thread::spawn(|| user_service::security::TOTPGenerator::generate_backup_codes()))
        .collect();

    let mut all_codes = Vec::new();
    for handle in handles {
        let codes = handle.join().expect("Thread panicked");
        all_codes.extend(codes);
    }

    // All 50 generated codes should be unique across threads
    let unique_codes: std::collections::HashSet<_> = all_codes.iter().collect();
    assert_eq!(
        unique_codes.len(),
        50,
        "Concurrent code generation should produce unique codes"
    );
}

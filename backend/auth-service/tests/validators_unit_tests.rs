/// Unit tests for auth-service input validators
///
/// This test module covers:
/// - Email format validation
/// - Username format validation
/// - Password strength requirements
/// - Edge cases and boundary conditions

use auth_service::validators::{validate_email, validate_password, validate_username};

// ============================================================================
// Email Validation Tests
// ============================================================================

#[test]
fn test_valid_email_formats() {
    assert!(validate_email("user@example.com"));
    assert!(validate_email("test.user@example.com"));
    assert!(validate_email("user+tag@example.co.uk"));
    assert!(validate_email("user_name@sub.domain.com"));
    assert!(validate_email("a@b.co"));
    assert!(validate_email("test123@example.com"));
}

#[test]
fn test_invalid_email_missing_at() {
    assert!(!validate_email("userexample.com"));
}

#[test]
fn test_invalid_email_missing_domain() {
    assert!(!validate_email("user@"));
}

#[test]
fn test_invalid_email_missing_local_part() {
    assert!(!validate_email("@example.com"));
}

#[test]
fn test_invalid_email_missing_tld() {
    assert!(!validate_email("user@example"));
}

#[test]
fn test_invalid_email_multiple_at_signs() {
    assert!(!validate_email("user@domain@example.com"));
}

#[test]
fn test_invalid_email_empty_string() {
    assert!(!validate_email(""));
}

#[test]
fn test_invalid_email_spaces() {
    assert!(!validate_email("user @example.com"));
    assert!(!validate_email("user@ example.com"));
}

#[test]
fn test_valid_email_max_length() {
    // RFC 5321: email addresses can be up to 254 characters
    let long_email = format!("{}@example.com", "a".repeat(240));
    assert!(validate_email(&long_email));
}

#[test]
fn test_invalid_email_exceeds_max_length() {
    // Email longer than 254 characters should fail
    let too_long_email = format!("{}@example.com", "a".repeat(250));
    assert!(!validate_email(&too_long_email));
}

// ============================================================================
// Username Validation Tests
// ============================================================================

#[test]
fn test_valid_username_formats() {
    assert!(validate_username("john_doe"));
    assert!(validate_username("user-123"));
    assert!(validate_username("abc"));
    assert!(validate_username("test_user_123"));
    assert!(validate_username("john-doe-2024"));
}

#[test]
fn test_invalid_username_too_short() {
    assert!(!validate_username("ab")); // 2 chars
    assert!(!validate_username("a"));  // 1 char
    assert!(!validate_username(""));   // 0 chars
}

#[test]
fn test_invalid_username_too_long() {
    assert!(!validate_username(&"a".repeat(33))); // 33 chars
}

#[test]
fn test_valid_username_boundary_3_chars() {
    assert!(validate_username("abc"));
}

#[test]
fn test_valid_username_boundary_32_chars() {
    assert!(validate_username(&"a".repeat(32)));
}

#[test]
fn test_invalid_username_invalid_characters() {
    assert!(!validate_username("user@name"));
    assert!(!validate_username("user name"));
    assert!(!validate_username("user.name"));
    assert!(!validate_username("user!"));
    assert!(!validate_username("user#"));
    assert!(!validate_username("user$"));
}

#[test]
fn test_valid_username_alphanumeric() {
    assert!(validate_username("user123"));
    assert!(validate_username("ABC123"));
    assert!(validate_username("test"));
}

// ============================================================================
// Password Strength Tests
// ============================================================================

#[test]
fn test_valid_password_all_requirements_met() {
    assert!(validate_password("SecurePass123!"));
    assert!(validate_password("MyP@ssw0rd"));
    assert!(validate_password("T3st#Pass"));
}

#[test]
fn test_invalid_password_too_short() {
    assert!(!validate_password("Short1!")); // 7 chars
}

#[test]
fn test_valid_password_minimum_length() {
    assert!(validate_password("ValidPass1!")); // 11 chars, meets all requirements
}

#[test]
fn test_invalid_password_no_uppercase() {
    assert!(!validate_password("securepass123!"));
}

#[test]
fn test_invalid_password_no_lowercase() {
    assert!(!validate_password("SECUREPASS123!"));
}

#[test]
fn test_invalid_password_no_digit() {
    assert!(!validate_password("SecurePass!"));
}

#[test]
fn test_invalid_password_no_special_character() {
    assert!(!validate_password("SecurePassword1"));
}

#[test]
fn test_valid_password_with_various_special_chars() {
    assert!(validate_password("Pass1!word"));
    assert!(validate_password("Pass1@word"));
    assert!(validate_password("Pass1#word"));
    assert!(validate_password("Pass1$word"));
    assert!(validate_password("Pass1%word"));
    assert!(validate_password("Pass1&word"));
    assert!(validate_password("Pass1*word"));
    assert!(validate_password("Pass1-word"));
    assert!(validate_password("Pass1_word"));
}

#[test]
fn test_valid_password_exactly_8_chars() {
    // Exactly 8 characters with all requirements met
    assert!(validate_password("Pass1!ab"));
}

#[test]
fn test_valid_password_long() {
    assert!(validate_password("VeryLongSecurePassword123!@#"));
}

#[test]
fn test_invalid_password_empty() {
    assert!(!validate_password(""));
}

// ============================================================================
// Combination Tests
// ============================================================================

#[test]
fn test_typical_user_registration_valid() {
    // Simulate a typical registration scenario
    let email = "jane.doe@example.com";
    let username = "jane_doe";
    let password = "SecurePassword123!";

    assert!(validate_email(email), "Email should be valid");
    assert!(validate_username(username), "Username should be valid");
    assert!(validate_password(password), "Password should be valid");
}

#[test]
fn test_typical_user_registration_invalid_password() {
    let email = "john@example.com";
    let username = "john_123";
    let password = "weakpass"; // Missing uppercase, digit, special char

    assert!(validate_email(email), "Email should be valid");
    assert!(validate_username(username), "Username should be valid");
    assert!(!validate_password(password), "Password should be invalid");
}

#[test]
fn test_typical_user_registration_invalid_username() {
    let email = "test@example.com";
    let username = "ab"; // Too short
    let password = "ValidPass1!";

    assert!(validate_email(email), "Email should be valid");
    assert!(!validate_username(username), "Username should be invalid");
    assert!(validate_password(password), "Password should be valid");
}

#[test]
fn test_typical_user_registration_invalid_email() {
    let email = "invalid.email"; // Missing domain TLD
    let username = "valid_user";
    let password = "ValidPass1!";

    assert!(!validate_email(email), "Email should be invalid");
    assert!(validate_username(username), "Username should be valid");
    assert!(validate_password(password), "Password should be valid");
}

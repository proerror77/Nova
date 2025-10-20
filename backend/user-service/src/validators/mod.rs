/// Input validation utilities for auth service
use validator::ValidateEmail;

/// Validates email format according to RFC 5322
pub fn validate_email(email: &str) -> bool {
    email.validate_email()
}

/// Validates password strength
/// Requirements:
/// - Minimum 8 characters
/// - At least one uppercase letter
/// - At least one lowercase letter
/// - At least one number
/// - At least one special character
pub fn validate_password(password: &str) -> bool {
    if password.len() < 8 {
        return false;
    }

    let has_upper = password.chars().any(|c| c.is_uppercase());
    let has_lower = password.chars().any(|c| c.is_lowercase());
    let has_digit = password.chars().any(|c| c.is_numeric());
    let has_special = password.chars().any(|c| !c.is_alphanumeric());

    has_upper && has_lower && has_digit && has_special
}

/// Validates username format
/// Requirements:
/// - Length between 3 and 32 characters
/// - Only alphanumeric, underscore, and hyphen allowed
/// - Must start with alphanumeric character
pub fn validate_username(username: &str) -> bool {
    if username.len() < 3 || username.len() > 32 {
        return false;
    }

    let first_char_valid = username
        .chars()
        .next()
        .map(|c| c.is_alphanumeric())
        .unwrap_or(false);

    if !first_char_valid {
        return false;
    }

    username
        .chars()
        .all(|c| c.is_alphanumeric() || c == '_' || c == '-')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_email_valid() {
        assert!(validate_email("user@example.com"));
        assert!(validate_email("user+tag@example.co.uk"));
    }

    #[test]
    fn test_validate_email_invalid() {
        assert!(!validate_email("invalid-email"));
        assert!(!validate_email("@example.com"));
        assert!(!validate_email("user@"));
    }

    #[test]
    fn test_validate_password_valid() {
        assert!(validate_password("SecurePass123!"));
        assert!(validate_password("MyPassword@2024"));
    }

    #[test]
    fn test_validate_password_too_short() {
        assert!(!validate_password("Pass1!"));
    }

    #[test]
    fn test_validate_password_missing_uppercase() {
        assert!(!validate_password("secure@pass123"));
    }

    #[test]
    fn test_validate_password_missing_lowercase() {
        assert!(!validate_password("SECURE@PASS123"));
    }

    #[test]
    fn test_validate_password_missing_digit() {
        assert!(!validate_password("SecurePass!"));
    }

    #[test]
    fn test_validate_password_missing_special() {
        assert!(!validate_password("SecurePass123"));
    }

    #[test]
    fn test_validate_username_valid() {
        assert!(validate_username("user123"));
        assert!(validate_username("user-name"));
        assert!(validate_username("user_name"));
    }

    #[test]
    fn test_validate_username_too_short() {
        assert!(!validate_username("ab"));
    }

    #[test]
    fn test_validate_username_too_long() {
        assert!(!validate_username(&"a".repeat(33)));
    }

    #[test]
    fn test_validate_username_starts_with_special() {
        assert!(!validate_username("_username"));
        assert!(!validate_username("-username"));
    }

    #[test]
    fn test_validate_username_invalid_characters() {
        assert!(!validate_username("user@name"));
        assert!(!validate_username("user.name"));
        assert!(!validate_username("user name"));
    }
}

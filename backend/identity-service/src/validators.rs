use once_cell::sync::Lazy;
use regex::Regex;
use validator::ValidationError;

/// Input validation utilities for identity service

// Compile regex patterns once at startup
// These patterns are hardcoded and always valid, so we use expect() with explicit reasoning
static EMAIL_REGEX: Lazy<Regex> = Lazy::new(|| {
    // This regex is hardcoded and validated - it is a compile-time constant in practice
    Regex::new(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
        .expect("hardcoded email regex is invalid - fix source code")
});

static USERNAME_REGEX: Lazy<Regex> = Lazy::new(|| {
    // This regex is hardcoded and validated - it is a compile-time constant in practice
    Regex::new(r"^[a-zA-Z0-9_-]{3,32}$")
        .expect("hardcoded username regex is invalid - fix source code")
});

/// Validate email format (RFC 5322 simplified)
pub fn validate_email(email: &str) -> bool {
    !email.is_empty() && email.len() <= 254 && EMAIL_REGEX.is_match(email)
}

/// Validate username format (3-32 characters, alphanumeric with - and _)
pub fn validate_username(username: &str) -> bool {
    USERNAME_REGEX.is_match(username)
}

/// validator crate compatible custom validator for username shape
pub fn validate_username_shape_validator(username: &str) -> Result<(), ValidationError> {
    if validate_username(username) {
        Ok(())
    } else {
        Err(ValidationError::new("invalid_username"))
    }
}

/// Validate password strength requirements
/// - Minimum 6 characters
/// - At least one uppercase letter
/// - At least one lowercase letter
/// - At least one digit
/// - At least one special character
pub fn validate_password(password: &str) -> bool {
    if password.len() < 6 {
        return false;
    }

    let has_uppercase = password.chars().any(|c| c.is_uppercase());
    let has_lowercase = password.chars().any(|c| c.is_lowercase());
    let has_digit = password.chars().any(|c| c.is_ascii_digit());
    let has_special = password.chars().any(|c| !c.is_alphanumeric());

    has_uppercase && has_lowercase && has_digit && has_special
}

/// Validate password strength using zxcvbn (entropy-based)
/// Returns true if password has zxcvbn score >= 3
pub fn validate_password_strength_zxcvbn(password: &str) -> bool {
    let entropy = zxcvbn::zxcvbn(password, &[]);
    match entropy {
        Ok(result) => result.score() >= 3,
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_email() {
        assert!(validate_email("user@example.com"));
        assert!(validate_email("test.user+tag@sub.example.co.uk"));
    }

    #[test]
    fn test_invalid_email() {
        assert!(!validate_email("invalid"));
        assert!(!validate_email("@example.com"));
        assert!(!validate_email("user@"));
    }

    #[test]
    fn test_valid_username() {
        assert!(validate_username("john_doe"));
        assert!(validate_username("user-123"));
        assert!(validate_username("abc"));
    }

    #[test]
    fn test_invalid_username() {
        assert!(!validate_username("ab")); // Too short
        assert!(!validate_username(&"a".repeat(33))); // Too long
        assert!(!validate_username("user@name")); // Invalid character
    }

    #[test]
    fn test_valid_password() {
        assert!(validate_password("SecurePass123!"));
        assert!(validate_password("MyP@ssw0rd"));
    }

    #[test]
    fn test_invalid_password() {
        assert!(!validate_password("short1!")); // Too short
        assert!(!validate_password("password123!")); // No uppercase
        assert!(!validate_password("PASSWORD123!")); // No lowercase
        assert!(!validate_password("SecurePassword1")); // No special char
        assert!(!validate_password("SecurePass!")); // No digit
    }

    #[test]
    fn test_password_strength_zxcvbn() {
        assert!(validate_password_strength_zxcvbn(
            "correct-horse-battery-staple"
        ));
        assert!(!validate_password_strength_zxcvbn("password"));
    }
}

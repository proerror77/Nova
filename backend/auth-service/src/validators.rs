/// Input validation utilities
use regex::Regex;
use once_cell::sync::Lazy;

// Compile regex patterns once at startup
static EMAIL_REGEX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$").unwrap()
});

static USERNAME_REGEX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"^[a-zA-Z0-9_-]{3,32}$").unwrap()
});

/// Validate email format
pub fn validate_email(email: &str) -> bool {
    !email.is_empty() && email.len() <= 254 && EMAIL_REGEX.is_match(email)
}

/// Validate username format (3-32 characters, alphanumeric with - and _)
pub fn validate_username(username: &str) -> bool {
    USERNAME_REGEX.is_match(username)
}

/// Validate password strength requirements
/// - Minimum 8 characters
/// - At least one uppercase letter
/// - At least one lowercase letter
/// - At least one digit
/// - At least one special character
pub fn validate_password(password: &str) -> bool {
    if password.len() < 8 {
        return false;
    }

    let has_uppercase = password.chars().any(|c| c.is_uppercase());
    let has_lowercase = password.chars().any(|c| c.is_lowercase());
    let has_digit = password.chars().any(|c| c.is_ascii_digit());
    let has_special = password.chars().any(|c| !c.is_alphanumeric());

    has_uppercase && has_lowercase && has_digit && has_special
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
        assert!(!validate_username("a".repeat(33))); // Too long
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
}

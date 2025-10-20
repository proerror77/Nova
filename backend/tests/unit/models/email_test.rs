/// Email validation tests (AUTH-1001)
/// Tests for RFC 5322 compliant email validation

#[cfg(test)]
mod tests {
    use validator::ValidateEmail;

    /// Helper function to validate email format
    fn validate_email(email: &str) -> bool {
        email.validate_email()
    }

    #[test]
    fn test_valid_email_basic() {
        assert!(validate_email("user@example.com"));
    }

    #[test]
    fn test_valid_email_with_subdomain() {
        assert!(validate_email("user@mail.example.com"));
    }

    #[test]
    fn test_valid_email_with_plus() {
        assert!(validate_email("user+tag@example.com"));
    }

    #[test]
    fn test_valid_email_with_numbers() {
        assert!(validate_email("user123@example123.com"));
    }

    #[test]
    fn test_valid_email_with_dots() {
        assert!(validate_email("user.name@example.com"));
    }

    #[test]
    fn test_valid_email_with_hyphen() {
        assert!(validate_email("user-name@example.com"));
    }

    #[test]
    fn test_invalid_email_no_at_sign() {
        assert!(!validate_email("userexample.com"));
    }

    #[test]
    fn test_invalid_email_no_domain() {
        assert!(!validate_email("user@"));
    }

    #[test]
    fn test_invalid_email_no_user() {
        assert!(!validate_email("@example.com"));
    }

    #[test]
    fn test_invalid_email_no_tld() {
        assert!(!validate_email("user@example"));
    }

    #[test]
    fn test_invalid_email_space() {
        assert!(!validate_email("user @example.com"));
    }

    #[test]
    fn test_invalid_email_double_at() {
        assert!(!validate_email("user@@example.com"));
    }

    #[test]
    fn test_invalid_email_consecutive_dots() {
        assert!(!validate_email("user..name@example.com"));
    }

    #[test]
    fn test_invalid_email_empty_string() {
        assert!(!validate_email(""));
    }

    #[test]
    fn test_invalid_email_only_whitespace() {
        assert!(!validate_email("   "));
    }

    #[test]
    fn test_valid_email_long_local_part() {
        let long_email = "verylonglocalpartwithmanycharacters12345@example.com";
        assert!(validate_email(long_email));
    }

    #[test]
    fn test_valid_email_numerical_domain() {
        assert!(validate_email("user@123.456.789.com"));
    }

    #[test]
    fn test_valid_email_uppercase() {
        // Email should be case-insensitive for domain part
        assert!(validate_email("User@Example.COM"));
    }

    #[test]
    fn test_invalid_email_special_chars() {
        assert!(!validate_email("user!name@example.com"));
    }
}

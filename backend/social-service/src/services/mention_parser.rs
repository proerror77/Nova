//! Mention Parser Utility
//!
//! Extracts @mentions from text content for notification purposes.

use regex::Regex;
use std::sync::LazyLock;

/// Regex pattern for matching @mentions
/// Matches @username where username can contain alphanumeric characters and underscores
static MENTION_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"@([a-zA-Z0-9_]+)").expect("Invalid mention regex"));

/// Extract @mentions from content text
///
/// Returns a deduplicated list of usernames mentioned (without the @ symbol).
///
/// # Examples
/// ```
/// use social_service::services::extract_mentions;
///
/// let content = "Hey @alice and @bob, check this out! @alice again";
/// let mentions = extract_mentions(content);
/// assert_eq!(mentions, vec!["alice", "bob"]);
/// ```
pub fn extract_mentions(content: &str) -> Vec<String> {
    let mentions: Vec<String> = MENTION_REGEX
        .captures_iter(content)
        .filter_map(|cap| cap.get(1).map(|m| m.as_str().to_lowercase()))
        .collect();

    // Deduplicate while preserving first occurrence order
    let mut seen = std::collections::HashSet::new();
    mentions
        .into_iter()
        .filter(|username| seen.insert(username.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_single_mention() {
        let content = "Hello @alice!";
        let mentions = extract_mentions(content);
        assert_eq!(mentions, vec!["alice"]);
    }

    #[test]
    fn test_extract_multiple_mentions() {
        let content = "Hey @alice and @bob123, check this out!";
        let mentions = extract_mentions(content);
        assert_eq!(mentions, vec!["alice", "bob123"]);
    }

    #[test]
    fn test_extract_duplicate_mentions() {
        let content = "@alice said hi to @bob, then @alice replied";
        let mentions = extract_mentions(content);
        assert_eq!(mentions, vec!["alice", "bob"]);
    }

    #[test]
    fn test_extract_no_mentions() {
        let content = "Hello world!";
        let mentions = extract_mentions(content);
        assert!(mentions.is_empty());
    }

    #[test]
    fn test_extract_mentions_case_insensitive() {
        let content = "@Alice and @ALICE and @alice";
        let mentions = extract_mentions(content);
        assert_eq!(mentions, vec!["alice"]); // All normalized to lowercase
    }

    #[test]
    fn test_extract_mentions_with_underscores() {
        let content = "Hello @user_name_123!";
        let mentions = extract_mentions(content);
        assert_eq!(mentions, vec!["user_name_123"]);
    }

    #[test]
    fn test_extract_mentions_at_boundaries() {
        let content = "@start middle @end";
        let mentions = extract_mentions(content);
        assert_eq!(mentions, vec!["start", "end"]);
    }

    #[test]
    fn test_extract_mentions_chinese_content() {
        let content = "你好 @alice 欢迎加入！";
        let mentions = extract_mentions(content);
        assert_eq!(mentions, vec!["alice"]);
    }
}

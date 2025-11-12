use crate::error::{Result, TrustSafetyError};
use crate::models::ModerationResult;
use regex::Regex;
use std::collections::HashSet;
use std::fs;
use std::path::Path;
use unicode_segmentation::UnicodeSegmentation;

/// Text moderator with sensitive words and pattern detection
pub struct TextModerator {
    sensitive_words: HashSet<String>,
    patterns: Vec<Regex>,
}

impl TextModerator {
    /// Create new text moderator
    pub fn new(words_file: impl AsRef<Path>) -> Result<Self> {
        let sensitive_words = Self::load_words(words_file)?;
        let patterns = Self::compile_patterns();

        Ok(Self {
            sensitive_words,
            patterns,
        })
    }

    /// Check text for violations
    pub fn check(&self, text: &str) -> ModerationResult {
        if text.is_empty() {
            return ModerationResult::safe();
        }

        let normalized = text.to_lowercase();
        let mut violations = Vec::new();

        // Check 1: Exact sensitive words
        for word in &self.sensitive_words {
            if self.contains_word(&normalized, word) {
                violations.push(format!("sensitive_word: {}", word));
                tracing::debug!("Flagged for sensitive word: {}", word);
            }
        }

        // Check 2: Suspicious patterns
        for (idx, pattern) in self.patterns.iter().enumerate() {
            if pattern.is_match(&normalized) {
                violations.push(format!("suspicious_pattern_{}", idx));
                tracing::debug!("Flagged for pattern match: {}", pattern.as_str());
            }
        }

        // Check 3: Excessive capitalization (spam indicator)
        if self.has_excessive_caps(text) {
            violations.push("excessive_capitalization".to_string());
        }

        // Check 4: Repeated characters (spam indicator)
        if self.has_repeated_chars(text) {
            violations.push("repeated_characters".to_string());
        }

        if violations.is_empty() {
            ModerationResult::safe()
        } else {
            ModerationResult::with_violations(
                violations.clone(),
                format!("Found {} violations", violations.len()),
            )
        }
    }

    /// Load sensitive words from file
    fn load_words(path: impl AsRef<Path>) -> Result<HashSet<String>> {
        let content = fs::read_to_string(path.as_ref()).map_err(|e| {
            TrustSafetyError::Config(format!(
                "Failed to load sensitive words from {}: {}",
                path.as_ref().display(),
                e
            ))
        })?;

        let words = content
            .lines()
            .filter(|line| !line.trim().is_empty() && !line.starts_with('#'))
            .map(|line| line.trim().to_lowercase())
            .collect();

        Ok(words)
    }

    /// Compile regex patterns for suspicious content
    fn compile_patterns() -> Vec<Regex> {
        vec![
            // Phone numbers (various formats)
            Regex::new(r"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b").expect("Phone regex pattern is valid"),
            // Email addresses
            Regex::new(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b")
                .expect("Email regex pattern is valid"),
            // URLs (basic pattern)
            Regex::new(r"https?://[^\s]+").expect("URL regex pattern is valid"),
            // Credit card patterns (basic)
            Regex::new(r"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b")
                .expect("Credit card regex pattern is valid"),
            // Excessive repeated punctuation
            Regex::new(r"[!?]{4,}").expect("Punctuation regex pattern is valid"),
        ]
    }

    /// Check if text contains word (word boundary aware)
    fn contains_word(&self, text: &str, word: &str) -> bool {
        // Use Unicode word boundaries
        let words = text.unicode_words().collect::<Vec<_>>();
        words.contains(&word)
    }

    /// Check for excessive capitalization (>70% caps)
    fn has_excessive_caps(&self, text: &str) -> bool {
        let letters: Vec<char> = text.chars().filter(|c| c.is_alphabetic()).collect();

        if letters.len() < 10 {
            return false; // Too short to determine
        }

        let caps_count = letters.iter().filter(|c| c.is_uppercase()).count();
        let caps_ratio = caps_count as f32 / letters.len() as f32;

        caps_ratio > 0.7
    }

    /// Check for repeated characters (e.g., "hellooooo")
    fn has_repeated_chars(&self, text: &str) -> bool {
        let pattern = Regex::new(r"(.)\1{4,}").expect("Repeated character regex pattern is valid");
        pattern.is_match(text)
    }

    /// Calculate toxicity score (0.0 - 1.0)
    pub fn calculate_toxicity_score(&self, text: &str) -> f32 {
        let result = self.check(text);

        if !result.is_flagged {
            return 0.0;
        }

        // Calculate score based on violation types
        let mut score: f32 = 0.0;

        for violation in &result.violations {
            if violation.starts_with("sensitive_word") {
                score += 0.3;
            } else if violation.starts_with("suspicious_pattern") {
                score += 0.2;
            } else if violation == "excessive_capitalization" {
                score += 0.1;
            } else if violation == "repeated_characters" {
                score += 0.1;
            }
        }

        score.min(1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn create_test_words_file() -> NamedTempFile {
        let mut file = NamedTempFile::new().unwrap();
        writeln!(file, "badword").unwrap();
        writeln!(file, "offensive").unwrap();
        writeln!(file, "# Comment line").unwrap();
        writeln!(file, "").unwrap();
        writeln!(file, "inappropriate").unwrap();
        file
    }

    #[test]
    fn test_load_words() {
        let file = create_test_words_file();
        let moderator = TextModerator::new(file.path()).unwrap();

        assert_eq!(moderator.sensitive_words.len(), 3);
        assert!(moderator.sensitive_words.contains("badword"));
        assert!(moderator.sensitive_words.contains("offensive"));
        assert!(moderator.sensitive_words.contains("inappropriate"));
    }

    #[test]
    fn test_check_safe_text() {
        let file = create_test_words_file();
        let moderator = TextModerator::new(file.path()).unwrap();

        let result = moderator.check("This is a perfectly safe message");
        assert!(!result.is_flagged);
        assert!(result.violations.is_empty());
    }

    #[test]
    fn test_check_flagged_text() {
        let file = create_test_words_file();
        let moderator = TextModerator::new(file.path()).unwrap();

        let result = moderator.check("This contains a badword");
        assert!(result.is_flagged);
        assert!(!result.violations.is_empty());
    }

    #[test]
    fn test_excessive_caps() {
        let file = create_test_words_file();
        let moderator = TextModerator::new(file.path()).unwrap();

        let result = moderator.check("HELLO THIS IS ALL CAPS");
        assert!(result.is_flagged);
        assert!(result
            .violations
            .contains(&"excessive_capitalization".to_string()));
    }

    #[test]
    fn test_repeated_chars() {
        let file = create_test_words_file();
        let moderator = TextModerator::new(file.path()).unwrap();

        let result = moderator.check("Hellooooooo");
        assert!(result.is_flagged);
        assert!(result
            .violations
            .contains(&"repeated_characters".to_string()));
    }

    #[test]
    fn test_email_pattern() {
        let file = create_test_words_file();
        let moderator = TextModerator::new(file.path()).unwrap();

        let result = moderator.check("Contact me at test@example.com");
        assert!(result.is_flagged);
    }

    #[test]
    fn test_toxicity_score() {
        let file = create_test_words_file();
        let moderator = TextModerator::new(file.path()).unwrap();

        let score1 = moderator.calculate_toxicity_score("This is fine");
        assert_eq!(score1, 0.0);

        let score2 = moderator.calculate_toxicity_score("This has badword");
        assert!(score2 > 0.0);
    }
}

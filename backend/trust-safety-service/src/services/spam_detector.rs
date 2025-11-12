use regex::Regex;
use std::collections::HashSet;

/// Context for spam detection
#[derive(Debug, Clone)]
pub struct SpamContext {
    pub has_repeated_content: bool,
    pub seconds_since_last_post: u64,
    pub recent_post_count: u32,
    pub account_age_days: u64,
    pub is_verified: bool,
    pub link_count: usize,
}

impl Default for SpamContext {
    fn default() -> Self {
        Self {
            has_repeated_content: false,
            seconds_since_last_post: 3600,
            recent_post_count: 0,
            account_age_days: 365,
            is_verified: false,
            link_count: 0,
        }
    }
}

/// Spam detector using heuristics
pub struct SpamDetector {
    url_pattern: Regex,
}

impl Default for SpamDetector {
    fn default() -> Self {
        Self::new()
    }
}

impl SpamDetector {
    pub fn new() -> Self {
        Self {
            url_pattern: Regex::new(r"https?://[^\s]+").unwrap(),
        }
    }

    /// Detect spam based on context and content
    pub fn detect(&self, context: &SpamContext, text: &str) -> f32 {
        let mut score: f32 = 0.0;

        // Heuristic 1: Repeated content (high weight)
        if context.has_repeated_content {
            score += 0.4;
            tracing::debug!("Spam indicator: repeated content (+0.4)");
        }

        // Heuristic 2: Rapid posting (time-based)
        if context.seconds_since_last_post < 10 {
            score += 0.4;
            tracing::debug!("Spam indicator: rapid posting (<10s, +0.4)");
        } else if context.seconds_since_last_post < 60 {
            score += 0.2;
            tracing::debug!("Spam indicator: fast posting (<60s, +0.2)");
        }

        // Heuristic 3: High post frequency
        if context.recent_post_count > 20 {
            score += 0.3;
            tracing::debug!("Spam indicator: high frequency (>20/hour, +0.3)");
        } else if context.recent_post_count > 10 {
            score += 0.15;
            tracing::debug!("Spam indicator: elevated frequency (>10/hour, +0.15)");
        }

        // Heuristic 4: New account (unverified)
        if !context.is_verified {
            if context.account_age_days < 1 {
                score += 0.3;
                tracing::debug!("Spam indicator: brand new account (<1 day, +0.3)");
            } else if context.account_age_days < 7 {
                score += 0.15;
                tracing::debug!("Spam indicator: new account (<7 days, +0.15)");
            }
        }

        // Heuristic 5: Excessive links
        let link_count = if context.link_count > 0 {
            context.link_count
        } else {
            self.count_links(text)
        };

        if link_count > 5 {
            score += 0.4;
            tracing::debug!("Spam indicator: many links (>5, +0.4)");
        } else if link_count > 3 {
            score += 0.2;
            tracing::debug!("Spam indicator: multiple links (>3, +0.2)");
        } else if link_count > 1 {
            score += 0.1;
            tracing::debug!("Spam indicator: some links (>1, +0.1)");
        }

        // Heuristic 6: Short message with links (classic spam)
        if !text.is_empty() && link_count > 0 {
            let word_count = text.split_whitespace().count();
            if word_count < 10 && link_count >= 1 {
                score += 0.2;
                tracing::debug!("Spam indicator: short message with links (+0.2)");
            }
        }

        // Heuristic 7: Suspicious patterns
        if self.has_suspicious_patterns(text) {
            score += 0.15;
            tracing::debug!("Spam indicator: suspicious patterns (+0.15)");
        }

        // Verified users get a discount
        if context.is_verified {
            score *= 0.5;
            tracing::debug!("Verified user: reducing spam score by 50%");
        }

        score.min(1.0)
    }

    /// Count links in text
    fn count_links(&self, text: &str) -> usize {
        self.url_pattern.find_iter(text).count()
    }

    /// Check for suspicious spam patterns
    fn has_suspicious_patterns(&self, text: &str) -> bool {
        let text_lower = text.to_lowercase();

        // Common spam indicators
        let spam_keywords = [
            "click here",
            "buy now",
            "limited time",
            "act now",
            "free money",
            "make money fast",
            "work from home",
            "weight loss",
            "viagra",
            "cialis",
            "casino",
            "lottery",
        ];

        spam_keywords.iter().any(|&keyword| text_lower.contains(keyword))
    }

    /// Detect if content is duplicated
    pub fn is_duplicate(&self, content: &str, recent_contents: &[String]) -> bool {
        let normalized = content.trim().to_lowercase();

        for recent in recent_contents {
            let recent_normalized = recent.trim().to_lowercase();

            // Exact match
            if normalized == recent_normalized {
                return true;
            }

            // High similarity (>90% same)
            if self.calculate_similarity(&normalized, &recent_normalized) > 0.9 {
                return true;
            }
        }

        false
    }

    /// Calculate similarity between two strings (Jaccard similarity)
    fn calculate_similarity(&self, s1: &str, s2: &str) -> f32 {
        let words1: HashSet<&str> = s1.split_whitespace().collect();
        let words2: HashSet<&str> = s2.split_whitespace().collect();

        let intersection = words1.intersection(&words2).count();
        let union = words1.union(&words2).count();

        if union == 0 {
            return 0.0;
        }

        intersection as f32 / union as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spam_detection_rapid_posting() {
        let detector = SpamDetector::new();
        let context = SpamContext {
            seconds_since_last_post: 5,
            recent_post_count: 25,
            account_age_days: 1,
            is_verified: false,
            has_repeated_content: false,
            link_count: 0,
        };

        let score = detector.detect(&context, "test message");
        assert!(score > 0.5, "Rapid posting should flag as spam");
    }

    #[test]
    fn test_spam_detection_excessive_links() {
        let detector = SpamDetector::new();
        let context = SpamContext::default();
        let text = "Check out https://spam1.com https://spam2.com https://spam3.com https://spam4.com";

        let score = detector.detect(&context, text);
        assert!(score > 0.2, "Multiple links should increase spam score");
    }

    #[test]
    fn test_verified_user_discount() {
        let detector = SpamDetector::new();
        let context_unverified = SpamContext {
            seconds_since_last_post: 5,
            is_verified: false,
            ..Default::default()
        };

        let context_verified = SpamContext {
            seconds_since_last_post: 5,
            is_verified: true,
            ..Default::default()
        };

        let score_unverified = detector.detect(&context_unverified, "test");
        let score_verified = detector.detect(&context_verified, "test");

        assert!(score_verified < score_unverified, "Verified users should have lower spam score");
    }

    #[test]
    fn test_count_links() {
        let detector = SpamDetector::new();
        let text = "Visit https://example.com and http://test.com for more";
        assert_eq!(detector.count_links(text), 2);
    }

    #[test]
    fn test_suspicious_patterns() {
        let detector = SpamDetector::new();
        assert!(detector.has_suspicious_patterns("Click here to buy now!"));
        assert!(!detector.has_suspicious_patterns("Just a normal message"));
    }

    #[test]
    fn test_duplicate_detection() {
        let detector = SpamDetector::new();
        let recent = vec![
            "Hello world".to_string(),
            "Test message".to_string(),
        ];

        assert!(detector.is_duplicate("Hello world", &recent));
        assert!(detector.is_duplicate("hello world", &recent)); // Case insensitive
        assert!(!detector.is_duplicate("Different message", &recent));
    }

    #[test]
    fn test_similarity_calculation() {
        let detector = SpamDetector::new();

        let sim1 = detector.calculate_similarity("hello world", "hello world");
        assert_eq!(sim1, 1.0);

        let sim2 = detector.calculate_similarity("hello world", "hello there");
        assert!(sim2 > 0.0 && sim2 < 1.0);

        let sim3 = detector.calculate_similarity("abc", "xyz");
        assert_eq!(sim3, 0.0);
    }
}

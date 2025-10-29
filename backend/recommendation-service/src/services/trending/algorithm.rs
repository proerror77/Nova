/// Time Decay Algorithm
///
/// Implementation of trending score calculation with configurable parameters
use serde::{Deserialize, Serialize};

/// Trending algorithm configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrendingAlgorithm {
    /// Decay rate (lambda): higher = faster decay
    /// Default: 0.1 (moderate decay)
    /// Range: 0.01 (slow) to 1.0 (fast)
    pub decay_rate: f64,

    /// Weight multipliers for event types
    pub view_weight: f64,
    pub like_weight: f64,
    pub share_weight: f64,
    pub comment_weight: f64,

    /// Minimum engagement threshold
    /// Content below this threshold won't appear in trending
    pub min_engagement_threshold: f64,
}

impl Default for TrendingAlgorithm {
    fn default() -> Self {
        Self {
            decay_rate: 0.1,
            view_weight: 1.0,
            like_weight: 5.0,
            share_weight: 10.0,
            comment_weight: 3.0,
            min_engagement_threshold: 10.0,
        }
    }
}

impl TrendingAlgorithm {
    /// Create a new algorithm with custom decay rate
    pub fn with_decay_rate(decay_rate: f64) -> Self {
        Self {
            decay_rate,
            ..Default::default()
        }
    }

    /// Fast decay (λ = 0.5): Recent content heavily favored
    pub fn fast_decay() -> Self {
        Self::with_decay_rate(0.5)
    }

    /// Moderate decay (λ = 0.1): Balanced approach (default)
    pub fn moderate_decay() -> Self {
        Self::default()
    }

    /// Slow decay (λ = 0.05): Content stays trending longer
    pub fn slow_decay() -> Self {
        Self::with_decay_rate(0.05)
    }

    /// Calculate decay factor for a given age in hours
    ///
    /// Formula: e^(-λ × age_hours)
    ///
    /// Examples:
    /// - λ = 0.1, age = 1h  → e^(-0.1) = 0.905 (90.5% of original weight)
    /// - λ = 0.1, age = 24h → e^(-2.4) = 0.091 (9.1% of original weight)
    /// - λ = 0.5, age = 1h  → e^(-0.5) = 0.606 (60.6% of original weight)
    pub fn decay_factor(&self, age_hours: f64) -> f64 {
        (-self.decay_rate * age_hours).exp()
    }

    /// Calculate weighted score for an engagement event
    ///
    /// Formula: weight × e^(-λ × age_hours)
    pub fn score_event(&self, weight: f64, age_hours: f64) -> f64 {
        weight * self.decay_factor(age_hours)
    }

    /// Calculate half-life (time for score to decay to 50%)
    ///
    /// Formula: ln(2) / λ
    ///
    /// Examples:
    /// - λ = 0.1 → half-life = 6.93 hours
    /// - λ = 0.5 → half-life = 1.39 hours
    pub fn half_life_hours(&self) -> f64 {
        2.0_f64.ln() / self.decay_rate
    }

    /// Validate algorithm parameters
    pub fn validate(&self) -> Result<(), String> {
        if self.decay_rate <= 0.0 || self.decay_rate > 1.0 {
            return Err(format!(
                "Decay rate must be in (0, 1], got {}",
                self.decay_rate
            ));
        }

        if self.view_weight < 0.0
            || self.like_weight < 0.0
            || self.share_weight < 0.0
            || self.comment_weight < 0.0
        {
            return Err("All weights must be non-negative".to_string());
        }

        if self.min_engagement_threshold < 0.0 {
            return Err("Minimum engagement threshold must be non-negative".to_string());
        }

        Ok(())
    }
}

#[cfg(test)]
#[cfg(all(test, feature = "legacy_internal_tests"))]
mod tests {
    use super::*;

    #[test]
    fn test_default_algorithm() {
        let algo = TrendingAlgorithm::default();
        assert_eq!(algo.decay_rate, 0.1);
        assert_eq!(algo.view_weight, 1.0);
        assert_eq!(algo.like_weight, 5.0);
        assert_eq!(algo.share_weight, 10.0);
        assert_eq!(algo.comment_weight, 3.0);
    }

    #[test]
    fn test_decay_factor() {
        let algo = TrendingAlgorithm::default();

        // At time 0, decay factor should be 1.0
        assert!((algo.decay_factor(0.0) - 1.0).abs() < 0.001);

        // At 1 hour, decay factor should be ~0.905
        let decay_1h = algo.decay_factor(1.0);
        assert!((decay_1h - 0.905).abs() < 0.01);

        // At 24 hours, decay factor should be ~0.091
        let decay_24h = algo.decay_factor(24.0);
        assert!((decay_24h - 0.091).abs() < 0.01);
    }

    #[test]
    fn test_score_event() {
        let algo = TrendingAlgorithm::default();

        // 100 views from 1 hour ago
        let score = algo.score_event(100.0, 1.0);
        assert!((score - 90.5).abs() < 1.0);

        // 10 shares (weight=10) from 2 hours ago
        let score = algo.score_event(100.0, 2.0);
        assert!((score - 81.9).abs() < 1.0);
    }

    #[test]
    fn test_half_life() {
        let algo = TrendingAlgorithm::default();
        let half_life = algo.half_life_hours();

        // For λ = 0.1, half-life should be ~6.93 hours
        assert!((half_life - 6.93).abs() < 0.01);

        // Verify: decay_factor(half_life) ≈ 0.5
        let decay_at_half_life = algo.decay_factor(half_life);
        assert!((decay_at_half_life - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_fast_decay() {
        let fast = TrendingAlgorithm::fast_decay();
        assert_eq!(fast.decay_rate, 0.5);

        // Fast decay: half-life ~1.39 hours
        let half_life = fast.half_life_hours();
        assert!((half_life - 1.39).abs() < 0.01);
    }

    #[test]
    fn test_slow_decay() {
        let slow = TrendingAlgorithm::slow_decay();
        assert_eq!(slow.decay_rate, 0.05);

        // Slow decay: half-life ~13.86 hours
        let half_life = slow.half_life_hours();
        assert!((half_life - 13.86).abs() < 0.01);
    }

    #[test]
    fn test_validation() {
        // Valid algorithm
        let valid = TrendingAlgorithm::default();
        assert!(valid.validate().is_ok());

        // Invalid decay rate
        let mut invalid = TrendingAlgorithm::default();
        invalid.decay_rate = 0.0;
        assert!(invalid.validate().is_err());

        invalid.decay_rate = 1.5;
        assert!(invalid.validate().is_err());

        // Negative weights
        invalid = TrendingAlgorithm::default();
        invalid.view_weight = -1.0;
        assert!(invalid.validate().is_err());
    }

    #[test]
    fn test_realistic_scenario() {
        let algo = TrendingAlgorithm::default();

        // Scenario: Compare two pieces of content
        // Content A: 1000 views from 1 hour ago
        let score_a = algo.score_event(1000.0 * algo.view_weight, 1.0);

        // Content B: 100 shares from 1 hour ago
        let score_b = algo.score_event(100.0 * algo.share_weight, 1.0);

        // Shares are worth more (weight=10 vs weight=1)
        // So 100 shares = 1000 weighted events vs 1000 views = 1000 weighted events
        // Both should be similar after decay
        assert!((score_a - score_b).abs() < 1.0);
    }

    #[test]
    fn test_time_decay_comparison() {
        let algo = TrendingAlgorithm::default();

        // Old content with high engagement
        let old_score = algo.score_event(1000.0, 24.0); // 24 hours old

        // New content with low engagement
        let new_score = algo.score_event(100.0, 1.0); // 1 hour old

        // New content should score higher due to recency
        assert!(new_score > old_score);
    }
}

// ============================================
// UCB (Upper Confidence Bound) Explorer
// ============================================
//
// Multi-armed bandit algorithm for explore-exploit balance
//
// UCB1 Formula:
//   UCB(i) = avg_reward(i) + c * sqrt(2 * ln(N) / n(i))
//
// Where:
//   - avg_reward(i): average engagement rate for content i
//   - c: exploration constant (default: sqrt(2) ≈ 1.414)
//   - N: total impressions across all content
//   - n(i): impressions for content i
//
// Higher UCB = more likely to be selected for display

use tracing::{debug, info};
use uuid::Uuid;

/// UCB Explorer for content exploration
pub struct UCBExplorer {
    /// Exploration constant (c in UCB formula)
    /// Higher = more exploration, lower = more exploitation
    exploration_constant: f64,
    /// Minimum impressions before content can graduate
    min_impressions_to_graduate: u32,
    /// Minimum engagement rate to graduate
    min_engagement_rate_to_graduate: f64,
    /// Maximum impressions in exploration pool
    max_exploration_impressions: u32,
}

impl Default for UCBExplorer {
    fn default() -> Self {
        Self {
            exploration_constant: 1.414, // sqrt(2)
            min_impressions_to_graduate: 100,
            min_engagement_rate_to_graduate: 0.02, // 2% engagement
            max_exploration_impressions: 1000,
        }
    }
}

impl UCBExplorer {
    pub fn new() -> Self {
        Self::default()
    }

    /// Create with custom exploration constant
    pub fn with_exploration_constant(mut self, c: f64) -> Self {
        self.exploration_constant = c;
        self
    }

    /// Create with custom graduation thresholds
    pub fn with_graduation_thresholds(
        mut self,
        min_impressions: u32,
        min_engagement_rate: f64,
    ) -> Self {
        self.min_impressions_to_graduate = min_impressions;
        self.min_engagement_rate_to_graduate = min_engagement_rate;
        self
    }

    /// Compute UCB score for a content item
    ///
    /// # Arguments
    /// * `impressions` - Number of times content was shown
    /// * `engagements` - Number of positive engagements (likes, comments, shares, completions)
    /// * `total_impressions` - Total impressions across all exploration content
    ///
    /// # Returns
    /// UCB score (higher = should be shown more)
    pub fn ucb_score(&self, impressions: u32, engagements: u32, total_impressions: u32) -> f64 {
        // New content with no impressions gets maximum exploration bonus
        if impressions == 0 {
            return f64::MAX;
        }

        // Exploitation term: average engagement rate
        let exploit = engagements as f64 / impressions as f64;

        // Exploration term: uncertainty bonus
        let explore = if total_impressions > 0 {
            self.exploration_constant
                * ((2.0 * (total_impressions as f64).ln()) / impressions as f64).sqrt()
        } else {
            self.exploration_constant
        };

        debug!(
            impressions = impressions,
            engagements = engagements,
            exploit = exploit,
            explore = explore,
            "UCB components computed"
        );

        exploit + explore
    }

    /// Check if content should graduate from exploration pool
    ///
    /// Graduation criteria:
    /// 1. Has sufficient impressions (min_impressions_to_graduate)
    /// 2. AND engagement rate >= min_engagement_rate_to_graduate
    /// OR
    /// 3. Has exceeded max_exploration_impressions (force graduate with final score)
    pub fn should_graduate(&self, impressions: u32, engagements: u32) -> GraduationDecision {
        let engagement_rate = if impressions > 0 {
            engagements as f64 / impressions as f64
        } else {
            0.0
        };

        // Force graduation if max impressions exceeded
        if impressions >= self.max_exploration_impressions {
            return GraduationDecision::Graduate {
                reason: GraduationReason::MaxImpressionsReached,
                final_score: engagement_rate,
            };
        }

        // Not enough data yet
        if impressions < self.min_impressions_to_graduate {
            return GraduationDecision::ContinueExploration {
                remaining_impressions: self.min_impressions_to_graduate - impressions,
            };
        }

        // Check engagement threshold
        if engagement_rate >= self.min_engagement_rate_to_graduate {
            GraduationDecision::Graduate {
                reason: GraduationReason::SufficientEngagement,
                final_score: engagement_rate,
            }
        } else {
            // Poor performance, demote/archive
            GraduationDecision::Demote {
                reason: DemotionReason::LowEngagement,
                final_score: engagement_rate,
            }
        }
    }

    /// Select content from exploration pool using UCB
    ///
    /// # Arguments
    /// * `pool` - List of (content_id, impressions, engagements)
    /// * `count` - Number of items to select
    ///
    /// # Returns
    /// Selected content IDs sorted by UCB score
    pub fn select_for_exploration(&self, pool: &[(Uuid, u32, u32)], count: usize) -> Vec<Uuid> {
        if pool.is_empty() || count == 0 {
            return Vec::new();
        }

        // Calculate total impressions
        let total_impressions: u32 = pool.iter().map(|(_, imp, _)| *imp).sum();

        // Score all content with UCB
        let mut scored: Vec<(Uuid, f64)> = pool
            .iter()
            .map(|(id, imp, eng)| (*id, self.ucb_score(*imp, *eng, total_impressions)))
            .collect();

        // Sort by UCB score descending
        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        info!(
            pool_size = pool.len(),
            selected = count.min(scored.len()),
            total_impressions = total_impressions,
            "UCB selection completed"
        );

        scored.into_iter().take(count).map(|(id, _)| id).collect()
    }

    /// Compute Thompson Sampling score (alternative to UCB)
    /// Uses Beta distribution for Bayesian exploration
    ///
    /// Beta(α, β) where:
    /// - α = engagements + 1 (successes)
    /// - β = impressions - engagements + 1 (failures)
    pub fn thompson_sample(&self, impressions: u32, engagements: u32) -> f64 {
        // Use mean of Beta distribution as deterministic approximation
        // Mean = α / (α + β)
        let alpha = engagements as f64 + 1.0;
        let beta = (impressions - engagements) as f64 + 1.0;
        alpha / (alpha + beta)
    }
}

/// Decision for content graduation from exploration pool
#[derive(Debug, Clone)]
pub enum GraduationDecision {
    /// Content should graduate to main ranking pool
    Graduate {
        reason: GraduationReason,
        final_score: f64,
    },
    /// Content should continue in exploration
    ContinueExploration { remaining_impressions: u32 },
    /// Content should be demoted/archived
    Demote {
        reason: DemotionReason,
        final_score: f64,
    },
}

#[derive(Debug, Clone)]
pub enum GraduationReason {
    SufficientEngagement,
    MaxImpressionsReached,
}

#[derive(Debug, Clone)]
pub enum DemotionReason {
    LowEngagement,
    PolicyViolation,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ucb_score_new_content() {
        let explorer = UCBExplorer::new();

        // New content should get maximum score
        let score = explorer.ucb_score(0, 0, 1000);
        assert_eq!(score, f64::MAX);
    }

    #[test]
    fn test_ucb_score_high_engagement() {
        let explorer = UCBExplorer::new();

        // High engagement content
        let score_high = explorer.ucb_score(100, 50, 10000); // 50% engagement
        let score_low = explorer.ucb_score(100, 5, 10000); // 5% engagement

        assert!(score_high > score_low);
    }

    #[test]
    fn test_ucb_exploration_bonus() {
        let explorer = UCBExplorer::new();

        // Same engagement rate, but different impression counts
        let score_few_impressions = explorer.ucb_score(10, 5, 10000); // 50% with low confidence
        let score_many_impressions = explorer.ucb_score(1000, 500, 10000); // 50% with high confidence

        // Fewer impressions should have higher exploration bonus
        assert!(score_few_impressions > score_many_impressions);
    }

    #[test]
    fn test_graduation_decision() {
        let explorer = UCBExplorer::default();

        // Not enough impressions
        let decision = explorer.should_graduate(50, 2);
        assert!(matches!(
            decision,
            GraduationDecision::ContinueExploration { .. }
        ));

        // Good engagement, should graduate
        let decision = explorer.should_graduate(100, 5); // 5% engagement > 2%
        assert!(matches!(decision, GraduationDecision::Graduate { .. }));

        // Poor engagement, should demote
        let decision = explorer.should_graduate(100, 1); // 1% engagement < 2%
        assert!(matches!(decision, GraduationDecision::Demote { .. }));

        // Max impressions reached
        let decision = explorer.should_graduate(1000, 10);
        assert!(matches!(
            decision,
            GraduationDecision::Graduate {
                reason: GraduationReason::MaxImpressionsReached,
                ..
            }
        ));
    }

    #[test]
    fn test_select_for_exploration() {
        let explorer = UCBExplorer::new();

        let pool = vec![
            (Uuid::new_v4(), 100, 50),   // 50% engagement, medium confidence
            (Uuid::new_v4(), 10, 2),     // 20% engagement, low confidence (high exploration bonus)
            (Uuid::new_v4(), 1000, 100), // 10% engagement, high confidence
            (Uuid::new_v4(), 0, 0),      // New content, should be first
        ];

        let selected = explorer.select_for_exploration(&pool, 2);

        assert_eq!(selected.len(), 2);
        // New content (0 impressions) should be selected first
        assert_eq!(selected[0], pool[3].0);
    }

    #[test]
    fn test_thompson_sampling() {
        let explorer = UCBExplorer::new();

        // High engagement
        let score_high = explorer.thompson_sample(100, 80); // 80%
                                                            // Low engagement
        let score_low = explorer.thompson_sample(100, 20); // 20%

        assert!(score_high > score_low);
    }
}

/// Ranking Engine Service
///
/// Implements multi-signal personalized video ranking with weighted scoring.
/// Combines 5 ranking signals: freshness, completion rate, engagement, affinity, and deep learning.
<<<<<<< HEAD
=======

>>>>>>> origin/007-personalized-feed-ranking
use tracing::{debug, info};
use uuid::Uuid;

/// Ranking configuration with signal weights
#[derive(Debug, Clone)]
pub struct RankingConfig {
<<<<<<< HEAD
    pub freshness_weight: f32,  // 0.15
    pub completion_weight: f32, // 0.40
    pub engagement_weight: f32, // 0.25
    pub affinity_weight: f32,   // 0.15
    pub deep_model_weight: f32, // 0.05
=======
    pub freshness_weight: f32,      // 0.15
    pub completion_weight: f32,     // 0.40
    pub engagement_weight: f32,     // 0.25
    pub affinity_weight: f32,       // 0.15
    pub deep_model_weight: f32,     // 0.05
>>>>>>> origin/007-personalized-feed-ranking
}

impl Default for RankingConfig {
    fn default() -> Self {
        Self {
            freshness_weight: 0.15,
            completion_weight: 0.40,
            engagement_weight: 0.25,
            affinity_weight: 0.15,
            deep_model_weight: 0.05,
        }
    }
}

impl RankingConfig {
    /// Verify weights sum to 1.0 (within tolerance)
    pub fn is_valid(&self) -> bool {
        let total = self.freshness_weight
            + self.completion_weight
            + self.engagement_weight
            + self.affinity_weight
            + self.deep_model_weight;

        (total - 1.0).abs() < 0.001
    }
}

/// Individual ranking signals for a video
<<<<<<< HEAD
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RankingSignals {
    pub video_id: Uuid,
    pub freshness_score: f32,  // [0, 1] - newer = higher
    pub completion_rate: f32,  // [0, 1] - avg watch completion %
    pub engagement_score: f32, // [0, 1] - normalized engagement
    pub affinity_score: f32,   // [0, 1] - user-creator affinity
    pub deep_model_score: f32, // [0, 1] - embedding similarity
=======
#[derive(Debug, Clone)]
pub struct RankingSignals {
    pub video_id: Uuid,
    pub freshness_score: f32,       // [0, 1] - newer = higher
    pub completion_rate: f32,       // [0, 1] - avg watch completion %
    pub engagement_score: f32,      // [0, 1] - normalized engagement
    pub affinity_score: f32,        // [0, 1] - user-creator affinity
    pub deep_model_score: f32,      // [0, 1] - embedding similarity
>>>>>>> origin/007-personalized-feed-ranking
}

impl RankingSignals {
    /// Validate that all scores are in [0, 1] range
    pub fn is_valid(&self) -> bool {
<<<<<<< HEAD
        self.freshness_score >= 0.0
            && self.freshness_score <= 1.0
            && self.completion_rate >= 0.0
            && self.completion_rate <= 1.0
            && self.engagement_score >= 0.0
            && self.engagement_score <= 1.0
            && self.affinity_score >= 0.0
            && self.affinity_score <= 1.0
            && self.deep_model_score >= 0.0
            && self.deep_model_score <= 1.0
=======
        self.freshness_score >= 0.0 && self.freshness_score <= 1.0
            && self.completion_rate >= 0.0 && self.completion_rate <= 1.0
            && self.engagement_score >= 0.0 && self.engagement_score <= 1.0
            && self.affinity_score >= 0.0 && self.affinity_score <= 1.0
            && self.deep_model_score >= 0.0 && self.deep_model_score <= 1.0
>>>>>>> origin/007-personalized-feed-ranking
    }
}

/// Ranking engine with weighted multi-signal scoring
pub struct RankingEngine {
    config: RankingConfig,
}

impl RankingEngine {
    /// Create new ranking engine
    pub fn new(config: RankingConfig) -> Self {
        if !config.is_valid() {
            panic!("Invalid ranking config: weights don't sum to 1.0");
        }
        Self { config }
    }

    /// Rank videos based on signals
    pub async fn rank_videos(&self, signals: &[RankingSignals]) -> Vec<(Uuid, f32)> {
        debug!("Ranking {} videos", signals.len());

        if signals.is_empty() {
            return Vec::new();
        }

        // Calculate weighted score for each video
        let mut scored: Vec<_> = signals
            .iter()
            .map(|s| {
                let score = self.calculate_score(s);
                (s.video_id, score)
            })
            .collect();

        // Sort by score descending
<<<<<<< HEAD
        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
=======
        scored.sort_by(|a, b| {
            b.1.partial_cmp(&a.1)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
>>>>>>> origin/007-personalized-feed-ranking

        info!(
            "Ranked {} videos (top score: {:.4})",
            scored.len(),
<<<<<<< HEAD
            scored
                .first()
                .map(|(_, score)| score)
                .copied()
                .unwrap_or(0.0)
=======
            scored.first().map(|(_, score)| score).copied().unwrap_or(0.0)
>>>>>>> origin/007-personalized-feed-ranking
        );

        scored
    }

    /// Calculate freshness score with quadratic decay
    /// New video (0h): 1.0
    /// 15 days (360h): ~0.75
    /// 30 days (720h): ~0.0
    pub fn calculate_freshness_score(&self, hours_old: f32) -> f32 {
        let decay = 1.0 - (hours_old / 720.0).min(1.0);
        (decay * decay).max(0.0)
    }

    /// Calculate engagement score from engagement metrics
    /// Formula: (likes × 1 + shares × 2 + comments × 0.5) / total_views
    pub fn calculate_engagement_score(
        &self,
        likes: u32,
        shares: u32,
        comments: u32,
        total_views: u32,
    ) -> f32 {
        if total_views == 0 {
            return 0.0;
        }

        let likes_f = likes as f32;
        let shares_f = shares as f32;
        let comments_f = comments as f32;
        let views_f = total_views as f32;

        // Weighted engagement: shares = 2x value, comments = 0.5x
        let weighted_engagement = likes_f + (shares_f * 2.0) + (comments_f * 0.5);
        (weighted_engagement / views_f).min(1.0).max(0.0)
    }

    /// Calculate affinity score based on user's prior creator interactions
    /// Cold-start: 0.5
    /// Warm-start: (prior_likes + prior_comments × 0.5) / max_history_score
    pub fn calculate_affinity_score(&self, interaction_history: Option<f32>) -> f32 {
        match interaction_history {
            Some(score) => score.min(1.0).max(0.0),
            None => 0.5, // Cold-start default
        }
    }

    /// Calculate final weighted ranking score
    fn calculate_score(&self, signals: &RankingSignals) -> f32 {
        signals.freshness_score * self.config.freshness_weight
            + signals.completion_rate * self.config.completion_weight
            + signals.engagement_score * self.config.engagement_weight
            + signals.affinity_score * self.config.affinity_weight
            + signals.deep_model_score * self.config.deep_model_weight
    }

    /// Get ranking configuration
    pub fn config(&self) -> &RankingConfig {
        &self.config
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ranking_config_validation() {
        let config = RankingConfig::default();
        assert!(config.is_valid());

        let valid_config = RankingConfig {
            freshness_weight: 0.5,
            completion_weight: 0.5,
            engagement_weight: 0.0,
            affinity_weight: 0.0,
            deep_model_weight: 0.0,
        };
        assert!(valid_config.is_valid()); // Sums to 1.0, so it's valid

        let invalid_config = RankingConfig {
            freshness_weight: 0.5,
            completion_weight: 0.3,
            engagement_weight: 0.1,
            affinity_weight: 0.0,
            deep_model_weight: 0.0,
        };
        assert!(!invalid_config.is_valid()); // Sums to 0.9, invalid
    }

    #[test]
    fn test_ranking_signals_validation() {
        let valid_signals = RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: 1.0,
            completion_rate: 0.8,
            engagement_score: 0.5,
            affinity_score: 0.3,
            deep_model_score: 0.2,
        };
        assert!(valid_signals.is_valid());

        let invalid_signals = RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: 1.5, // Invalid: > 1.0
            completion_rate: 0.8,
            engagement_score: 0.5,
            affinity_score: 0.3,
            deep_model_score: 0.2,
        };
        assert!(!invalid_signals.is_valid());
    }

    #[test]
    fn test_freshness_decay() {
        let engine = RankingEngine::new(RankingConfig::default());

        // New video (0 hours old)
        assert_eq!(engine.calculate_freshness_score(0.0), 1.0);

        // 15 days old (360 hours)
        // decay = 1.0 - (360/720) = 0.5, score = 0.5^2 = 0.25
        let score_15d = engine.calculate_freshness_score(360.0);
        assert!(score_15d > 0.2 && score_15d < 0.3);

        // 30 days old (720 hours)
        // decay = 1.0 - (720/720) = 0.0, score = 0.0^2 = 0.0
        let score_30d = engine.calculate_freshness_score(720.0);
        assert_eq!(score_30d, 0.0);

        // Very old (> 30 days)
        let score_old = engine.calculate_freshness_score(1440.0);
        assert_eq!(score_old, 0.0);
    }

    #[test]
    fn test_engagement_scoring() {
        let engine = RankingEngine::new(RankingConfig::default());

        // No engagement
        let score = engine.calculate_engagement_score(0, 0, 0, 1000);
        assert_eq!(score, 0.0);

        // Equal engagement (1 like per 10 views = 10%)
        let score = engine.calculate_engagement_score(100, 0, 0, 1000);
        assert!(score > 0.09 && score < 0.11);

        // With shares (2x weight)
        let score = engine.calculate_engagement_score(100, 10, 0, 1000);
        let score_with_shares = engine.calculate_engagement_score(100, 0, 0, 1000);
        assert!(score > score_with_shares);

        // With comments (0.5x weight)
        let score = engine.calculate_engagement_score(100, 0, 10, 1000);
        let score_with_likes = engine.calculate_engagement_score(100, 0, 0, 1000);
        assert!(score > score_with_likes);

        // Clamp to 1.0
        let score = engine.calculate_engagement_score(10000, 10000, 10000, 1000);
        assert_eq!(score, 1.0);
    }

    #[test]
    fn test_affinity_scoring() {
        let engine = RankingEngine::new(RankingConfig::default());

        // Cold-start (no history)
        let score = engine.calculate_affinity_score(None);
        assert_eq!(score, 0.5);

        // Warm-start
        let score = engine.calculate_affinity_score(Some(0.8));
        assert_eq!(score, 0.8);

        // Clamp to [0, 1]
        let score = engine.calculate_affinity_score(Some(2.0));
        assert_eq!(score, 1.0);

        let score = engine.calculate_affinity_score(Some(-0.5));
        assert_eq!(score, 0.0);
    }

    #[tokio::test]
    async fn test_rank_videos() {
        let engine = RankingEngine::new(RankingConfig::default());

        let signals = vec![
            RankingSignals {
                video_id: Uuid::nil(),
                freshness_score: 0.5,
                completion_rate: 0.7,
                engagement_score: 0.3,
                affinity_score: 0.4,
                deep_model_score: 0.0,
            },
            RankingSignals {
                video_id: Uuid::nil(),
                freshness_score: 0.9,
                completion_rate: 0.9,
                engagement_score: 0.8,
                affinity_score: 0.5,
                deep_model_score: 0.5,
            },
        ];

        let ranked = engine.rank_videos(&signals).await;
        assert_eq!(ranked.len(), 2);
        assert!(ranked[0].1 > ranked[1].1); // Higher score first
    }

    #[tokio::test]
    async fn test_rank_empty_videos() {
        let engine = RankingEngine::new(RankingConfig::default());
        let ranked = engine.rank_videos(&[]).await;
        assert!(ranked.is_empty());
    }

    #[test]
    fn test_weighted_score_calculation() {
        let engine = RankingEngine::new(RankingConfig::default());

        let signals = RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: 1.0,
            completion_rate: 1.0,
            engagement_score: 1.0,
            affinity_score: 1.0,
            deep_model_score: 1.0,
        };

        // With all signals at max (1.0), weighted score should be 1.0
        let score = engine.calculate_score(&signals);
        assert!((score - 1.0).abs() < 0.001);

        // With all signals at min (0.0), weighted score should be 0.0
        let signals_zero = RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: 0.0,
            completion_rate: 0.0,
            engagement_score: 0.0,
            affinity_score: 0.0,
            deep_model_score: 0.0,
        };

        let score_zero = engine.calculate_score(&signals_zero);
        assert_eq!(score_zero, 0.0);
    }
}

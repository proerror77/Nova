/// Ranking Engine Service
///
/// Implements multi-signal personalized video ranking with weighted scoring.
/// Combines 5 ranking signals: freshness, completion rate, engagement, affinity, and deep learning.
use tracing::{debug, info};
use uuid::Uuid;

/// Ranking configuration with signal weights
#[derive(Debug, Clone)]
pub struct RankingConfig {
    pub freshness_weight: f32,
    pub completion_weight: f32,
    pub engagement_weight: f32,
    pub affinity_weight: f32,
    pub deep_model_weight: f32,
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
#[derive(Debug, Clone)]
pub struct RankingSignals {
    pub video_id: Uuid,
    pub freshness_score: f32,
    pub completion_rate: f32,
    pub engagement_score: f32,
    pub affinity_score: f32,
    pub deep_model_score: f32,
}

impl RankingSignals {
    /// Validate that all scores are in [0, 1] range
    pub fn is_valid(&self) -> bool {
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
    }
}

/// Ranking engine with weighted multi-signal scoring
pub struct RankingEngine {
    config: RankingConfig,
}

impl RankingEngine {
    /// Create new ranking engine with config
    pub fn new(config: RankingConfig) -> Self {
        Self { config }
    }

    /// Calculate combined ranking score from individual signals
    pub fn calculate_score(&self, signals: &RankingSignals) -> f32 {
        if !signals.is_valid() {
            return 0.0;
        }

        self.config.freshness_weight * signals.freshness_score
            + self.config.completion_weight * signals.completion_rate
            + self.config.engagement_weight * signals.engagement_score
            + self.config.affinity_weight * signals.affinity_score
            + self.config.deep_model_weight * signals.deep_model_score
    }

    /// Rank multiple videos by combined score
    pub fn rank_videos(&self, videos: &[RankingSignals]) -> Vec<(Uuid, f32)> {
        let mut scored: Vec<_> = videos
            .iter()
            .map(|v| (v.video_id, self.calculate_score(v)))
            .collect();

        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        scored
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ranking_config_validation() {
        let config = RankingConfig::default();
        assert!(config.is_valid());
    }

    #[test]
    fn test_ranking_signals_validation() {
        let signals = RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: 0.8,
            completion_rate: 0.75,
            engagement_score: 0.9,
            affinity_score: 0.6,
            deep_model_score: 0.7,
        };
        assert!(signals.is_valid());
    }

    #[test]
    fn test_calculate_score() {
        let config = RankingConfig::default();
        let engine = RankingEngine::new(config);

        let signals = RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: 1.0,
            completion_rate: 1.0,
            engagement_score: 1.0,
            affinity_score: 1.0,
            deep_model_score: 1.0,
        };

        let score = engine.calculate_score(&signals);
        assert!((score - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_calculate_zero_score() {
        let config = RankingConfig::default();
        let engine = RankingEngine::new(config);

        let signals = RankingSignals {
            video_id: Uuid::new_v4(),
            freshness_score: 0.0,
            completion_rate: 0.0,
            engagement_score: 0.0,
            affinity_score: 0.0,
            deep_model_score: 0.0,
        };

        let score = engine.calculate_score(&signals);
        assert_eq!(score, 0.0);
    }
}

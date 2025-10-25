/// Unit Tests for Video Ranking Algorithm (T132)
/// Tests score calculation, weight combinations, edge cases

/// Video ranking score components
#[derive(Debug, Clone)]
pub struct VideoRankingScore {
    pub view_score: f64,
    pub engagement_score: f64,
    pub recency_score: f64,
    pub quality_score: f64,
    pub combined_score: f64,
}

/// Video ranking algorithm
pub struct VideoRankingAlgorithm {
    view_weight: f64,
    engagement_weight: f64,
    recency_weight: f64,
    quality_weight: f64,
}

impl VideoRankingAlgorithm {
    pub fn new(
        view_weight: f64,
        engagement_weight: f64,
        recency_weight: f64,
        quality_weight: f64,
    ) -> Self {
        Self {
            view_weight,
            engagement_weight,
            recency_weight,
            quality_weight,
        }
    }

    pub fn with_default_weights() -> Self {
        Self::new(0.25, 0.35, 0.25, 0.15)
    }

    /// Calculate view score (logarithmic to prevent extremes)
    pub fn calculate_view_score(&self, view_count: u32) -> f64 {
        let views_f = (view_count as f64 + 1.0).log10();
        (views_f / 6.0).min(1.0).max(0.0) // Normalize to [0, 1]
    }

    /// Calculate engagement score (likes + comments + shares)
    pub fn calculate_engagement_score(&self, likes: u32, comments: u32, shares: u32) -> f64 {
        let engagement_rate =
            (likes as f64 * 0.3 + comments as f64 * 0.5 + shares as f64 * 0.2) / 100.0; // Normalize
        engagement_rate.min(1.0).max(0.0)
    }

    /// Calculate recency score (favor newer content)
    pub fn calculate_recency_score(&self, minutes_ago: u32) -> f64 {
        let hours_ago = minutes_ago as f64 / 60.0;
        let decay_factor = 1.0 / (1.0 + 0.1 * hours_ago);
        decay_factor.min(1.0).max(0.0)
    }

    /// Calculate quality score (user ratings, flags, etc.)
    pub fn calculate_quality_score(&self, average_rating: f64, flag_count: u32) -> f64 {
        let rating_score = (average_rating / 5.0).min(1.0).max(0.0);
        let flag_penalty = (flag_count as f64 * 0.05).min(1.0);
        (rating_score - flag_penalty).min(1.0).max(0.0)
    }

    /// Calculate combined ranking score
    pub fn calculate_combined_score(
        &self,
        view_score: f64,
        engagement_score: f64,
        recency_score: f64,
        quality_score: f64,
    ) -> f64 {
        let total_weight =
            self.view_weight + self.engagement_weight + self.recency_weight + self.quality_weight;

        (view_score * self.view_weight
            + engagement_score * self.engagement_weight
            + recency_score * self.recency_weight
            + quality_score * self.quality_weight)
            / total_weight
    }

    /// Full ranking calculation
    pub fn rank_video(
        &self,
        view_count: u32,
        likes: u32,
        comments: u32,
        shares: u32,
        minutes_ago: u32,
        average_rating: f64,
        flag_count: u32,
    ) -> VideoRankingScore {
        let view_score = self.calculate_view_score(view_count);
        let engagement_score = self.calculate_engagement_score(likes, comments, shares);
        let recency_score = self.calculate_recency_score(minutes_ago);
        let quality_score = self.calculate_quality_score(average_rating, flag_count);

        let combined_score = self.calculate_combined_score(
            view_score,
            engagement_score,
            recency_score,
            quality_score,
        );

        VideoRankingScore {
            view_score,
            engagement_score,
            recency_score,
            quality_score,
            combined_score,
        }
    }
}

// ============================================
// Unit Tests (T132)
// ============================================

#[test]
fn test_view_score_zero_views() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_view_score(0);
    assert!(score >= 0.0 && score <= 1.0);
}

#[test]
fn test_view_score_logarithmic_scaling() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score_10 = algo.calculate_view_score(10);
    let score_100 = algo.calculate_view_score(100);
    let score_1000 = algo.calculate_view_score(1000);

    // Higher views should have higher scores
    assert!(score_100 > score_10);
    assert!(score_1000 > score_100);

    // Scores should be normalized
    assert!(score_1000 <= 1.0);
}

#[test]
fn test_view_score_saturation() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score_high = algo.calculate_view_score(1_000_000);
    assert!(score_high <= 1.0);
}

#[test]
fn test_engagement_score_no_engagement() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_engagement_score(0, 0, 0);
    assert_eq!(score, 0.0);
}

#[test]
fn test_engagement_score_high_engagement() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_engagement_score(100, 50, 25);
    assert!(score > 0.0 && score <= 1.0);
}

#[test]
fn test_engagement_score_weighted() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score_likes = algo.calculate_engagement_score(100, 0, 0);
    let score_comments = algo.calculate_engagement_score(0, 100, 0);

    // Comments should have higher weight than likes
    assert!(score_comments > score_likes);
}

#[test]
fn test_recency_score_very_new() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_recency_score(1); // 1 minute ago
    assert!(score > 0.95); // Very fresh
}

#[test]
fn test_recency_score_old_content() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_recency_score(24 * 60); // 24 hours ago
    assert!(score < 0.5); // Decayed
}

#[test]
fn test_recency_score_exponential_decay() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score_1h = algo.calculate_recency_score(60);
    let score_2h = algo.calculate_recency_score(120);
    let score_4h = algo.calculate_recency_score(240);

    // Should decay exponentially
    assert!(score_1h > score_2h);
    assert!(score_2h > score_4h);
}

#[test]
fn test_quality_score_perfect_rating() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_quality_score(5.0, 0);
    assert_eq!(score, 1.0);
}

#[test]
fn test_quality_score_no_rating() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_quality_score(0.0, 0);
    assert_eq!(score, 0.0);
}

#[test]
fn test_quality_score_with_flags() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score_no_flags = algo.calculate_quality_score(4.0, 0);
    let score_with_flags = algo.calculate_quality_score(4.0, 5);

    // Flags should reduce score
    assert!(score_with_flags < score_no_flags);
}

#[test]
fn test_combined_score_normalization() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_combined_score(1.0, 1.0, 1.0, 1.0);
    assert_eq!(score, 1.0); // Perfect score
}

#[test]
fn test_combined_score_zero() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score = algo.calculate_combined_score(0.0, 0.0, 0.0, 0.0);
    assert_eq!(score, 0.0);
}

#[test]
fn test_combined_score_weighted() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let score_engagement_heavy = algo.calculate_combined_score(0.0, 1.0, 0.0, 0.0);
    let score_recency_heavy = algo.calculate_combined_score(0.0, 0.0, 1.0, 0.0);

    // Engagement weight (0.35) is higher than recency weight (0.25)
    assert!(score_engagement_heavy > score_recency_heavy);
}

#[test]
fn test_rank_video_viral() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let ranking = algo.rank_video(
        10000, // views
        500,   // likes
        200,   // comments
        100,   // shares
        30,    // 30 minutes ago (fresh)
        4.8,   // rating
        0,     // no flags
    );

    assert!(ranking.combined_score > 0.7);
}

#[test]
fn test_rank_video_low_engagement() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let ranking = algo.rank_video(
        100,  // few views
        5,    // few likes
        2,    // few comments
        1,    // few shares
        1440, // 24 hours old
        2.0,  // low rating
        10,   // many flags
    );

    assert!(ranking.combined_score < 0.3);
}

#[test]
fn test_rank_video_balanced() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let ranking = algo.rank_video(
        1000, // medium views
        50,   // medium likes
        20,   // medium comments
        10,   // medium shares
        240,  // 4 hours ago (medium age)
        3.5,  // medium rating
        2,    // few flags
    );

    assert!(ranking.combined_score > 0.3 && ranking.combined_score < 0.7);
}

#[test]
fn test_ranking_components_independent() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let ranking1 = algo.rank_video(1000, 0, 0, 0, 0, 5.0, 0);
    let ranking2 = algo.rank_video(0, 500, 200, 100, 0, 5.0, 0);

    // Different components should contribute differently
    assert!(ranking1.view_score > ranking1.engagement_score);
    assert!(ranking2.engagement_score > ranking2.view_score);
}

#[test]
fn test_custom_weights() {
    let algo_default = VideoRankingAlgorithm::with_default_weights();
    let algo_custom = VideoRankingAlgorithm::new(0.7, 0.1, 0.1, 0.1); // More extreme weights

    let ranking_default = algo_default.rank_video(1000, 50, 20, 10, 60, 4.0, 0);
    let ranking_custom = algo_custom.rank_video(1000, 50, 20, 10, 60, 4.0, 0);

    // Custom weights should produce notably different scores
    let diff = (ranking_default.combined_score - ranking_custom.combined_score).abs();
    assert!(
        diff > 0.01,
        "Weights should produce different scores, diff: {}",
        diff
    );
}

#[test]
fn test_score_stability() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    // Same input should produce same output
    let ranking1 = algo.rank_video(1000, 50, 20, 10, 60, 4.0, 0);
    let ranking2 = algo.rank_video(1000, 50, 20, 10, 60, 4.0, 0);

    assert_eq!(ranking1.combined_score, ranking2.combined_score);
}

#[test]
fn test_edge_case_very_large_numbers() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let ranking = algo.rank_video(
        1_000_000, // 1M views
        100_000,   // 100k likes
        50_000,    // 50k comments
        25_000,    // 25k shares
        1,         // just published
        5.0,       // perfect rating
        0,         // no flags
    );

    assert!(ranking.combined_score >= 0.0 && ranking.combined_score <= 1.0);
}

#[test]
fn test_score_components_bounds() {
    let algo = VideoRankingAlgorithm::with_default_weights();

    let ranking = algo.rank_video(1_000_000, 100_000, 50_000, 25_000, 1, 5.0, 0);

    // All components should be normalized
    assert!(ranking.view_score >= 0.0 && ranking.view_score <= 1.0);
    assert!(ranking.engagement_score >= 0.0 && ranking.engagement_score <= 1.0);
    assert!(ranking.recency_score >= 0.0 && ranking.recency_score <= 1.0);
    assert!(ranking.quality_score >= 0.0 && ranking.quality_score <= 1.0);
    assert!(ranking.combined_score >= 0.0 && ranking.combined_score <= 1.0);
}

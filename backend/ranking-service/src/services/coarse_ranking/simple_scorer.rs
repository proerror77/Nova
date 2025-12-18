// ============================================
// Simple Coarse Scorer (简单粗排打分器)
// ============================================
//
// Lightweight scoring for filtering recall candidates
// Target: < 10ms for 10000 candidates
//
// Features used:
// - Engagement score (from recall weight)
// - Recency score (exponential decay)
// - Author quality score (from feature store)
// - Interest match score (Jaccard similarity)
// - Content type preference (video/image/text)

use crate::models::Candidate;
use anyhow::Result;
use std::collections::HashSet;
use tracing::{debug, info};
use uuid::Uuid;

/// User features for coarse ranking
#[derive(Debug, Clone, Default)]
pub struct UserFeatures {
    /// User's interest tags (from profile)
    pub interest_tags: Vec<String>,
    /// Preferred content types (video, image, text)
    pub content_type_preferences: Vec<String>,
    /// Active hours bitmap (0-23)
    pub active_hours: Vec<u8>,
    /// Average session length in seconds
    pub avg_session_length: i32,
    /// User's followed author IDs
    pub followed_authors: HashSet<Uuid>,
}

/// Extended candidate with additional features for coarse ranking
#[derive(Debug, Clone)]
pub struct CoarseCandidate {
    pub candidate: Candidate,
    /// Content tags for interest matching
    pub tags: Vec<String>,
    /// Content type (video, image, text)
    pub content_type: String,
    /// Author quality score (0.0 - 1.0)
    pub author_quality: f32,
    /// Author ID
    pub author_id: Option<Uuid>,
    /// Is from followed author
    pub is_followed_author: bool,
}

impl From<Candidate> for CoarseCandidate {
    fn from(candidate: Candidate) -> Self {
        Self {
            candidate,
            tags: Vec::new(),
            content_type: "video".to_string(),
            author_quality: 0.5,
            author_id: None,
            is_followed_author: false,
        }
    }
}

/// Configurable weights for coarse ranking
#[derive(Debug, Clone)]
pub struct CoarseWeights {
    /// Weight for engagement/recall score
    pub engagement: f32,
    /// Weight for recency
    pub recency: f32,
    /// Weight for author quality
    pub author_quality: f32,
    /// Weight for interest match
    pub interest_match: f32,
    /// Bonus for followed authors
    pub followed_author_bonus: f32,
    /// Weight for content type preference match
    pub content_type_match: f32,
}

impl Default for CoarseWeights {
    fn default() -> Self {
        Self {
            engagement: 0.25,
            recency: 0.20,
            author_quality: 0.15,
            interest_match: 0.20,
            followed_author_bonus: 0.10,
            content_type_match: 0.10,
        }
    }
}

/// Coarse ranking layer
pub struct CoarseRankingLayer {
    weights: CoarseWeights,
    output_limit: usize,
    /// Minimum score threshold to pass coarse ranking
    min_score_threshold: f32,
}

impl CoarseRankingLayer {
    /// Create new coarse ranking layer with default weights
    pub fn new(output_limit: usize) -> Self {
        Self {
            weights: CoarseWeights::default(),
            output_limit,
            min_score_threshold: 0.1,
        }
    }

    /// Create with custom weights
    pub fn with_weights(output_limit: usize, weights: CoarseWeights) -> Self {
        Self {
            weights,
            output_limit,
            min_score_threshold: 0.1,
        }
    }

    /// Set minimum score threshold
    pub fn with_min_threshold(mut self, threshold: f32) -> Self {
        self.min_score_threshold = threshold;
        self
    }

    /// Rank candidates using coarse scoring
    ///
    /// Input: ~10000 recall candidates
    /// Output: ~1000 candidates for fine ranking
    pub fn rank(
        &self,
        candidates: Vec<CoarseCandidate>,
        user_features: &UserFeatures,
    ) -> Result<Vec<CoarseCandidate>> {
        if candidates.is_empty() {
            return Ok(Vec::new());
        }

        let input_count = candidates.len();

        // Score all candidates
        let mut scored: Vec<(CoarseCandidate, f32)> = candidates
            .into_iter()
            .map(|c| {
                let score = self.compute_score(&c, user_features);
                (c, score)
            })
            .filter(|(_, score)| *score >= self.min_score_threshold)
            .collect();

        // Sort by score descending
        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // Take top N
        let output: Vec<CoarseCandidate> = scored
            .into_iter()
            .take(self.output_limit)
            .map(|(c, _)| c)
            .collect();

        info!(
            input_count = input_count,
            output_count = output.len(),
            "Coarse ranking completed"
        );

        Ok(output)
    }

    /// Compute coarse ranking score for a candidate
    fn compute_score(&self, candidate: &CoarseCandidate, user: &UserFeatures) -> f32 {
        let engagement = candidate.candidate.recall_weight;
        let recency = self.compute_recency_score(candidate.candidate.timestamp);
        let author_quality = candidate.author_quality;
        let interest_match = self.compute_interest_match(&candidate.tags, &user.interest_tags);
        let followed_bonus = if candidate.is_followed_author {
            1.0
        } else {
            0.0
        };
        let content_type_match = self
            .compute_content_type_match(&candidate.content_type, &user.content_type_preferences);

        let score = self.weights.engagement * engagement
            + self.weights.recency * recency
            + self.weights.author_quality * author_quality
            + self.weights.interest_match * interest_match
            + self.weights.followed_author_bonus * followed_bonus
            + self.weights.content_type_match * content_type_match;

        debug!(
            post_id = %candidate.candidate.post_id,
            engagement = engagement,
            recency = recency,
            interest_match = interest_match,
            score = score,
            "Coarse score computed"
        );

        score
    }

    /// Compute recency score with exponential decay
    /// Fresh content (0h) = 1.0, 24h = 0.37, 48h = 0.14
    fn compute_recency_score(&self, timestamp: i64) -> f32 {
        let now = chrono::Utc::now().timestamp();
        let age_seconds = (now - timestamp).max(0) as f32;
        let age_hours = age_seconds / 3600.0;

        // Exponential decay with 24-hour half-life
        (-age_hours / 24.0).exp().max(0.05)
    }

    /// Compute interest match using Jaccard similarity
    fn compute_interest_match(&self, content_tags: &[String], user_interests: &[String]) -> f32 {
        if content_tags.is_empty() || user_interests.is_empty() {
            return 0.3; // Default score when no tags available
        }

        let content_set: HashSet<&str> = content_tags.iter().map(|s| s.as_str()).collect();
        let user_set: HashSet<&str> = user_interests.iter().map(|s| s.as_str()).collect();

        let intersection = content_set.intersection(&user_set).count();
        let union = content_set.union(&user_set).count();

        if union == 0 {
            0.3
        } else {
            intersection as f32 / union as f32
        }
    }

    /// Compute content type match score
    fn compute_content_type_match(&self, content_type: &str, preferences: &[String]) -> f32 {
        if preferences.is_empty() {
            return 0.5; // Default when no preference
        }

        // Check if content type matches user preference
        let position = preferences
            .iter()
            .position(|p| p.eq_ignore_ascii_case(content_type));

        match position {
            Some(0) => 1.0, // First preference
            Some(1) => 0.7, // Second preference
            Some(2) => 0.5, // Third preference
            Some(_) => 0.3, // Lower preference
            None => 0.2,    // Not in preferences
        }
    }

    /// Enrich candidates with additional features from feature store
    /// This should be called before ranking if candidates don't have all features
    pub fn enrich_candidates(
        &self,
        mut candidates: Vec<CoarseCandidate>,
        user_features: &UserFeatures,
    ) -> Vec<CoarseCandidate> {
        for candidate in &mut candidates {
            // Set is_followed_author flag
            if let Some(author_id) = candidate.author_id {
                candidate.is_followed_author = user_features.followed_authors.contains(&author_id);
            }
        }
        candidates
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::RecallSource;

    fn create_test_candidate(post_id: &str, recall_weight: f32, timestamp: i64) -> CoarseCandidate {
        CoarseCandidate {
            candidate: Candidate {
                post_id: post_id.to_string(),
                recall_source: RecallSource::Trending,
                recall_weight,
                timestamp,
            },
            tags: vec!["music".to_string(), "dance".to_string()],
            content_type: "video".to_string(),
            author_quality: 0.7,
            author_id: None,
            is_followed_author: false,
        }
    }

    #[test]
    fn test_coarse_ranking() {
        let layer = CoarseRankingLayer::new(2);
        let now = chrono::Utc::now().timestamp();

        let candidates = vec![
            create_test_candidate("post1", 0.9, now - 3600), // 1 hour ago, high engagement
            create_test_candidate("post2", 0.5, now),        // Fresh, medium engagement
            create_test_candidate("post3", 0.3, now - 86400), // 1 day old, low engagement
        ];

        let user_features = UserFeatures {
            interest_tags: vec!["music".to_string()],
            content_type_preferences: vec!["video".to_string()],
            ..Default::default()
        };

        let ranked = layer.rank(candidates, &user_features).unwrap();

        assert_eq!(ranked.len(), 2);
        // First should be post1 (high engagement) or post2 (fresh)
        assert!(ranked[0].candidate.post_id == "post1" || ranked[0].candidate.post_id == "post2");
    }

    #[test]
    fn test_interest_match() {
        let layer = CoarseRankingLayer::new(10);

        // Perfect match
        let score = layer.compute_interest_match(
            &["music".to_string(), "dance".to_string()],
            &["music".to_string(), "dance".to_string()],
        );
        assert!((score - 1.0).abs() < 0.01);

        // Partial match
        let score = layer.compute_interest_match(
            &["music".to_string(), "dance".to_string()],
            &["music".to_string(), "cooking".to_string()],
        );
        assert!(score > 0.0 && score < 1.0);

        // No match
        let score = layer.compute_interest_match(&["music".to_string()], &["cooking".to_string()]);
        assert_eq!(score, 0.0);
    }

    #[test]
    fn test_recency_score() {
        let layer = CoarseRankingLayer::new(10);
        let now = chrono::Utc::now().timestamp();

        // Fresh content
        let score = layer.compute_recency_score(now);
        assert!(score > 0.95);

        // 24 hours old
        let score = layer.compute_recency_score(now - 86400);
        assert!(score < 0.4 && score > 0.3);

        // 48 hours old
        let score = layer.compute_recency_score(now - 172800);
        assert!(score < 0.2);
    }

    #[test]
    fn test_followed_author_bonus() {
        let layer = CoarseRankingLayer::new(10);
        let now = chrono::Utc::now().timestamp();
        let author_id = Uuid::new_v4();

        let mut candidate = create_test_candidate("post1", 0.5, now);
        candidate.author_id = Some(author_id);

        let mut user_features = UserFeatures::default();
        user_features.interest_tags = vec!["music".to_string()];

        // Without followed author
        let score_not_followed = layer.compute_score(&candidate, &user_features);

        // With followed author
        user_features.followed_authors.insert(author_id);
        let candidates = layer.enrich_candidates(vec![candidate.clone()], &user_features);
        let score_followed = layer.compute_score(&candidates[0], &user_features);

        assert!(score_followed > score_not_followed);
    }
}

use crate::models::{Candidate, PostFeatures, RankedPost};
use crate::services::features::FeatureClient;
use anyhow::Result;
use std::sync::Arc;
use tracing::debug;

/// Ranking Layer - Fine-grained scoring
/// Phase D: Linear weighted scoring with real features
/// Phase E: GBDT ONNX model inference (planned)
pub struct RankingLayer {
    feature_client: Arc<FeatureClient>,
    weights: RankingWeights,
}

/// Configurable ranking weights
#[derive(Debug, Clone)]
pub struct RankingWeights {
    pub engagement: f32,
    pub recency: f32,
    pub author_quality: f32,
    pub content_quality: f32,
    pub completion_rate: f32,
}

impl Default for RankingWeights {
    fn default() -> Self {
        Self {
            engagement: 0.30,
            recency: 0.25,
            author_quality: 0.15,
            content_quality: 0.15,
            completion_rate: 0.15,
        }
    }
}

impl RankingLayer {
    /// Create new ranking layer with feature client
    pub fn new(feature_client: Arc<FeatureClient>) -> Self {
        Self {
            feature_client,
            weights: RankingWeights::default(),
        }
    }

    /// Create with custom weights
    pub fn with_weights(feature_client: Arc<FeatureClient>, weights: RankingWeights) -> Self {
        Self {
            feature_client,
            weights,
        }
    }

    /// Rank candidates with real feature extraction
    pub async fn rank_candidates(&self, candidates: Vec<Candidate>) -> Result<Vec<RankedPost>> {
        if candidates.is_empty() {
            return Ok(Vec::new());
        }

        // Batch fetch features for all candidates
        let content_ids: Vec<String> = candidates.iter().map(|c| c.post_id.clone()).collect();
        let features_map = self
            .feature_client
            .batch_get_content_features(&content_ids)
            .await;

        debug!(
            "Fetched features for {} candidates, found {} in cache",
            candidates.len(),
            features_map.len()
        );

        let mut ranked_posts: Vec<RankedPost> = candidates
            .into_iter()
            .map(|candidate| {
                let content_features = features_map.get(&candidate.post_id);
                let features = self.extract_features(&candidate, content_features);
                let score = self.compute_score(&features);

                RankedPost {
                    post_id: candidate.post_id,
                    score,
                    recall_source: candidate.recall_source,
                    features,
                }
            })
            .collect();

        // Sort by score descending
        ranked_posts.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        Ok(ranked_posts)
    }

    /// Extract features from candidate with fetched content features
    fn extract_features(
        &self,
        candidate: &Candidate,
        content_features: Option<&crate::services::features::ContentFeatures>,
    ) -> PostFeatures {
        let (author_quality, content_quality, author_id, completion_rate) =
            if let Some(cf) = content_features {
                (
                    cf.author_quality,
                    cf.content_quality,
                    cf.author_id,
                    cf.completion_rate,
                )
            } else {
                // Fallback to defaults when features not available
                (0.5, 0.5, None, 0.5)
            };

        PostFeatures {
            engagement_score: candidate.recall_weight * 0.8,
            recency_score: self.compute_recency_score(candidate.timestamp),
            author_quality_score: author_quality,
            content_quality_score: content_quality,
            completion_rate_score: completion_rate,
            author_id,
        }
    }

    /// Compute recency score with exponential decay
    /// Score = e^(-age_hours / 24)
    /// Fresh content (0h) = 1.0, 24h old = 0.37, 48h old = 0.14
    fn compute_recency_score(&self, timestamp: i64) -> f32 {
        let now = chrono::Utc::now().timestamp();
        let age_seconds = (now - timestamp).max(0) as f32;
        let age_hours = age_seconds / 3600.0;

        // Exponential decay with 24-hour half-life
        (-age_hours / 24.0).exp().max(0.1)
    }

    /// Compute final ranking score
    /// Phase D: Linear weighted combination
    /// Phase E: Replace with GBDT ONNX model
    fn compute_score(&self, features: &PostFeatures) -> f32 {
        features.engagement_score * self.weights.engagement
            + features.recency_score * self.weights.recency
            + features.author_quality_score * self.weights.author_quality
            + features.content_quality_score * self.weights.content_quality
            + features.completion_rate_score * self.weights.completion_rate
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::RecallSource;

    fn create_test_feature_client() -> Arc<FeatureClient> {
        let redis_client =
            redis::Client::open("redis://localhost:6379").expect("Failed to create test Redis");
        Arc::new(FeatureClient::new(redis_client))
    }

    #[tokio::test]
    async fn test_rank_candidates() {
        let feature_client = create_test_feature_client();
        let layer = RankingLayer::new(feature_client);

        let candidates = vec![
            Candidate {
                post_id: "post1".to_string(),
                recall_source: RecallSource::Graph,
                recall_weight: 0.9,
                timestamp: chrono::Utc::now().timestamp() - 3600, // 1 hour ago
            },
            Candidate {
                post_id: "post2".to_string(),
                recall_source: RecallSource::Trending,
                recall_weight: 0.7,
                timestamp: chrono::Utc::now().timestamp() - 7200, // 2 hours ago
            },
        ];

        let ranked = layer.rank_candidates(candidates).await.unwrap();

        assert_eq!(ranked.len(), 2);
        assert!(ranked[0].score >= ranked[1].score);
    }

    #[test]
    fn test_recency_score() {
        let feature_client = create_test_feature_client();
        let layer = RankingLayer::new(feature_client);
        let now = chrono::Utc::now().timestamp();

        // Just posted
        let score_fresh = layer.compute_recency_score(now);
        assert!(score_fresh > 0.9, "Fresh content should have high score");

        // 24 hours ago
        let score_old = layer.compute_recency_score(now - 86400);
        assert!(
            score_old < 0.5,
            "24h old content should have lower score: {}",
            score_old
        );

        // 48 hours ago
        let score_very_old = layer.compute_recency_score(now - 172800);
        assert!(
            score_very_old < 0.2,
            "48h old content should have very low score: {}",
            score_very_old
        );
    }

    #[test]
    fn test_compute_score_with_weights() {
        let feature_client = create_test_feature_client();
        let layer = RankingLayer::new(feature_client);

        let features = PostFeatures {
            engagement_score: 0.8,
            recency_score: 0.9,
            author_quality_score: 0.7,
            content_quality_score: 0.6,
            completion_rate_score: 0.85,
            author_id: None,
        };

        let score = layer.compute_score(&features);

        // Expected: 0.8*0.30 + 0.9*0.25 + 0.7*0.15 + 0.6*0.15 + 0.85*0.15
        // = 0.24 + 0.225 + 0.105 + 0.09 + 0.1275 = 0.7875
        assert!(
            (score - 0.7875).abs() < 0.01,
            "Score should be ~0.7875, got {}",
            score
        );
    }

    #[test]
    fn test_custom_weights() {
        let feature_client = create_test_feature_client();
        let custom_weights = RankingWeights {
            engagement: 0.5,
            recency: 0.2,
            author_quality: 0.1,
            content_quality: 0.1,
            completion_rate: 0.1,
        };
        let layer = RankingLayer::with_weights(feature_client, custom_weights);

        assert_eq!(layer.weights.engagement, 0.5);
        assert_eq!(layer.weights.recency, 0.2);
    }
}

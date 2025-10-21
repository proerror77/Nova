// ============================================
// Hybrid Recommendation Ranker (T247)
// ============================================
//
// Combines collaborative filtering and content-based filtering with
// learned weights and diversity optimization (MMR).

use crate::error::{AppError, Result};
use crate::services::feed_ranking::RankedPost;
use crate::services::recommendation_v2::{CollaborativeFilteringModel, ContentBasedModel};
use std::collections::HashMap;
use uuid::Uuid;

/// Hybrid ranker weights
#[derive(Debug, Clone, Copy)]
pub struct HybridWeights {
    pub collaborative: f64,
    pub content_based: f64,
    pub v1_fallback: f64,
}

impl HybridWeights {
    /// Create default balanced weights
    pub fn balanced() -> Self {
        Self {
            collaborative: 0.4,
            content_based: 0.3,
            v1_fallback: 0.3,
        }
    }

    /// Create cold-start weights (rely on v1.0 trending)
    pub fn cold_start() -> Self {
        Self {
            collaborative: 0.1,
            content_based: 0.1,
            v1_fallback: 0.8,
        }
    }

    /// Create power-user weights (high personalization)
    pub fn power_user() -> Self {
        Self {
            collaborative: 0.5,
            content_based: 0.4,
            v1_fallback: 0.1,
        }
    }

    /// Validate weights sum to 1.0
    pub fn validate(&self) -> Result<()> {
        let sum = self.collaborative + self.content_based + self.v1_fallback;
        if (sum - 1.0).abs() > 0.01 {
            return Err(AppError::BadRequest(format!(
                "Weights must sum to 1.0 (got {})",
                sum
            )));
        }
        Ok(())
    }
}

/// Ranking strategy
#[derive(Debug, Clone, Copy)]
pub enum RankingStrategy {
    Balanced,  // Equal weights
    ColdStart, // Rely on v1.0 trending
    PowerUser, // High personalization
    Custom(HybridWeights),
}

/// Hybrid recommendation ranker
pub struct HybridRanker {
    pub cf_model: CollaborativeFilteringModel,
    pub cb_model: ContentBasedModel,
    pub weights: HybridWeights,
}

impl HybridRanker {
    /// Create new hybrid ranker
    pub fn new(
        cf_model: CollaborativeFilteringModel,
        cb_model: ContentBasedModel,
        weights: HybridWeights,
    ) -> Result<Self> {
        weights.validate()?;
        Ok(Self {
            cf_model,
            cb_model,
            weights,
        })
    }

    /// Get top-K recommendations for user
    pub async fn recommend(
        &self,
        user_id: Uuid,
        candidates: Vec<Uuid>,
        k: usize,
    ) -> Result<Vec<RankedPost>> {
        if candidates.is_empty() {
            return Ok(Vec::new());
        }

        // Step 1: Score with collaborative filtering
        let cf_scores = self.score_collaborative(user_id, &candidates).await?;

        // Step 2: Score with content-based filtering
        let cb_scores = self.score_content_based(user_id, &candidates).await?;

        // Step 3: Score with v1.0 fallback (mock for now)
        let v1_scores = self.score_v1_fallback(&candidates).await?;

        // Step 4: Combine with learned weights
        let hybrid_scores = self.combine_scores(&candidates, &cf_scores, &cb_scores, &v1_scores)?;

        // Step 5: Apply diversity optimization (MMR)
        let diversified = self.apply_diversity(hybrid_scores, k)?;

        Ok(diversified)
    }

    /// Score candidates using collaborative filtering
    async fn score_collaborative(
        &self,
        user_id: Uuid,
        candidates: &[Uuid],
    ) -> Result<HashMap<Uuid, f64>> {
        // TODO: Get recent user interactions
        let recent_posts: Vec<Uuid> = vec![];
        let seen_posts: Vec<Uuid> = vec![];

        // Use item-based CF
        let recommendations =
            self.cf_model
                .recommend_item_based(&recent_posts, &seen_posts, candidates.len())?;

        Ok(recommendations.into_iter().collect())
    }

    /// Score candidates using content-based filtering
    async fn score_content_based(
        &self,
        user_id: Uuid,
        candidates: &[Uuid],
    ) -> Result<HashMap<Uuid, f64>> {
        let recommendations = self
            .cb_model
            .recommend(user_id, candidates.to_vec(), candidates.len())
            .await?;

        Ok(recommendations.into_iter().collect())
    }

    /// Score candidates using v1.0 fallback (mock)
    async fn score_v1_fallback(&self, candidates: &[Uuid]) -> Result<HashMap<Uuid, f64>> {
        // TODO: Use existing v1.0 ranking service
        // For now, return uniform scores
        Ok(candidates.iter().map(|&id| (id, 0.5)).collect())
    }

    /// Combine scores with learned weights
    fn combine_scores(
        &self,
        candidates: &[Uuid],
        cf_scores: &HashMap<Uuid, f64>,
        cb_scores: &HashMap<Uuid, f64>,
        v1_scores: &HashMap<Uuid, f64>,
    ) -> Result<Vec<(Uuid, f64)>> {
        let mut hybrid_scores = Vec::new();

        for &post_id in candidates {
            let cf = cf_scores.get(&post_id).copied().unwrap_or(0.0);
            let cb = cb_scores.get(&post_id).copied().unwrap_or(0.0);
            let v1 = v1_scores.get(&post_id).copied().unwrap_or(0.0);

            let final_score = self.weights.collaborative * cf
                + self.weights.content_based * cb
                + self.weights.v1_fallback * v1;

            hybrid_scores.push((post_id, final_score));
        }

        // Sort by final_score (descending)
        hybrid_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        Ok(hybrid_scores)
    }

    /// Apply diversity optimization using MMR (Maximal Marginal Relevance)
    ///
    /// Algorithm:
    /// 1. Select post with highest relevance
    /// 2. For each remaining post, compute MMR score:
    ///    MMR = λ × relevance - (1-λ) × max_similarity_to_selected
    /// 3. Select post with highest MMR
    /// 4. Repeat until k posts selected
    fn apply_diversity(&self, mut scored: Vec<(Uuid, f64)>, k: usize) -> Result<Vec<RankedPost>> {
        if scored.is_empty() {
            return Ok(Vec::new());
        }

        let lambda = 0.5; // Balance between relevance and diversity
        let mut selected = Vec::new();

        // Select first post (highest relevance)
        let first = scored.remove(0);
        selected.push(RankedPost {
            post_id: first.0,
            combined_score: first.1,
            reason: "hybrid_v2".to_string(),
        });

        // Select remaining posts with MMR
        while selected.len() < k && !scored.is_empty() {
            let mut best_idx = 0;
            let mut best_mmr = f64::NEG_INFINITY;

            for (idx, (post_id, relevance)) in scored.iter().enumerate() {
                // Compute max similarity to already selected posts
                let max_sim = self.compute_max_similarity(*post_id, &selected);

                // MMR score
                let mmr = lambda * relevance - (1.0 - lambda) * max_sim;

                if mmr > best_mmr {
                    best_mmr = mmr;
                    best_idx = idx;
                }
            }

            let next = scored.remove(best_idx);
            selected.push(RankedPost {
                post_id: next.0,
                combined_score: next.1,
                reason: "hybrid_v2".to_string(),
            });
        }

        Ok(selected)
    }

    /// Compute max similarity between candidate and already selected posts
    fn compute_max_similarity(&self, candidate: Uuid, selected: &[RankedPost]) -> f64 {
        // TODO: Use actual similarity from item-item matrix
        // For now, return low similarity (no diversity penalty)
        0.1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hybrid_weights_validation() {
        let weights = HybridWeights {
            collaborative: 0.4,
            content_based: 0.3,
            v1_fallback: 0.3,
        };
        assert!(weights.validate().is_ok());

        let invalid_weights = HybridWeights {
            collaborative: 0.5,
            content_based: 0.5,
            v1_fallback: 0.5,
        };
        assert!(invalid_weights.validate().is_err());
    }

    #[test]
    fn test_combine_scores() {
        let cf_model = CollaborativeFilteringModel {
            user_similarity: HashMap::new(),
            item_similarity: HashMap::new(),
            k_neighbors: 50,
            metric: crate::services::recommendation_v2::collaborative_filtering::SimilarityMetric::Cosine,
        };

        let cb_model = ContentBasedModel {
            post_features: HashMap::new(),
            user_profiles: HashMap::new(),
            vocab_size: 1000,
        };

        let weights = HybridWeights::balanced();
        let ranker = HybridRanker::new(cf_model, cb_model, weights).unwrap();

        let candidates = vec![Uuid::new_v4(), Uuid::new_v4()];
        let mut cf_scores = HashMap::new();
        let mut cb_scores = HashMap::new();
        let mut v1_scores = HashMap::new();

        cf_scores.insert(candidates[0], 0.8);
        cb_scores.insert(candidates[0], 0.6);
        v1_scores.insert(candidates[0], 0.4);

        cf_scores.insert(candidates[1], 0.2);
        cb_scores.insert(candidates[1], 0.4);
        v1_scores.insert(candidates[1], 0.6);

        let hybrid = ranker
            .combine_scores(&candidates, &cf_scores, &cb_scores, &v1_scores)
            .unwrap();

        assert_eq!(hybrid.len(), 2);
        // First post should have higher score (0.4*0.8 + 0.3*0.6 + 0.3*0.4 = 0.62)
        assert!(hybrid[0].1 > hybrid[1].1);
    }
}

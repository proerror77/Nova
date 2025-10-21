// ============================================
// Collaborative Filtering Model (T245)
// ============================================
//
// Implements user-user and item-item collaborative filtering using:
// - k-Nearest Neighbors (kNN) with cosine similarity
// - (Optional) Matrix Factorization (ALS) with latent factors
//
// Data Flow:
//   ClickHouse (user_item_interactions) → Similarity Computation → Sparse Matrix
//                                                ↓
//                                         Recommendations

use crate::error::{AppError, Result};
use std::collections::HashMap;
use uuid::Uuid;

/// Similarity metric for collaborative filtering
#[derive(Debug, Clone, Copy)]
pub enum SimilarityMetric {
    Cosine,
    Jaccard,
    Pearson,
}

/// Collaborative filtering model
pub struct CollaborativeFilteringModel {
    /// User-User similarity: user_id → [(similar_user_id, similarity_score)]
    pub user_similarity: HashMap<Uuid, Vec<(Uuid, f64)>>,

    /// Item-Item similarity: post_id → [(similar_post_id, similarity_score)]
    pub item_similarity: HashMap<Uuid, Vec<(Uuid, f64)>>,

    /// Configuration
    pub k_neighbors: usize,
    pub metric: SimilarityMetric,
}

impl CollaborativeFilteringModel {
    /// Load pre-computed similarity matrices from disk
    ///
    /// Expected file format: bincode serialized HashMap<Uuid, Vec<(Uuid, f64)>>
    pub fn load(user_sim_path: &str, item_sim_path: &str, k_neighbors: usize) -> Result<Self> {
        // TODO: Implement loading from bincode files
        // let user_similarity = load_bincode(user_sim_path)?;
        // let item_similarity = load_bincode(item_sim_path)?;

        todo!("Implement load from disk")
    }

    /// Get recommended posts using user-user collaborative filtering
    ///
    /// Algorithm:
    /// 1. Find top-K similar users to target user
    /// 2. Aggregate posts they engaged with (weighted by similarity)
    /// 3. Filter out posts target user already seen
    /// 4. Return top-N posts by weighted score
    pub fn recommend_user_based(
        &self,
        user_id: Uuid,
        seen_posts: &[Uuid],
        n: usize,
    ) -> Result<Vec<(Uuid, f64)>> {
        // TODO: Implement user-based CF
        // 1. Get similar users from self.user_similarity
        // 2. Query their liked posts from ClickHouse
        // 3. Aggregate scores: score[post] = Σ(similarity[user] * interaction[user, post])
        // 4. Sort by score, filter seen_posts, return top-N

        todo!("Implement recommend_user_based")
    }

    /// Get recommended posts using item-item collaborative filtering
    ///
    /// Algorithm:
    /// 1. Get recent posts user engaged with
    /// 2. For each post, find top-K similar posts
    /// 3. Aggregate similarity scores
    /// 4. Filter out already seen posts
    /// 5. Return top-N posts by aggregated score
    pub fn recommend_item_based(
        &self,
        recent_posts: &[Uuid],
        seen_posts: &[Uuid],
        n: usize,
    ) -> Result<Vec<(Uuid, f64)>> {
        if recent_posts.is_empty() {
            return Ok(Vec::new());
        }

        let mut aggregated_scores: HashMap<Uuid, f64> = HashMap::new();

        for &recent_post in recent_posts {
            if let Some(similar_posts) = self.item_similarity.get(&recent_post) {
                for &(similar_post, similarity) in similar_posts {
                    // Skip if already seen
                    if seen_posts.contains(&similar_post) {
                        continue;
                    }

                    // Aggregate similarity scores
                    *aggregated_scores.entry(similar_post).or_insert(0.0) += similarity;
                }
            }
        }

        // Sort by aggregated score (descending)
        let mut ranked: Vec<(Uuid, f64)> = aggregated_scores.into_iter().collect();
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        Ok(ranked.into_iter().take(n).collect())
    }

    /// Find top-K similar users to target user
    pub fn find_similar_users(&self, user_id: Uuid, k: usize) -> Vec<(Uuid, f64)> {
        self.user_similarity
            .get(&user_id)
            .map(|users| users.iter().take(k).copied().collect())
            .unwrap_or_default()
    }

    /// Find top-K similar posts to target post
    pub fn find_similar_posts(&self, post_id: Uuid, k: usize) -> Vec<(Uuid, f64)> {
        self.item_similarity
            .get(&post_id)
            .map(|posts| posts.iter().take(k).copied().collect())
            .unwrap_or_default()
    }

    /// Compute cosine similarity between two interaction vectors
    ///
    /// Formula: cos(A, B) = (A · B) / (||A|| × ||B||)
    fn cosine_similarity(vec_a: &[f64], vec_b: &[f64]) -> f64 {
        if vec_a.len() != vec_b.len() {
            return 0.0;
        }

        let dot_product: f64 = vec_a.iter().zip(vec_b.iter()).map(|(a, b)| a * b).sum();
        let norm_a: f64 = vec_a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let norm_b: f64 = vec_b.iter().map(|x| x * x).sum::<f64>().sqrt();

        if norm_a == 0.0 || norm_b == 0.0 {
            0.0
        } else {
            dot_product / (norm_a * norm_b)
        }
    }

    /// Get model metadata
    pub fn metadata(&self) -> ModelMetadata {
        ModelMetadata {
            user_count: self.user_similarity.len(),
            item_count: self.item_similarity.len(),
            k_neighbors: self.k_neighbors,
            metric: format!("{:?}", self.metric),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ModelMetadata {
    pub user_count: usize,
    pub item_count: usize,
    pub k_neighbors: usize,
    pub metric: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity() {
        let vec_a = vec![1.0, 2.0, 3.0];
        let vec_b = vec![4.0, 5.0, 6.0];

        let similarity = CollaborativeFilteringModel::cosine_similarity(&vec_a, &vec_b);
        assert!(similarity > 0.9); // Nearly collinear vectors
    }

    #[test]
    fn test_cosine_similarity_orthogonal() {
        let vec_a = vec![1.0, 0.0];
        let vec_b = vec![0.0, 1.0];

        let similarity = CollaborativeFilteringModel::cosine_similarity(&vec_a, &vec_b);
        assert_eq!(similarity, 0.0); // Orthogonal vectors
    }

    #[tokio::test]
    async fn test_recommend_item_based() {
        // Create mock similarity matrix
        let mut item_similarity = HashMap::new();
        let post1 = Uuid::new_v4();
        let post2 = Uuid::new_v4();
        let post3 = Uuid::new_v4();

        item_similarity.insert(post1, vec![(post2, 0.8), (post3, 0.6)]);

        let model = CollaborativeFilteringModel {
            user_similarity: HashMap::new(),
            item_similarity,
            k_neighbors: 50,
            metric: SimilarityMetric::Cosine,
        };

        let recent_posts = vec![post1];
        let seen_posts = vec![];
        let recommendations = model
            .recommend_item_based(&recent_posts, &seen_posts, 10)
            .unwrap();

        assert_eq!(recommendations.len(), 2);
        assert_eq!(recommendations[0].0, post2); // Higher similarity first
        assert_eq!(recommendations[0].1, 0.8);
    }
}

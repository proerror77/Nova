// ============================================
// Content-Based Filtering Model (T246)
// ============================================
//
// Extracts post features (TF-IDF) and builds user interest profiles
// for semantic content matching.
//
// Data Flow:
//   Posts (caption + hashtags) → TF-IDF Vectorization → Post Features
//   User Interactions → Feature Aggregation → User Profile
//   User Profile × Post Features → Content Similarity Score

use crate::error::Result;
use std::collections::HashMap;
use uuid::Uuid;

/// Content-based filtering model
#[derive(Debug, Clone)]
pub struct ContentBasedModel {
    /// Post feature vectors (TF-IDF): post_id → feature_vector
    pub post_features: HashMap<Uuid, Vec<f32>>,

    /// User interest profiles: user_id → aggregated_feature_vector
    pub user_profiles: HashMap<Uuid, Vec<f32>>,

    /// TF-IDF vocabulary size
    pub vocab_size: usize,
}

/// Post features (TF-IDF vector)
#[derive(Debug, Clone)]
pub struct PostFeatures {
    pub post_id: Uuid,
    pub features: Vec<f32>,
}

/// User interest profile (aggregated TF-IDF)
#[derive(Debug, Clone)]
pub struct UserProfile {
    pub user_id: Uuid,
    pub features: Vec<f32>,
    pub last_updated: chrono::DateTime<chrono::Utc>,
}

impl ContentBasedModel {
    /// Load post features from parquet file (generated offline by Python script)
    pub fn load_post_features(path: &str) -> Result<HashMap<Uuid, Vec<f32>>> {
        // Minimal implementation: return empty map to avoid panic
        // TODO: Load parquet file using arrow-rs when offline feature extraction is ready
        // Expected format: (post_id, feature_0, feature_1, ..., feature_999)

        let _ = path;

        Ok(HashMap::new())
    }

    /// Build user profile from interaction history
    ///
    /// Algorithm:
    /// 1. Query user's engaged posts from ClickHouse (liked, commented, shared)
    /// 2. Aggregate feature vectors with weights:
    ///    - Like: weight = 1.0
    ///    - Comment: weight = 2.0
    ///    - Share: weight = 3.0
    /// 3. Normalize to unit vector (L2 norm = 1)
    pub async fn build_user_profile(&self, _user_id: Uuid) -> Result<Vec<f32>> {
        // TODO: Query user interactions from ClickHouse
        // let interactions = query_user_interactions(_user_id).await?;

        // Mock implementation
        let interactions: Vec<(Uuid, String, f64)> = vec![]; // (post_id, action, weight)

        let mut aggregated = vec![0.0f32; self.vocab_size];

        for (post_id, _action, weight) in interactions {
            if let Some(post_feat) = self.post_features.get(&post_id) {
                for (i, &feat_val) in post_feat.iter().enumerate() {
                    aggregated[i] += feat_val * weight as f32;
                }
            }
        }

        // Normalize to unit vector
        let norm: f32 = aggregated.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm > 0.0 {
            aggregated.iter_mut().for_each(|x| *x /= norm);
        }

        Ok(aggregated)
    }

    /// Compute cosine similarity between user profile and post features
    ///
    /// Formula: cos(user, post) = Σ(user[i] × post[i]) / (||user|| × ||post||)
    pub fn compute_similarity(&self, user_profile: &[f32], post_id: Uuid) -> f64 {
        let post_feat = match self.post_features.get(&post_id) {
            Some(feat) => feat,
            None => return 0.0, // Post features not available
        };

        if user_profile.len() != post_feat.len() {
            return 0.0;
        }

        // Cosine similarity
        let dot_product: f32 = user_profile
            .iter()
            .zip(post_feat.iter())
            .map(|(u, p)| u * p)
            .sum();

        let norm_user: f32 = user_profile.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_post: f32 = post_feat.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm_user == 0.0 || norm_post == 0.0 {
            0.0
        } else {
            (dot_product / (norm_user * norm_post)) as f64
        }
    }

    /// Get top-K content-based recommendations for user
    pub async fn recommend(
        &self,
        user_id: Uuid,
        candidates: Vec<Uuid>,
        k: usize,
    ) -> Result<Vec<(Uuid, f64)>> {
        // Build user profile (or load from cache)
        let user_profile = if let Some(cached) = self.user_profiles.get(&user_id) {
            cached.clone()
        } else {
            self.build_user_profile(user_id).await?
        };

        // Score each candidate
        let mut scored: Vec<(Uuid, f64)> = candidates
            .into_iter()
            .map(|post_id| {
                let similarity = self.compute_similarity(&user_profile, post_id);
                (post_id, similarity)
            })
            .collect();

        // Sort by similarity (descending)
        scored.sort_by(|a, b| {
            b.1.partial_cmp(&a.1)
                .expect("Similarity scores should not be NaN")
        });

        Ok(scored.into_iter().take(k).collect())
    }

    /// Update user profile in cache
    pub fn cache_user_profile(&mut self, user_id: Uuid, profile: Vec<f32>) {
        self.user_profiles.insert(user_id, profile);
    }

    /// Aggregate weighted post features into a user profile vector
    pub fn aggregate_profile(&self, weighted_posts: &[(Uuid, f32)]) -> Option<Vec<f32>> {
        if weighted_posts.is_empty() || self.vocab_size == 0 {
            return None;
        }

        let mut profile = vec![0.0f32; self.vocab_size];
        let mut total_weight = 0.0f32;

        for (post_id, weight) in weighted_posts {
            if *weight <= 0.0 {
                continue;
            }

            if let Some(features) = self.post_features.get(post_id) {
                for (idx, &value) in features.iter().enumerate() {
                    if idx < profile.len() {
                        profile[idx] += value * *weight;
                    }
                }
                total_weight += *weight;
            }
        }

        if total_weight == 0.0 {
            return None;
        }

        // Convert to weighted average
        profile.iter_mut().for_each(|v| *v /= total_weight);

        let norm: f32 = profile.iter().map(|x| x * x).sum::<f32>().sqrt();
        if norm == 0.0 {
            return None;
        }

        profile.iter_mut().for_each(|v| *v /= norm);
        Some(profile)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity() {
        let mut model = ContentBasedModel {
            post_features: HashMap::new(),
            user_profiles: HashMap::new(),
            vocab_size: 3,
        };

        let post_id = Uuid::new_v4();
        model.post_features.insert(post_id, vec![1.0, 0.0, 0.0]);

        let user_profile = vec![1.0, 0.0, 0.0]; // Same direction
        let similarity = model.compute_similarity(&user_profile, post_id);

        assert!((similarity - 1.0).abs() < 0.01); // Should be ~1.0
    }

    #[test]
    fn test_cosine_similarity_orthogonal() {
        let mut model = ContentBasedModel {
            post_features: HashMap::new(),
            user_profiles: HashMap::new(),
            vocab_size: 2,
        };

        let post_id = Uuid::new_v4();
        model.post_features.insert(post_id, vec![1.0, 0.0]);

        let user_profile = vec![0.0, 1.0]; // Orthogonal
        let similarity = model.compute_similarity(&user_profile, post_id);

        assert_eq!(similarity, 0.0);
    }

    #[tokio::test]
    async fn test_recommend() {
        let mut model = ContentBasedModel {
            post_features: HashMap::new(),
            user_profiles: HashMap::new(),
            vocab_size: 3,
        };

        let post1 = Uuid::new_v4();
        let post2 = Uuid::new_v4();
        let post3 = Uuid::new_v4();

        model.post_features.insert(post1, vec![1.0, 0.0, 0.0]);
        model.post_features.insert(post2, vec![0.9, 0.1, 0.0]); // Similar to user profile
        model.post_features.insert(post3, vec![0.0, 0.0, 1.0]); // Orthogonal

        let user_profile = vec![1.0, 0.0, 0.0];
        model.cache_user_profile(Uuid::new_v4(), user_profile.clone());

        let user_id = Uuid::new_v4();
        model.cache_user_profile(user_id, user_profile);

        let candidates = vec![post1, post2, post3];
        let recommendations = model.recommend(user_id, candidates, 2).await.unwrap();

        assert_eq!(recommendations.len(), 2);
        assert_eq!(recommendations[0].0, post1); // Highest similarity
        assert!(recommendations[0].1 > 0.9);
    }
}

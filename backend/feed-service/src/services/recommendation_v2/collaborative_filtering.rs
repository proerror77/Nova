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

use crate::error::Result;
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use tracing::{info, warn};
use uuid::Uuid;

/// Similarity metric for collaborative filtering
#[derive(Debug, Clone, Copy)]
pub enum SimilarityMetric {
    Cosine,
    Jaccard,
    Pearson,
}

/// Collaborative filtering model
#[derive(Debug, Clone)]
pub struct CollaborativeFilteringModel {
    /// User-User similarity: user_id → [(similar_user_id, similarity_score)]
    pub user_similarity: HashMap<Uuid, Vec<(Uuid, f64)>>,

    /// Item-Item similarity: post_id → [(similar_post_id, similarity_score)]
    pub item_similarity: HashMap<Uuid, Vec<(Uuid, f64)>>,

    /// User-Liked posts: user_id → [(post_id, interaction_weight)]
    /// Interaction weights: like=1.0, comment=2.0, share=3.0, complete_watch=1.5
    pub user_liked_posts: HashMap<Uuid, Vec<(Uuid, f64)>>,

    /// Configuration
    pub k_neighbors: usize,
    pub metric: SimilarityMetric,
}

impl CollaborativeFilteringModel {
    /// Load pre-computed similarity matrices from disk
    ///
    /// Expected file format: JSON serialized HashMap<Uuid, Vec<(Uuid, f64)>>
    pub fn load(user_sim_path: &str, item_sim_path: &str, k_neighbors: usize) -> Result<Self> {
        let user_path = normalize_path(user_sim_path, "user_similarity.json");
        let item_path = normalize_path(item_sim_path, "item_similarity.json");
        let user_liked_path = normalize_path(user_sim_path, "user_liked_posts.json");

        let user_similarity = load_similarity_map(&user_path, k_neighbors)?;
        let item_similarity = load_similarity_map(&item_path, k_neighbors)?;
        let user_liked_posts = load_user_liked_posts(&user_liked_path)?;

        info!(
            user_entries = user_similarity.len(),
            item_entries = item_similarity.len(),
            user_liked_entries = user_liked_posts.len(),
            "Collaborative filtering data loaded"
        );

        Ok(Self {
            user_similarity,
            item_similarity,
            user_liked_posts,
            k_neighbors,
            metric: SimilarityMetric::Cosine,
        })
    }

    /// Create an empty model (for testing or initialization)
    pub fn empty(k_neighbors: usize) -> Self {
        Self {
            user_similarity: HashMap::new(),
            item_similarity: HashMap::new(),
            user_liked_posts: HashMap::new(),
            k_neighbors,
            metric: SimilarityMetric::Cosine,
        }
    }

    /// Update user liked posts (for real-time updates)
    pub fn update_user_liked_posts(&mut self, user_id: Uuid, post_id: Uuid, weight: f64) {
        let posts = self.user_liked_posts.entry(user_id).or_default();
        // Update existing entry or add new one
        if let Some(existing) = posts.iter_mut().find(|(p, _)| *p == post_id) {
            existing.1 = weight.max(existing.1); // Keep highest weight
        } else {
            posts.push((post_id, weight));
            // Keep only top 100 posts per user
            if posts.len() > 100 {
                posts.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
                posts.truncate(100);
            }
        }
    }

    /// Get recommended posts using user-user collaborative filtering
    ///
    /// Algorithm:
    /// 1. Find top-K similar users to target user
    /// 2. Aggregate posts they engaged with (weighted by similarity)
    /// 3. Filter out posts target user already seen
    /// 4. Return top-N posts by weighted score
    ///
    /// Formula: score[post] = Σ(similarity[user] × interaction_weight[user, post])
    pub fn recommend_user_based(
        &self,
        user_id: Uuid,
        seen_posts: &[Uuid],
        n: usize,
    ) -> Result<Vec<(Uuid, f64)>> {
        // Step 1: Find similar users
        let similar_users = self.find_similar_users(user_id, self.k_neighbors);

        if similar_users.is_empty() {
            info!(
                user_id = %user_id,
                "No similar users found for user-based CF"
            );
            return Ok(Vec::new());
        }

        // Step 2: Aggregate posts from similar users weighted by similarity
        let mut aggregated_scores: HashMap<Uuid, f64> = HashMap::new();

        for (similar_user_id, user_similarity) in &similar_users {
            // Get posts this similar user liked
            if let Some(liked_posts) = self.user_liked_posts.get(similar_user_id) {
                for (post_id, interaction_weight) in liked_posts {
                    // Skip if already seen by target user
                    if seen_posts.contains(post_id) {
                        continue;
                    }

                    // Weighted score: similarity × interaction_weight
                    let weighted_score = user_similarity * interaction_weight;
                    *aggregated_scores.entry(*post_id).or_insert(0.0) += weighted_score;
                }
            }
        }

        if aggregated_scores.is_empty() {
            info!(
                user_id = %user_id,
                similar_users_count = similar_users.len(),
                "No unseen posts from similar users"
            );
            return Ok(Vec::new());
        }

        // Step 3: Sort by aggregated score (descending) and return top-N
        let mut ranked: Vec<(Uuid, f64)> = aggregated_scores.into_iter().collect();
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        info!(
            user_id = %user_id,
            similar_users_count = similar_users.len(),
            candidate_posts = ranked.len(),
            "User-based CF recommendations generated"
        );

        Ok(ranked.into_iter().take(n).collect())
    }

    /// Get user liked posts (for inspection/debugging)
    pub fn get_user_liked_posts(&self, user_id: Uuid) -> Option<&Vec<(Uuid, f64)>> {
        self.user_liked_posts.get(&user_id)
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
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).expect("Scores should not be NaN"));

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

fn normalize_path(path: &str, default_file: &str) -> PathBuf {
    let candidate = Path::new(path);
    if candidate.is_dir() {
        candidate.join(default_file)
    } else {
        candidate.to_path_buf()
    }
}

/// Load user liked posts from JSON file
/// Format: { "user_id": [{"id": "post_id", "score": 1.5}, ...] }
fn load_user_liked_posts(path: &Path) -> Result<HashMap<Uuid, Vec<(Uuid, f64)>>> {
    if path.as_os_str().is_empty() {
        return Ok(HashMap::new());
    }

    if !path.exists() {
        warn!("User liked posts file missing: {}", path.display());
        return Ok(HashMap::new());
    }

    let data = fs::read(path)?;
    if data.is_empty() {
        return Ok(HashMap::new());
    }

    let parsed: HashMap<String, SimilarityEntries> = serde_json::from_slice(&data)?;
    let mut result = HashMap::with_capacity(parsed.len());

    for (user_key, entries) in parsed {
        let user_id = match Uuid::parse_str(&user_key) {
            Ok(id) => id,
            Err(err) => {
                warn!("Invalid UUID in user liked posts key {}: {}", user_key, err);
                continue;
            }
        };

        let mut posts = Vec::new();
        for entry in entries.flatten() {
            if entry.score <= 0.0 {
                continue;
            }

            match Uuid::parse_str(&entry.id) {
                Ok(post_id) => posts.push((post_id, entry.score)),
                Err(err) => warn!(
                    "Invalid UUID in user liked posts entry {}: {}",
                    entry.id, err
                ),
            }
        }

        if !posts.is_empty() {
            // Sort by score descending
            posts.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
            result.insert(user_id, posts);
        }
    }

    info!(users_count = result.len(), "User liked posts loaded");

    Ok(result)
}

fn load_similarity_map(path: &Path, k_neighbors: usize) -> Result<HashMap<Uuid, Vec<(Uuid, f64)>>> {
    if path.as_os_str().is_empty() {
        return Ok(HashMap::new());
    }

    if !path.exists() {
        warn!("Similarity file missing: {}", path.display());
        return Ok(HashMap::new());
    }

    let data = fs::read(path)?;
    if data.is_empty() {
        return Ok(HashMap::new());
    }

    let parsed: HashMap<String, SimilarityEntries> = serde_json::from_slice(&data)?;
    let mut result = HashMap::with_capacity(parsed.len());

    for (key, entries) in parsed {
        let entity_id = match Uuid::parse_str(&key) {
            Ok(id) => id,
            Err(err) => {
                warn!("Invalid UUID in similarity map key {}: {}", key, err);
                continue;
            }
        };

        let mut neighbours = Vec::new();
        for entry in entries.flatten() {
            if entry.score <= 0.0 {
                continue;
            }

            match Uuid::parse_str(&entry.id) {
                Ok(id) => neighbours.push((id, entry.score)),
                Err(err) => warn!("Invalid UUID in similarity entry {}: {}", entry.id, err),
            }
        }

        if !neighbours.is_empty() {
            neighbours.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
            neighbours.truncate(k_neighbors);
            result.insert(entity_id, neighbours);
        }
    }

    Ok(result)
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum SimilarityEntries {
    List(Vec<SimilarityEntry>),
    Map(HashMap<String, f64>),
}

impl SimilarityEntries {
    fn flatten(self) -> Vec<SimilarityEntry> {
        match self {
            SimilarityEntries::List(list) => list,
            SimilarityEntries::Map(map) => map
                .into_iter()
                .map(|(id, score)| SimilarityEntry { id, score })
                .collect(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct SimilarityEntry {
    #[serde(alias = "user_id", alias = "post_id", alias = "id")]
    id: String,
    #[serde(alias = "similarity", alias = "score", alias = "value")]
    score: f64,
}

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
            user_liked_posts: HashMap::new(),
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

    #[tokio::test]
    async fn test_recommend_user_based() {
        // Create mock data
        let user1 = Uuid::new_v4(); // Target user
        let user2 = Uuid::new_v4(); // Similar user
        let user3 = Uuid::new_v4(); // Another similar user
        let post1 = Uuid::new_v4(); // Already seen
        let post2 = Uuid::new_v4(); // Should be recommended (liked by user2)
        let post3 = Uuid::new_v4(); // Should be recommended (liked by user2 and user3)
        let post4 = Uuid::new_v4(); // Should be recommended (liked by user3)

        let mut user_similarity = HashMap::new();
        user_similarity.insert(user1, vec![(user2, 0.9), (user3, 0.7)]);

        let mut user_liked_posts = HashMap::new();
        user_liked_posts.insert(
            user2,
            vec![
                (post1, 1.0), // Seen by target, should be filtered
                (post2, 2.0), // Not seen, should appear
                (post3, 1.5), // Not seen, should appear
            ],
        );
        user_liked_posts.insert(
            user3,
            vec![
                (post3, 3.0), // Also liked by user3, should get combined score
                (post4, 1.0), // Only liked by user3
            ],
        );

        let model = CollaborativeFilteringModel {
            user_similarity,
            item_similarity: HashMap::new(),
            user_liked_posts,
            k_neighbors: 50,
            metric: SimilarityMetric::Cosine,
        };

        let seen_posts = vec![post1];
        let recommendations = model.recommend_user_based(user1, &seen_posts, 10).unwrap();

        assert_eq!(recommendations.len(), 3);

        // post3 should have highest score: 0.9 * 1.5 + 0.7 * 3.0 = 1.35 + 2.1 = 3.45
        assert_eq!(recommendations[0].0, post3);
        assert!((recommendations[0].1 - 3.45).abs() < 0.01);

        // post2 should be second: 0.9 * 2.0 = 1.8
        assert_eq!(recommendations[1].0, post2);
        assert!((recommendations[1].1 - 1.8).abs() < 0.01);

        // post4 should be third: 0.7 * 1.0 = 0.7
        assert_eq!(recommendations[2].0, post4);
        assert!((recommendations[2].1 - 0.7).abs() < 0.01);
    }

    #[test]
    fn test_update_user_liked_posts() {
        let mut model = CollaborativeFilteringModel::empty(50);
        let user = Uuid::new_v4();
        let post1 = Uuid::new_v4();
        let post2 = Uuid::new_v4();

        // Add first interaction
        model.update_user_liked_posts(user, post1, 1.0);
        assert_eq!(model.user_liked_posts.get(&user).unwrap().len(), 1);

        // Add second interaction
        model.update_user_liked_posts(user, post2, 2.0);
        assert_eq!(model.user_liked_posts.get(&user).unwrap().len(), 2);

        // Update existing with higher weight
        model.update_user_liked_posts(user, post1, 3.0);
        let posts = model.user_liked_posts.get(&user).unwrap();
        assert_eq!(posts.len(), 2);

        // post1 should now have weight 3.0
        let post1_entry = posts.iter().find(|(p, _)| *p == post1).unwrap();
        assert_eq!(post1_entry.1, 3.0);
    }
}

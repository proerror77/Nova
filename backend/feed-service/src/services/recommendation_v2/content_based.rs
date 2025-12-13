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
//
// Supported file formats:
//   - JSON: { "post_id": [f32; N], ... }
//   - Binary: bincode serialized HashMap<String, Vec<f32>>
//   - Parquet: (post_id, feature_0, ..., feature_N) (requires parquet feature)

use crate::error::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use tracing::{info, warn};
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

/// Serializable post features entry for JSON/bincode format
#[derive(Debug, Clone, Serialize, Deserialize)]
struct PostFeaturesEntry {
    #[serde(alias = "post_id", alias = "id")]
    id: String,
    #[serde(alias = "features", alias = "vector", alias = "embedding")]
    features: Vec<f32>,
}

impl ContentBasedModel {
    /// Create a new ContentBasedModel with post features and user profiles
    pub fn new(
        post_features: HashMap<Uuid, Vec<f32>>,
        user_profiles: HashMap<Uuid, Vec<f32>>,
        vocab_size: usize,
    ) -> Self {
        Self {
            post_features,
            user_profiles,
            vocab_size,
        }
    }

    /// Create an empty model (for testing or initialization)
    pub fn empty(vocab_size: usize) -> Self {
        Self {
            post_features: HashMap::new(),
            user_profiles: HashMap::new(),
            vocab_size,
        }
    }

    /// Load post features from file (JSON, bincode, or parquet format)
    ///
    /// Supported formats:
    /// - `.json`: JSON object { "uuid": [f32; N], ... } or array [{ id, features }, ...]
    /// - `.bin`: bincode serialized HashMap<String, Vec<f32>>
    /// - `.parquet`: Apache Parquet (requires parquet feature, uses JSON fallback)
    ///
    /// # Arguments
    /// * `path` - Path to the features file
    ///
    /// # Returns
    /// HashMap of post_id -> feature vector
    pub fn load_post_features(path: &str) -> Result<HashMap<Uuid, Vec<f32>>> {
        let file_path = Path::new(path);

        if !file_path.exists() {
            warn!("Post features file not found: {}", path);
            return Ok(HashMap::new());
        }

        let extension = file_path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("");

        match extension {
            "json" => Self::load_from_json(file_path),
            "bin" | "bincode" => Self::load_from_bincode(file_path),
            "parquet" => {
                warn!(
                    "Parquet loading not implemented yet, please convert to JSON: {}",
                    path
                );
                Ok(HashMap::new())
            }
            _ => {
                warn!("Unknown file format for post features: {}", extension);
                Ok(HashMap::new())
            }
        }
    }

    /// Load from JSON format
    /// Supports both object format { "uuid": [...] } and array format [{ id, features }]
    fn load_from_json(path: &Path) -> Result<HashMap<Uuid, Vec<f32>>> {
        let file = File::open(path)?;
        let reader = BufReader::new(file);

        // Try object format first: { "uuid": [f32; N], ... }
        let parsed: serde_json::Value = serde_json::from_reader(reader)?;

        let mut result = HashMap::new();

        if let Some(obj) = parsed.as_object() {
            // Object format: { "uuid": [...] }
            for (key, value) in obj {
                if let Ok(post_id) = Uuid::parse_str(key) {
                    if let Some(features) = value.as_array() {
                        let vec: Vec<f32> = features
                            .iter()
                            .filter_map(|v| v.as_f64().map(|f| f as f32))
                            .collect();
                        if !vec.is_empty() {
                            result.insert(post_id, vec);
                        }
                    }
                } else {
                    warn!("Invalid UUID in post features: {}", key);
                }
            }
        } else if let Some(arr) = parsed.as_array() {
            // Array format: [{ id, features }, ...]
            for item in arr {
                if let Ok(entry) = serde_json::from_value::<PostFeaturesEntry>(item.clone()) {
                    if let Ok(post_id) = Uuid::parse_str(&entry.id) {
                        if !entry.features.is_empty() {
                            result.insert(post_id, entry.features);
                        }
                    } else {
                        warn!("Invalid UUID in post features entry: {}", entry.id);
                    }
                }
            }
        }

        info!(
            posts_count = result.len(),
            feature_dim = result.values().next().map(|v| v.len()).unwrap_or(0),
            "Loaded post features from JSON"
        );

        Ok(result)
    }

    /// Load from bincode format (binary serialized HashMap)
    fn load_from_bincode(path: &Path) -> Result<HashMap<Uuid, Vec<f32>>> {
        let data = std::fs::read(path)?;
        if data.is_empty() {
            return Ok(HashMap::new());
        }

        // Try to deserialize as HashMap<String, Vec<f32>>
        // Note: bincode doesn't have a stable API, using a simple format
        let parsed: HashMap<String, Vec<f32>> =
            bincode::deserialize(&data).map_err(|e| anyhow::anyhow!("Bincode error: {}", e))?;

        let mut result = HashMap::new();
        for (key, features) in parsed {
            if let Ok(post_id) = Uuid::parse_str(&key) {
                result.insert(post_id, features);
            } else {
                warn!("Invalid UUID in bincode post features: {}", key);
            }
        }

        info!(
            posts_count = result.len(),
            "Loaded post features from bincode"
        );

        Ok(result)
    }

    /// Load user profiles from JSON file
    pub fn load_user_profiles(path: &str) -> Result<HashMap<Uuid, Vec<f32>>> {
        let file_path = Path::new(path);
        if !file_path.exists() {
            warn!("User profiles file not found: {}", path);
            return Ok(HashMap::new());
        }

        // Reuse the JSON loading logic
        Self::load_from_json(file_path)
    }

    /// Full load: load both post features and user profiles from directory
    pub fn load_from_directory(dir_path: &str) -> Result<Self> {
        let dir = Path::new(dir_path);

        // Try different file extensions
        let post_features_path = ["post_features.json", "post_features.bin", "post_features.parquet"]
            .iter()
            .map(|f| dir.join(f))
            .find(|p| p.exists());

        let user_profiles_path = ["user_profiles.json", "user_profiles.bin"]
            .iter()
            .map(|f| dir.join(f))
            .find(|p| p.exists());

        let post_features = if let Some(path) = post_features_path {
            Self::load_post_features(path.to_str().unwrap_or(""))?
        } else {
            warn!("No post features file found in: {}", dir_path);
            HashMap::new()
        };

        let user_profiles = if let Some(path) = user_profiles_path {
            Self::load_user_profiles(path.to_str().unwrap_or(""))?
        } else {
            info!("No user profiles file found, starting with empty profiles");
            HashMap::new()
        };

        // Detect vocab size from post features
        let vocab_size = post_features
            .values()
            .next()
            .map(|v| v.len())
            .unwrap_or(512); // Default TF-IDF/embedding dimension

        info!(
            posts = post_features.len(),
            users = user_profiles.len(),
            vocab_size = vocab_size,
            "Content-based model loaded from directory"
        );

        Ok(Self {
            post_features,
            user_profiles,
            vocab_size,
        })
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

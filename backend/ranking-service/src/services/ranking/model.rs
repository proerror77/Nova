/// GBDT Model Inference Module
///
/// Loads and runs ONNX-exported GBDT models using tract-onnx.
/// Supports both real ONNX models and fallback heuristic scoring.

use super::{Result, RankingError};
use ndarray::{Array1, Array2};
use std::path::Path;
use std::sync::Arc;
use tracing::{debug, warn};

/// Feature vector size (user features + post features + interaction features)
/// - User: 3 features (follower_count, post_count, engagement_rate)
/// - Post: 4 features (like_count, comment_count, share_count, age_hours)
/// - Interaction: 2 features (author_is_following, previous_interactions)
const FEATURE_VECTOR_SIZE: usize = 9;

/// GBDT Ranking Model
///
/// Wraps tract-onnx model with fallback to heuristic scoring if ONNX model unavailable.
pub struct RankingModel {
    /// ONNX model (None = use heuristic fallback)
    model: Option<Arc<tract_onnx::prelude::SimplePlan<
        tract_onnx::prelude::TypedFact,
        Box<dyn tract_onnx::prelude::TypedOp>,
        tract_onnx::prelude::Graph<
            tract_onnx::prelude::TypedFact,
            Box<dyn tract_onnx::prelude::TypedOp>,
        >,
    >>>,

    /// Model type indicator
    model_type: ModelType,
}

#[derive(Debug, Clone, Copy)]
enum ModelType {
    Onnx,
    Heuristic,
}

impl RankingModel {
    /// Load ONNX model from file path
    ///
    /// Falls back to heuristic scoring if model file not found or loading fails.
    pub fn load<P: AsRef<Path>>(model_path: P) -> Result<Self> {
        let path = model_path.as_ref();

        match Self::try_load_onnx(path) {
            Ok(model) => {
                debug!(
                    "✅ Loaded ONNX ranking model from: {}",
                    path.display()
                );
                Ok(Self {
                    model: Some(Arc::new(model)),
                    model_type: ModelType::Onnx,
                })
            }
            Err(e) => {
                warn!(
                    "⚠️  Failed to load ONNX model from {}: {}",
                    path.display(),
                    e
                );
                warn!("   Falling back to heuristic scoring");
                Ok(Self {
                    model: None,
                    model_type: ModelType::Heuristic,
                })
            }
        }
    }

    /// Create model with heuristic fallback (for testing/development)
    pub fn heuristic() -> Self {
        debug!("Using heuristic ranking model");
        Self {
            model: None,
            model_type: ModelType::Heuristic,
        }
    }

    /// Predict relevance scores for batch of feature vectors
    ///
    /// # Arguments
    /// * `features` - 2D array (batch_size × FEATURE_VECTOR_SIZE)
    ///
    /// # Returns
    /// * Array of relevance scores (batch_size)
    pub fn predict(&self, features: Array2<f32>) -> Result<Array1<f32>> {
        let batch_size = features.shape()[0];

        if features.shape()[1] != FEATURE_VECTOR_SIZE {
            return Err(RankingError::InvalidInput(format!(
                "Expected {} features, got {}",
                FEATURE_VECTOR_SIZE,
                features.shape()[1]
            )));
        }

        match self.model_type {
            ModelType::Onnx => self.predict_onnx(features),
            ModelType::Heuristic => self.predict_heuristic(features),
        }
    }

    /// ONNX model inference
    fn predict_onnx(&self, features: Array2<f32>) -> Result<Array1<f32>> {
        let model = self.model.as_ref().ok_or_else(|| {
            RankingError::InferenceError("ONNX model not loaded".to_string())
        })?;

        let batch_size = features.shape()[0];

        // Convert ndarray to tract tensor
        let input_tensor = tract_onnx::prelude::tract_ndarray::Array2::from_shape_fn(
            (batch_size, FEATURE_VECTOR_SIZE),
            |(i, j)| features[[i, j]],
        );

        // Run inference
        let input = tract_onnx::prelude::tvec![input_tensor.into_dyn().into()];
        let output = model
            .run(input)
            .map_err(|e| RankingError::InferenceError(format!("ONNX inference failed: {}", e)))?;

        // Extract scores from output tensor
        let scores_tensor = output[0]
            .to_array_view::<f32>()
            .map_err(|e| RankingError::InferenceError(format!("Output extraction failed: {}", e)))?;

        let scores = Array1::from_iter(scores_tensor.iter().copied());

        Ok(scores)
    }

    /// Heuristic scoring (fallback when no ONNX model)
    ///
    /// Formula: `score = (like_count * 0.3 + comment_count * 0.5 + share_count * 0.2) / (age_hours + 1.0)`
    ///
    /// Features layout:
    /// - [0..3]: User features (follower_count, post_count, engagement_rate)
    /// - [3..7]: Post features (like_count, comment_count, share_count, age_hours)
    /// - [7..9]: Interaction features (author_is_following, previous_interactions)
    fn predict_heuristic(&self, features: Array2<f32>) -> Result<Array1<f32>> {
        let batch_size = features.shape()[0];
        let mut scores = Array1::zeros(batch_size);

        for i in 0..batch_size {
            // Extract post engagement features
            let like_count = features[[i, 3]];
            let comment_count = features[[i, 4]];
            let share_count = features[[i, 5]];
            let age_hours = features[[i, 6]];

            // Extract interaction features
            let author_is_following = features[[i, 7]];
            let previous_interactions = features[[i, 8]];

            // Base score: weighted engagement normalized by age
            let engagement_score =
                (like_count * 0.3 + comment_count * 0.5 + share_count * 0.2) / (age_hours + 1.0);

            // Boost for followed authors
            let following_boost = if author_is_following > 0.5 { 1.2 } else { 1.0 };

            // Boost for previous interactions
            let interaction_boost = 1.0 + (previous_interactions * 0.1).min(0.5);

            scores[i] = engagement_score * following_boost * interaction_boost;
        }

        Ok(scores)
    }

    /// Try to load ONNX model (private helper)
    fn try_load_onnx(
        path: &Path,
    ) -> std::result::Result<
        tract_onnx::prelude::SimplePlan<
            tract_onnx::prelude::TypedFact,
            Box<dyn tract_onnx::prelude::TypedOp>,
            tract_onnx::prelude::Graph<
                tract_onnx::prelude::TypedFact,
                Box<dyn tract_onnx::prelude::TypedOp>,
            >,
        >,
        Box<dyn std::error::Error>,
    > {
        if !path.exists() {
            return Err(format!("Model file not found: {}", path.display()).into());
        }

        // Load ONNX model
        let model = tract_onnx::onnx()
            .model_for_path(path)?
            .into_optimized()?
            .into_runnable()?;

        Ok(model)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_heuristic_model_single_post() {
        let model = RankingModel::heuristic();

        // Single post: high engagement, recent, from followed author
        let features = Array2::from_shape_vec(
            (1, 9),
            vec![
                1000.0, 500.0, 0.8,    // user: follower_count, post_count, engagement_rate
                100.0, 50.0, 20.0, 2.0, // post: likes, comments, shares, age_hours
                1.0, 5.0,               // interaction: is_following, previous_interactions
            ],
        )
        .unwrap();

        let scores = model.predict(features).unwrap();

        assert_eq!(scores.len(), 1);
        assert!(scores[0] > 0.0, "Score should be positive");
        // Expected: (100*0.3 + 50*0.5 + 20*0.2) / (2+1) * 1.2 * 1.5 ≈ 40.0
        assert!(scores[0] > 30.0 && scores[0] < 50.0);
    }

    #[test]
    fn test_heuristic_model_batch() {
        let model = RankingModel::heuristic();

        // Batch of 3 posts with varying engagement
        let features = Array2::from_shape_vec(
            (3, 9),
            vec![
                // Post 1: High engagement, recent
                1000.0, 500.0, 0.8, 100.0, 50.0, 20.0, 1.0, 1.0, 3.0,
                // Post 2: Low engagement, old
                1000.0, 500.0, 0.8, 10.0, 5.0, 2.0, 24.0, 0.0, 0.0,
                // Post 3: Medium engagement, medium age
                1000.0, 500.0, 0.8, 50.0, 25.0, 10.0, 6.0, 1.0, 1.0,
            ],
        )
        .unwrap();

        let scores = model.predict(features).unwrap();

        assert_eq!(scores.len(), 3);
        // Post 1 should have highest score (recent + high engagement + following)
        // Post 2 should have lowest score (old + low engagement + not following)
        assert!(scores[0] > scores[2]);
        assert!(scores[2] > scores[1]);
    }

    #[test]
    fn test_invalid_feature_vector_size() {
        let model = RankingModel::heuristic();

        // Wrong size: 5 features instead of 9
        let features = Array2::from_shape_vec((1, 5), vec![1.0, 2.0, 3.0, 4.0, 5.0]).unwrap();

        let result = model.predict(features);

        assert!(result.is_err());
        assert!(matches!(result, Err(RankingError::InvalidInput(_))));
    }

    #[test]
    fn test_following_boost() {
        let model = RankingModel::heuristic();

        // Same post, different following status
        let features_following = Array2::from_shape_vec(
            (1, 9),
            vec![
                1000.0, 500.0, 0.8, 50.0, 25.0, 10.0, 5.0, 1.0, // following
                0.0,
            ],
        )
        .unwrap();

        let features_not_following = Array2::from_shape_vec(
            (1, 9),
            vec![
                1000.0, 500.0, 0.8, 50.0, 25.0, 10.0, 5.0, 0.0, // not following
                0.0,
            ],
        )
        .unwrap();

        let score_following = model.predict(features_following).unwrap()[0];
        let score_not_following = model.predict(features_not_following).unwrap()[0];

        // Following should give 1.2x boost
        assert!(
            (score_following / score_not_following - 1.2).abs() < 0.01,
            "Following boost should be ~1.2x"
        );
    }
}

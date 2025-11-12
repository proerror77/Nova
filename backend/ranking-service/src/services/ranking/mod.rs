/// Ranking Module
///
/// Implements ML-based candidate ranking using GBDT models for feed personalization.
///
/// # Architecture
/// - **Model Layer**: ONNX model inference with tract-onnx (Phase E)
/// - **Scoring Layer**: Batch scoring with feature engineering
/// - **Feature Layer**: Integration with feature-store for real-time features
///
/// # Workflow
/// 1. Fetch user/post features from feature-store
/// 2. Compute interaction features (author_is_following, previous_interactions)
/// 3. Run GBDT model inference → relevance scores
/// 4. Apply diversity reranking (MMR algorithm)
pub mod simple; // Phase D: Simple ranking layer

// Phase E: Advanced ranking with ONNX models
// pub mod model;
// pub mod scorer;

pub use simple::RankingLayer;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum RankingError {
    #[error("Model loading failed: {0}")]
    ModelLoadError(String),

    #[error("Feature extraction failed: {0}")]
    FeatureExtractionError(String),

    #[error("Model inference failed: {0}")]
    InferenceError(String),

    #[error("Feature store client error: {0}")]
    FeatureStoreError(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),
}

pub type Result<T> = std::result::Result<T, RankingError>;

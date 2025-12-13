// ============================================
// Coarse Ranking Layer (粗排层)
// ============================================
//
// TikTok-style 4-layer pipeline: Recall → Coarse → Fine → Diversity
//
// Purpose:
// - Filter 10000+ recall candidates down to ~1000 for fine ranking
// - Use lightweight features and rules (< 10ms latency target)
// - Balance relevance with diversity and freshness
//
// Architecture:
// - SimpleCoarseScorer: Rule-based scoring with configurable weights
// - LightweightModel: Optional LightGBM ONNX model (Phase E)

pub mod simple_scorer;

pub use simple_scorer::{CoarseCandidate, CoarseRankingLayer, CoarseWeights, UserFeatures};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum CoarseRankingError {
    #[error("Feature extraction failed: {0}")]
    FeatureExtractionError(String),

    #[error("Model inference failed: {0}")]
    InferenceError(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),
}

pub type Result<T> = std::result::Result<T, CoarseRankingError>;

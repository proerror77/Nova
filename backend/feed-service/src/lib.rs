pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
pub mod handlers;
pub mod metrics;
pub mod middleware;
pub mod models;
pub mod security;
pub mod services;
pub mod utils;

pub use config::Config;
pub use error::{AppError, Result};

// Re-export recommendation service components
pub use services::{
    ABTestingFramework, CollaborativeFilteringModel, ContentBasedModel, HybridRanker,
    HybridWeights, ModelInfo, ONNXModelServer, RankedPost, RankingStrategy, RecommendationConfig,
    RecommendationServiceV2, UserContext, Variant,
};

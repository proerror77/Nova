//! Service layer for recommendation engine
//!
//! Implements hybrid recommendation algorithm combining:
//! - Collaborative filtering (user-user, item-item)
//! - Content-based filtering (TF-IDF features)
//! - A/B testing framework for experiment tracking
//! - ONNX model serving for deep learning inference
//!
//! Migration status:
//! ✅ Phase 1: Migrate recommendation_v2 from user-service
//! ⏳ Phase 2: HTTP API and gRPC service implementation
//! ⏳ Phase 3: Kafka event consumer integration
//! ⏳ Phase 4: Milvus vector search integration

pub mod graph;
pub mod recommendation_v2;
pub mod trending;

pub use graph::GraphService;
pub use recommendation_v2::{
    ABTestingFramework, CollaborativeFilteringModel, ContentBasedModel, Experiment,
    ExperimentEvent, HybridRanker, HybridWeights, ModelInfo, ONNXModelServer,
    RankedPost, RankingStrategy, RecommendationConfig, RecommendationServiceV2, UserContext,
    Variant,
};
pub use trending::TrendingService;

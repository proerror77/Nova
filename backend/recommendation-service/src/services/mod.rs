//! Recommendation service module
//!
//! Migrated from user-service to recommendation-service
//!
//! Migration strategy:
//! 1. Phase 1 (CURRENT): Implement gRPC server in this service
//! 2. Phase 2: Incrementally migrate business logic from user-service
//! 3. Phase 3: user-service becomes pure API gateway calling gRPC

pub mod graph;
pub mod trending;

pub use graph::GraphService;
pub use trending::TrendingService;

use serde::{Deserialize, Serialize};

// Placeholder types for future implementation
// These are re-exported for backward compatibility

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ABTestingFramework;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Variant;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollaborativeFilteringModel;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentBasedModel;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HybridRanker;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HybridWeights;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankedPost {
    pub id: String,
    pub score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RankingStrategy;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelMetadata;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ONNXModelServer;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecommendationConfig;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecommendationServiceV2;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserContext;

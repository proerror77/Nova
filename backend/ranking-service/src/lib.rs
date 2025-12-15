pub mod config;
pub mod grpc;
pub mod jobs;
pub mod models;
pub mod services;
pub mod utils;

pub use config::Config;
pub use grpc::ranking_proto;
pub use jobs::{ProfileBatchConfig, ProfileBatchJob};
pub use services::{DiversityLayer, FeatureClient, RankingLayer, RecallLayer};

// Re-export profile builder types for convenience
pub use services::profile_builder::{
    ClickHouseProfileDatabase, LlmProfileAnalyzer, ProfileDatabase, ProfileUpdater,
    UserPersona, UserProfile, UserSegment,
};

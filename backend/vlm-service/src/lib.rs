//! VLM Service - Vision Language Model service for image analysis and tagging
//!
//! This service provides:
//! - Google Cloud Vision API integration for image analysis
//! - Tag generation from VLM results
//! - Channel matching based on tags
//! - Kafka event processing for async analysis

pub mod config;
pub mod jobs;
pub mod kafka;
pub mod providers;
pub mod services;

pub use config::Config;
pub use kafka::{
    topics, PostCreatedForVLM, SharedVLMProducer, VLMConsumer, VLMConsumerConfig, VLMPostAnalyzed,
    VLMProducer,
};
pub use providers::{GoogleVisionClient, ImageAnalysisResult, Label};
pub use services::{
    generate_tags, match_channels, Channel, ChannelMatch, GeneratedTag, KeywordWeight, TagSource,
};

pub use jobs::{BackfillJob, BackfillStats};

/// VLM service error types
#[derive(Debug, thiserror::Error)]
pub enum VlmError {
    #[error("Vision API error: {0}")]
    VisionApi(String),

    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Cache error: {0}")]
    Cache(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

impl From<anyhow::Error> for VlmError {
    fn from(err: anyhow::Error) -> Self {
        VlmError::Internal(err.to_string())
    }
}

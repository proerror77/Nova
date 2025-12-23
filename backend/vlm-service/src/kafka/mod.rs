//! Kafka Integration for VLM Service
//!
//! Provides event-driven VLM processing:
//! - Consumer: Listens for posts that need VLM analysis
//! - Producer: Publishes analysis results and channel assignments
//! - Events: Kafka message schemas

pub mod consumer;
pub mod events;
pub mod producer;

pub use consumer::{VLMConsumer, VLMConsumerConfig, VLMConsumerError};
pub use events::{
    topics, ChannelsAutoAssigned, PostCreatedForVLM, VLMChannelSuggestion, VLMDeadLetterEvent,
    VLMPostAnalyzed, VLMTag,
};
pub use producer::{SharedVLMProducer, VLMProducer, VLMProducerError};

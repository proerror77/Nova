//! Service Layer for Streaming Service
//!
//! This module contains business logic for streaming operations:
//! - Stream lifecycle management
//! - Manifest generation (HLS/DASH)
//! - Stream discovery and analytics
//! - WebSocket-based chat

pub mod kafka_producer;
pub mod streaming;
pub mod streaming_manifest;

// Re-export commonly used types
pub use kafka_producer::{EventProducer, SharedEventProducer};
pub use streaming::{
    CreateStreamRequest, CreateStreamResponse, JoinStreamResponse,
    RtmpWebhookHandler, StreamAnalytics, StreamAnalyticsService,
    StreamCategory, StreamChatActor, StreamChatHandlerState,
    StreamChatStore, StreamComment, StreamConnectionRegistry,
    StreamDetails, StreamDiscoveryService, StreamRepository,
    StreamService, StreamStatus, StreamSummary, ViewerCounter,
};
pub use streaming_manifest::{QualityTier, StreamingManifestGenerator};

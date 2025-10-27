//! Live Streaming Service Layer
//!
//! This module handles live video streaming functionality:
//! - Stream lifecycle management (create, start, end)
//! - RTMP authentication webhooks
//! - Viewer counting (Redis-based)
//! - Stream discovery and metadata
//!
//! ## Architecture Principles
//!
//! 1. **Separation of Concerns**
//!    - RTMP ingestion: Nginx-RTMP (separate container)
//!    - HLS delivery: CDN (CloudFront)
//!    - Coordination: This service (PostgreSQL + Redis)
//!
//! 2. **Stateless Design**
//!    - No in-memory stream state
//!    - All state in PostgreSQL (persistent) or Redis (ephemeral)
//!    - Horizontally scalable
//!
//! 3. **Performance**
//!    - Viewer counts in Redis (not PostgreSQL)
//!    - Chat messages via WebSocket (not database)
//!    - Analytics in ClickHouse (not PostgreSQL)
//!
//! ## Module Structure
//!
//! - `models.rs` - Data models (CreateStreamRequest, StreamResponse, etc.)
//! - `repository.rs` - Database operations (PostgreSQL queries)
//! - `redis_counter.rs` - Redis viewer counting
//! - `stream_service.rs` - Business logic (orchestrates repo + Redis)
//! - `actor.rs` - Actor pattern implementation (message-passing based)
//! - `commands.rs` - Command enum for actor pattern
//! - `rtmp_webhook.rs` - RTMP authentication webhook handlers
//! - `discovery.rs` - Stream discovery and listing
//! - `analytics.rs` - Analytics aggregation (ClickHouse queries)

pub mod actor;
pub mod analytics;
pub mod chat_store;
pub mod commands;
pub mod discovery;
pub mod handler_adapter;
pub mod models;
pub mod redis_counter;
pub mod repository;
pub mod rtmp_webhook;
pub mod stream_service;
pub mod ws;

pub use actor::StreamActor;
pub use analytics::StreamAnalyticsService;
pub use commands::StreamCommand;
pub use discovery::StreamDiscoveryService;
pub use handler_adapter as stream_handler_adapter;
pub use models::{
    CreateStreamRequest, CreateStreamResponse, JoinStreamResponse, StreamAnalytics, StreamCategory,
    StreamDetails, StreamStatus, StreamSummary,
};
pub use rtmp_webhook::RtmpWebhookHandler;
pub use stream_service::StreamService;

// Re-export for convenience
pub use chat_store::{StreamChatStore, StreamComment};
pub use redis_counter::ViewerCounter;
pub use repository::StreamRepository;
pub use ws::{StreamChatActor, StreamChatHandlerState, StreamConnectionRegistry};

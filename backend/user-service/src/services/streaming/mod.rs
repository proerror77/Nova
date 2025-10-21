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
//! - `rtmp_webhook.rs` - RTMP authentication webhook handlers
//! - `discovery.rs` - Stream discovery and listing
//! - `analytics.rs` - Analytics aggregation (ClickHouse queries)
//! - `websocket_handler.rs` - Real-time WebSocket updates for viewers (exported from handlers)

pub mod analytics;
pub mod discovery;
pub mod models;
pub mod redis_counter;
pub mod repository;
pub mod rtmp_webhook;
pub mod stream_service;

pub use models::{
    CreateStreamRequest, CreateStreamResponse, JoinStreamResponse, StreamAnalytics, StreamDetails,
    StreamStatus, StreamSummary,
};
pub use stream_service::StreamService;

// Re-export for convenience
pub use redis_counter::ViewerCounter;
pub use repository::StreamRepository;

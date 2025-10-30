/// Service layer for social features and infrastructure
/// Authentication and email services have been extracted to auth-service
// pub mod backup_codes; // REMOVED - moved to auth-service (port 8084) [DELETED]
pub mod cdc;
// pub mod cdn_failover; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod cdn_handler_integration; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod cdn_service; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod deep_learning_inference; // REMOVED - should be in ML service [DELETED]
// pub mod email_service; // REMOVED - moved to auth-service (port 8084) [DELETED]
// pub mod email_verification; // REMOVED - moved to auth-service (port 8084) [DELETED]
pub mod events;
// pub mod experiments; // REMOVED - moved to feed-service (port 8089) [DELETED]
// pub mod ffmpeg_optimizer; // REMOVED - moved to media-service (port 8082) [DELETED]
pub mod graph;
// pub mod image_processing; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod job_queue; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub mod jwt_key_rotation; // REMOVED - moved to auth-service (port 8084) [DELETED]
pub mod kafka_producer;
pub mod moderation_service;
// pub mod notifications; // REMOVED - moved to notification-service (port 8090) [DELETED]
// pub mod oauth; // REMOVED - moved to auth-service (port 8084) [DELETED]
// pub mod origin_shield; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod password_reset_service; // REMOVED - moved to auth-service (port 8084) [DELETED]
pub mod query_profiler;
// pub mod ranking_engine; // REMOVED - moved to feed-service (port 8089) [DELETED]
pub mod redis_job;
pub mod social_graph_sync;
// pub mod resumable_upload_service; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod s3_service; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod stories; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub mod streaming; // REMOVED - moved to streaming-service (port 8088) [DELETED]
// pub mod streaming_manifest; // REMOVED - moved to media-service (port 8082) [DELETED]
pub mod token_revocation;
// pub mod transcoding_optimizer; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod transcoding_progress; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod transcoding_progress_handler; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod two_fa; // REMOVED - moved to auth-service (port 8084) [DELETED]
// pub mod video_job_queue; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod video_service; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod video_transcoding; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod webhooks; // REMOVED - video webhook handling moved to media-service (port 8082) [DELETED]

// ==================== SERVICE MODULES DOCUMENTATION ====================
//
// STREAMING & LIVE VIDEO:
// - streaming: Live streaming infrastructure with RTMP/HLS/DASH support
// - streaming_manifest: HLS/DASH manifest generation for live streams
// - video_transcoding: FFmpeg-based transcoding, thumbnail extraction, metadata parsing
// - video_service: Video upload, processing, and streaming orchestration
//
// CDN & EDGE COMPUTING:
// - cdn_failover: CDN failover and fallback logic for reliability
// - cdn_handler_integration: Integration layer between services and CDN
// - cdn_service: Main CDN service for edge caching and distribution
// - origin_shield: Origin protection and intelligent caching layer
//
// VIDEO PROCESSING:
// - ffmpeg_optimizer: FFmpeg configuration and optimization strategies
// - transcoding_optimizer: Transcoding workflow optimization
// - transcoding_progress: Progress tracking and status reporting for transcoding jobs
// - video_processing_pipeline: Orchestrates entire video processing workflow (Phase 7)
//
// MACHINE LEARNING & RANKING:
// - Recommendation engine moved to feed-service
//
// GRAPH & SOCIAL:
// - graph: Neo4j integration for social graph (follows, suggestions, mutual connections)
// - social_graph_sync: Kafka consumer for syncing social events (follow/unfollow) to Neo4j
//
// COMMON SERVICES:
// - cdc: Change Data Capture consumer (PostgreSQL → Kafka → ClickHouse sync)
// - events: Application events consumer (Kafka → ClickHouse for analytics)
// - kafka_producer: Kafka message producer for events and CDC (now supports multiple topics)
// - query_profiler: PostgreSQL query performance profiling
// - redis_job: Background jobs for hot posts, suggestions, and feed cache warming
// - token_revocation: JWT token blacklist management for logout
//
// REMOVED (moved to media-service):
// - image_processing: Image resizing and variant generation (thumbnail, medium, original)
// - origin_shield: Origin protection and intelligent caching layer
// - s3_service: AWS S3 integration for image upload and storage
//
// REMOVED (moved to auth-service):
// - backup_codes: Two-factor authentication backup codes management
// - email_verification: Email verification token management with Redis
// - jwt_key_rotation: JWT signing key rotation for enhanced security
// - oauth: OAuth2 authentication (Google, GitHub providers)
// - password_reset_service: Password reset token management
// - two_fa: Two-factor authentication (TOTP) management

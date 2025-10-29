/// Service layer for authentication, email operations, S3 storage, and social features
/// UNIFIED MODULE: Integrates streaming infrastructure with ML-based feed ranking
///
/// This module now combines three major feature sets:
/// 1. Streaming Infrastructure: RTMP/HLS/DASH live streaming with transcoding
/// 2. CDN & Video Processing: Edge caching, optimization, and video processing
/// 3. ML Ranking System: Deep learning-based feed personalization and recommendations
pub mod backup_codes;
pub mod cdc;
pub mod cdn_failover;
pub mod cdn_handler_integration;
pub mod cdn_service;
pub mod deep_learning_inference;
pub mod email_service;
pub mod email_verification;
pub mod events;
pub mod experiments;
pub mod ffmpeg_optimizer;
pub mod graph;
pub mod image_processing;
pub mod job_queue;
pub mod jwt_key_rotation;
pub mod kafka_producer;
pub mod moderation_service;
pub mod notifications;
pub mod oauth;
pub mod origin_shield;
pub mod password_reset_service;
pub mod query_profiler;
pub mod ranking_engine;
pub mod recommendation_v2;
pub mod redis_job;
pub mod social_graph_sync;
pub mod resumable_upload_service;
pub mod s3_service;
pub mod stories;
pub mod streaming;
pub mod streaming_manifest;
pub mod token_revocation;
pub mod transcoding_optimizer;
pub mod transcoding_progress;
pub mod transcoding_progress_handler;
pub mod trending;
pub mod two_fa;
pub mod video_job_queue;
pub mod video_service;
pub mod video_transcoding;
pub mod webhooks;

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
// - recommendation_v2: Hybrid recommendation engine v2 (collaborative filtering + content-based + AB testing)
//
// GRAPH & SOCIAL:
// - graph: Neo4j integration for social graph (follows, suggestions, mutual connections)
// - social_graph_sync: Kafka consumer for syncing social events (follow/unfollow) to Neo4j
//
// COMMON SERVICES:
// - backup_codes: Two-factor authentication backup codes management
// - cdc: Change Data Capture consumer (PostgreSQL → Kafka → ClickHouse sync)
// - email_verification: Email verification token management with Redis
// - events: Application events consumer (Kafka → ClickHouse for analytics)
// - image_processing: Image resizing and variant generation (thumbnail, medium, original)
// - job_queue: Background job queue for async image processing (MPSC channel-based)
// - jwt_key_rotation: JWT signing key rotation for enhanced security
// - kafka_producer: Kafka message producer for events and CDC (now supports multiple topics)
// - oauth: OAuth2 authentication (Google, GitHub providers)
// - password_reset_service: Password reset token management
// - query_profiler: PostgreSQL query performance profiling
// - redis_job: Background jobs for hot posts, suggestions, and feed cache warming
// - s3_service: AWS S3 integration for image upload and storage
// - token_revocation: JWT token blacklist management for logout
// - two_fa: Two-factor authentication (TOTP) management

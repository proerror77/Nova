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
// pub mod clickhouse_feature_extractor;  // TODO: Phase 2 - needs RankingSignals with Serialize/Deserialize
// pub mod deep_learning_inference;       // TODO: Phase 2 - pending implementation
pub mod email_verification;
pub mod events;
pub mod feed_ranking;
pub mod ffmpeg_optimizer;
pub mod image_processing;
pub mod job_queue;
pub mod jwt_key_rotation;
pub mod kafka_producer;
pub mod messaging;
pub mod notifications;
pub mod oauth;
pub mod origin_shield;
pub mod password_reset_service;
pub mod query_profiler;
pub mod ranking_engine;
pub mod recommendation_v2;
pub mod redis_job;
pub mod s3_service;
pub mod streaming;
pub mod streaming_manifest;
pub mod token_revocation;
pub mod transcoding_optimizer;
pub mod transcoding_progress;
pub mod two_fa;
// pub mod video_processing_pipeline;     // TODO: Phase 2 - depends on VideoTranscodingService methods

// ==================== SERVICE MODULES DOCUMENTATION ====================
//
// STREAMING & LIVE VIDEO:
// - streaming: Live streaming infrastructure with RTMP/HLS/DASH support
// - streaming_manifest: HLS/DASH manifest generation for live streams
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
// - clickhouse_feature_extractor: Feature extraction for ML model training
// - deep_learning_inference: TensorFlow Serving + Milvus integration for embeddings
// - recommendation_v2: Hybrid recommendation engine v2 (collaborative filtering + content-based + AB testing)
//
// PHASE 5 FEATURES:
// - notifications: Real-time multi-channel notifications (Phase 5, Feature 1)
//   Kafka consumer with batch aggregation, multi-channel delivery (FCM, APNs, Email, In-App)
// - messaging: Private messaging with end-to-end encryption (Phase 5, Feature 2)
//   NaCl Box E2E encryption, key exchange protocol, key rotation, forward secrecy
//
// COMMON SERVICES:
// - backup_codes: Two-factor authentication backup codes management
// - cdc: Change Data Capture consumer (PostgreSQL → Kafka → ClickHouse sync)
// - email_verification: Email verification token management with Redis
// - events: Application events consumer (Kafka → ClickHouse for analytics)
// - feed_ranking: Core feed ranking algorithm with ClickHouse integration and caching
// - image_processing: Image resizing and variant generation (thumbnail, medium, original)
// - job_queue: Background job queue for async image processing (MPSC channel-based)
// - jwt_key_rotation: JWT signing key rotation for enhanced security
// - kafka_producer: Kafka message producer for events and CDC
// - oauth: OAuth2 authentication (Google, GitHub providers)
// - password_reset_service: Password reset token management
// - query_profiler: PostgreSQL query performance profiling
// - redis_job: Background jobs for hot posts, suggestions, and feed cache warming
// - s3_service: AWS S3 integration for image upload and storage
// - token_revocation: JWT token blacklist management for logout
// - two_fa: Two-factor authentication (TOTP) management

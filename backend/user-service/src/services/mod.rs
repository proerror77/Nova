/// Service layer for authentication, email operations, S3 storage, and social features
pub mod backup_codes;
pub mod cdc;
pub mod email_verification;
pub mod events;
pub mod feed_ranking;
pub mod feed_service;
pub mod image_processing;
pub mod job_queue;
pub mod jwt_key_rotation;
pub mod kafka_producer;
pub mod oauth;
pub mod password_reset_service;
pub mod query_profiler;
pub mod redis_job;
pub mod s3_service;
pub mod token_revocation;
pub mod two_fa;
pub mod video_service;
pub mod video_transcoding;
pub mod video_processing_pipeline;
pub mod deep_learning_inference;

// Service modules:
// - backup_codes: Two-factor authentication backup codes management
// - cdc: Change Data Capture consumer (PostgreSQL → Kafka → ClickHouse sync)
// - email_verification: Email verification token management with Redis
// - events: Application events consumer (Kafka → ClickHouse for analytics)
// - feed_service: Personalized feed ranking with ClickHouse (Follow + Trending + Affinity)
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
// - video_service: Video upload, processing, and streaming (Phase 4)
// - video_transcoding: FFmpeg-based transcoding, thumbnail extraction, metadata parsing (Phase 4)
// - video_processing_pipeline: Orchestrates entire video processing workflow (Phase 4)
// - deep_learning_inference: TensorFlow Serving + Milvus integration for embeddings (Phase 4)

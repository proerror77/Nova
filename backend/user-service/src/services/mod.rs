/// Service layer for authentication, email operations, and S3 storage
pub mod email_verification;
pub mod image_processing;
pub mod job_queue;
pub mod s3_service;
pub mod token_revocation;

// Service modules:
// - email_verification: Email verification token management with Redis
// - image_processing: Image resizing and variant generation (thumbnail, medium, original)
// - job_queue: Background job queue for async image processing (MPSC channel-based)
// - token_revocation: JWT token blacklist management for logout
// - s3_service: AWS S3 integration for image upload and storage
// - Placeholder: Authentication service (register, login, refresh token)
// - Placeholder: Email service (send verification, password reset emails)

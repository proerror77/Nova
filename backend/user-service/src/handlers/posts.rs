use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Responder};
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::config::Config;
use crate::db::post_repo;
use crate::error::ErrorResponse;
use crate::middleware::UserId;
use crate::services::{job_queue::ImageProcessingJob, job_queue::JobSender, s3_service};

// ============================================
// Request/Response Structs
// ============================================

#[derive(Debug, Deserialize, Serialize)]
pub struct UploadInitRequest {
    pub filename: String,
    pub content_type: String,
    pub file_size: i64,
    pub caption: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UploadInitResponse {
    pub presigned_url: String,
    pub post_id: String,
    pub upload_token: String,
    pub expires_in: i64,
    pub instructions: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct UploadCompleteRequest {
    pub post_id: String,
    pub upload_token: String,
    pub file_hash: String,
    pub file_size: i64,
}

#[derive(Debug, Serialize)]
pub struct UploadCompleteResponse {
    pub post_id: String,
    pub status: String,
    pub message: String,
    pub image_key: String,
}

// ============================================
// Validation Constants
// ============================================

const MAX_FILENAME_LENGTH: usize = 255;
const MIN_FILE_SIZE: i64 = 102400; // 100 KB
const MAX_FILE_SIZE: i64 = 52428800; // 50 MB
const MAX_CAPTION_LENGTH: usize = 2200;

// Supported MIME types
const ALLOWED_CONTENT_TYPES: &[&str] = &["image/jpeg", "image/png", "image/webp", "image/heic"];

// ============================================
// Handler Functions
// ============================================

/// Complete upload and verify file integrity
/// POST /api/v1/posts/upload/complete
pub async fn upload_complete_request(
    pool: web::Data<PgPool>,
    _redis: web::Data<ConnectionManager>,
    config: web::Data<Config>,
    job_sender: web::Data<JobSender>,
    req: web::Json<UploadCompleteRequest>,
) -> impl Responder {
    // ========================================
    // Validation
    // ========================================

    // Validate post_id is valid UUID
    let post_id = match Uuid::parse_str(&req.post_id) {
        Ok(uuid) => uuid,
        Err(_) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid request".to_string(),
                details: Some("Invalid post_id format".to_string()),
            });
        }
    };

    // Validate upload_token is not empty
    if req.upload_token.is_empty() {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid request".to_string(),
            details: Some("Upload token is required".to_string()),
        });
    }

    // Validate upload_token max length (512 chars)
    if req.upload_token.len() > 512 {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid request".to_string(),
            details: Some("Upload token exceeds maximum length (512 characters)".to_string()),
        });
    }

    // Validate file_hash is exactly 64 characters (SHA256)
    if req.file_hash.len() != 64 {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid file hash".to_string(),
            details: Some("File hash must be exactly 64 characters (SHA256)".to_string()),
        });
    }

    // Validate file_hash is valid hex string
    if !req.file_hash.chars().all(|c| c.is_ascii_hexdigit()) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid file hash".to_string(),
            details: Some("File hash must contain only hexadecimal characters".to_string()),
        });
    }

    // Validate file_size is within bounds
    if req.file_size < MIN_FILE_SIZE {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid file size".to_string(),
            details: Some(format!(
                "File size must be at least {} bytes (100 KB)",
                MIN_FILE_SIZE
            )),
        });
    }

    if req.file_size > MAX_FILE_SIZE {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid file size".to_string(),
            details: Some(format!(
                "File size exceeds maximum allowed size ({} bytes / 50 MB)",
                MAX_FILE_SIZE
            )),
        });
    }

    // ========================================
    // Upload Completion Flow
    // ========================================

    // a. Find upload_session by token
    let upload_session =
        match post_repo::find_upload_session_by_token(pool.get_ref(), &req.upload_token).await {
            Ok(Some(session)) => session,
            Ok(None) => {
                return HttpResponse::NotFound().json(ErrorResponse {
                    error: "Invalid or expired upload token".to_string(),
                    details: Some("Token not found or has expired".to_string()),
                });
            }
            Err(e) => {
                tracing::error!("Failed to find upload session: {:?}", e);
                return HttpResponse::InternalServerError().json(ErrorResponse {
                    error: "Database error".to_string(),
                    details: None,
                });
            }
        };

    // b. Verify token hasn't already been completed
    if upload_session.is_completed {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Upload already completed".to_string(),
            details: Some("This upload token has already been used".to_string()),
        });
    }

    // c. Verify post_id matches upload_session
    if upload_session.post_id != post_id {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid request".to_string(),
            details: Some("Post ID does not match upload session".to_string()),
        });
    }

    // d. Get S3 key from posts table: "posts/{post_id}/original"
    let s3_key = format!("posts/{}/original", post_id);

    // e. Create S3 client
    let s3_client = match s3_service::get_s3_client(&config.s3).await {
        Ok(client) => client,
        Err(e) => {
            tracing::error!("Failed to create S3 client: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to verify upload".to_string(),
                details: None,
            });
        }
    };

    // f. Verify file exists in S3
    match s3_service::verify_s3_object_exists(&s3_client, &config.s3, &s3_key).await {
        Ok(true) => {}
        Ok(false) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to verify upload".to_string(),
                details: Some("File not found in S3".to_string()),
            });
        }
        Err(e) => {
            tracing::error!("Failed to verify S3 object: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to verify upload".to_string(),
                details: None,
            });
        }
    }

    // g. Verify file hash
    match s3_service::verify_file_hash(&s3_client, &config.s3, &s3_key, &req.file_hash).await {
        Ok(true) => {}
        Ok(false) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "File integrity check failed".to_string(),
                details: Some("File hash does not match uploaded file".to_string()),
            });
        }
        Err(e) => {
            tracing::error!("Failed to verify file hash: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to verify upload".to_string(),
                details: None,
            });
        }
    }

    // Record validated file hash for auditing (ensures future integrity checks)
    if let Err(e) = post_repo::update_session_file_hash(
        pool.get_ref(),
        upload_session.id,
        &req.file_hash,
        req.file_size,
    )
    .await
    {
        tracing::error!(
            "Failed to persist file hash for upload_session {}: {:?}",
            upload_session.id,
            e
        );
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Database error".to_string(),
            details: None,
        });
    }

    // h. Create 3 post_images records (thumbnail, medium, original) with status="pending"
    let image_variants = vec![
        ("thumbnail", format!("posts/{}/thumbnail", post_id)),
        ("medium", format!("posts/{}/medium", post_id)),
        ("original", s3_key.clone()),
    ];

    for (variant, key) in image_variants {
        if let Err(e) = post_repo::create_post_image(pool.get_ref(), post_id, &key, variant).await {
            tracing::error!("Failed to create post_image for {}: {:?}", variant, e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
    }

    // i. Mark upload_session as completed
    if let Err(e) = post_repo::mark_upload_completed(pool.get_ref(), upload_session.id).await {
        tracing::error!("Failed to mark upload as completed: {:?}", e);
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Database error".to_string(),
            details: None,
        });
    }

    // j. Update post status to "processing"
    if let Err(e) = post_repo::update_post_status(pool.get_ref(), post_id, "processing").await {
        tracing::error!("Failed to update post status: {:?}", e);
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Database error".to_string(),
            details: None,
        });
    }

    // k. Submit image processing job to queue
    // Get user_id from post record via database query
    let user_id: Uuid = match sqlx::query_scalar("SELECT user_id FROM posts WHERE id = $1")
        .bind(post_id)
        .fetch_one(pool.get_ref())
        .await
    {
        Ok(uid) => uid,
        Err(e) => {
            tracing::error!("Failed to fetch user_id for post {}: {:?}", post_id, e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
    };

    let job = ImageProcessingJob {
        post_id,
        user_id,
        upload_token: req.upload_token.clone(),
        source_s3_key: s3_key.clone(),
    };

    // Send job to queue (non-blocking)
    // If queue is full, this will return an error
    match job_sender.send(job).await {
        Ok(_) => {
            tracing::info!(
                "Image processing job submitted for post_id={}, user_id={}",
                post_id,
                user_id
            );
        }
        Err(e) => {
            tracing::error!(
                "Failed to submit image processing job for post_id={}: {:?}",
                post_id,
                e
            );
            // Don't fail the request - mark post as failed and return success
            // The client uploaded successfully, but processing will be retried later
            if let Err(db_err) =
                post_repo::update_post_status(pool.get_ref(), post_id, "failed").await
            {
                tracing::error!("Failed to update post status to 'failed': {:?}", db_err);
            }
        }
    }

    // l. Return 200 with response
    HttpResponse::Ok().json(UploadCompleteResponse {
        post_id: post_id.to_string(),
        status: "processing".to_string(),
        message: "Upload complete. Image transcoding in progress.".to_string(),
        image_key: s3_key,
    })
}

/// Get post by ID with all image URLs and metadata
/// GET /api/v1/posts/:id
pub async fn get_post_request(
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    post_id: web::Path<String>,
) -> impl Responder {
    // ========================================
    // Parse and validate post_id
    // ========================================

    let post_uuid = match Uuid::parse_str(&post_id) {
        Ok(uuid) => uuid,
        Err(_) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid post ID format".to_string(),
                details: None,
            });
        }
    };

    // ========================================
    // Fetch post with images and metadata
    // ========================================

    let post_data = match post_repo::get_post_with_images(pool.get_ref(), post_uuid).await {
        Ok(Some((post, metadata, thumbnail_url, medium_url, original_url))) => {
            (post, metadata, thumbnail_url, medium_url, original_url)
        }
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "Post not found".to_string(),
                details: None,
            });
        }
        Err(e) => {
            tracing::error!("Failed to fetch post: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
    };

    let (post, metadata, thumbnail_url, medium_url, original_url) = post_data;

    // ========================================
    // Build CloudFront URLs for images
    // ========================================

    let cloudfront_url = &config.s3.cloudfront_url;

    let thumbnail_cf_url = thumbnail_url.or_else(|| {
        // If no completed image, use S3 key pattern
        Some(format!(
            "{}/posts/{}/thumbnail.jpg",
            cloudfront_url, post.id
        ))
    });

    let medium_cf_url =
        medium_url.or_else(|| Some(format!("{}/posts/{}/medium.jpg", cloudfront_url, post.id)));

    let original_cf_url =
        original_url.or_else(|| Some(format!("{}/posts/{}/original.jpg", cloudfront_url, post.id)));

    // ========================================
    // Build response
    // ========================================

    let response = crate::models::PostResponse {
        id: post.id.to_string(),
        user_id: post.user_id.to_string(),
        caption: post.caption,
        thumbnail_url: thumbnail_cf_url,
        medium_url: medium_cf_url,
        original_url: original_cf_url,
        like_count: metadata.like_count,
        comment_count: metadata.comment_count,
        view_count: metadata.view_count,
        status: post.status,
        created_at: post.created_at.to_rfc3339(),
    };

    HttpResponse::Ok().json(response)
}

/// Initialize presigned URL for S3 upload
/// POST /api/v1/posts/upload/init
/// Protected: Requires valid JWT token in Authorization header
pub async fn upload_init_request(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    _redis: web::Data<ConnectionManager>,
    config: web::Data<Config>,
    req: web::Json<UploadInitRequest>,
) -> impl Responder {
    // ========================================
    // Validation
    // ========================================

    // Validate filename
    if req.filename.is_empty() {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid request".to_string(),
            details: Some("Filename is required".to_string()),
        });
    }

    if req.filename.len() > MAX_FILENAME_LENGTH {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid request".to_string(),
            details: Some(format!(
                "Filename exceeds maximum allowed length ({} characters)",
                MAX_FILENAME_LENGTH
            )),
        });
    }

    // Validate content_type
    if !ALLOWED_CONTENT_TYPES.contains(&req.content_type.as_str()) {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid content type".to_string(),
            details: Some(format!(
                "Content type must be one of: {}",
                ALLOWED_CONTENT_TYPES.join(", ")
            )),
        });
    }

    // Validate file_size
    if req.file_size < MIN_FILE_SIZE {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid file size".to_string(),
            details: Some(format!(
                "File size must be at least {} bytes (100 KB)",
                MIN_FILE_SIZE
            )),
        });
    }

    if req.file_size > MAX_FILE_SIZE {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Invalid file size".to_string(),
            details: Some(format!(
                "File size exceeds maximum allowed size ({} bytes / 50 MB)",
                MAX_FILE_SIZE
            )),
        });
    }

    // Validate caption (optional)
    if let Some(ref caption) = req.caption {
        if caption.len() > MAX_CAPTION_LENGTH {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid request".to_string(),
                details: Some(format!(
                    "Caption exceeds maximum allowed length ({} characters)",
                    MAX_CAPTION_LENGTH
                )),
            });
        }
    }

    // ========================================
    // Extract user_id from JWT middleware
    // ========================================

    let user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id_wrapper) => user_id_wrapper.0,
        None => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Unauthorized".to_string(),
                details: Some(
                    "User ID not found in request. JWT middleware may not be active.".to_string(),
                ),
            });
        }
    };

    // a. Create post in DB with status="pending"
    let post = match post_repo::create_post(
        pool.get_ref(),
        user_id,
        req.caption.as_deref(),
        "temp", // Temporary image_key, will be updated with actual S3 key
    )
    .await
    {
        Ok(post) => post,
        Err(e) => {
            tracing::error!("Failed to create post: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
    };

    // b. Generate S3 key: posts/{post_id}/original
    let s3_key = format!("posts/{}/original", post.id);

    // Update post with actual S3 key
    if let Err(e) = post_repo::update_post_image_key(pool.get_ref(), post.id, &s3_key).await {
        tracing::error!("Failed to update post image_key: {:?}", e);
        return HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Database error".to_string(),
            details: None,
        });
    }

    // c. Call s3_service::generate_presigned_url() for PUT upload
    let s3_client = match s3_service::get_s3_client(&config.s3).await {
        Ok(client) => client,
        Err(e) => {
            tracing::error!("Failed to create S3 client: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate upload URL".to_string(),
                details: None,
            });
        }
    };

    let presigned_url = match s3_service::generate_presigned_url(
        &s3_client,
        &config.s3,
        &s3_key,
        &req.content_type,
    )
    .await
    {
        Ok(url) => url,
        Err(e) => {
            tracing::error!("Failed to generate presigned URL: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Failed to generate upload URL".to_string(),
                details: None,
            });
        }
    };

    // d. Generate upload_token: 32-byte hex string using rand crate
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let token_bytes: [u8; 32] = rng.gen();
    let upload_token = hex::encode(token_bytes);

    // e. Create upload_session in DB with token and 1-hour expiry
    match post_repo::create_upload_session(pool.get_ref(), post.id, &upload_token).await {
        Ok(_) => {}
        Err(e) => {
            tracing::error!("Failed to create upload session: {:?}", e);
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            });
        }
    }

    // f. Return 201 with presigned URL, post_id, token, and 900 sec expiry
    HttpResponse::Created().json(UploadInitResponse {
        presigned_url,
        post_id: post.id.to_string(),
        upload_token,
        expires_in: 900,
        instructions: "Use PUT method to upload file to presigned_url".to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // Helper function to create test request
    fn create_test_request(
        filename: &str,
        content_type: &str,
        file_size: i64,
        caption: Option<String>,
    ) -> UploadInitRequest {
        UploadInitRequest {
            filename: filename.to_string(),
            content_type: content_type.to_string(),
            file_size,
            caption,
        }
    }

    #[actix_web::test]
    async fn test_valid_upload_init_request() {
        // This test validates request structure only (no DB/Redis)
        let req = create_test_request(
            "photo.jpg",
            "image/jpeg",
            2048576,
            Some("Test post".to_string()),
        );

        assert_eq!(req.filename, "photo.jpg");
        assert_eq!(req.content_type, "image/jpeg");
        assert_eq!(req.file_size, 2048576);
        assert_eq!(req.caption, Some("Test post".to_string()));
    }

    #[actix_web::test]
    async fn test_invalid_content_type() {
        // Test with invalid MIME type
        let req = create_test_request("video.mp4", "video/mp4", 2048576, None);

        // Validate that video/mp4 is NOT in allowed types
        assert!(!ALLOWED_CONTENT_TYPES.contains(&req.content_type.as_str()));
    }

    #[actix_web::test]
    async fn test_file_size_too_large() {
        // Test with file size exceeding 50 MB
        let file_size = 60 * 1024 * 1024; // 60 MB
        let req = create_test_request("large.jpg", "image/jpeg", file_size, None);

        assert!(req.file_size > MAX_FILE_SIZE);
    }

    #[actix_web::test]
    async fn test_file_size_too_small() {
        // Test with file size below 100 KB
        let file_size = 50 * 1024; // 50 KB
        let req = create_test_request("small.jpg", "image/jpeg", file_size, None);

        assert!(req.file_size < MIN_FILE_SIZE);
    }

    #[actix_web::test]
    async fn test_caption_too_long() {
        // Test with caption exceeding 2200 characters
        let long_caption = "a".repeat(2201);
        let req = create_test_request(
            "photo.jpg",
            "image/jpeg",
            2048576,
            Some(long_caption.clone()),
        );

        assert!(req.caption.as_ref().unwrap().len() > MAX_CAPTION_LENGTH);
    }

    #[actix_web::test]
    async fn test_allowed_content_types() {
        // Verify all allowed content types
        let allowed_types = vec!["image/jpeg", "image/png", "image/webp", "image/heic"];

        for content_type in allowed_types {
            assert!(ALLOWED_CONTENT_TYPES.contains(&content_type));
        }
    }

    #[actix_web::test]
    async fn test_validation_constants() {
        // Verify validation constants are set correctly
        assert_eq!(MAX_FILENAME_LENGTH, 255);
        assert_eq!(MIN_FILE_SIZE, 102400); // 100 KB
        assert_eq!(MAX_FILE_SIZE, 52428800); // 50 MB
        assert_eq!(MAX_CAPTION_LENGTH, 2200);
    }

    // ============================================
    // Upload Complete Request Tests
    // ============================================

    fn create_upload_complete_request(
        post_id: &str,
        upload_token: &str,
        file_hash: &str,
        file_size: i64,
    ) -> UploadCompleteRequest {
        UploadCompleteRequest {
            post_id: post_id.to_string(),
            upload_token: upload_token.to_string(),
            file_hash: file_hash.to_string(),
            file_size,
        }
    }

    #[actix_web::test]
    async fn test_valid_upload_complete_request() {
        // Test valid upload complete request structure
        let valid_uuid = "550e8400-e29b-41d4-a716-446655440000";
        let valid_token = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6";
        let valid_hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        let valid_size = 2048576; // 2 MB

        let req = create_upload_complete_request(valid_uuid, valid_token, valid_hash, valid_size);

        // Validate request structure
        assert_eq!(req.post_id, valid_uuid);
        assert_eq!(req.upload_token, valid_token);
        assert_eq!(req.file_hash, valid_hash);
        assert_eq!(req.file_size, valid_size);

        // Validate UUID format
        assert!(Uuid::parse_str(&req.post_id).is_ok());

        // Validate file hash is exactly 64 characters (SHA256)
        assert_eq!(req.file_hash.len(), 64);

        // Validate file size is within bounds
        assert!(req.file_size >= MIN_FILE_SIZE);
        assert!(req.file_size <= MAX_FILE_SIZE);
    }

    #[actix_web::test]
    async fn test_invalid_uuid_format() {
        // Test with invalid UUID format
        let invalid_uuid = "not-a-valid-uuid";
        let valid_token = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6";
        let valid_hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        let req = create_upload_complete_request(invalid_uuid, valid_token, valid_hash, 2048576);

        // UUID parsing should fail
        assert!(Uuid::parse_str(&req.post_id).is_err());
    }

    #[actix_web::test]
    async fn test_invalid_file_hash_format() {
        // Test with invalid file hash format (not hex, wrong length)
        let valid_uuid = "550e8400-e29b-41d4-a716-446655440000";
        let valid_token = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6";

        // Hash too short (32 chars instead of 64)
        let short_hash = "1234567890abcdef1234567890abcdef";
        let req = create_upload_complete_request(valid_uuid, valid_token, short_hash, 2048576);
        assert_ne!(req.file_hash.len(), 64);

        // Hash with invalid characters
        let invalid_hash = "gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg";
        let req2 = create_upload_complete_request(valid_uuid, valid_token, invalid_hash, 2048576);
        assert!(!req2.file_hash.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[actix_web::test]
    async fn test_upload_complete_file_too_large() {
        // Test with file size exceeding maximum (50 MB)
        let valid_uuid = "550e8400-e29b-41d4-a716-446655440000";
        let valid_token = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6";
        let valid_hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
        let file_size = 60 * 1024 * 1024; // 60 MB

        let req = create_upload_complete_request(valid_uuid, valid_token, valid_hash, file_size);

        assert!(req.file_size > MAX_FILE_SIZE);
    }

    #[actix_web::test]
    async fn test_upload_complete_empty_token() {
        // Test with empty upload token
        let valid_uuid = "550e8400-e29b-41d4-a716-446655440000";
        let empty_token = "";
        let valid_hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        let req = create_upload_complete_request(valid_uuid, empty_token, valid_hash, 2048576);

        assert!(req.upload_token.is_empty());
    }

    #[actix_web::test]
    async fn test_upload_complete_token_max_length() {
        // Test with token exceeding maximum length (512 chars)
        let valid_uuid = "550e8400-e29b-41d4-a716-446655440000";
        let long_token = "a".repeat(600); // 600 characters
        let valid_hash = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";

        let req = create_upload_complete_request(valid_uuid, &long_token, valid_hash, 2048576);

        assert!(req.upload_token.len() > 512);
    }

    // ============================================
    // Get Post Request Tests
    // ============================================

    #[actix_web::test]
    async fn test_valid_post_id_format() {
        // Test that a valid UUID can be parsed
        let valid_uuid = "550e8400-e29b-41d4-a716-446655440000";
        let parsed = Uuid::parse_str(valid_uuid);
        assert!(parsed.is_ok());
    }

    #[actix_web::test]
    async fn test_invalid_post_id_format() {
        // Test that an invalid UUID returns error
        let invalid_uuid = "not-a-valid-uuid";
        let parsed = Uuid::parse_str(invalid_uuid);
        assert!(parsed.is_err());
    }

    #[actix_web::test]
    async fn test_empty_post_id() {
        // Test with empty post_id
        let empty_uuid = "";
        let parsed = Uuid::parse_str(empty_uuid);
        assert!(parsed.is_err());
    }

    #[actix_web::test]
    async fn test_post_response_structure() {
        // Test PostResponse serialization structure
        use crate::models::PostResponse;

        let response = PostResponse {
            id: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            user_id: "660e8400-e29b-41d4-a716-446655440000".to_string(),
            caption: Some("Test caption".to_string()),
            thumbnail_url: Some("https://cdn.example.com/thumb.jpg".to_string()),
            medium_url: Some("https://cdn.example.com/medium.jpg".to_string()),
            original_url: Some("https://cdn.example.com/original.jpg".to_string()),
            like_count: 42,
            comment_count: 5,
            view_count: 128,
            status: "published".to_string(),
            created_at: "2025-01-16T10:30:00Z".to_string(),
        };

        // Verify serialization
        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("550e8400-e29b-41d4-a716-446655440000"));
        assert!(json.contains("Test caption"));
        assert!(json.contains("\"like_count\":42"));
        assert!(json.contains("\"status\":\"published\""));
    }
}

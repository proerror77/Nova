use crate::config::S3Config;
use error_handling::ServiceError;
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::Client;
use sha2::{Digest, Sha256};
use std::time::Duration;

/// Generate a presigned URL for uploading a file to S3
///
/// This function creates a temporary URL that allows direct upload to S3
/// without exposing AWS credentials to the client. The URL expires after
/// the configured time (default: 15 minutes).
///
/// # Arguments
/// * `client` - AWS S3 client instance
/// * `config` - S3 configuration (bucket, region, expiry time)
/// * `s3_key` - The S3 object key (path) where the file will be stored
/// * `content_type` - MIME type of the file to be uploaded
///
/// # Returns
/// Presigned URL as a String that can be used for PUT requests
pub async fn generate_presigned_url(
    client: &Client,
    config: &S3Config,
    s3_key: &str,
    content_type: &str,
) -> Result<String, ServiceError> {
    // Create presigning configuration with expiry time
    let expires_in = Duration::from_secs(config.presigned_url_expiry_secs);
    let presigning_config = PresigningConfig::builder()
        .expires_in(expires_in)
        .build()
        .map_err(|e| ServiceError::InternalError(format!("Failed to create presigning config: {e}")))?;

    // Generate presigned PUT request
    let presigned_request = client
        .put_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .content_type(content_type)
        .presigned(presigning_config)
        .await
        .map_err(|e| ServiceError::InternalError(format!("Failed to generate presigned URL: {e}")))?;

    Ok(presigned_request.uri().to_string())
}

/// Verify that an S3 object exists after upload
///
/// Uses HeadObject API call to check if a file exists in S3 without
/// downloading the entire file. This is more efficient than GetObject
/// for verification purposes.
///
/// # Arguments
/// * `client` - AWS S3 client instance
/// * `config` - S3 configuration (bucket name)
/// * `s3_key` - The S3 object key to verify
///
/// # Returns
/// true if the object exists, false otherwise
pub async fn verify_s3_object_exists(
    client: &Client,
    config: &S3Config,
    s3_key: &str,
) -> Result<bool, ServiceError> {
    // Use head_object to check existence without downloading
    match client
        .head_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .send()
        .await
    {
        Ok(_) => Ok(true),
        Err(e) => {
            // Check if error is 404 (not found) or actual error
            let error_msg = e.to_string();
            if error_msg.contains("404") || error_msg.contains("NotFound") {
                Ok(false)
            } else {
                Err(ServiceError::InternalError(format!(
                    "Failed to verify S3 object: {e}"
                )))
            }
        }
    }
}

/// Verify file integrity by comparing SHA256 hashes
///
/// Downloads the file from S3, computes its SHA256 hash, and compares
/// it with the expected hash to ensure file integrity.
///
/// # Arguments
/// * `client` - AWS S3 client instance
/// * `config` - S3 configuration (bucket name)
/// * `s3_key` - The S3 object key to verify
/// * `expected_hash` - Expected SHA256 hash (hex-encoded string)
///
/// # Returns
/// true if hashes match, false otherwise
pub async fn verify_file_hash(
    client: &Client,
    config: &S3Config,
    s3_key: &str,
    expected_hash: &str,
) -> Result<bool, ServiceError> {
    // Download file from S3
    let response = client
        .get_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .send()
        .await
        .map_err(|e| ServiceError::InternalError(format!("Failed to download S3 object: {e}")))?;

    // Read file contents
    let bytes = response
        .body
        .collect()
        .await
        .map_err(|e| ServiceError::InternalError(format!("Failed to read S3 object body: {e}")))?
        .into_bytes();

    // Compute SHA256 hash
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    let computed_hash = hex::encode(hasher.finalize());

    // Compare hashes (case-insensitive)
    Ok(computed_hash.eq_ignore_ascii_case(expected_hash))
}

/// Initialize AWS S3 client with credentials from config
///
/// Creates a new S3 client using AWS SDK with explicit credentials.
/// In production, consider using IAM roles instead of access keys.
///
/// # Arguments
/// * `config` - S3 configuration with AWS credentials
///
/// # Returns
/// Configured AWS S3 client
pub async fn get_s3_client(config: &S3Config) -> Result<Client, ServiceError> {
    use aws_sdk_s3::config::{Credentials, Region};

    // Create credentials from config
    let credentials = Credentials::new(
        &config.aws_access_key_id,
        &config.aws_secret_access_key,
        None, // No session token
        None, // No expiration
        "s3_service",
    );

    // Create AWS config with region and credentials
    let aws_config = aws_config::defaults(aws_config::BehaviorVersion::latest())
        .region(Region::new(config.region.clone()))
        .credentials_provider(credentials)
        .load()
        .await;

    // Create S3 client from config
    let s3_client = Client::new(&aws_config);

    Ok(s3_client)
}

/// Upload an image file to S3 with metadata
///
/// Uploads a local file to S3 bucket with appropriate metadata for image variants.
/// The file is uploaded with private ACL (not publicly readable), relying on CloudFront
/// for public access. Metadata includes size variant, post ID, and upload timestamp.
///
/// # Arguments
/// * `client` - AWS S3 client instance
/// * `config` - S3 configuration (bucket name, CloudFront URL)
/// * `local_path` - Path to local file to upload
/// * `s3_key` - The S3 object key (path) where the file will be stored
/// * `content_type` - MIME type of the file (typically "image/jpeg")
///
/// # Returns
/// CloudFront URL for accessing the uploaded image
///
/// # Errors
/// Returns `ServiceError::InternalError` if:
/// - Local file cannot be read
/// - S3 upload fails
/// - Invalid S3 key format
pub async fn upload_image_to_s3(
    client: &Client,
    config: &S3Config,
    local_path: &str,
    s3_key: &str,
    content_type: &str,
) -> Result<String, ServiceError> {
    use aws_sdk_s3::primitives::ByteStream;
    use std::path::Path;

    // Validate local file exists
    let path = Path::new(local_path);
    if !path.exists() {
        return Err(ServiceError::InternalError(format!(
            "Local file not found: {}",
            local_path
        )));
    }

    // Extract metadata from S3 key
    // Expected format: posts/{post_id}/{size_variant}.jpg
    let parts: Vec<&str> = s3_key.split('/').collect();
    if parts.len() < 3 {
        return Err(ServiceError::InternalError(format!(
            "Invalid S3 key format: {}",
            s3_key
        )));
    }

    let post_id = parts[1];
    let size_variant = parts[2].trim_end_matches(".jpg");

    // Get current timestamp in ISO8601 format
    let uploaded_at = chrono::Utc::now().to_rfc3339();

    // Read file as ByteStream for async upload
    let body = ByteStream::from_path(path)
        .await
        .map_err(|e| ServiceError::InternalError(format!("Failed to read file {}: {}", local_path, e)))?;

    // Upload to S3 with metadata and cache headers
    client
        .put_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .body(body)
        .content_type(content_type)
        // ACL is private - CloudFront will provide public access
        .metadata("size_variant", size_variant)
        .metadata("post_id", post_id)
        .metadata("uploaded_at", &uploaded_at)
        // Cache-Control: 1 year (images are immutable, versioned by path)
        .cache_control("max-age=31536000")
        .send()
        .await
        .map_err(|e| {
            let error_msg = e.to_string();
            if error_msg.contains("403") || error_msg.contains("Forbidden") {
                ServiceError::InternalError(format!("S3 auth failed (403): Check AWS credentials"))
            } else if error_msg.contains("NoSuchBucket") {
                ServiceError::InternalError(format!("S3 bucket not found: {}", config.bucket_name))
            } else {
                ServiceError::InternalError(format!("S3 upload failed: {}", e))
            }
        })?;

    // Generate CloudFront URL for the uploaded image
    let cloudfront_url = generate_cloudfront_url(config, s3_key)?;

    Ok(cloudfront_url)
}

/// Delete an object from S3
///
/// Removes an object from the S3 bucket. This is typically used when cleaning up
/// after failed uploads or when deleting posts with their associated images.
///
/// # Arguments
/// * `client` - AWS S3 client instance
/// * `config` - S3 configuration (bucket name)
/// * `s3_key` - The S3 object key to delete
///
/// # Returns
/// Empty result on success
///
/// # Errors
/// Returns `ServiceError::InternalError` if S3 deletion fails
pub async fn delete_s3_object(
    client: &Client,
    config: &S3Config,
    s3_key: &str,
) -> Result<(), ServiceError> {
    client
        .delete_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .send()
        .await
        .map_err(|e| {
            let error_msg = e.to_string();
            if error_msg.contains("403") || error_msg.contains("Forbidden") {
                ServiceError::InternalError(format!("S3 auth failed (403): Check AWS credentials"))
            } else {
                ServiceError::InternalError(format!("S3 delete failed: {}", e))
            }
        })?;

    Ok(())
}

/// Generate CloudFront URL for an S3 object
///
/// Creates a full CloudFront URL for accessing an S3 object through CDN.
/// This is a pure string operation with no AWS API calls.
///
/// # Arguments
/// * `config` - S3 configuration (CloudFront URL)
/// * `s3_key` - The S3 object key (path)
///
/// # Returns
/// Full CloudFront URL (e.g., https://d1234567890.cloudfront.net/posts/abc-123/thumbnail.jpg)
///
/// # Errors
/// This function cannot fail - it always returns a valid URL string
pub fn generate_cloudfront_url(config: &S3Config, s3_key: &str) -> Result<String, ServiceError> {
    // CloudFront URL format: {CLOUDFRONT_URL}/{s3_key}
    // Example: https://d1234567890.cloudfront.net/posts/abc-123/thumbnail.jpg
    let url = format!("{}/{}", config.cloudfront_url.trim_end_matches('/'), s3_key);
    Ok(url)
}

/// Health check for S3 connectivity and bucket access
///
/// Verifies that:
/// 1. AWS credentials are valid
/// 2. S3 bucket is accessible
/// 3. Bucket has appropriate permissions for upload/download
///
/// This is a critical check because video processing depends entirely on S3.
/// If this fails, the application should not start.
///
/// # Arguments
/// * `client` - AWS S3 client instance
/// * `config` - S3 configuration
///
/// # Returns
/// Ok(()) if S3 is healthy, Err(ServiceError) with detailed message otherwise
pub async fn health_check(client: &Client, config: &S3Config) -> Result<(), ServiceError> {
    // Attempt to list objects in bucket as a connectivity test
    // This validates:
    // - AWS credentials are valid
    // - Bucket exists and is accessible
    // - User has ListBucket permission
    match client
        .list_objects_v2()
        .bucket(&config.bucket_name)
        .max_keys(1)
        .send()
        .await
    {
        Ok(_) => {
            tracing::info!(
                "✅ S3 connection validated (bucket: {}, region: {})",
                config.bucket_name,
                config.region
            );
            Ok(())
        }
        Err(e) => {
            let error_msg = e.to_string();

            // Provide specific error guidance based on error type
            let guidance = if error_msg.contains("InvalidAccessKeyId") {
                "Invalid AWS Access Key ID. Check AWS_ACCESS_KEY_ID environment variable."
            } else if error_msg.contains("SignatureDoesNotMatch") {
                "Invalid AWS Secret Access Key. Check AWS_SECRET_ACCESS_KEY environment variable."
            } else if error_msg.contains("NoSuchBucket") {
                &format!(
                    "Bucket does not exist: {}. Create it with: aws s3api create-bucket --bucket {} --region {} --create-bucket-configuration LocationConstraint={}",
                    config.bucket_name, config.bucket_name, config.region, config.region
                )
            } else if error_msg.contains("AccessDenied") {
                "Access denied to S3 bucket. Ensure sonic-shih user has S3 permissions (AmazonS3FullAccess or equivalent)."
            } else {
                "S3 health check failed. Ensure S3 bucket is accessible and credentials are valid."
            };

            tracing::error!("❌ FATAL: S3 health check failed");
            tracing::error!("   Error: {}", error_msg);
            tracing::error!("   Bucket: {}", config.bucket_name);
            tracing::error!("   Region: {}", config.region);
            tracing::error!("   Guidance: {}", guidance);

            Err(ServiceError::InternalError(format!(
                "S3 health check failed: {}. {}",
                error_msg, guidance
            )))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_config() -> S3Config {
        S3Config {
            bucket_name: "test-bucket".to_string(),
            region: "us-east-1".to_string(),
            aws_access_key_id: "test-key-id".to_string(),
            aws_secret_access_key: "test-secret-key".to_string(),
            cloudfront_url: "https://d1234567890.cloudfront.net".to_string(),
            presigned_url_expiry_secs: 900,
        }
    }

    #[tokio::test]
    async fn test_s3_config_expiry_time() {
        let config = create_test_config();
        assert_eq!(config.presigned_url_expiry_secs, 900); // 15 minutes
    }

    #[tokio::test]
    async fn test_hash_computation() {
        // Test SHA256 hash computation
        let test_data = b"test file content";
        let mut hasher = Sha256::new();
        hasher.update(test_data);
        let hash = hex::encode(hasher.finalize());

        // Expected SHA256 of "test file content"
        assert_eq!(
            hash,
            "60f5237ed4049f0382661ef009d2bc42e48c3ceb3edb6600f7024e7ab3b838f3"
        );
    }

    #[tokio::test]
    async fn test_hash_comparison_case_insensitive() {
        let hash1 = "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358";
        let hash2 = "4F8B42C22DD3729B519BA6F68D2DA7CC5B2D606D05DAED5AD5128CC03E6C6358";

        // Test case-insensitive comparison
        assert!(hash1.eq_ignore_ascii_case(hash2));
    }

    #[tokio::test]
    async fn test_generate_cloudfront_url() {
        let config = create_test_config();
        let s3_key = "posts/abc-123/thumbnail.jpg";

        let result = generate_cloudfront_url(&config, s3_key);

        assert!(result.is_ok());
        let url = result.unwrap();
        assert_eq!(
            url,
            "https://d1234567890.cloudfront.net/posts/abc-123/thumbnail.jpg"
        );
    }

    #[tokio::test]
    async fn test_generate_cloudfront_url_with_trailing_slash() {
        let mut config = create_test_config();
        config.cloudfront_url = "https://d1234567890.cloudfront.net/".to_string();
        let s3_key = "posts/abc-123/medium.jpg";

        let result = generate_cloudfront_url(&config, s3_key);

        assert!(result.is_ok());
        let url = result.unwrap();
        // Should not have double slash
        assert_eq!(
            url,
            "https://d1234567890.cloudfront.net/posts/abc-123/medium.jpg"
        );
        assert!(!url.contains("//posts"));
    }
}

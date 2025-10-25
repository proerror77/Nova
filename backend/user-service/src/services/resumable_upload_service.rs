/// Resumable Upload Service
///
/// Handles chunked video uploads with S3 multipart upload support, integrity verification,
/// and automatic resume capability. Designed for large video files that may be interrupted.

use crate::config::S3Config;
use crate::db::upload_repo::*;
use crate::error::{AppError, Result};
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::Client as S3Client;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

pub struct ResumableUploadService;

impl ResumableUploadService {
    /// Initialize a new multipart upload session in S3
    ///
    /// Creates S3 multipart upload ID and stores it in database for tracking.
    /// This ID is used to assemble chunks into final file.
    pub async fn init_s3_multipart(
        s3_client: &S3Client,
        s3_config: &S3Config,
        pool: &PgPool,
        upload_id: Uuid,
        s3_key: &str,
    ) -> Result<String> {
        // Create S3 multipart upload
        let multipart_resp = s3_client
            .create_multipart_upload()
            .bucket(&s3_config.bucket_name)
            .key(s3_key)
            .content_type("video/mp4") // Default to mp4, can be parameterized
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to init S3 multipart: {}", e)))?;

        let s3_upload_id = multipart_resp
            .upload_id()
            .ok_or_else(|| AppError::Internal("S3 multipart upload ID missing".to_string()))?
            .to_string();

        // Store S3 upload ID in database
        set_s3_upload_id(pool, upload_id, s3_upload_id.clone())
            .await
            .map_err(|e| AppError::Internal(format!("Failed to store S3 upload ID: {}", e)))?;

        Ok(s3_upload_id)
    }

    /// Upload a single chunk to S3 multipart upload
    ///
    /// Uploads chunk bytes to S3, records ETag for final assembly.
    /// Returns chunk metadata including hash for integrity verification.
    pub async fn upload_chunk(
        s3_client: &S3Client,
        s3_config: &S3Config,
        pool: &PgPool,
        upload_id: Uuid,
        s3_upload_id: &str,
        s3_key: &str,
        chunk_index: i32,
        chunk_data: Vec<u8>,
    ) -> Result<crate::models::video::UploadChunk> {
        // Compute SHA256 hash for integrity
        let chunk_hash = Self::compute_sha256(&chunk_data);
        let chunk_size = chunk_data.len() as i64;

        // S3 part numbers are 1-indexed
        let part_number = chunk_index + 1;

        // Upload chunk as part of multipart upload
        let upload_part_resp = s3_client
            .upload_part()
            .bucket(&s3_config.bucket_name)
            .key(s3_key)
            .upload_id(s3_upload_id)
            .part_number(part_number)
            .body(ByteStream::from(chunk_data))
            .send()
            .await
            .map_err(|e| {
                AppError::Internal(format!("Failed to upload chunk {}: {}", chunk_index, e))
            })?;

        // Extract ETag (required for completing multipart upload)
        let etag = upload_part_resp
            .e_tag()
            .ok_or_else(|| AppError::Internal(format!("Missing ETag for chunk {}", chunk_index)))?
            .to_string();

        // Record chunk in database (idempotent)
        let chunk_entity = upsert_chunk(
            pool,
            upload_id,
            chunk_index,
            chunk_size,
            &etag,
            Some(&chunk_hash),
        )
        .await
        .map_err(|e| AppError::Internal(format!("Failed to record chunk: {}", e)))?;

        // Update total uploaded count
        update_chunk_count(pool, upload_id)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to update chunk count: {}", e)))?;

        Ok(chunk_entity)
    }

    /// Verify chunk integrity before uploading
    ///
    /// Client sends hash with chunk; verify it matches computed hash.
    /// Prevents corrupted data from being stored.
    pub fn verify_chunk_hash(chunk_data: &[u8], expected_hash: &str) -> Result<bool> {
        let computed_hash = Self::compute_sha256(chunk_data);
        Ok(computed_hash.eq_ignore_ascii_case(expected_hash))
    }

    /// Complete multipart upload and assemble final file
    ///
    /// Tells S3 to assemble all uploaded chunks into final file.
    /// Requires all chunks to be uploaded in correct order with their ETags.
    pub async fn complete_s3_multipart(
        s3_client: &S3Client,
        s3_config: &S3Config,
        pool: &PgPool,
        upload_id: Uuid,
        s3_upload_id: &str,
        s3_key: &str,
    ) -> Result<()> {
        // Get all uploaded chunks (ordered by index)
        let chunks = get_chunks(pool, upload_id)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to fetch chunks: {}", e)))?;

        // Build CompletedPart array for S3
        use aws_sdk_s3::types::CompletedPart;
        let completed_parts: Vec<CompletedPart> = chunks
            .iter()
            .map(|chunk| {
                CompletedPart::builder()
                    .part_number(chunk.chunk_number + 1) // 1-indexed
                    .e_tag(&chunk.etag)
                    .build()
            })
            .collect();

        // Build CompletedMultipartUpload
        use aws_sdk_s3::types::CompletedMultipartUpload;
        let completed_upload = CompletedMultipartUpload::builder()
            .set_parts(Some(completed_parts))
            .build();

        // Complete multipart upload
        s3_client
            .complete_multipart_upload()
            .bucket(&s3_config.bucket_name)
            .key(s3_key)
            .upload_id(s3_upload_id)
            .multipart_upload(completed_upload)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to complete multipart: {}", e)))?;

        Ok(())
    }

    /// Abort multipart upload (cleanup on failure)
    ///
    /// Cancels S3 multipart upload and deletes uploaded chunks.
    /// Used when upload fails or user cancels.
    pub async fn abort_s3_multipart(
        s3_client: &S3Client,
        s3_config: &S3Config,
        s3_upload_id: &str,
        s3_key: &str,
    ) -> Result<()> {
        s3_client
            .abort_multipart_upload()
            .bucket(&s3_config.bucket_name)
            .key(s3_key)
            .upload_id(s3_upload_id)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to abort multipart: {}", e)))?;

        Ok(())
    }

    /// Get next chunk index to upload
    ///
    /// Determines which chunk should be uploaded next based on what's already uploaded.
    /// Enables resume from last successful chunk.
    pub async fn get_next_chunk_index(pool: &PgPool, upload_id: Uuid) -> Result<i32> {
        let upload = get_upload(pool, upload_id)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to fetch upload: {}", e)))?
            .ok_or_else(|| AppError::NotFound("Upload not found".to_string()))?;

        // Get all uploaded chunks
        let chunks = get_chunks(pool, upload_id)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to fetch chunks: {}", e)))?;

        // Find first missing chunk index
        let uploaded_indices: Vec<i32> = chunks.iter().map(|c| c.chunk_number).collect();

        for i in 0..upload.chunks_total {
            if !uploaded_indices.contains(&i) {
                return Ok(i);
            }
        }

        // All chunks uploaded
        Ok(upload.chunks_total)
    }

    /// Check if upload is complete
    ///
    /// Returns true if all chunks have been uploaded.
    pub async fn is_upload_complete(pool: &PgPool, upload_id: Uuid) -> Result<bool> {
        let upload = get_upload(pool, upload_id)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to fetch upload: {}", e)))?
            .ok_or_else(|| AppError::NotFound("Upload not found".to_string()))?;

        Ok(upload.chunks_completed >= upload.chunks_total)
    }

    /// Compute SHA256 hash of data
    fn compute_sha256(data: &[u8]) -> String {
        let mut hasher = Sha256::new();
        hasher.update(data);
        hex::encode(hasher.finalize())
    }

    /// Calculate upload progress percentage
    pub fn calculate_progress(chunks_uploaded: i32, chunks_total: i32) -> f64 {
        if chunks_total == 0 {
            return 0.0;
        }
        (chunks_uploaded as f64 / chunks_total as f64) * 100.0
    }

    /// Validate chunk index is within valid range
    pub fn validate_chunk_index(chunk_index: i32, chunks_total: i32) -> Result<()> {
        if chunk_index < 0 || chunk_index >= chunks_total {
            return Err(AppError::BadRequest(format!(
                "Chunk index {} out of range (0-{})",
                chunk_index,
                chunks_total - 1
            )));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_sha256() {
        let data = b"test chunk data";
        let hash = ResumableUploadService::compute_sha256(data);

        // Verify hash is 64 hex characters (32 bytes)
        assert_eq!(hash.len(), 64);

        // Same data should produce same hash
        let hash2 = ResumableUploadService::compute_sha256(data);
        assert_eq!(hash, hash2);
    }

    #[test]
    fn test_verify_chunk_hash() {
        let data = b"test chunk data";
        let correct_hash = ResumableUploadService::compute_sha256(data);

        // Should match with correct hash
        assert!(ResumableUploadService::verify_chunk_hash(data, &correct_hash).unwrap());

        // Should not match with incorrect hash
        let wrong_hash = "0000000000000000000000000000000000000000000000000000000000000000";
        assert!(!ResumableUploadService::verify_chunk_hash(data, wrong_hash).unwrap());
    }

    #[test]
    fn test_calculate_progress() {
        assert_eq!(ResumableUploadService::calculate_progress(0, 100), 0.0);
        assert_eq!(ResumableUploadService::calculate_progress(50, 100), 50.0);
        assert_eq!(ResumableUploadService::calculate_progress(100, 100), 100.0);
        assert_eq!(ResumableUploadService::calculate_progress(0, 0), 0.0);
    }

    #[test]
    fn test_validate_chunk_index() {
        // Valid indices
        assert!(ResumableUploadService::validate_chunk_index(0, 100).is_ok());
        assert!(ResumableUploadService::validate_chunk_index(50, 100).is_ok());
        assert!(ResumableUploadService::validate_chunk_index(99, 100).is_ok());

        // Invalid indices
        assert!(ResumableUploadService::validate_chunk_index(-1, 100).is_err());
        assert!(ResumableUploadService::validate_chunk_index(100, 100).is_err());
        assert!(ResumableUploadService::validate_chunk_index(200, 100).is_err());
    }
}

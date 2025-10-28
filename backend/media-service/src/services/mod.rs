/// Service layer for videos and uploads
///
/// This module provides business logic for:
/// - Video service: video lifecycle management
/// - Upload service: upload handling and resumable uploads
///
/// Extracted from user-service as part of P1.2 service splitting.

use sqlx::PgPool;
use uuid::Uuid;

use crate::error::Result;
use crate::models::{Video, Upload};

/// Video service for handling video operations
pub struct VideoService {
    pool: PgPool,
}

impl VideoService {
    /// Create a new VideoService
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Get a video by ID
    pub async fn get_video(&self, video_id: Uuid) -> Result<Option<Video>> {
        let video = sqlx::query_as::<_, Video>(
            "SELECT id, creator_id, title, description, duration_seconds, cdn_url, \
             thumbnail_url, status, visibility, created_at, updated_at \
             FROM videos WHERE id = $1 AND deleted_at IS NULL"
        )
        .bind(video_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| crate::error::AppError::DatabaseError(e.to_string()))?;

        Ok(video)
    }

    /// Get user's videos
    pub async fn get_user_videos(&self, user_id: Uuid, limit: i32) -> Result<Vec<Video>> {
        let videos = sqlx::query_as::<_, Video>(
            "SELECT id, creator_id, title, description, duration_seconds, cdn_url, \
             thumbnail_url, status, visibility, created_at, updated_at \
             FROM videos WHERE creator_id = $1 AND deleted_at IS NULL \
             ORDER BY created_at DESC LIMIT $2"
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| crate::error::AppError::DatabaseError(e.to_string()))?;

        Ok(videos)
    }

    /// Update video status
    pub async fn update_video_status(&self, video_id: Uuid, status: &str) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE videos SET status = $2, updated_at = NOW() WHERE id = $1 AND deleted_at IS NULL"
        )
        .bind(video_id)
        .bind(status)
        .execute(&self.pool)
        .await
        .map_err(|e| crate::error::AppError::DatabaseError(e.to_string()))?;

        Ok(result.rows_affected() > 0)
    }
}

/// Upload service for handling upload operations
pub struct UploadService {
    pool: PgPool,
}

impl UploadService {
    /// Create a new UploadService
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Get an upload by ID
    pub async fn get_upload(&self, upload_id: Uuid) -> Result<Option<Upload>> {
        let upload = sqlx::query_as::<_, Upload>(
            "SELECT id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at \
             FROM uploads WHERE id = $1"
        )
        .bind(upload_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| crate::error::AppError::DatabaseError(e.to_string()))?;

        Ok(upload)
    }

    /// Get user's uploads
    pub async fn get_user_uploads(&self, user_id: Uuid, limit: i32) -> Result<Vec<Upload>> {
        let uploads = sqlx::query_as::<_, Upload>(
            "SELECT id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at \
             FROM uploads WHERE user_id = $1 \
             ORDER BY created_at DESC LIMIT $2"
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| crate::error::AppError::DatabaseError(e.to_string()))?;

        Ok(uploads)
    }

    /// Update upload progress
    pub async fn update_progress(&self, upload_id: Uuid, uploaded_size: i64) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE uploads SET uploaded_size = $2, updated_at = NOW() WHERE id = $1"
        )
        .bind(upload_id)
        .bind(uploaded_size)
        .execute(&self.pool)
        .await
        .map_err(|e| crate::error::AppError::DatabaseError(e.to_string()))?;

        Ok(result.rows_affected() > 0)
    }

    /// Check if upload is complete
    pub async fn is_complete(&self, upload_id: Uuid) -> Result<bool> {
        let result = sqlx::query_scalar::<_, bool>(
            "SELECT file_size = uploaded_size FROM uploads WHERE id = $1"
        )
        .bind(upload_id)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| crate::error::AppError::DatabaseError(e.to_string()))?;

        Ok(result.unwrap_or(false))
    }
}

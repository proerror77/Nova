/// Upload repository - database operations for resumable video uploads
///
/// Provides CRUD operations for upload sessions and chunks matching migration 034
use crate::models::video::{ResumableUpload, UploadChunk};
use chrono::{DateTime, Duration, Utc};
use sqlx::PgPool;
use uuid::Uuid;

// ========================================
// Upload Session Operations
// ========================================

/// Create a new resumable upload session
pub async fn create_upload_session(
    pool: &PgPool,
    video_id: Uuid,
    user_id: Uuid,
    file_name: &str,
    file_size: i64,
    chunk_size: i32,
    s3_bucket: &str,
    s3_key: &str,
    s3_upload_id: &str,
    content_hash: Option<&str>,
) -> Result<ResumableUpload, sqlx::Error> {
    let chunks_total = ((file_size + chunk_size as i64 - 1) / chunk_size as i64) as i32;
    let expires_at = Utc::now() + Duration::days(7);

    sqlx::query_as::<_, ResumableUpload>(
        r#"
        INSERT INTO uploads (
            video_id, user_id, file_name, file_size, chunk_size, chunks_total,
            s3_bucket, s3_key, s3_upload_id, content_hash, expires_at, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'pending')
        ON CONFLICT (video_id, user_id) DO UPDATE
        SET
            file_name = EXCLUDED.file_name,
            file_size = EXCLUDED.file_size,
            chunk_size = EXCLUDED.chunk_size,
            chunks_total = EXCLUDED.chunks_total,
            s3_bucket = EXCLUDED.s3_bucket,
            s3_key = EXCLUDED.s3_key,
            s3_upload_id = EXCLUDED.s3_upload_id,
            content_hash = EXCLUDED.content_hash,
            expires_at = EXCLUDED.expires_at,
            status = 'pending',
            uploaded_size = 0,
            chunks_completed = 0,
            updated_at = NOW()
        RETURNING
            id, user_id, video_id, file_name, file_size, uploaded_size,
            chunk_size, chunks_total, chunks_completed, status,
            s3_upload_id, s3_bucket, s3_key, content_hash,
            expires_at, created_at, updated_at, completed_at
        "#,
    )
    .bind(video_id)
    .bind(user_id)
    .bind(file_name)
    .bind(file_size)
    .bind(chunk_size)
    .bind(chunks_total)
    .bind(s3_bucket)
    .bind(s3_key)
    .bind(s3_upload_id)
    .bind(content_hash)
    .bind(expires_at)
    .fetch_one(pool)
    .await
}

/// Get upload session by ID and user_id (security check)
pub async fn get_upload_session(
    pool: &PgPool,
    session_id: Uuid,
    user_id: Uuid,
) -> Result<Option<ResumableUpload>, sqlx::Error> {
    sqlx::query_as::<_, ResumableUpload>(
        r#"
        SELECT
            id, user_id, video_id, file_name, file_size, uploaded_size,
            chunk_size, chunks_total, chunks_completed, status,
            s3_upload_id, s3_bucket, s3_key, content_hash,
            expires_at, created_at, updated_at, completed_at
        FROM uploads
        WHERE id = $1 AND user_id = $2
        "#,
    )
    .bind(session_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

/// Get upload session by video_id and user_id
pub async fn get_upload_session_by_video(
    pool: &PgPool,
    video_id: Uuid,
    user_id: Uuid,
) -> Result<Option<ResumableUpload>, sqlx::Error> {
    sqlx::query_as::<_, ResumableUpload>(
        r#"
        SELECT
            id, user_id, video_id, file_name, file_size, uploaded_size,
            chunk_size, chunks_total, chunks_completed, status,
            s3_upload_id, s3_bucket, s3_key, content_hash,
            expires_at, created_at, updated_at, completed_at
        FROM uploads
        WHERE video_id = $1 AND user_id = $2
        ORDER BY created_at DESC
        LIMIT 1
        "#,
    )
    .bind(video_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

/// Update upload session status
pub async fn update_upload_status(
    pool: &PgPool,
    session_id: Uuid,
    status: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET status = $1, updated_at = NOW()
        WHERE id = $2
        "#,
    )
    .bind(status)
    .bind(session_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Mark upload as completed
pub async fn mark_upload_completed(
    pool: &PgPool,
    session_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET status = 'completed', completed_at = NOW(), updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(session_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Update upload progress (uploaded_size and chunks_completed)
pub async fn update_upload_progress(
    pool: &PgPool,
    session_id: Uuid,
    uploaded_size: i64,
    chunks_completed: i32,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET uploaded_size = $1, chunks_completed = $2, updated_at = NOW()
        WHERE id = $3
        "#,
    )
    .bind(uploaded_size)
    .bind(chunks_completed)
    .bind(session_id)
    .execute(pool)
    .await?;
    Ok(())
}

// ========================================
// Chunk Operations
// ========================================

/// Create or update a chunk record
pub async fn upsert_chunk(
    pool: &PgPool,
    upload_id: Uuid,
    chunk_number: i32,
    chunk_size: i64,
    etag: &str,
    chunk_hash: Option<&str>,
) -> Result<UploadChunk, sqlx::Error> {
    sqlx::query_as::<_, UploadChunk>(
        r#"
        INSERT INTO upload_chunks (
            upload_id, chunk_number, chunk_size, etag, chunk_hash, status, completed_at
        )
        VALUES ($1, $2, $3, $4, $5, 'completed', NOW())
        ON CONFLICT (upload_id, chunk_number) DO UPDATE
        SET
            etag = EXCLUDED.etag,
            chunk_hash = EXCLUDED.chunk_hash,
            status = 'completed',
            completed_at = NOW(),
            upload_attempts = upload_chunks.upload_attempts + 1
        RETURNING
            id, upload_id, chunk_number, chunk_size, etag, chunk_hash,
            status, upload_attempts, last_error, created_at, completed_at
        "#,
    )
    .bind(upload_id)
    .bind(chunk_number)
    .bind(chunk_size)
    .bind(etag)
    .bind(chunk_hash)
    .fetch_one(pool)
    .await
}

/// Get all chunks for an upload session
pub async fn get_chunks(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<Vec<UploadChunk>, sqlx::Error> {
    sqlx::query_as::<_, UploadChunk>(
        r#"
        SELECT
            id, upload_id, chunk_number, chunk_size, etag, chunk_hash,
            status, upload_attempts, last_error, created_at, completed_at
        FROM upload_chunks
        WHERE upload_id = $1
        ORDER BY chunk_number ASC
        "#,
    )
    .bind(upload_id)
    .fetch_all(pool)
    .await
}

/// Get failed chunks (for retry)
pub async fn get_failed_chunks(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<Vec<i32>, sqlx::Error> {
    let rows: Vec<(i32,)> = sqlx::query_as(
        r#"
        SELECT chunk_number
        FROM upload_chunks
        WHERE upload_id = $1 AND status = 'failed'
        ORDER BY chunk_number ASC
        "#,
    )
    .bind(upload_id)
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(|(n,)| n).collect())
}

/// Get completed chunk count
pub async fn get_completed_chunk_count(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<i64, sqlx::Error> {
    let (count,): (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(*)
        FROM upload_chunks
        WHERE upload_id = $1 AND status = 'completed'
        "#,
    )
    .bind(upload_id)
    .fetch_one(pool)
    .await?;

    Ok(count)
}

/// Get upload progress (optimized query using DB function)
#[derive(Debug, sqlx::FromRow)]
pub struct UploadProgress {
    pub chunks_completed_count: i32,
    pub chunks_failed_count: i32,
    pub uploaded_bytes: i64,
}

pub async fn get_upload_progress(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<UploadProgress, sqlx::Error> {
    sqlx::query_as::<_, UploadProgress>(
        r#"
        SELECT * FROM get_upload_progress($1)
        "#,
    )
    .bind(upload_id)
    .fetch_one(pool)
    .await
}

/// Mark chunk as failed
pub async fn mark_chunk_failed(
    pool: &PgPool,
    upload_id: Uuid,
    chunk_number: i32,
    error_message: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE upload_chunks
        SET
            status = 'failed',
            last_error = $3,
            upload_attempts = upload_attempts + 1
        WHERE upload_id = $1 AND chunk_number = $2
        "#,
    )
    .bind(upload_id)
    .bind(chunk_number)
    .bind(error_message)
    .execute(pool)
    .await?;
    Ok(())
}

// ========================================
// Cleanup Operations
// ========================================

/// Delete upload session and all chunks (cascade)
pub async fn delete_upload_session(
    pool: &PgPool,
    session_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        DELETE FROM uploads WHERE id = $1
        "#,
    )
    .bind(session_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Cleanup expired uploads (call from scheduled task)
pub async fn cleanup_expired_uploads(pool: &PgPool) -> Result<i64, sqlx::Error> {
    let (count,): (i64,) = sqlx::query_as(
        r#"
        SELECT * FROM cleanup_expired_uploads()
        "#,
    )
    .fetch_one(pool)
    .await?;

    Ok(count)
}

// ========================================
// Convenience Aliases (for handler compatibility)
// ========================================

/// Alias for create_upload_session - creates new upload session
pub async fn create_upload(
    pool: &PgPool,
    user_id: Uuid,
    file_name: String,
    file_size: i64,
    chunk_size: i32,
) -> Result<ResumableUpload, sqlx::Error> {
    let s3_key = format!("uploads/{}/{}", user_id, uuid::Uuid::new_v4());
    create_upload_session(
        pool,
        uuid::Uuid::new_v4(), // Generate video_id
        user_id,
        &file_name,
        file_size,
        chunk_size,
        "nova-videos",
        &s3_key,
        "", // s3_upload_id will be set by init_s3_multipart
        None,
    )
    .await
}

/// Alias for get_upload_session_by_video
pub async fn get_upload_by_user(
    pool: &PgPool,
    upload_id: Uuid,
    user_id: Uuid,
) -> Result<Option<ResumableUpload>, sqlx::Error> {
    // Get the upload first to get video_id, then fetch with security check
    sqlx::query_as::<_, ResumableUpload>(
        r#"
        SELECT
            id, user_id, video_id, file_name, file_size, uploaded_size,
            chunk_size, chunks_total, chunks_completed, status,
            s3_upload_id, s3_bucket, s3_key, content_hash,
            expires_at, created_at, updated_at, completed_at
        FROM uploads
        WHERE id = $1 AND user_id = $2
        "#,
    )
    .bind(upload_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

/// Get single chunk by upload_id and chunk_number
pub async fn get_chunk(
    pool: &PgPool,
    upload_id: Uuid,
    chunk_number: i32,
) -> Result<Option<UploadChunk>, sqlx::Error> {
    sqlx::query_as::<_, UploadChunk>(
        r#"
        SELECT
            id, upload_id, chunk_number, chunk_size, etag, chunk_hash,
            status, upload_attempts, last_error, created_at, completed_at
        FROM upload_chunks
        WHERE upload_id = $1 AND chunk_number = $2
        "#,
    )
    .bind(upload_id)
    .bind(chunk_number)
    .fetch_optional(pool)
    .await
}

/// Alias for mark_upload_completed - marks upload session as complete
pub async fn complete_upload(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<(), sqlx::Error> {
    mark_upload_completed(pool, upload_id).await
}

/// Alias for delete_upload_session - cancels upload session
pub async fn cancel_upload(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<(), sqlx::Error> {
    delete_upload_session(pool, upload_id).await
}

/// Get upload session by ID only (without user check - for internal service use)
pub async fn get_upload(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<Option<ResumableUpload>, sqlx::Error> {
    sqlx::query_as::<_, ResumableUpload>(
        r#"
        SELECT
            id, user_id, video_id, file_name, file_size, uploaded_size,
            chunk_size, chunks_total, chunks_completed, status,
            s3_upload_id, s3_bucket, s3_key, content_hash,
            expires_at, created_at, updated_at, completed_at
        FROM uploads
        WHERE id = $1
        "#,
    )
    .bind(upload_id)
    .fetch_optional(pool)
    .await
}

/// Set S3 multipart upload ID for an upload session
pub async fn set_s3_upload_id(
    pool: &PgPool,
    upload_id: Uuid,
    s3_upload_id: String,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET s3_upload_id = $1, updated_at = NOW()
        WHERE id = $2
        "#,
    )
    .bind(s3_upload_id)
    .bind(upload_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Update chunk count - recalculate chunks_completed from database
pub async fn update_chunk_count(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads u
        SET
            chunks_completed = (
                SELECT COUNT(*)::int
                FROM upload_chunks
                WHERE upload_id = u.id AND status = 'completed'
            ),
            uploaded_size = (
                SELECT COALESCE(SUM(chunk_size), 0)
                FROM upload_chunks
                WHERE upload_id = u.id AND status = 'completed'
            ),
            updated_at = NOW()
        WHERE u.id = $1
        "#,
    )
    .bind(upload_id)
    .execute(pool)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chunk_calculation() {
        let file_size = 10_737_418_240i64; // 10GB
        let chunk_size = 5_242_880i32; // 5MB
        let chunks_total = ((file_size + chunk_size as i64 - 1) / chunk_size as i64) as i32;
        assert_eq!(chunks_total, 2048);
    }

    #[test]
    fn test_small_file_chunks() {
        let file_size = 3_000_000i64; // 3MB
        let chunk_size = 5_242_880i32; // 5MB
        let chunks_total = ((file_size + chunk_size as i64 - 1) / chunk_size as i64) as i32;
        assert_eq!(chunks_total, 1);
    }
}

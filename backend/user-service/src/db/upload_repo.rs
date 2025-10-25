use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgPool};
use uuid::Uuid;

/// Upload status enum matching database type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "upload_status", rename_all = "lowercase")]
pub enum UploadStatus {
    Uploading,
    Completed,
    Failed,
    Cancelled,
}

/// Main upload tracking entity
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct UploadEntity {
    pub id: Uuid,
    pub user_id: Uuid,
    pub video_id: Option<Uuid>,
    pub file_name: String,
    pub file_size: i64,
    pub chunk_size: i32,
    pub chunks_total: i32,
    pub chunks_uploaded: i32,
    pub status: UploadStatus,
    pub s3_upload_id: Option<String>,
    pub final_hash: Option<String>,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Individual chunk entity
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct UploadChunkEntity {
    pub id: Uuid,
    pub upload_id: Uuid,
    pub chunk_index: i32,
    pub chunk_size: i64,
    pub chunk_hash: String,
    pub s3_etag: String,
    pub s3_key: String,
    pub uploaded_at: DateTime<Utc>,
}

/// Create new upload session
pub async fn create_upload(
    pool: &PgPool,
    user_id: Uuid,
    file_name: String,
    file_size: i64,
    chunk_size: i32,
) -> Result<UploadEntity, sqlx::Error> {
    let chunks_total = ((file_size as f64) / (chunk_size as f64)).ceil() as i32;

    sqlx::query_as::<_, UploadEntity>(
        r#"
        INSERT INTO uploads (user_id, file_name, file_size, chunk_size, chunks_total)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, user_id, video_id, file_name, file_size, chunk_size, chunks_total,
                  chunks_uploaded, status, s3_upload_id, final_hash, expires_at, created_at, updated_at
        "#,
    )
    .bind(user_id)
    .bind(file_name)
    .bind(file_size)
    .bind(chunk_size)
    .bind(chunks_total)
    .fetch_one(pool)
    .await
}

/// Get upload by ID
pub async fn get_upload(pool: &PgPool, upload_id: Uuid) -> Result<Option<UploadEntity>, sqlx::Error> {
    sqlx::query_as::<_, UploadEntity>(
        r#"
        SELECT id, user_id, video_id, file_name, file_size, chunk_size, chunks_total,
               chunks_uploaded, status, s3_upload_id, final_hash, expires_at, created_at, updated_at
        FROM uploads
        WHERE id = $1
        "#,
    )
    .bind(upload_id)
    .fetch_optional(pool)
    .await
}

/// Get upload by ID with ownership check
pub async fn get_upload_by_user(
    pool: &PgPool,
    upload_id: Uuid,
    user_id: Uuid,
) -> Result<Option<UploadEntity>, sqlx::Error> {
    sqlx::query_as::<_, UploadEntity>(
        r#"
        SELECT id, user_id, video_id, file_name, file_size, chunk_size, chunks_total,
               chunks_uploaded, status, s3_upload_id, final_hash, expires_at, created_at, updated_at
        FROM uploads
        WHERE id = $1 AND user_id = $2
        "#,
    )
    .bind(upload_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

/// Update S3 multipart upload ID
pub async fn set_s3_upload_id(
    pool: &PgPool,
    upload_id: Uuid,
    s3_upload_id: String,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET s3_upload_id = $2, updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(upload_id)
    .bind(s3_upload_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Record uploaded chunk (idempotent)
pub async fn upsert_chunk(
    pool: &PgPool,
    upload_id: Uuid,
    chunk_index: i32,
    chunk_size: i64,
    chunk_hash: String,
    s3_etag: String,
    s3_key: String,
) -> Result<UploadChunkEntity, sqlx::Error> {
    sqlx::query_as::<_, UploadChunkEntity>(
        r#"
        INSERT INTO upload_chunks (upload_id, chunk_index, chunk_size, chunk_hash, s3_etag, s3_key)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (upload_id, chunk_index)
        DO UPDATE SET
            chunk_hash = EXCLUDED.chunk_hash,
            s3_etag = EXCLUDED.s3_etag,
            uploaded_at = NOW()
        RETURNING id, upload_id, chunk_index, chunk_size, chunk_hash, s3_etag, s3_key, uploaded_at
        "#,
    )
    .bind(upload_id)
    .bind(chunk_index)
    .bind(chunk_size)
    .bind(chunk_hash)
    .bind(s3_etag)
    .bind(s3_key)
    .fetch_one(pool)
    .await
}

/// Get all chunks for an upload (ordered by index)
pub async fn get_chunks(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<Vec<UploadChunkEntity>, sqlx::Error> {
    sqlx::query_as::<_, UploadChunkEntity>(
        r#"
        SELECT id, upload_id, chunk_index, chunk_size, chunk_hash, s3_etag, s3_key, uploaded_at
        FROM upload_chunks
        WHERE upload_id = $1
        ORDER BY chunk_index ASC
        "#,
    )
    .bind(upload_id)
    .fetch_all(pool)
    .await
}

/// Get specific chunk
pub async fn get_chunk(
    pool: &PgPool,
    upload_id: Uuid,
    chunk_index: i32,
) -> Result<Option<UploadChunkEntity>, sqlx::Error> {
    sqlx::query_as::<_, UploadChunkEntity>(
        r#"
        SELECT id, upload_id, chunk_index, chunk_size, chunk_hash, s3_etag, s3_key, uploaded_at
        FROM upload_chunks
        WHERE upload_id = $1 AND chunk_index = $2
        "#,
    )
    .bind(upload_id)
    .bind(chunk_index)
    .fetch_optional(pool)
    .await
}

/// Update chunks_uploaded counter
pub async fn update_chunk_count(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<i32, sqlx::Error> {
    use sqlx::Row;

    let row = sqlx::query(
        r#"
        UPDATE uploads
        SET chunks_uploaded = (
            SELECT COUNT(*)::int FROM upload_chunks WHERE upload_id = $1
        ),
        updated_at = NOW()
        WHERE id = $1
        RETURNING chunks_uploaded
        "#,
    )
    .bind(upload_id)
    .fetch_one(pool)
    .await?;

    Ok(row.get::<i32, _>("chunks_uploaded"))
}

/// Mark upload as completed and link to video
pub async fn complete_upload(
    pool: &PgPool,
    upload_id: Uuid,
    video_id: Uuid,
    final_hash: String,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET status = 'completed', video_id = $2, final_hash = $3, updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(upload_id)
    .bind(video_id)
    .bind(final_hash)
    .execute(pool)
    .await?;
    Ok(())
}

/// Mark upload as failed
pub async fn fail_upload(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET status = 'failed', updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(upload_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Cancel upload
pub async fn cancel_upload(
    pool: &PgPool,
    upload_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE uploads
        SET status = 'cancelled', updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(upload_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Get all expired uploads (for cleanup)
pub async fn get_expired_uploads(pool: &PgPool) -> Result<Vec<UploadEntity>, sqlx::Error> {
    sqlx::query_as::<_, UploadEntity>(
        r#"
        SELECT id, user_id, video_id, file_name, file_size, chunk_size, chunks_total,
               chunks_uploaded, status, s3_upload_id, final_hash, expires_at, created_at, updated_at
        FROM uploads
        WHERE status = 'uploading' AND expires_at < NOW()
        "#,
    )
    .fetch_all(pool)
    .await
}

/// Get active uploads for a user
pub async fn get_user_uploads(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<Vec<UploadEntity>, sqlx::Error> {
    sqlx::query_as::<_, UploadEntity>(
        r#"
        SELECT id, user_id, video_id, file_name, file_size, chunk_size, chunks_total,
               chunks_uploaded, status, s3_upload_id, final_hash, expires_at, created_at, updated_at
        FROM uploads
        WHERE user_id = $1 AND status IN ('uploading', 'completed')
        ORDER BY created_at DESC
        LIMIT 20
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}

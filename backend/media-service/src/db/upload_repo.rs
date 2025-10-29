/// Upload repository - database operations for uploads
///
/// This module centralizes all SQLx queries touching the `uploads`
/// table so higher layers (handlers/services) can stay focused on
/// transport and business rules.
use crate::error::Result;
use crate::models::Upload;
use sqlx::PgPool;
use uuid::Uuid;

/// Insert a brand new upload session for the given user.
pub async fn create_upload(
    pool: &PgPool,
    upload_id: Uuid,
    user_id: Uuid,
    file_name: &str,
    file_size: i64,
) -> Result<Upload> {
    let status = "uploading";

    let upload = sqlx::query_as::<_, Upload>(
        "INSERT INTO uploads (
            id, user_id, video_id, file_name, file_size,
            uploaded_size, status, created_at, updated_at
        ) VALUES ($1, $2, NULL, $3, $4, 0, $5, NOW(), NOW())
        RETURNING id, user_id, video_id, file_name, file_size,
                  uploaded_size, status, created_at, updated_at",
    )
    .bind(upload_id)
    .bind(user_id)
    .bind(file_name)
    .bind(file_size)
    .bind(status)
    .fetch_one(pool)
    .await?;

    Ok(upload)
}

/// Fetch a single upload by its identifier.
pub async fn get_upload(pool: &PgPool, upload_id: Uuid) -> Result<Option<Upload>> {
    let upload = sqlx::query_as::<_, Upload>(
        "SELECT id, user_id, video_id, file_name, file_size,
                uploaded_size, status, created_at, updated_at
         FROM uploads WHERE id = $1",
    )
    .bind(upload_id)
    .fetch_optional(pool)
    .await?;

    Ok(upload)
}

/// Fetch recent uploads for a specific user (ordered newest first).
pub async fn get_user_uploads(pool: &PgPool, user_id: Uuid, limit: i32) -> Result<Vec<Upload>> {
    let uploads = sqlx::query_as::<_, Upload>(
        "SELECT id, user_id, video_id, file_name, file_size,
                uploaded_size, status, created_at, updated_at
         FROM uploads
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT $2",
    )
    .bind(user_id)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(uploads)
}

/// Update the uploaded size field and return the refreshed row.
pub async fn update_uploaded_size(
    pool: &PgPool,
    upload_id: Uuid,
    uploaded_size: i64,
) -> Result<Option<Upload>> {
    let upload = sqlx::query_as::<_, Upload>(
        "UPDATE uploads
         SET uploaded_size = $2, updated_at = NOW()
         WHERE id = $1
         RETURNING id, user_id, video_id, file_name, file_size,
                   uploaded_size, status, created_at, updated_at",
    )
    .bind(upload_id)
    .bind(uploaded_size)
    .fetch_optional(pool)
    .await?;

    Ok(upload)
}

/// Update the upload status (`uploading`, `completed`, `cancelled`, etc.).
pub async fn update_status(pool: &PgPool, upload_id: Uuid, status: &str) -> Result<Option<Upload>> {
    let upload = sqlx::query_as::<_, Upload>(
        "UPDATE uploads
         SET status = $2, updated_at = NOW()
         WHERE id = $1
         RETURNING id, user_id, video_id, file_name, file_size,
                   uploaded_size, status, created_at, updated_at",
    )
    .bind(upload_id)
    .bind(status)
    .fetch_optional(pool)
    .await?;

    Ok(upload)
}

/// Cancel an upload by setting its status to `cancelled`.
pub async fn cancel_upload(pool: &PgPool, upload_id: Uuid) -> Result<bool> {
    let result = sqlx::query(
        "UPDATE uploads
         SET status = 'cancelled', updated_at = NOW()
         WHERE id = $1",
    )
    .bind(upload_id)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}

/// Determine whether the uploaded bytes match the expected file size.
pub async fn is_complete(pool: &PgPool, upload_id: Uuid) -> Result<bool> {
    let result = sqlx::query_scalar::<_, bool>(
        "SELECT file_size = uploaded_size FROM uploads WHERE id = $1",
    )
    .bind(upload_id)
    .fetch_optional(pool)
    .await?;

    Ok(result.unwrap_or(false))
}

/// Upload handlers - HTTP endpoints for upload operations
use actix_web::web;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::models::{StartUploadRequest, Upload, UploadResponse};

/// Start a new upload session
pub async fn start_upload(
    pool: web::Data<PgPool>,
    user_id: Uuid,
    req: web::Json<StartUploadRequest>,
) -> Result<actix_web::HttpResponse> {
    if req.file_name.is_empty() || req.file_size <= 0 {
        return Err(AppError::BadRequest("Invalid file name or size".to_string()));
    }

    let upload_id = Uuid::new_v4();
    let status = "uploading";

    let upload = sqlx::query_as::<_, Upload>(
        "INSERT INTO uploads (id, user_id, video_id, file_name, file_size, \
         uploaded_size, status, created_at, updated_at) \
         VALUES ($1, $2, NULL, $3, $4, 0, $5, NOW(), NOW()) \
         RETURNING id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at"
    )
    .bind(upload_id)
    .bind(user_id)
    .bind(&req.file_name)
    .bind(req.file_size)
    .bind(status)
    .fetch_one(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(actix_web::HttpResponse::Created().json(UploadResponse::from(upload)))
}

/// Get upload progress
pub async fn get_upload(
    pool: web::Data<PgPool>,
    upload_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let upload = sqlx::query_as::<_, Upload>(
        "SELECT id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at \
         FROM uploads WHERE id = $1"
    )
    .bind(upload_uuid)
    .fetch_optional(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?
    .ok_or(AppError::NotFound("Upload not found".to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Update upload progress
pub async fn update_upload_progress(
    pool: web::Data<PgPool>,
    upload_id: web::Path<String>,
    progress: web::Json<serde_json::Value>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let uploaded_size: i64 = progress
        .get("uploaded_size")
        .and_then(|v| v.as_i64())
        .ok_or(AppError::BadRequest("Invalid uploaded_size".to_string()))?;

    let upload = sqlx::query_as::<_, Upload>(
        "UPDATE uploads SET uploaded_size = $2, updated_at = NOW() WHERE id = $1 \
         RETURNING id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at"
    )
    .bind(upload_uuid)
    .bind(uploaded_size)
    .fetch_one(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Complete an upload
pub async fn complete_upload(
    pool: web::Data<PgPool>,
    upload_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let upload = sqlx::query_as::<_, Upload>(
        "UPDATE uploads SET status = 'completed', updated_at = NOW() WHERE id = $1 \
         RETURNING id, user_id, video_id, file_name, file_size, uploaded_size, status, created_at, updated_at"
    )
    .bind(upload_uuid)
    .fetch_one(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(UploadResponse::from(upload)))
}

/// Cancel an upload
pub async fn cancel_upload(
    pool: web::Data<PgPool>,
    upload_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let upload_uuid = Uuid::parse_str(&upload_id)
        .map_err(|_| AppError::BadRequest("Invalid upload ID".to_string()))?;

    let result = sqlx::query("UPDATE uploads SET status = 'cancelled', updated_at = NOW() WHERE id = $1")
        .bind(upload_uuid)
        .execute(pool.get_ref())
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Upload not found".to_string()));
    }

    Ok(actix_web::HttpResponse::NoContent().finish())
}

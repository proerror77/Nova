/// Reel handlers - HTTP endpoints for reel operations
use actix_web::web;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::models::{CreateReelRequest, Reel, ReelResponse};

/// List all reels
pub async fn list_reels(pool: web::Data<PgPool>) -> Result<actix_web::HttpResponse> {
    let reels = sqlx::query_as::<_, Reel>(
        "SELECT id, creator_id, video_id, title, music, created_at, updated_at \
         FROM reels ORDER BY created_at DESC LIMIT 100"
    )
    .fetch_all(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    let responses: Vec<ReelResponse> = reels.into_iter().map(|r| r.into()).collect();
    Ok(actix_web::HttpResponse::Ok().json(responses))
}

/// Get a specific reel
pub async fn get_reel(
    pool: web::Data<PgPool>,
    reel_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let reel_uuid = Uuid::parse_str(&reel_id)
        .map_err(|_| AppError::BadRequest("Invalid reel ID".to_string()))?;

    let reel = sqlx::query_as::<_, Reel>(
        "SELECT id, creator_id, video_id, title, music, created_at, updated_at \
         FROM reels WHERE id = $1"
    )
    .bind(reel_uuid)
    .fetch_optional(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?
    .ok_or(AppError::NotFound("Reel not found".to_string()))?;

    Ok(actix_web::HttpResponse::Ok().json(ReelResponse::from(reel)))
}

/// Create a new reel
pub async fn create_reel(
    pool: web::Data<PgPool>,
    creator_id: Uuid,
    req: web::Json<CreateReelRequest>,
) -> Result<actix_web::HttpResponse> {
    if req.title.is_empty() {
        return Err(AppError::BadRequest("Title is required".to_string()));
    }

    let video_id = Uuid::parse_str(&req.video_id)
        .map_err(|_| AppError::BadRequest("Invalid video ID".to_string()))?;

    let reel_id = Uuid::new_v4();

    let reel = sqlx::query_as::<_, Reel>(
        "INSERT INTO reels (id, creator_id, video_id, title, music, created_at, updated_at) \
         VALUES ($1, $2, $3, $4, $5, NOW(), NOW()) \
         RETURNING id, creator_id, video_id, title, music, created_at, updated_at"
    )
    .bind(reel_id)
    .bind(creator_id)
    .bind(video_id)
    .bind(&req.title)
    .bind(&req.music)
    .fetch_one(pool.get_ref())
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(actix_web::HttpResponse::Created().json(ReelResponse::from(reel)))
}

/// Delete a reel
pub async fn delete_reel(
    pool: web::Data<PgPool>,
    reel_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let reel_uuid = Uuid::parse_str(&reel_id)
        .map_err(|_| AppError::BadRequest("Invalid reel ID".to_string()))?;

    let result = sqlx::query("DELETE FROM reels WHERE id = $1")
        .bind(reel_uuid)
        .execute(pool.get_ref())
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Reel not found".to_string()));
    }

    Ok(actix_web::HttpResponse::NoContent().finish())
}

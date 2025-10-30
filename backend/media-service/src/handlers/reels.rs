/// Reel handlers - HTTP endpoints for reel operations
use actix_web::{web, HttpRequest};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::models::CreateReelRequest;
use crate::services::{ReelService, ReelTranscodePipeline};

const USER_ID_HEADER: &str = "x-user-id";

/// List all reels (default limit: 50)
pub async fn list_reels(pool: web::Data<PgPool>) -> Result<actix_web::HttpResponse> {
    let service = ReelService::new(pool.get_ref().clone());
    let reels = service.list_reels(50).await?;
    Ok(actix_web::HttpResponse::Ok().json(reels))
}

/// Get a specific reel by ID
pub async fn get_reel(
    pool: web::Data<PgPool>,
    reel_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let reel_uuid = Uuid::parse_str(&reel_id)
        .map_err(|_| AppError::BadRequest("Invalid reel ID".to_string()))?;

    let service = ReelService::new(pool.get_ref().clone());
    let reel = service.get_reel(reel_uuid).await?;

    Ok(actix_web::HttpResponse::Ok().json(reel))
}

/// Create a new reel and kick off transcoding pipeline
pub async fn create_reel(
    req: HttpRequest,
    pool: web::Data<PgPool>,
    pipeline: web::Data<ReelTranscodePipeline>,
    payload: web::Json<CreateReelRequest>,
) -> Result<actix_web::HttpResponse> {
    let creator_id = extract_user_id(&req)?;
    let service = ReelService::new(pool.get_ref().clone());
    let reel = service
        .create_reel(creator_id, payload.into_inner(), pipeline.get_ref())
        .await?;

    Ok(actix_web::HttpResponse::Created().json(reel))
}

/// Delete (soft-delete) a reel
pub async fn delete_reel(
    pool: web::Data<PgPool>,
    reel_id: web::Path<String>,
) -> Result<actix_web::HttpResponse> {
    let reel_uuid = Uuid::parse_str(&reel_id)
        .map_err(|_| AppError::BadRequest("Invalid reel ID".to_string()))?;

    let service = ReelService::new(pool.get_ref().clone());
    service.delete_reel(reel_uuid).await?;

    Ok(actix_web::HttpResponse::NoContent().finish())
}

fn extract_user_id(req: &HttpRequest) -> Result<Uuid> {
    let header_value = req
        .headers()
        .get(USER_ID_HEADER)
        .ok_or_else(|| AppError::Unauthorized("Missing x-user-id header".into()))?;

    let value = header_value
        .to_str()
        .map_err(|_| AppError::Unauthorized("Invalid x-user-id header".into()))?;

    Uuid::parse_str(value)
        .map_err(|_| AppError::Unauthorized("Invalid x-user-id header value".into()))
}

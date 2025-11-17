use actix_web::{get, post, put, web, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    error::AppError,
    services::moderation_service::{
        CreateModerationActionRequest, CreateReportRequest, ModerationService,
    },
};

#[derive(Debug, Deserialize)]
pub struct CreateReportPayload {
    pub reported_user_id: Option<Uuid>,
    pub reason_code: String,
    pub target_type: String,
    pub target_id: Uuid,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateActionPayload {
    pub report_id: Option<Uuid>,
    pub action_type: String,
    pub target_type: String,
    pub target_id: Uuid,
    pub duration_days: Option<i32>,
    pub reason: Option<String>,
    pub notes: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateReportPayload {
    pub status: String,
}

#[derive(Debug, Serialize)]
pub struct ReportResponse {
    pub id: Uuid,
    pub status: String,
}

#[post("/api/v1/reports")]
pub async fn create_report(
    db: web::Data<PgPool>,
    _req: HttpRequest,
    payload: web::Json<CreateReportPayload>,
) -> Result<HttpResponse, AppError> {
    // Placeholder: In production, extract from JWT via middleware
    let reporter_id = Uuid::new_v4();

    let request = CreateReportRequest {
        reporter_id,
        reported_user_id: payload.reported_user_id,
        reason_code: payload.reason_code.clone(),
        target_type: payload.target_type.clone(),
        target_id: payload.target_id,
        description: payload.description.clone(),
    };

    let report = ModerationService::create_report(db.as_ref(), request)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to create report: {}", e)))?;

    Ok(HttpResponse::Created().json(ReportResponse {
        id: report.id,
        status: report.status,
    }))
}

#[get("/api/v1/reports")]
pub async fn get_reports(
    db: web::Data<PgPool>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> Result<HttpResponse, AppError> {
    let status = query.get("status").map(|s| s.as_str());
    let limit = query
        .get("limit")
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(20);
    let offset = query
        .get("offset")
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(0);

    let (reports, total) = ModerationService::get_reports(db.as_ref(), status, limit, offset)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch reports: {}", e)))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "reports": reports,
        "total": total,
        "limit": limit,
        "offset": offset
    })))
}

#[put("/api/v1/reports/{report_id}")]
pub async fn update_report_status(
    db: web::Data<PgPool>,
    report_id: web::Path<Uuid>,
    payload: web::Json<UpdateReportPayload>,
) -> Result<HttpResponse, AppError> {
    let report = ModerationService::update_report_status(
        db.as_ref(),
        report_id.into_inner(),
        &payload.status,
    )
    .await
    .map_err(|e| AppError::Internal(format!("Failed to update report: {}", e)))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": report.id,
        "status": report.status,
        "updated_at": report.updated_at
    })))
}

#[post("/api/v1/moderation/actions")]
pub async fn create_moderation_action(
    db: web::Data<PgPool>,
    _req: HttpRequest,
    payload: web::Json<CreateActionPayload>,
) -> Result<HttpResponse, AppError> {
    // Placeholder: In production, extract from JWT via middleware
    let moderator_id = Uuid::new_v4();

    let request = CreateModerationActionRequest {
        report_id: payload.report_id,
        moderator_id,
        action_type: payload.action_type.clone(),
        target_type: payload.target_type.clone(),
        target_id: payload.target_id,
        duration_days: payload.duration_days,
        reason: payload.reason.clone(),
        notes: payload.notes.clone(),
    };

    let action = ModerationService::create_action(db.as_ref(), request)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to create action: {}", e)))?;

    Ok(HttpResponse::Created().json(serde_json::json!({
        "id": action.id,
        "action_type": action.action_type,
        "status": action.status
    })))
}

#[get("/api/v1/users/{user_id}/restrictions")]
pub async fn get_user_restrictions(
    db: web::Data<PgPool>,
    user_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let actions = ModerationService::get_user_restrictions(db.as_ref(), user_id.into_inner())
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch restrictions: {}", e)))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "restrictions": actions,
        "count": actions.len()
    })))
}

#[get("/api/v1/moderation/queue/stats")]
pub async fn get_queue_stats(db: web::Data<PgPool>) -> Result<HttpResponse, AppError> {
    let stats = ModerationService::get_queue_stats(db.as_ref())
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch queue stats: {}", e)))?;

    Ok(HttpResponse::Ok().json(stats))
}

#[post("/api/v1/moderation/actions/{action_id}/appeal")]
pub async fn appeal_action(
    db: web::Data<PgPool>,
    _req: HttpRequest,
    action_id: web::Path<Uuid>,
    payload: web::Json<serde_json::Value>,
) -> Result<HttpResponse, AppError> {
    // Placeholder: In production, extract from JWT via middleware
    let user_id = Uuid::new_v4();
    let reason = payload
        .get("reason")
        .and_then(|v| v.as_str())
        .unwrap_or("No reason provided");

    ModerationService::appeal_action(db.as_ref(), action_id.into_inner(), user_id, reason)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to submit appeal: {}", e)))?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": "Appeal submitted successfully"
    })))
}

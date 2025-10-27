use actix_web::{
    web, Either, Error as ActixError, HttpMessage, HttpRequest, HttpResponse, Result as ActixResult,
};
use anyhow::Error;
use serde::Deserialize;
use serde_json::json;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;
use validator::Validate;

use crate::error::AppError;
use crate::middleware::jwt_auth::UserId;
use crate::services::streaming::{
    CreateStreamRequest, RtmpWebhookHandler, StreamAnalyticsService, StreamCategory, StreamCommand,
    StreamComment, StreamDiscoveryService,
};
use tokio::sync::mpsc;

/// Shared state for streaming handlers
pub struct StreamHandlerState {
    pub stream_tx: mpsc::Sender<StreamCommand>,
    pub discovery_service: Arc<Mutex<StreamDiscoveryService>>,
    pub analytics_service: Arc<StreamAnalyticsService>,
    pub rtmp_handler: Arc<Mutex<RtmpWebhookHandler>>,
}

#[allow(dead_code)]
fn _assert_stream_handler_state_send_sync() {
    fn assert_send_sync<T: Send + Sync>() {}
    assert_send_sync::<StreamHandlerState>();
}

#[derive(Debug, Deserialize)]
pub struct StreamListQuery {
    #[serde(default = "default_page")]
    pub page: i32,
    #[serde(default = "default_limit")]
    pub limit: i32,
    pub category: Option<StreamCategory>,
}

fn default_page() -> i32 {
    1
}

fn default_limit() -> i32 {
    20
}

#[derive(Debug, Deserialize)]
pub struct StreamSearchQuery {
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i32,
}

#[derive(Debug, Deserialize, Validate)]
pub struct StreamCommentPayload {
    #[validate(length(min = 1, max = 500))]
    pub message: String,
}

#[derive(Debug, Deserialize)]
pub struct CommentQuery {
    #[serde(default = "default_limit")]
    pub limit: i32,
}

#[derive(Debug, Deserialize)]
pub struct RtmpAuthRequest {
    #[serde(alias = "name", alias = "stream", alias = "stream_key")]
    pub stream_key: String,
    #[serde(default)]
    pub client_ip: Option<String>,
}

pub async fn create_stream(
    req: HttpRequest,
    state: web::Data<StreamHandlerState>,
    payload: web::Json<CreateStreamRequest>,
) -> ActixResult<HttpResponse> {
    let user_id = extract_user_id(&req).map_err(map_app_error)?;
    payload
        .validate()
        .map_err(AppError::from)
        .map_err(map_app_error)?;

    let response = crate::services::streaming::stream_handler_adapter::create_stream(
        &state.stream_tx,
        user_id,
        payload.into_inner(),
    )
    .await
    .map_err(map_anyhow)?;

    Ok(HttpResponse::Created().json(response))
}

pub async fn list_live_streams(
    query: web::Query<StreamListQuery>,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let params = query.into_inner();
    let response =
        crate::services::streaming::stream_handler_adapter::list_live_streams(
            &state.stream_tx,
            params.category,
            params.page,
            params.limit,
        )
        .await
        .map_err(map_anyhow)?;
    Ok(HttpResponse::Ok().json(response))
}

pub async fn search_streams(
    query: web::Query<StreamSearchQuery>,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let params = query.into_inner();
    let mut service = state.discovery_service.lock().await;
    let streams = service
        .search_streams(&params.q, params.limit)
        .await
        .map_err(map_anyhow)?;
    Ok(HttpResponse::Ok().json(streams))
}

pub async fn get_stream_details(
    path: web::Path<Uuid>,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let stream_id = path.into_inner();
    let details = crate::services::streaming::stream_handler_adapter::get_stream_details(
        &state.stream_tx,
        stream_id,
    )
    .await
    .map_err(map_anyhow)?;
    Ok(HttpResponse::Ok().json(details))
}

pub async fn join_stream(
    path: web::Path<Uuid>,
    req: HttpRequest,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let stream_id = path.into_inner();
    let user_id = extract_user_id(&req).map_err(map_app_error)?;
    let response = crate::services::streaming::stream_handler_adapter::join_stream(
        &state.stream_tx,
        stream_id,
        user_id,
    )
    .await
    .map_err(map_anyhow)?;
    Ok(HttpResponse::Ok().json(response))
}

pub async fn leave_stream(
    path: web::Path<Uuid>,
    req: HttpRequest,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let stream_id = path.into_inner();
    let user_id = extract_user_id(&req).map_err(map_app_error)?;
    crate::services::streaming::stream_handler_adapter::leave_stream(
        &state.stream_tx,
        stream_id,
        user_id,
    )
    .await
    .map_err(map_anyhow)?;
    Ok(HttpResponse::Accepted().json(json!({ "success": true })))
}

pub async fn post_stream_comment(
    path: web::Path<Uuid>,
    req: HttpRequest,
    state: web::Data<StreamHandlerState>,
    payload: web::Json<StreamCommentPayload>,
) -> ActixResult<HttpResponse> {
    payload
        .validate()
        .map_err(AppError::from)
        .map_err(map_app_error)?;
    let stream_id = path.into_inner();
    let user_id = extract_user_id(&req).map_err(map_app_error)?;

    let message = payload.message.trim();
    if message.is_empty() {
        return Err(AppError::Validation("Comment cannot be empty".into()).into());
    }

    let comment = StreamComment::new(stream_id, user_id, None, message.to_string());
    let saved = crate::services::streaming::stream_handler_adapter::post_comment(
        &state.stream_tx,
        comment,
    )
    .await
    .map_err(map_anyhow)?;

    Ok(HttpResponse::Ok().json(saved))
}

pub async fn get_stream_comments(
    path: web::Path<Uuid>,
    query: web::Query<CommentQuery>,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let stream_id = path.into_inner();
    let params = query.into_inner();
    let comments = crate::services::streaming::stream_handler_adapter::recent_comments(
        &state.stream_tx,
        stream_id,
        params.limit.max(1) as usize,
    )
    .await
    .map_err(map_anyhow)?;

    Ok(HttpResponse::Ok().json(comments))
}

pub async fn get_stream_analytics(
    path: web::Path<Uuid>,
    req: HttpRequest,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let stream_id = path.into_inner();
    let user_id = extract_user_id(&req).map_err(map_app_error)?;

    let details = crate::services::streaming::stream_handler_adapter::get_stream_details(
        &state.stream_tx,
        stream_id,
    )
    .await
    .map_err(map_anyhow)?;

    if details.creator.id != user_id {
        return Err(AppError::Authorization("Only the creator can access analytics".into()).into());
    }

    let analytics = state
        .analytics_service
        .get_stream_analytics(stream_id)
        .await
        .map_err(map_anyhow)?;

    Ok(HttpResponse::Ok().json(analytics))
}

pub async fn rtmp_authenticate(
    payload: Either<web::Json<RtmpAuthRequest>, web::Form<RtmpAuthRequest>>,
    state: web::Data<StreamHandlerState>,
    req: HttpRequest,
) -> ActixResult<HttpResponse> {
    let payload = match payload {
        Either::Left(json) => json.into_inner(),
        Either::Right(form) => form.into_inner(),
    };

    let client_ip = payload
        .client_ip
        .or_else(|| {
            req.connection_info()
                .realip_remote_addr()
                .map(|s| s.to_string())
        })
        .unwrap_or_else(|| "unknown".to_string());

    let mut handler = state.rtmp_handler.lock().await;
    if handler
        .authenticate_stream(&payload.stream_key, &client_ip)
        .await
        .map_err(map_anyhow)?
    {
        Ok(HttpResponse::Ok().json(json!({"authorized": true})))
    } else {
        Ok(HttpResponse::Unauthorized().json(json!({"authorized": false})))
    }
}

pub async fn rtmp_done(
    payload: Either<web::Json<RtmpAuthRequest>, web::Form<RtmpAuthRequest>>,
    state: web::Data<StreamHandlerState>,
) -> ActixResult<HttpResponse> {
    let payload = match payload {
        Either::Left(json) => json.into_inner(),
        Either::Right(form) => form.into_inner(),
    };

    let mut handler = state.rtmp_handler.lock().await;
    handler
        .on_stream_done(&payload.stream_key)
        .await
        .map_err(map_anyhow)?;
    Ok(HttpResponse::Ok().json(json!({"success": true})))
}

fn extract_user_id(req: &HttpRequest) -> std::result::Result<Uuid, AppError> {
    req.extensions()
        .get::<UserId>()
        .map(|id| id.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))
}

fn map_anyhow(err: Error) -> ActixError {
    AppError::Internal(err.to_string()).into()
}

fn map_app_error(err: AppError) -> ActixError {
    err.into()
}

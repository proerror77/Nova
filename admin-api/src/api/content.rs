use axum::{
    extract::{ConnectInfo, Path, Query, State},
    http::HeaderMap,
    routing::{get, post},
    Extension, Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::middleware::CurrentAdmin;
use crate::models::{AuditAction, CreateAuditLog, ResourceType};
use crate::services::{AuditService, ContentService, ListContentParams};
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/posts", get(list_posts))
        .route("/posts/:id", get(get_post))
        .route("/posts/:id/approve", post(approve_post))
        .route("/posts/:id/reject", post(reject_post))
        .route("/posts/:id/remove", post(remove_post))
        .route("/posts/:id/restore", post(restore_post))
        .route("/comments", get(list_comments))
        .route("/comments/:id/approve", post(approve_comment))
        .route("/comments/:id/reject", post(reject_comment))
        .route("/comments/:id/remove", post(remove_comment))
        .route("/moderation-queue", get(get_moderation_queue))
}

#[derive(Debug, Deserialize)]
pub struct ListContentQuery {
    pub page: Option<u32>,
    pub limit: Option<u32>,
    pub status: Option<String>,
    pub search: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PostListResponse {
    pub posts: Vec<PostSummaryResponse>,
    pub total: i64,
    pub page: u32,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct PostSummaryResponse {
    pub id: String,
    pub author_id: String,
    pub content_preview: String,
    pub status: String,
    pub images_count: i32,
    pub likes_count: i64,
    pub comments_count: i64,
    pub reports_count: i64,
    pub created_at: String,
}

async fn list_posts(
    State(state): State<AppState>,
    Query(query): Query<ListContentQuery>,
) -> Result<Json<PostListResponse>> {
    let page = query.page.unwrap_or(1).max(1);
    let limit = query.limit.unwrap_or(20).min(100);

    let content_service = ContentService::new(state.db.clone());
    let (posts, total) = content_service.list_posts(ListContentParams {
        page,
        limit,
        status: query.status,
        search: query.search,
    }).await?;

    // Get report counts for each post
    let mut posts_response = Vec::new();
    for post in posts {
        let reports_count = content_service.get_reports_count("post", post.id).await.unwrap_or(0);

        // Create content preview (first 100 chars)
        let content_preview = if post.content.len() > 100 {
            format!("{}...", &post.content[..100])
        } else {
            post.content.clone()
        };

        posts_response.push(PostSummaryResponse {
            id: post.id.to_string(),
            author_id: post.user_id.to_string(),
            content_preview,
            status: post.status,
            images_count: post.images_count,
            likes_count: post.likes_count,
            comments_count: post.comments_count,
            reports_count,
            created_at: post.created_at.to_rfc3339(),
        });
    }

    Ok(Json(PostListResponse {
        posts: posts_response,
        total,
        page,
        limit,
    }))
}

#[derive(Debug, Serialize)]
pub struct PostDetailResponse {
    pub id: String,
    pub author: Option<AuthorInfoResponse>,
    pub content: String,
    pub images: Vec<String>,
    pub status: String,
    pub stats: PostStatsResponse,
    pub reports: Vec<ReportSummaryResponse>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize)]
pub struct AuthorInfoResponse {
    pub id: String,
    pub nickname: String,
    pub avatar: Option<String>,
    pub warnings_count: i64,
    pub is_banned: bool,
}

#[derive(Debug, Serialize)]
pub struct PostStatsResponse {
    pub likes_count: i64,
    pub comments_count: i64,
    pub shares_count: i64,
    pub reports_count: i64,
}

#[derive(Debug, Serialize)]
pub struct ReportSummaryResponse {
    pub id: String,
    pub reason: String,
    pub reporter_id: String,
    pub status: String,
    pub created_at: String,
}

async fn get_post(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> Result<Json<PostDetailResponse>> {
    let post_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid post ID".to_string()))?;

    let content_service = ContentService::new(state.db.clone());
    let post = content_service.get_post(post_id).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let admin_id = current_admin.id.parse().unwrap_or_default();
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::ViewContent,
        resource_type: ResourceType::Post,
        resource_id: Some(id.clone()),
        details: None,
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(PostDetailResponse {
        id: post.id.to_string(),
        author: post.author.map(|a| AuthorInfoResponse {
            id: a.id.to_string(),
            nickname: a.nickname,
            avatar: a.avatar,
            warnings_count: a.warnings_count,
            is_banned: a.is_banned,
        }),
        content: post.content,
        images: post.images,
        status: post.status,
        stats: PostStatsResponse {
            likes_count: post.likes_count,
            comments_count: post.comments_count,
            shares_count: post.shares_count,
            reports_count: post.reports.len() as i64,
        },
        reports: post.reports.into_iter().map(|r| ReportSummaryResponse {
            id: r.id.to_string(),
            reason: r.reason,
            reporter_id: r.reporter_id.to_string(),
            status: r.status,
            created_at: r.created_at.to_rfc3339(),
        }).collect(),
        created_at: post.created_at.to_rfc3339(),
        updated_at: post.updated_at.to_rfc3339(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct ModerationRequest {
    pub notes: Option<String>,
}

async fn approve_post(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<ModerationRequest>,
) -> Result<Json<serde_json::Value>> {
    let post_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid post ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    // Check permission
    if !current_admin.role.can_moderate_content() {
        return Err(AppError::Forbidden);
    }

    let content_service = ContentService::new(state.db.clone());
    content_service.approve_post(post_id, admin_id, payload.notes.as_deref()).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::ApproveContent,
        resource_type: ResourceType::Post,
        resource_id: Some(id.clone()),
        details: payload.notes.map(|n| serde_json::json!({ "notes": n })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Post {} has been approved", id),
    })))
}

#[derive(Debug, Deserialize)]
pub struct RejectRequest {
    pub reason: String,
    pub notes: Option<String>,
}

async fn reject_post(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<RejectRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.trim().is_empty() {
        return Err(AppError::BadRequest("Rejection reason is required".to_string()));
    }

    let post_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid post ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    // Check permission
    if !current_admin.role.can_moderate_content() {
        return Err(AppError::Forbidden);
    }

    let content_service = ContentService::new(state.db.clone());
    content_service.reject_post(post_id, admin_id, &payload.reason, payload.notes.as_deref()).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::RejectContent,
        resource_type: ResourceType::Post,
        resource_id: Some(id.clone()),
        details: Some(serde_json::json!({
            "reason": payload.reason,
            "notes": payload.notes,
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Post {} has been rejected", id),
        "reason": payload.reason,
    })))
}

#[derive(Debug, Serialize)]
pub struct CommentListResponse {
    pub comments: Vec<CommentSummaryResponse>,
    pub total: i64,
    pub page: u32,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct CommentSummaryResponse {
    pub id: String,
    pub post_id: String,
    pub author_id: String,
    pub content: String,
    pub status: String,
    pub reports_count: i64,
    pub created_at: String,
}

async fn list_comments(
    State(state): State<AppState>,
    Query(query): Query<ListContentQuery>,
) -> Result<Json<CommentListResponse>> {
    let page = query.page.unwrap_or(1).max(1);
    let limit = query.limit.unwrap_or(20).min(100);

    let content_service = ContentService::new(state.db.clone());
    let (comments, total) = content_service.list_comments(ListContentParams {
        page,
        limit,
        status: query.status,
        search: query.search,
    }).await?;

    let mut comments_response = Vec::new();
    for comment in comments {
        let reports_count = content_service.get_reports_count("comment", comment.id).await.unwrap_or(0);

        comments_response.push(CommentSummaryResponse {
            id: comment.id.to_string(),
            post_id: comment.post_id.to_string(),
            author_id: comment.user_id.to_string(),
            content: comment.content,
            status: comment.status,
            reports_count,
            created_at: comment.created_at.to_rfc3339(),
        });
    }

    Ok(Json(CommentListResponse {
        comments: comments_response,
        total,
        page,
        limit,
    }))
}

async fn approve_comment(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<ModerationRequest>,
) -> Result<Json<serde_json::Value>> {
    let comment_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid comment ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    if !current_admin.role.can_moderate_content() {
        return Err(AppError::Forbidden);
    }

    let content_service = ContentService::new(state.db.clone());
    content_service.approve_comment(comment_id, admin_id, payload.notes.as_deref()).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::ApproveContent,
        resource_type: ResourceType::Comment,
        resource_id: Some(id.clone()),
        details: payload.notes.map(|n| serde_json::json!({ "notes": n })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Comment {} has been approved", id),
    })))
}

async fn reject_comment(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<RejectRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.trim().is_empty() {
        return Err(AppError::BadRequest("Rejection reason is required".to_string()));
    }

    let comment_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid comment ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    if !current_admin.role.can_moderate_content() {
        return Err(AppError::Forbidden);
    }

    let content_service = ContentService::new(state.db.clone());
    content_service.reject_comment(comment_id, admin_id, &payload.reason, payload.notes.as_deref()).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::RejectContent,
        resource_type: ResourceType::Comment,
        resource_id: Some(id.clone()),
        details: Some(serde_json::json!({
            "reason": payload.reason,
            "notes": payload.notes,
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Comment {} has been rejected", id),
        "reason": payload.reason,
    })))
}

// Remove post (soft delete)
async fn remove_post(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<RejectRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.trim().is_empty() {
        return Err(AppError::BadRequest("Removal reason is required".to_string()));
    }

    let post_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid post ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    if !current_admin.role.can_moderate_content() {
        return Err(AppError::Forbidden);
    }

    let content_service = ContentService::new(state.db.clone());
    content_service.remove_post(post_id, admin_id, &payload.reason, payload.notes.as_deref()).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::RemoveContent,
        resource_type: ResourceType::Post,
        resource_id: Some(id.clone()),
        details: Some(serde_json::json!({
            "reason": payload.reason,
            "notes": payload.notes,
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Post {} has been removed", id),
        "reason": payload.reason,
    })))
}

// Restore post
async fn restore_post(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<ModerationRequest>,
) -> Result<Json<serde_json::Value>> {
    let post_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid post ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    if !current_admin.role.can_moderate_content() {
        return Err(AppError::Forbidden);
    }

    let content_service = ContentService::new(state.db.clone());
    content_service.restore_post(post_id, admin_id, payload.notes.as_deref()).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::RestoreContent,
        resource_type: ResourceType::Post,
        resource_id: Some(id.clone()),
        details: payload.notes.map(|n| serde_json::json!({ "notes": n })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Post {} has been restored", id),
    })))
}

// Remove comment (soft delete)
async fn remove_comment(
    State(state): State<AppState>,
    Extension(current_admin): Extension<CurrentAdmin>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(payload): Json<RejectRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.trim().is_empty() {
        return Err(AppError::BadRequest("Removal reason is required".to_string()));
    }

    let comment_id = Uuid::parse_str(&id)
        .map_err(|_| AppError::BadRequest("Invalid comment ID".to_string()))?;
    let admin_id: Uuid = current_admin.id.parse()
        .map_err(|_| AppError::BadRequest("Invalid admin ID".to_string()))?;

    if !current_admin.role.can_moderate_content() {
        return Err(AppError::Forbidden);
    }

    let content_service = ContentService::new(state.db.clone());
    content_service.remove_comment(comment_id, admin_id, &payload.reason, payload.notes.as_deref()).await?;

    // Log audit event
    let audit_service = AuditService::new(state.db.clone());
    let _ = audit_service.log(CreateAuditLog {
        admin_id,
        action: AuditAction::RemoveContent,
        resource_type: ResourceType::Comment,
        resource_id: Some(id.clone()),
        details: Some(serde_json::json!({
            "reason": payload.reason,
            "notes": payload.notes,
        })),
        ip_address: Some(addr.ip().to_string()),
        user_agent: headers.get("user-agent").and_then(|v| v.to_str().ok()).map(String::from),
    }).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "message": format!("Comment {} has been removed", id),
        "reason": payload.reason,
    })))
}

// Moderation queue response
#[derive(Debug, Serialize)]
pub struct ModerationQueueResponse {
    pub pending_posts: Vec<PostSummaryResponse>,
    pub pending_comments: Vec<CommentSummaryResponse>,
    pub total_pending_posts: i64,
    pub total_pending_comments: i64,
}

#[derive(Debug, Deserialize)]
pub struct ModerationQueueQuery {
    pub limit: Option<u32>,
}

// Get moderation queue
async fn get_moderation_queue(
    State(state): State<AppState>,
    Query(query): Query<ModerationQueueQuery>,
) -> Result<Json<ModerationQueueResponse>> {
    let limit = query.limit.unwrap_or(50).min(100);

    let content_service = ContentService::new(state.db.clone());
    let queue = content_service.get_moderation_queue(limit).await?;

    // Transform to response format
    let pending_posts: Vec<PostSummaryResponse> = queue.pending_posts.into_iter().map(|post| {
        let content_preview = if post.content.len() > 100 {
            format!("{}...", &post.content[..100])
        } else {
            post.content.clone()
        };

        PostSummaryResponse {
            id: post.id.to_string(),
            author_id: post.user_id.to_string(),
            content_preview,
            status: post.status,
            images_count: post.images_count,
            likes_count: post.likes_count,
            comments_count: post.comments_count,
            reports_count: 0, // Will be fetched separately if needed
            created_at: post.created_at.to_rfc3339(),
        }
    }).collect();

    let pending_comments: Vec<CommentSummaryResponse> = queue.pending_comments.into_iter().map(|comment| {
        CommentSummaryResponse {
            id: comment.id.to_string(),
            post_id: comment.post_id.to_string(),
            author_id: comment.user_id.to_string(),
            content: comment.content,
            status: comment.status,
            reports_count: 0,
            created_at: comment.created_at.to_rfc3339(),
        }
    }).collect();

    Ok(Json(ModerationQueueResponse {
        pending_posts,
        pending_comments,
        total_pending_posts: queue.total_pending_posts,
        total_pending_comments: queue.total_pending_comments,
    }))
}

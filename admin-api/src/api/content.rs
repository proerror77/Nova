use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};

use crate::error::{AppError, Result};
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/posts", get(list_posts))
        .route("/posts/:id", get(get_post))
        .route("/posts/:id/approve", post(approve_post))
        .route("/posts/:id/reject", post(reject_post))
        .route("/comments", get(list_comments))
        .route("/comments/:id/approve", post(approve_comment))
        .route("/comments/:id/reject", post(reject_comment))
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
    pub posts: Vec<PostSummary>,
    pub total: i64,
    pub page: u32,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct PostSummary {
    pub id: String,
    pub author_id: String,
    pub author_name: String,
    pub title: Option<String>,
    pub content_preview: String,
    pub status: String,
    pub images_count: i32,
    pub likes_count: i64,
    pub comments_count: i64,
    pub reports_count: i64,
    pub created_at: String,
}

async fn list_posts(
    State(_state): State<AppState>,
    Query(query): Query<ListContentQuery>,
) -> Result<Json<PostListResponse>> {
    let page = query.page.unwrap_or(1);
    let limit = query.limit.unwrap_or(20).min(100);
    let _status = query.status.clone();
    let _search = query.search.clone();

    // TODO: Query real posts from database

    Ok(Json(PostListResponse {
        posts: vec![
            PostSummary {
                id: "post_1".to_string(),
                author_id: "user_1".to_string(),
                author_name: "测试用户".to_string(),
                title: Some("测试帖子".to_string()),
                content_preview: "这是一条测试帖子的内容预览...".to_string(),
                status: "pending".to_string(),
                images_count: 3,
                likes_count: 42,
                comments_count: 12,
                reports_count: 1,
                created_at: "2024-01-15T10:30:00Z".to_string(),
            },
        ],
        total: 1,
        page,
        limit,
    }))
}

#[derive(Debug, Serialize)]
pub struct PostDetail {
    pub id: String,
    pub author: AuthorInfo,
    pub title: Option<String>,
    pub content: String,
    pub images: Vec<String>,
    pub status: String,
    pub moderation_notes: Option<String>,
    pub stats: PostStats,
    pub reports: Vec<ReportSummary>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize)]
pub struct AuthorInfo {
    pub id: String,
    pub nickname: String,
    pub avatar: Option<String>,
    pub risk_level: String,
}

#[derive(Debug, Serialize)]
pub struct PostStats {
    pub views_count: i64,
    pub likes_count: i64,
    pub comments_count: i64,
    pub shares_count: i64,
    pub reports_count: i64,
}

#[derive(Debug, Serialize)]
pub struct ReportSummary {
    pub id: String,
    pub reason: String,
    pub reporter_id: String,
    pub created_at: String,
}

async fn get_post(
    State(_state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<PostDetail>> {
    // TODO: Query real post from database

    Ok(Json(PostDetail {
        id,
        author: AuthorInfo {
            id: "user_1".to_string(),
            nickname: "测试用户".to_string(),
            avatar: None,
            risk_level: "low".to_string(),
        },
        title: Some("测试帖子".to_string()),
        content: "这是一条测试帖子的完整内容。".to_string(),
        images: vec![],
        status: "pending".to_string(),
        moderation_notes: None,
        stats: PostStats {
            views_count: 1200,
            likes_count: 42,
            comments_count: 12,
            shares_count: 5,
            reports_count: 1,
        },
        reports: vec![
            ReportSummary {
                id: "report_1".to_string(),
                reason: "不当内容".to_string(),
                reporter_id: "user_2".to_string(),
                created_at: "2024-01-15T11:00:00Z".to_string(),
            },
        ],
        created_at: "2024-01-15T10:30:00Z".to_string(),
        updated_at: "2024-01-15T10:30:00Z".to_string(),
    }))
}

#[derive(Debug, Deserialize)]
pub struct ModerationRequest {
    pub notes: Option<String>,
}

async fn approve_post(
    State(_state): State<AppState>,
    Path(id): Path<String>,
    Json(payload): Json<ModerationRequest>,
) -> Result<Json<serde_json::Value>> {
    // TODO: Implement post approval
    // 1. Update post status
    // 2. Log audit event
    // 3. Notify author if needed

    Ok(Json(serde_json::json!({
        "message": format!("Post {} has been approved", id),
        "notes": payload.notes,
    })))
}

#[derive(Debug, Deserialize)]
pub struct RejectRequest {
    pub reason: String,
    pub notes: Option<String>,
}

async fn reject_post(
    State(_state): State<AppState>,
    Path(id): Path<String>,
    Json(payload): Json<RejectRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.is_empty() {
        return Err(AppError::BadRequest("Rejection reason is required".to_string()));
    }

    // TODO: Implement post rejection
    // 1. Update post status
    // 2. Log audit event
    // 3. Notify author

    Ok(Json(serde_json::json!({
        "message": format!("Post {} has been rejected", id),
        "reason": payload.reason,
        "notes": payload.notes,
    })))
}

#[derive(Debug, Serialize)]
pub struct CommentListResponse {
    pub comments: Vec<CommentSummary>,
    pub total: i64,
    pub page: u32,
    pub limit: u32,
}

#[derive(Debug, Serialize)]
pub struct CommentSummary {
    pub id: String,
    pub post_id: String,
    pub author_id: String,
    pub author_name: String,
    pub content: String,
    pub status: String,
    pub reports_count: i64,
    pub created_at: String,
}

async fn list_comments(
    State(_state): State<AppState>,
    Query(query): Query<ListContentQuery>,
) -> Result<Json<CommentListResponse>> {
    let page = query.page.unwrap_or(1);
    let limit = query.limit.unwrap_or(20).min(100);
    let _status = query.status;
    let _search = query.search;

    // TODO: Query real comments from database

    Ok(Json(CommentListResponse {
        comments: vec![
            CommentSummary {
                id: "comment_1".to_string(),
                post_id: "post_1".to_string(),
                author_id: "user_2".to_string(),
                author_name: "评论用户".to_string(),
                content: "这是一条待审核的评论内容".to_string(),
                status: "pending".to_string(),
                reports_count: 0,
                created_at: "2024-01-15T11:30:00Z".to_string(),
            },
        ],
        total: 1,
        page,
        limit,
    }))
}

async fn approve_comment(
    State(_state): State<AppState>,
    Path(id): Path<String>,
    Json(payload): Json<ModerationRequest>,
) -> Result<Json<serde_json::Value>> {
    // TODO: Implement comment approval

    Ok(Json(serde_json::json!({
        "message": format!("Comment {} has been approved", id),
        "notes": payload.notes,
    })))
}

async fn reject_comment(
    State(_state): State<AppState>,
    Path(id): Path<String>,
    Json(payload): Json<RejectRequest>,
) -> Result<Json<serde_json::Value>> {
    if payload.reason.is_empty() {
        return Err(AppError::BadRequest("Rejection reason is required".to_string()));
    }

    // TODO: Implement comment rejection

    Ok(Json(serde_json::json!({
        "message": format!("Comment {} has been rejected", id),
        "reason": payload.reason,
        "notes": payload.notes,
    })))
}

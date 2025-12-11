use actix_web::{delete, get, post, web, HttpMessage, HttpRequest, HttpResponse};
use tracing::error;

use crate::clients::proto::social::{
    CheckUserLikedRequest, CreateCommentRequest, CreateLikeRequest, CreateShareRequest,
    DeleteCommentRequest, DeleteLikeRequest, GetCommentsRequest, GetLikesRequest,
    GetShareCountRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use serde::Deserialize;

#[post("/api/v2/social/like")]
pub async fn create_like(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<LikeBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let req = CreateLikeRequest {
        user_id,
        post_id: body.post_id.clone(),
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.create_like(req).await }
        })
        .await
    {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"success": true})),
        Err(e) => {
            error!("create_like failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[delete("/api/v2/social/unlike")]
pub async fn delete_like(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<LikeBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let req = DeleteLikeRequest {
        user_id,
        post_id: body.post_id.clone(),
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.delete_like(req).await }
        })
        .await
    {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"success": true})),
        Err(e) => {
            error!("delete_like failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[get("/api/v2/social/likes")]
pub async fn get_likes(
    clients: web::Data<ServiceClients>,
    query: web::Query<LikesQuery>,
) -> HttpResponse {
    let q = query.into_inner();
    let req = GetLikesRequest {
        post_id: q.post_id,
        limit: q.limit.unwrap_or(50) as i32,
        offset: q.offset.unwrap_or(0) as i32,
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_likes(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("get_likes failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[get("/api/v2/social/check-liked")]
pub async fn check_liked(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<CheckLikedQuery>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let q = query.into_inner();
    let req = CheckUserLikedRequest {
        user_id,
        post_id: q.post_id,
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.check_user_liked(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("check_liked failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[post("/api/v2/social/comment")]
pub async fn create_comment(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<CommentBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let b = body.into_inner();
    let req = CreateCommentRequest {
        user_id,
        post_id: b.post_id,
        content: b.content,
        parent_comment_id: b.parent_comment_id.unwrap_or_default(),
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.create_comment(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("create_comment failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[delete("/api/v2/social/comment")]
pub async fn delete_comment(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<DeleteCommentBody>,
) -> HttpResponse {
    delete_comment_inner(http_req, clients, body).await
}

// Compatibility path for iOS config: /api/v2/social/comment/delete
#[delete("/api/v2/social/comment/delete")]
pub async fn delete_comment_v2(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<DeleteCommentBody>,
) -> HttpResponse {
    delete_comment_inner(http_req, clients, body).await
}

async fn delete_comment_inner(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<DeleteCommentBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let b = body.into_inner();
    let req = DeleteCommentRequest {
        user_id,
        comment_id: b.comment_id,
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.delete_comment(req).await }
        })
        .await
    {
        Ok(_) => HttpResponse::Ok().finish(),
        Err(e) => {
            error!("delete_comment failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[get("/api/v2/social/comments")]
pub async fn get_comments(
    clients: web::Data<ServiceClients>,
    query: web::Query<CommentsQuery>,
) -> HttpResponse {
    let q = query.into_inner();
    let req = GetCommentsRequest {
        post_id: q.post_id,
        limit: q.limit.unwrap_or(50) as i32,
        offset: q.offset.unwrap_or(0) as i32,
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_comments(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("get_comments failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[post("/api/v2/social/share")]
pub async fn create_share(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<ShareBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let b = body.into_inner();
    let req = CreateShareRequest {
        user_id,
        post_id: b.post_id,
        caption: b.caption.unwrap_or_default(),
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.create_share(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("create_share failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[get("/api/v2/social/shares/count")]
pub async fn get_share_count(
    clients: web::Data<ServiceClients>,
    query: web::Query<ShareCountQuery>,
) -> HttpResponse {
    let q = query.into_inner();
    let req = GetShareCountRequest { post_id: q.post_id };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_share_count(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("get_share_count failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct LikeBody {
    pub post_id: String,
}

#[derive(Debug, Deserialize)]
pub struct LikesQuery {
    pub post_id: String,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

#[derive(Debug, Deserialize)]
pub struct CheckLikedQuery {
    pub post_id: String,
}

#[derive(Debug, Deserialize)]
pub struct CommentBody {
    pub post_id: String,
    pub content: String,
    pub parent_comment_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct DeleteCommentBody {
    pub comment_id: String,
}

#[derive(Debug, Deserialize)]
pub struct CommentsQuery {
    pub post_id: String,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

#[derive(Debug, Deserialize)]
pub struct ShareBody {
    pub post_id: String,
    pub caption: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ShareCountQuery {
    pub post_id: String,
}

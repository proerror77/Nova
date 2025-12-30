use actix_web::{delete, get, post, web, HttpMessage, HttpRequest, HttpResponse};
use std::collections::HashMap;
use tracing::{error, warn};

use crate::clients::proto::auth::GetUserProfilesByIdsRequest;
use crate::clients::proto::social::{
    BatchCheckBookmarkedRequest, CheckUserBookmarkedRequest, CheckUserLikedRequest,
    CreateBookmarkRequest, CreateCommentRequest, CreateLikeRequest, CreateShareRequest,
    DeleteBookmarkRequest, DeleteCommentRequest, DeleteLikeRequest, GetBookmarksRequest,
    GetCommentsRequest, GetLikesRequest, GetShareCountRequest, GetUserLikedPostsRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use crate::rest_api::models::{EnrichedComment, GetCommentsResponse};
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
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({
            "success": resp.success,
            "likeCount": resp.like_count
        })),
        Err(e) => {
            error!("create_like failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
        }
    }
}

/// Delete like - supports path parameter for iOS compatibility
#[delete("/api/v2/social/unlike/{post_id}")]
pub async fn delete_like(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let post_id = path.into_inner();
    let req = DeleteLikeRequest { user_id, post_id };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.delete_like(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({
            "success": resp.success,
            "likeCount": resp.like_count
        })),
        Err(e) => {
            error!("delete_like failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
        }
    }
}

/// Delete like - legacy endpoint with body (for backward compatibility)
#[delete("/api/v2/social/unlike")]
pub async fn delete_like_legacy(
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
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({
            "success": resp.success,
            "likeCount": resp.like_count
        })),
        Err(e) => {
            error!("delete_like failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
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
        Ok(resp) => {
            // Enrich comments with author information
            let enriched = enrich_comments_with_authors(resp.comments, &clients).await;

            HttpResponse::Ok().json(GetCommentsResponse {
                comments: enriched,
                total: resp.total,
            })
        }
        Err(e) => {
            error!("get_comments failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// Helper function to enrich comments with author information
///
/// Batch fetches user profiles from auth-service and merges them into EnrichedComment responses.
/// Gracefully handles missing profiles by leaving author fields as None.
async fn enrich_comments_with_authors(
    comments: Vec<crate::clients::proto::social::Comment>,
    clients: &ServiceClients,
) -> Vec<EnrichedComment> {
    // Collect unique user IDs
    let user_ids: Vec<String> = comments
        .iter()
        .map(|c| c.user_id.clone())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();

    // Batch fetch user profiles
    let profiles = if !user_ids.is_empty() {
        let mut auth_client = clients.auth_client();
        let request = tonic::Request::new(GetUserProfilesByIdsRequest {
            user_ids: user_ids.clone(),
        });

        match auth_client.get_user_profiles_by_ids(request).await {
            Ok(response) => {
                let profiles_list = response.into_inner().profiles;
                // Create a HashMap for O(1) lookup
                profiles_list
                    .into_iter()
                    .map(|p| (p.user_id.clone(), p))
                    .collect::<HashMap<_, _>>()
            }
            Err(status) => {
                warn!(
                    error = %status,
                    "Failed to fetch user profiles for comments, continuing without author info"
                );
                HashMap::new()
            }
        }
    } else {
        HashMap::new()
    };

    // Merge profiles into comments
    comments
        .into_iter()
        .map(|comment| {
            let profile = profiles.get(&comment.user_id);

            // Fallback: if display_name is empty/None, use username
            let author_display_name = profile.and_then(|p| {
                let display_name = p.display_name.clone().unwrap_or_default();
                if display_name.is_empty() {
                    Some(p.username.clone())
                } else {
                    Some(display_name)
                }
            });

            // Convert timestamp to ISO8601 string
            let created_at = comment.created_at.map(|ts| {
                chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                    .map(|dt| dt.to_rfc3339())
                    .unwrap_or_default()
            });

            EnrichedComment {
                id: comment.id,
                user_id: comment.user_id.clone(),
                post_id: comment.post_id,
                content: comment.content,
                parent_comment_id: comment.parent_comment_id,
                created_at,
                author_username: profile.map(|p| p.username.clone()),
                author_display_name,
                author_avatar_url: profile.and_then(|p| p.avatar_url.clone()),
            }
        })
        .collect()
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

/// Get share count - supports path parameter for iOS compatibility
#[get("/api/v2/social/shares/count/{post_id}")]
pub async fn get_share_count(
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    let post_id = path.into_inner();
    let req = GetShareCountRequest { post_id };
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

/// Get share count - legacy endpoint with query parameter (for backward compatibility)
#[get("/api/v2/social/shares/count")]
pub async fn get_share_count_legacy(
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

// ============================================================================
// BOOKMARK ENDPOINTS
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct BookmarkBody {
    pub post_id: String,
}

#[derive(Debug, Deserialize)]
pub struct BookmarksQuery {
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

/// Create a bookmark for a post
#[post("/api/v2/social/bookmark")]
pub async fn create_bookmark(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<BookmarkBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let req = CreateBookmarkRequest {
        user_id,
        post_id: body.post_id.clone(),
        collection_id: String::new(), // Default: no collection
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.create_bookmark(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({
            "success": resp.success,
            "bookmark": resp.bookmark
        })),
        Err(e) => {
            error!("create_bookmark failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
        }
    }
}

/// Delete a bookmark from a post
#[delete("/api/v2/social/bookmark/{post_id}")]
pub async fn delete_bookmark(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let post_id = path.into_inner();
    let req = DeleteBookmarkRequest { user_id, post_id };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.delete_bookmark(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({"success": resp.success})),
        Err(e) => {
            error!("delete_bookmark failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
        }
    }
}

/// Get user's bookmarked posts
#[get("/api/v2/social/bookmarks")]
pub async fn get_bookmarks(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<BookmarksQuery>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let q = query.into_inner();
    let req = GetBookmarksRequest {
        user_id,
        limit: q.limit.unwrap_or(50) as i32,
        offset: q.offset.unwrap_or(0) as i32,
        collection_id: String::new(), // Default: all bookmarks
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_bookmarks(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({
            "post_ids": resp.post_ids,
            "total_count": resp.total_count
        })),
        Err(e) => {
            error!("get_bookmarks failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
        }
    }
}

/// Check if user has bookmarked a post
#[get("/api/v2/social/check-bookmarked/{post_id}")]
pub async fn check_bookmarked(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let post_id = path.into_inner();
    let req = CheckUserBookmarkedRequest { user_id, post_id };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.check_user_bookmarked(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({"bookmarked": resp.bookmarked})),
        Err(e) => {
            error!("check_bookmarked failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
        }
    }
}

/// Batch check if user has bookmarked multiple posts
#[post("/api/v2/social/bookmarks/batch-check")]
pub async fn batch_check_bookmarked(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<BatchCheckBookmarkedBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let req = BatchCheckBookmarkedRequest {
        user_id,
        post_ids: body.post_ids.clone(),
    };
    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.batch_check_bookmarked(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok()
            .json(serde_json::json!({"bookmarked_post_ids": resp.bookmarked_post_ids})),
        Err(e) => {
            error!("batch_check_bookmarked failed: {}", e);
            HttpResponse::ServiceUnavailable().json(
                serde_json::json!({"success": false, "error": "Service temporarily unavailable"}),
            )
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct BatchCheckBookmarkedBody {
    pub post_ids: Vec<String>,
}

// ============================================================================
// USER LIKED POSTS ENDPOINT
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct UserLikedPostsQuery {
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

/// Get posts liked by a user
#[get("/api/v2/social/users/{user_id}/liked-posts")]
pub async fn get_user_liked_posts(
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
    query: web::Query<UserLikedPostsQuery>,
) -> HttpResponse {
    let user_id = path.into_inner();
    let q = query.into_inner();

    let req = GetUserLikedPostsRequest {
        user_id,
        limit: q.limit.unwrap_or(20) as i32,
        offset: q.offset.unwrap_or(0) as i32,
    };

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_user_liked_posts(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({
            "post_ids": resp.post_ids,
            "total": resp.total
        })),
        Err(e) => {
            error!("get_user_liked_posts failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

// ============================================================================
// DEPRECATED BOOKMARK ENDPOINTS (Backward Compatibility)
// These endpoints are DEPRECATED and will be removed after 2026-04-01.
// Please migrate to the new endpoints:
//   - POST /api/v2/social/save
//   - DELETE /api/v2/social/save/{id}
//   - GET /api/v2/social/saved-posts
//   - GET /api/v2/social/saved-posts/{id}/check
//   - POST /api/v2/social/saved-posts/batch-check
// ============================================================================

use super::social_likes::{BatchCheckBookmarkedBody, BookmarkBody, BookmarksQuery};
use crate::clients::proto::social::{
    BatchCheckBookmarkedRequest, CheckUserBookmarkedRequest, CreateBookmarkRequest,
    DeleteBookmarkRequest, GetBookmarksRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use actix_web::{delete, get, post, web, HttpMessage, HttpRequest, HttpResponse};
use tracing::{error, warn};

/// DEPRECATED: Use POST /api/v2/social/save instead
#[post("/api/v2/social/bookmark")]
pub async fn create_bookmark_deprecated(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<BookmarkBody>,
) -> HttpResponse {
    warn!("DEPRECATED: POST /api/v2/social/bookmark called - migrate to POST /api/v2/social/save");

    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let req = CreateBookmarkRequest {
        user_id,
        post_id: body.post_id.clone(),
        collection_id: String::new(),
    };

    let mut resp = match clients
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
    };

    // Add deprecation headers
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("deprecation"),
        actix_web::http::header::HeaderValue::from_static("true"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("sunset"),
        actix_web::http::header::HeaderValue::from_static("Tue, 1 Apr 2026 23:59:59 GMT"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("link"),
        actix_web::http::header::HeaderValue::from_static(r#"</api/v2/social/save>; rel="alternate""#),
    );

    resp
}

/// DEPRECATED: Use DELETE /api/v2/social/save/{post_id} instead
#[delete("/api/v2/social/bookmark/{post_id}")]
pub async fn delete_bookmark_deprecated(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    warn!("DEPRECATED: DELETE /api/v2/social/bookmark/{{id}} called - migrate to DELETE /api/v2/social/save/{{id}}");

    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let post_id = path.into_inner();
    let req = DeleteBookmarkRequest { user_id, post_id };

    let mut resp = match clients
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
    };

    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("deprecation"),
        actix_web::http::header::HeaderValue::from_static("true"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("sunset"),
        actix_web::http::header::HeaderValue::from_static("Tue, 1 Apr 2026 23:59:59 GMT"),
    );

    resp
}

/// DEPRECATED: Use GET /api/v2/social/saved-posts instead
#[get("/api/v2/social/bookmarks")]
pub async fn get_bookmarks_deprecated(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<BookmarksQuery>,
) -> HttpResponse {
    warn!("DEPRECATED: GET /api/v2/social/bookmarks called - migrate to GET /api/v2/social/saved-posts");

    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let q = query.into_inner();
    let req = GetBookmarksRequest {
        user_id,
        limit: q.limit.unwrap_or(50) as i32,
        offset: q.offset.unwrap_or(0) as i32,
        collection_id: String::new(),
    };

    let mut resp = match clients
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
    };

    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("deprecation"),
        actix_web::http::header::HeaderValue::from_static("true"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("sunset"),
        actix_web::http::header::HeaderValue::from_static("Tue, 1 Apr 2026 23:59:59 GMT"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("link"),
        actix_web::http::header::HeaderValue::from_static(r#"</api/v2/social/saved-posts>; rel="alternate""#),
    );

    resp
}

/// DEPRECATED: Use GET /api/v2/social/saved-posts/{post_id}/check instead
#[get("/api/v2/social/check-bookmarked/{post_id}")]
pub async fn check_bookmarked_deprecated(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> HttpResponse {
    warn!("DEPRECATED: GET /api/v2/social/check-bookmarked/{{id}} called - migrate to GET /api/v2/social/saved-posts/{{id}}/check");

    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let post_id = path.into_inner();
    let req = CheckUserBookmarkedRequest { user_id, post_id };

    let mut resp = match clients
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
    };

    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("deprecation"),
        actix_web::http::header::HeaderValue::from_static("true"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("sunset"),
        actix_web::http::header::HeaderValue::from_static("Tue, 1 Apr 2026 23:59:59 GMT"),
    );

    resp
}

/// DEPRECATED: Use POST /api/v2/social/saved-posts/batch-check instead
#[post("/api/v2/social/bookmarks/batch-check")]
pub async fn batch_check_bookmarked_deprecated(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<BatchCheckBookmarkedBody>,
) -> HttpResponse {
    warn!("DEPRECATED: POST /api/v2/social/bookmarks/batch-check called - migrate to POST /api/v2/social/saved-posts/batch-check");

    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    if body.post_ids.len() > 100 {
        return HttpResponse::BadRequest()
            .json(serde_json::json!({"error": "Maximum 100 post_ids allowed"}));
    }

    let req = BatchCheckBookmarkedRequest {
        user_id,
        post_ids: body.post_ids.clone(),
    };

    let mut resp = match clients
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
    };

    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("deprecation"),
        actix_web::http::header::HeaderValue::from_static("true"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("sunset"),
        actix_web::http::header::HeaderValue::from_static("Tue, 1 Apr 2026 23:59:59 GMT"),
    );
    resp.headers_mut().insert(
        actix_web::http::header::HeaderName::from_static("link"),
        actix_web::http::header::HeaderValue::from_static(r#"</api/v2/social/saved-posts/batch-check>; rel="alternate""#),
    );

    resp
}

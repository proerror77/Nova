/// Feed API endpoints
///
/// GET /api/v2/feed - Get personalized feed for current user
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use tracing::{error, info};

use super::models::{ErrorResponse, FeedPost, GetFeedResponse};
use crate::clients::proto::feed::GetFeedRequest as ProtoGetFeedRequest;
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

/// GET /api/v2/feed
/// Returns personalized feed for the authenticated user
/// Query parameters:
///   - user_id: The user ID to fetch feed for (required)
///   - limit: Number of posts to return (default: 20, max: 100)
///   - cursor: Pagination cursor for next page (optional)
///   - algorithm: Algorithm variant - "ch", "v2", "hybrid" (default: "v2")
pub async fn get_feed(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<FeedQueryParams>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let limit = query.limit.unwrap_or(20).min(100);
    let cursor = query.cursor.clone().unwrap_or_default();
    let algorithm = query.algorithm.clone().unwrap_or_else(|| "v2".to_string());

    info!(
        user_id = %user_id,
        limit = %limit,
        cursor = %cursor,
        algorithm = %algorithm,
        "GET /api/v2/feed"
    );

    // Call feed-service via gRPC
    let mut feed_client = clients.feed_client();

    let grpc_request = tonic::Request::new(ProtoGetFeedRequest {
        user_id: user_id.clone(),
        limit: limit as u32,
        cursor,
        algorithm,
    });

    match feed_client.get_feed(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();
            let post_count = grpc_response.posts.len();
            let next_cursor = grpc_response.next_cursor;
            let has_more = grpc_response.has_more;

            // Convert gRPC FeedPost to REST FeedPost
            let posts = grpc_response
                .posts
                .into_iter()
                .map(|post| FeedPost {
                    id: post.id,
                    user_id: post.user_id,
                    content: post.content,
                    created_at: post.created_at,
                    ranking_score: post.ranking_score,
                    like_count: post.like_count,
                    comment_count: post.comment_count,
                    share_count: post.share_count,
                    media_urls: post.media_urls,
                    media_type: post.media_type,
                })
                .collect();

            info!(
                user_id = %user_id,
                post_count = post_count,
                "Feed retrieved successfully"
            );

            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts,
                next_cursor: if next_cursor.is_empty() {
                    None
                } else {
                    Some(next_cursor)
                },
                has_more,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get feed from feed-service"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("User not found"))
                }
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::new("Unauthorized"))
                }
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

/// GET /api/v2/feed/user/{user_id}
pub async fn get_feed_by_user(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<FeedQueryParams>,
) -> Result<HttpResponse> {
    if req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return Ok(HttpResponse::Unauthorized().finish());
    }
    let mut feed_client = clients.feed_client();
    let grpc_request = tonic::Request::new(ProtoGetFeedRequest {
        user_id: path.into_inner(),
        limit: query.limit.unwrap_or(20).min(100),
        cursor: query.cursor.clone().unwrap_or_default(),
        algorithm: query.algorithm.clone().unwrap_or_else(|| "v2".to_string()),
    });

    match feed_client.get_feed(grpc_request).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts: inner
                    .posts
                    .into_iter()
                    .map(|p| FeedPost {
                        id: p.id,
                        user_id: p.user_id,
                        content: p.content,
                        created_at: p.created_at,
                        ranking_score: p.ranking_score,
                        like_count: p.like_count,
                        comment_count: p.comment_count,
                        share_count: p.share_count,
                        media_urls: p.media_urls,
                        media_type: p.media_type,
                    })
                    .collect(),
                next_cursor: if inner.next_cursor.is_empty() {
                    None
                } else {
                    Some(inner.next_cursor)
                },
                has_more: inner.has_more,
            }))
        }
        Err(e) => Ok(HttpResponse::ServiceUnavailable().body(e.to_string())),
    }
}

/// GET /api/v2/feed/explore
pub async fn get_explore_feed(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<FeedQueryParams>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };
    // reuse feed-service; for now same as get_feed but with algorithm override
    let mut feed_client = clients.feed_client();
    let grpc_request = tonic::Request::new(ProtoGetFeedRequest {
        user_id,
        limit: query.limit.unwrap_or(20).min(100),
        cursor: query.cursor.clone().unwrap_or_default(),
        algorithm: "explore".to_string(),
    });
    match feed_client.get_feed(grpc_request).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts: inner
                    .posts
                    .into_iter()
                    .map(|p| FeedPost {
                        id: p.id,
                        user_id: p.user_id,
                        content: p.content,
                        created_at: p.created_at,
                        ranking_score: p.ranking_score,
                        like_count: p.like_count,
                        comment_count: p.comment_count,
                        share_count: p.share_count,
                        media_urls: p.media_urls,
                        media_type: p.media_type,
                    })
                    .collect(),
                next_cursor: if inner.next_cursor.is_empty() {
                    None
                } else {
                    Some(inner.next_cursor)
                },
                has_more: inner.has_more,
            }))
        }
        Err(e) => Ok(HttpResponse::ServiceUnavailable().body(e.to_string())),
    }
}

/// GET /api/v2/feed/trending
pub async fn get_trending_feed(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<FeedQueryParams>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };
    let mut feed_client = clients.feed_client();
    let grpc_request = tonic::Request::new(ProtoGetFeedRequest {
        user_id,
        limit: query.limit.unwrap_or(20).min(100),
        cursor: query.cursor.clone().unwrap_or_default(),
        algorithm: "trending".to_string(),
    });
    match feed_client.get_feed(grpc_request).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts: inner
                    .posts
                    .into_iter()
                    .map(|p| FeedPost {
                        id: p.id,
                        user_id: p.user_id,
                        content: p.content,
                        created_at: p.created_at,
                        ranking_score: p.ranking_score,
                        like_count: p.like_count,
                        comment_count: p.comment_count,
                        share_count: p.share_count,
                        media_urls: p.media_urls,
                        media_type: p.media_type,
                    })
                    .collect(),
                next_cursor: if inner.next_cursor.is_empty() {
                    None
                } else {
                    Some(inner.next_cursor)
                },
                has_more: inner.has_more,
            }))
        }
        Err(e) => Ok(HttpResponse::ServiceUnavailable().body(e.to_string())),
    }
}

#[derive(Debug, serde::Deserialize)]
pub struct FeedQueryParams {
    pub limit: Option<u32>,
    pub cursor: Option<String>,
    pub algorithm: Option<String>,
}

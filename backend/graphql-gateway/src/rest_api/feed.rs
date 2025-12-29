/// Feed API endpoints
///
/// GET /api/v2/feed - Get personalized feed for current user
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use std::collections::HashMap;
use tracing::{error, info, warn};

use super::models::{
    ErrorResponse, FeedPost, GetFeedResponse, GetRecommendedCreatorsResponse, RecommendedCreator,
};
use crate::clients::proto::auth::GetUserProfilesByIdsRequest;
use crate::clients::proto::feed::{
    GetFeedRequest as ProtoGetFeedRequest, GetRecommendedCreatorsRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

/// Helper function to enrich feed posts with author information
///
/// Batch fetches user profiles from auth-service and merges them into FeedPost responses.
/// Gracefully handles missing profiles by leaving author fields as None.
async fn enrich_posts_with_authors(
    posts: Vec<crate::clients::proto::feed::FeedPost>,
    clients: &ServiceClients,
) -> Vec<FeedPost> {
    // Collect unique user IDs
    let user_ids: Vec<String> = posts
        .iter()
        .map(|p| p.user_id.clone())
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
                    "Failed to fetch user profiles from auth-service, continuing without author info"
                );
                HashMap::new()
            }
        }
    } else {
        HashMap::new()
    };

    // Merge profiles into posts
    posts
        .into_iter()
        .map(|post| {
            let profile = profiles.get(&post.user_id);

            // Fallback: if display_name is empty/None, use username
            let author_display_name = profile.and_then(|p| {
                let display_name = p.display_name.clone().unwrap_or_default();
                if display_name.is_empty() {
                    Some(p.username.clone())
                } else {
                    Some(display_name)
                }
            });

            FeedPost {
                id: post.id,
                user_id: post.user_id.clone(),
                content: post.content,
                created_at: post.created_at,
                ranking_score: post.ranking_score,
                like_count: post.like_count,
                comment_count: post.comment_count,
                share_count: post.share_count,
                bookmark_count: post.bookmark_count,
                media_urls: post.media_urls,
                media_type: post.media_type,
                // User-specific engagement status (from feed-service gRPC)
                is_liked: post.is_liked,
                is_bookmarked: post.is_bookmarked,
                // Author information
                author_username: profile.map(|p| p.username.clone()),
                author_display_name,
                author_avatar: profile.and_then(|p| p.avatar_url.clone()),
            }
        })
        .collect()
}

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

    let channel_id = query.channel_id.clone().unwrap_or_default();

    info!(
        user_id = %user_id,
        limit = %limit,
        cursor = %cursor,
        algorithm = %algorithm,
        channel_id = %channel_id,
        "GET /api/v2/feed"
    );

    // Call feed-service via gRPC
    let mut feed_client = clients.feed_client();

    let grpc_request = tonic::Request::new(ProtoGetFeedRequest {
        user_id: user_id.clone(),
        limit,
        cursor,
        algorithm,
        channel_id,
    });

    match feed_client.get_feed(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();
            let post_count = grpc_response.posts.len();
            let next_cursor = grpc_response.next_cursor;
            let has_more = grpc_response.has_more;

            // Enrich posts with author information from auth-service
            let posts = enrich_posts_with_authors(grpc_response.posts, &clients).await;

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
        channel_id: query.channel_id.clone().unwrap_or_default(),
    });

    match feed_client.get_feed(grpc_request).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            let posts = enrich_posts_with_authors(inner.posts, &clients).await;

            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts,
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
        channel_id: String::new(),
    });
    match feed_client.get_feed(grpc_request).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            let posts = enrich_posts_with_authors(inner.posts, &clients).await;

            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts,
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
        channel_id: String::new(),
    });
    match feed_client.get_feed(grpc_request).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            let posts = enrich_posts_with_authors(inner.posts, &clients).await;

            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts,
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

/// GET /api/v2/guest/feed/trending
///
/// Public trending feed for unauthenticated (guest) users.
/// Uses feed-service gRPC with a synthetic "guest" user_id and the "trending" algorithm.
/// This returns the same `GetFeedResponse` shape as authenticated feed endpoints,
/// but does not require a JWT.
pub async fn get_guest_trending_feed(
    clients: web::Data<ServiceClients>,
    query: web::Query<FeedQueryParams>,
) -> Result<HttpResponse> {
    // Synthetic guest user ID used only for caching/metrics in feed-service.
    // Use a distinct ID to avoid clashing with any previous cached entries.
    let user_id = "guest_trending".to_string();

    let mut feed_client = clients.feed_client();
    let grpc_request = tonic::Request::new(ProtoGetFeedRequest {
        user_id,
        limit: query.limit.unwrap_or(20).min(100),
        cursor: query.cursor.clone().unwrap_or_default(),
        algorithm: "trending".to_string(),
        channel_id: String::new(),
    });

    match feed_client.get_feed(grpc_request).await {
        Ok(resp) => {
            let inner = resp.into_inner();
            let posts = enrich_posts_with_authors(inner.posts, &clients).await;

            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts,
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
    pub channel_id: Option<String>, // Optional: Filter feed by channel (UUID or slug)
}

/// GET /api/v2/feed/recommended-creators
///
/// Returns recommended creators for the authenticated user.
/// Query parameters:
///   - limit: Number of creators to return (default: 20, max: 50)
pub async fn get_recommended_creators(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<RecommendedCreatorsQueryParams>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let limit = query.limit.unwrap_or(20).min(50);

    info!(
        user_id = %user_id,
        limit = %limit,
        "GET /api/v2/feed/recommended-creators"
    );

    let mut feed_client = clients.feed_client();

    let grpc_request = tonic::Request::new(GetRecommendedCreatorsRequest {
        user_id: user_id.clone(),
        limit,
    });

    match feed_client.get_recommended_creators(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            let creators: Vec<RecommendedCreator> = grpc_response
                .creators
                .into_iter()
                .map(|c| RecommendedCreator {
                    id: c.id,
                    name: c.name,
                    avatar: if c.avatar.is_empty() {
                        None
                    } else {
                        Some(c.avatar)
                    },
                    relevance_score: c.relevance_score,
                    follower_count: c.follower_count,
                    reason: if c.reason.is_empty() {
                        None
                    } else {
                        Some(c.reason)
                    },
                })
                .collect();

            info!(
                user_id = %user_id,
                creator_count = creators.len(),
                "Recommended creators retrieved successfully"
            );

            Ok(HttpResponse::Ok().json(GetRecommendedCreatorsResponse { creators }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get recommended creators from feed-service"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("User not found"))
                }
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::new("Unauthorized"))
                }
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

#[derive(Debug, serde::Deserialize)]
pub struct RecommendedCreatorsQueryParams {
    pub limit: Option<u32>,
}

/// Search API endpoints
///
/// GET /api/v2/search - Unified search (content, users, hashtags)
/// GET /api/v2/search/content - Search posts/articles
/// GET /api/v2/search/users - Search users
/// GET /api/v2/search/hashtags - Search hashtags
/// GET /api/v2/search/suggestions - Get search suggestions
/// GET /api/v2/search/trending - Get trending topics/hashtags
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::search::{
    GetSearchSuggestionsRequest, GetTrendingTopicsRequest, SearchAllRequest, SearchContentRequest,
    SearchHashtagsRequest, SearchUsersRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use crate::rest_api::models::ErrorResponse;

// ============================================================================
// Query Parameters
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct SearchAllQuery {
    pub q: String,
    #[serde(default = "default_limit_per_type")]
    pub limit_per_type: i32,
}

fn default_limit_per_type() -> i32 {
    5
}

#[derive(Debug, Deserialize)]
pub struct SearchContentQuery {
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
    pub verified_only: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct SearchUsersQuery {
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i32,
    #[serde(default)]
    pub offset: i32,
    pub verified_only: Option<bool>,
    pub min_followers: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct SearchHashtagsQuery {
    pub q: String,
    #[serde(default = "default_limit")]
    pub limit: i32,
    pub trending_only: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct SuggestionsQuery {
    pub q: String,
    #[serde(default = "default_suggestions_limit")]
    pub limit: i32,
}

#[derive(Debug, Deserialize)]
pub struct TrendingQuery {
    #[serde(default = "default_trending_limit")]
    pub limit: i32,
    pub location: Option<String>,
}

fn default_limit() -> i32 {
    20
}

fn default_suggestions_limit() -> i32 {
    10
}

fn default_trending_limit() -> i32 {
    10
}

// ============================================================================
// Response Models
// ============================================================================

#[derive(Debug, Serialize)]
pub struct SearchAllResponse {
    pub content: Vec<ContentResult>,
    pub users: Vec<UserResult>,
    pub hashtags: Vec<HashtagResult>,
    pub total_results: i32,
}

#[derive(Debug, Serialize)]
pub struct SearchContentResponse {
    pub results: Vec<ContentResult>,
    pub total_count: i32,
    pub has_more: bool,
}

#[derive(Debug, Serialize)]
pub struct SearchUsersResponse {
    pub results: Vec<UserResult>,
    pub total_count: i32,
    pub has_more: bool,
}

#[derive(Debug, Serialize)]
pub struct SearchHashtagsResponse {
    pub results: Vec<HashtagResult>,
}

#[derive(Debug, Serialize)]
pub struct SuggestionsResponse {
    pub suggestions: Vec<SearchSuggestion>,
}

#[derive(Debug, Serialize)]
pub struct TrendingResponse {
    pub topics: Vec<TrendingTopic>,
}

#[derive(Debug, Serialize)]
pub struct ContentResult {
    pub id: String,
    #[serde(rename = "type")]
    pub content_type: String,
    pub title: Option<String>,
    pub content: String,
    pub author_id: String,
    pub author_username: Option<String>,
    pub author_avatar: Option<String>,
    pub media_urls: Vec<String>,
    pub like_count: i32,
    pub comment_count: i32,
    pub relevance_score: f64,
    pub created_at: i64,
}

#[derive(Debug, Serialize)]
pub struct UserResult {
    pub id: String,
    pub username: String,
    pub display_name: String,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub is_verified: bool,
    pub follower_count: i32,
    pub relevance_score: f64,
}

#[derive(Debug, Serialize)]
pub struct HashtagResult {
    pub tag: String,
    pub post_count: i64,
    pub usage_count_24h: i64,
    pub is_trending: bool,
}

#[derive(Debug, Serialize)]
pub struct SearchSuggestion {
    pub text: String,
    #[serde(rename = "type")]
    pub suggestion_type: String,
    pub frequency: i64,
}

#[derive(Debug, Serialize)]
pub struct TrendingTopic {
    pub tag: String,
    pub post_count: i64,
    pub usage_count_24h: i64,
    pub trend_score: f64,
}

// ============================================================================
// Handlers
// ============================================================================

/// GET /api/v2/search
/// Unified search across content, users, and hashtags
pub async fn search_all(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<SearchAllQuery>,
) -> Result<HttpResponse> {
    // Require authentication
    if req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    info!(
        query = %query.q,
        limit_per_type = query.limit_per_type,
        "GET /api/v2/search"
    );

    let mut search_client = clients.search_client();

    let grpc_request = tonic::Request::new(SearchAllRequest {
        query: query.q.clone(),
        limit_per_type: query.limit_per_type,
    });

    match search_client.search_all(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let content: Vec<ContentResult> = inner
                .content
                .into_iter()
                .map(|c| ContentResult {
                    id: c.id,
                    content_type: format!("{:?}", c.r#type),
                    title: if c.title.is_empty() {
                        None
                    } else {
                        Some(c.title)
                    },
                    content: c.content,
                    author_id: c.author_id,
                    author_username: if c.author_username.is_empty() {
                        None
                    } else {
                        Some(c.author_username)
                    },
                    author_avatar: if c.author_avatar.is_empty() {
                        None
                    } else {
                        Some(c.author_avatar)
                    },
                    media_urls: c.media_urls,
                    like_count: c.like_count,
                    comment_count: c.comment_count,
                    relevance_score: c.relevance_score,
                    created_at: c.created_at.map(|t| t.seconds).unwrap_or(0),
                })
                .collect();

            let users: Vec<UserResult> = inner
                .users
                .into_iter()
                .map(|u| UserResult {
                    id: u.id,
                    username: u.username,
                    display_name: u.display_name,
                    bio: if u.bio.is_empty() { None } else { Some(u.bio) },
                    avatar_url: if u.avatar_url.is_empty() {
                        None
                    } else {
                        Some(u.avatar_url)
                    },
                    is_verified: u.is_verified,
                    follower_count: u.follower_count,
                    relevance_score: u.relevance_score,
                })
                .collect();

            let hashtags: Vec<HashtagResult> = inner
                .hashtags
                .into_iter()
                .map(|h| HashtagResult {
                    tag: h.tag,
                    post_count: h.post_count,
                    usage_count_24h: h.usage_count_24h,
                    is_trending: h.is_trending,
                })
                .collect();

            Ok(HttpResponse::Ok().json(SearchAllResponse {
                content,
                users,
                hashtags,
                total_results: inner.total_results,
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to search");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Search failed",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/search/content
/// Search posts and articles
pub async fn search_content(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<SearchContentQuery>,
) -> Result<HttpResponse> {
    if req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    info!(
        query = %query.q,
        limit = query.limit,
        offset = query.offset,
        "GET /api/v2/search/content"
    );

    let mut search_client = clients.search_client();

    // Build filter
    let filter =
        query.verified_only.map(
            |verified_only| crate::clients::proto::search::SearchFilter {
                types: vec![],
                author_ids: vec![],
                hashtags: vec![],
                from: None,
                to: None,
                verified_only,
            },
        );

    let grpc_request = tonic::Request::new(SearchContentRequest {
        query: query.q.clone(),
        filter,
        sort: None,
        limit: query.limit,
        offset: query.offset,
    });

    match search_client.search_content(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let results: Vec<ContentResult> = inner
                .results
                .into_iter()
                .map(|c| ContentResult {
                    id: c.id,
                    content_type: format!("{:?}", c.r#type),
                    title: if c.title.is_empty() {
                        None
                    } else {
                        Some(c.title)
                    },
                    content: c.content,
                    author_id: c.author_id,
                    author_username: if c.author_username.is_empty() {
                        None
                    } else {
                        Some(c.author_username)
                    },
                    author_avatar: if c.author_avatar.is_empty() {
                        None
                    } else {
                        Some(c.author_avatar)
                    },
                    media_urls: c.media_urls,
                    like_count: c.like_count,
                    comment_count: c.comment_count,
                    relevance_score: c.relevance_score,
                    created_at: c.created_at.map(|t| t.seconds).unwrap_or(0),
                })
                .collect();

            Ok(HttpResponse::Ok().json(SearchContentResponse {
                results,
                total_count: inner.total_count,
                has_more: inner.has_more,
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to search content");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Search failed",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/search/users-full
/// Full user search (different from the simple search in social.rs)
pub async fn search_users_full(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<SearchUsersQuery>,
) -> Result<HttpResponse> {
    if req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    info!(
        query = %query.q,
        limit = query.limit,
        offset = query.offset,
        "GET /api/v2/search/users-full"
    );

    let mut search_client = clients.search_client();

    let filter = if query.verified_only.is_some() || query.min_followers.is_some() {
        Some(crate::clients::proto::search::UserSearchFilter {
            verified_only: query.verified_only.unwrap_or(false),
            min_followers: query.min_followers.unwrap_or(0),
            location: String::new(),
        })
    } else {
        None
    };

    let grpc_request = tonic::Request::new(SearchUsersRequest {
        query: query.q.clone(),
        filter,
        limit: query.limit,
        offset: query.offset,
    });

    match search_client.search_users(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let results: Vec<UserResult> = inner
                .results
                .into_iter()
                .map(|u| UserResult {
                    id: u.id,
                    username: u.username,
                    display_name: u.display_name,
                    bio: if u.bio.is_empty() { None } else { Some(u.bio) },
                    avatar_url: if u.avatar_url.is_empty() {
                        None
                    } else {
                        Some(u.avatar_url)
                    },
                    is_verified: u.is_verified,
                    follower_count: u.follower_count,
                    relevance_score: u.relevance_score,
                })
                .collect();

            Ok(HttpResponse::Ok().json(SearchUsersResponse {
                results,
                total_count: inner.total_count,
                has_more: inner.has_more,
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to search users");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Search failed",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/search/hashtags
/// Search hashtags
pub async fn search_hashtags(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<SearchHashtagsQuery>,
) -> Result<HttpResponse> {
    if req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    info!(
        query = %query.q,
        limit = query.limit,
        "GET /api/v2/search/hashtags"
    );

    let mut search_client = clients.search_client();

    let grpc_request = tonic::Request::new(SearchHashtagsRequest {
        query: query.q.clone(),
        limit: query.limit,
        trending_only: query.trending_only.unwrap_or(false),
    });

    match search_client.search_hashtags(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let results: Vec<HashtagResult> = inner
                .results
                .into_iter()
                .map(|h| HashtagResult {
                    tag: h.tag,
                    post_count: h.post_count,
                    usage_count_24h: h.usage_count_24h,
                    is_trending: h.is_trending,
                })
                .collect();

            Ok(HttpResponse::Ok().json(SearchHashtagsResponse { results }))
        }
        Err(status) => {
            error!(error = %status, "Failed to search hashtags");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Search failed",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/search/suggestions
/// Get search suggestions based on partial query
pub async fn get_suggestions(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<SuggestionsQuery>,
) -> Result<HttpResponse> {
    if req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return Ok(HttpResponse::Unauthorized().finish());
    }

    info!(
        query = %query.q,
        limit = query.limit,
        "GET /api/v2/search/suggestions"
    );

    let mut search_client = clients.search_client();

    let grpc_request = tonic::Request::new(GetSearchSuggestionsRequest {
        query: query.q.clone(),
        limit: query.limit,
    });

    match search_client.get_search_suggestions(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let suggestions: Vec<SearchSuggestion> = inner
                .suggestions
                .into_iter()
                .map(|s| SearchSuggestion {
                    text: s.text,
                    suggestion_type: format!("{:?}", s.r#type),
                    frequency: s.frequency,
                })
                .collect();

            Ok(HttpResponse::Ok().json(SuggestionsResponse { suggestions }))
        }
        Err(status) => {
            error!(error = %status, "Failed to get suggestions");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Suggestions failed",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/search/trending
/// Get trending topics/hashtags
pub async fn get_trending_topics(
    clients: web::Data<ServiceClients>,
    query: web::Query<TrendingQuery>,
) -> Result<HttpResponse> {
    // No auth required for trending topics (public)
    info!(
        limit = query.limit,
        location = ?query.location,
        "GET /api/v2/search/trending"
    );

    let mut search_client = clients.search_client();

    let grpc_request = tonic::Request::new(GetTrendingTopicsRequest {
        limit: query.limit,
        location: query.location.clone().unwrap_or_default(),
    });

    match search_client.get_trending_topics(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let topics: Vec<TrendingTopic> = inner
                .topics
                .into_iter()
                .map(|t| TrendingTopic {
                    tag: t.tag,
                    post_count: t.post_count,
                    usage_count_24h: t.usage_count_24h,
                    trend_score: t.trend_score,
                })
                .collect();

            Ok(HttpResponse::Ok().json(TrendingResponse { topics }))
        }
        Err(status) => {
            error!(error = %status, "Failed to get trending topics");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Trending topics failed",
                    status.message(),
                )),
            )
        }
    }
}

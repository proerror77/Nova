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
    FullTextSearchRequest, GetSearchSuggestionsRequest, GetTrendingSearchesRequest,
    SearchHashtagsRequest, SearchPostsRequest, SearchUsersRequest,
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
/// Uses full_text_search which returns mixed results
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

    let grpc_request = tonic::Request::new(FullTextSearchRequest {
        query: query.q.clone(),
        limit: query.limit_per_type * 3, // Approximate total
        offset: 0,
        filters: None,
    });

    match search_client.full_text_search(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            // FullTextSearchResponse returns SearchResult items with type field
            // We need to separate them into content, users, and hashtags
            let mut content: Vec<ContentResult> = Vec::new();
            let mut users: Vec<UserResult> = Vec::new();
            let mut hashtags: Vec<HashtagResult> = Vec::new();

            for result in inner.results {
                match result.r#type.as_str() {
                    "post" => {
                        content.push(ContentResult {
                            id: result.id,
                            content_type: "post".to_string(),
                            title: if result.title.is_empty() {
                                None
                            } else {
                                Some(result.title)
                            },
                            content: result.description,
                            author_id: String::new(),
                            author_username: None,
                            author_avatar: None,
                            media_urls: vec![],
                            like_count: 0,
                            comment_count: 0,
                            relevance_score: result.relevance_score as f64,
                            created_at: result.created_at,
                        });
                    }
                    "user" => {
                        users.push(UserResult {
                            id: result.id,
                            username: result.title.clone(),
                            display_name: result.title.clone(),
                            bio: if result.description.is_empty() {
                                None
                            } else {
                                Some(result.description)
                            },
                            avatar_url: if result.thumbnail_url.is_empty() {
                                None
                            } else {
                                Some(result.thumbnail_url)
                            },
                            is_verified: false,
                            follower_count: 0,
                            relevance_score: result.relevance_score as f64,
                        });
                    }
                    "hashtag" => {
                        hashtags.push(HashtagResult {
                            tag: result.title,
                            post_count: 0,
                            usage_count_24h: 0,
                            is_trending: false,
                        });
                    }
                    _ => {}
                }
            }

            Ok(HttpResponse::Ok().json(SearchAllResponse {
                content,
                users,
                hashtags,
                total_results: inner.total_count,
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

    // Build filter (SearchFilters in new proto)
    let filters =
        query.verified_only.map(
            |verified_only| crate::clients::proto::search::SearchFilters {
                content_type: String::new(),
                date_from: 0,
                date_to: 0,
                hashtags: vec![],
                language: String::new(),
                verified_only,
                sort_by: String::new(),
            },
        );

    let grpc_request = tonic::Request::new(SearchPostsRequest {
        query: query.q.clone(),
        limit: query.limit,
        offset: query.offset,
        filters,
    });

    match search_client.search_posts(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let results: Vec<ContentResult> = inner
                .posts
                .into_iter()
                .map(|c| ContentResult {
                    id: c.id,
                    content_type: "post".to_string(),
                    title: if c.title.is_empty() {
                        None
                    } else {
                        Some(c.title)
                    },
                    content: c.content,
                    author_id: c.author_id,
                    author_username: None,
                    author_avatar: None,
                    media_urls: vec![],
                    like_count: c.like_count,
                    comment_count: c.comment_count,
                    relevance_score: c.relevance_score as f64,
                    created_at: c.created_at,
                })
                .collect();

            let has_more = results.len() as i32 >= query.limit;

            Ok(HttpResponse::Ok().json(SearchContentResponse {
                results,
                total_count: inner.total_count,
                has_more,
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

    // New proto has verified_only as direct field, no UserSearchFilter
    let grpc_request = tonic::Request::new(SearchUsersRequest {
        query: query.q.clone(),
        limit: query.limit,
        offset: query.offset,
        verified_only: query.verified_only.unwrap_or(false),
    });

    match search_client.search_users(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let results: Vec<UserResult> = inner
                .users
                .into_iter()
                .map(|u| UserResult {
                    id: u.user_id,
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
                    relevance_score: u.relevance_score as f64,
                })
                .collect();

            let has_more = results.len() as i32 >= query.limit;

            Ok(HttpResponse::Ok().json(SearchUsersResponse {
                results,
                total_count: inner.total_count,
                has_more,
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

    // New proto doesn't have trending_only field
    let grpc_request = tonic::Request::new(SearchHashtagsRequest {
        query: query.q.clone(),
        limit: query.limit,
        offset: 0,
    });

    match search_client.search_hashtags(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            let results: Vec<HashtagResult> = inner
                .hashtags
                .into_iter()
                .map(|h| HashtagResult {
                    tag: h.tag,
                    post_count: h.post_count as i64,
                    usage_count_24h: h.usage_count as i64,
                    is_trending: h.trending_status == "trending",
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

    // New proto uses partial_query instead of query
    let grpc_request = tonic::Request::new(GetSearchSuggestionsRequest {
        partial_query: query.q.clone(),
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
                    suggestion_type: s.r#type,
                    frequency: s.popularity as i64, // popularity instead of frequency
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
/// Get trending searches (not hashtags/topics)
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

    // New proto uses GetTrendingSearchesRequest
    let grpc_request = tonic::Request::new(GetTrendingSearchesRequest {
        limit: query.limit,
        time_window: "24h".to_string(), // Default to 24h window
    });

    match search_client.get_trending_searches(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            // Map trending searches to topics format
            let topics: Vec<TrendingTopic> = inner
                .searches
                .into_iter()
                .map(|t| TrendingTopic {
                    tag: t.query,
                    post_count: 0,
                    usage_count_24h: t.search_count as i64,
                    trend_score: t.trend_score as f64,
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

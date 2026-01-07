/// Recommendation API Handlers
///
/// HTTP endpoints for personalized recommendations
use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::cache::CachedFeedPost;
use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::services::fallback_rank_posts;
use grpc_clients::nova::content_service::ListRecentPostsRequest;
use grpc_clients::nova::ranking_service::v1::{RankFeedRequest, RecallConfig};
use grpc_clients::RankingServiceClient;

/// Request body for ranking API (internal testing)
#[derive(Debug, Deserialize)]
pub struct RankingRequest {
    /// User ID to get recommendations for
    pub user_id: Uuid,

    /// Post IDs to rank
    pub candidates: Vec<Uuid>,

    /// Number of top recommendations to return (default: 20, max: 100)
    #[serde(default = "default_limit")]
    pub limit: usize,
}

/// Query parameters for GET /recommendations (v2)
#[derive(Debug, Deserialize)]
pub struct RecommendationQuery {
    /// Number of recommendations to return (default: 20, max: 100)
    #[serde(default = "default_limit")]
    pub limit: usize,
}

fn default_limit() -> usize {
    20
}

/// Recommendation response
#[derive(Debug, Serialize)]
pub struct RecommendationResponse {
    /// Array of post IDs in ranked order
    pub posts: Vec<Uuid>,

    /// Total count of recommendations
    pub count: usize,
}

/// Model info response
#[derive(Debug, Serialize)]
pub struct ModelInfoResponse {
    pub collaborative_version: String,
    pub content_version: String,
    pub onnx_version: String,
    pub deployed_at: String,
}

/// Ranked post in ranking response
#[derive(Debug, Serialize)]
pub struct RankedPostResponse {
    pub post_id: Uuid,
    pub score: f64,
    pub reason: String,
}

/// Ranking response
#[derive(Debug, Serialize)]
pub struct RankingResponse {
    pub posts: Vec<RankedPostResponse>,
    pub count: usize,
}

/// Handler state for recommendation service
pub struct RecommendationHandlerState {
    pub ranking_client: Arc<RankingServiceClient<tonic::transport::Channel>>,
}

/// GET /api/v2/recommendations
/// Get personalized recommendations for authenticated user
/// Delegates ranking to ranking-service, with smart fallback
#[get("/api/v2/recommendations")]
pub async fn get_recommendations(
    req: HttpRequest,
    query: web::Query<RecommendationQuery>,
    state: web::Data<RecommendationHandlerState>,
) -> Result<HttpResponse> {
    // Extract user ID from JWT token
    let user_id = req
        .extensions()
        .get::<UserId>()
        .cloned()
        .ok_or_else(|| AppError::Authentication("Missing user ID".to_string()))?
        .0;

    let limit = query.limit.min(100).max(1);

    debug!(
        "Getting recommendations for user: {}, limit: {}",
        user_id, limit
    );

    // Call ranking-service via gRPC
    let ranking_request = RankFeedRequest {
        user_id: user_id.to_string(),
        limit: limit as i32,
        recall_config: Some(RecallConfig {
            graph_recall_limit: 200,
            trending_recall_limit: 100,
            personalized_recall_limit: 100,
            enable_diversity: true,
        }),
    };

    let mut ranking_client = (*state.ranking_client).clone();

    match ranking_client.rank_feed(ranking_request).await {
        Ok(response) => {
            let ranked_posts = response.into_inner();
            let posts: Vec<Uuid> = ranked_posts
                .posts
                .into_iter()
                .filter_map(|p| Uuid::parse_str(&p.post_id).ok())
                .collect();

            let count = posts.len();
            Ok(HttpResponse::Ok().json(RecommendationResponse { posts, count }))
        }
        Err(err) => {
            warn!(
                "Ranking service unavailable: {:?}, using fallback ranking",
                err
            );

            // Track fallback usage (via tracing, metrics can be added later)
            tracing::info!(target: "feed.metrics", event = "ranking_fallback_used", reason = ?err);

            // Fallback: Fetch posts and apply local time-decay ranking
            match fetch_posts_with_metadata(user_id, limit).await {
                Ok(posts_with_metadata) => {
                    // Apply fallback ranking algorithm
                    let ranked_posts = fallback_rank_posts(posts_with_metadata);

                    // Convert to UUID vec
                    let posts: Vec<Uuid> = ranked_posts
                        .into_iter()
                        .filter_map(|p| Uuid::parse_str(&p.id).ok())
                        .collect();

                    let count = posts.len();
                    Ok(HttpResponse::Ok().json(RecommendationResponse { posts, count }))
                }
                Err(fallback_err) => {
                    error!("Fallback feed fetch failed: {:?}", fallback_err);
                    Err(AppError::Internal(format!(
                        "Failed to fetch feed: {:?}",
                        fallback_err
                    )))
                }
            }
        }
    }
}

/// Fetch posts with metadata for fallback ranking
/// Returns posts with engagement counts and timestamps needed for time-decay ranking
async fn fetch_posts_with_metadata(user_id: Uuid, limit: usize) -> Result<Vec<CachedFeedPost>> {
    // Load gRPC config and connect to content-service
    let cfg = grpc_clients::config::GrpcConfig::from_env()
        .map_err(|e| AppError::Internal(format!("load gRPC config failed: {}", e)))?;
    let channel = cfg
        .make_endpoint(&cfg.content_service.url)
        .map_err(|e| AppError::Internal(format!("content endpoint build failed: {}", e)))?
        .connect_lazy();

    let mut content_client =
        grpc_clients::nova::content_service::content_service_client::ContentServiceClient::new(
            channel.clone(),
        );

    // Fetch recent posts from content-service
    let list_resp = content_client
        .list_recent_posts(ListRecentPostsRequest {
            limit: limit as i32,
            exclude_user_id: user_id.to_string(),
        })
        .await
        .map_err(|e| AppError::Internal(format!("list_recent_posts fallback failed: {}", e)))?
        .into_inner();

    if list_resp.post_ids.is_empty() {
        return Ok(vec![]);
    }

    // Fetch full post details with metadata
    let get_resp = content_client
        .get_posts_by_ids(grpc_clients::nova::content_service::GetPostsByIdsRequest {
            post_ids: list_resp.post_ids.clone(),
        })
        .await
        .map_err(|e| AppError::Internal(format!("get_posts_by_ids fallback failed: {}", e)))?
        .into_inner();

    // Fetch social stats from social-service for engagement counts
    let social_channel = cfg
        .make_endpoint(&cfg.social_service.url)
        .map_err(|e| AppError::Internal(format!("social endpoint build failed: {}", e)))?
        .connect_lazy();

    let mut social_client =
        grpc_clients::nova::social_service::social_service_client::SocialServiceClient::new(
            social_channel,
        );

    let social_counts = match social_client
        .batch_get_counts(
            grpc_clients::nova::social_service::v2::BatchGetCountsRequest {
                post_ids: list_resp.post_ids.clone(),
            },
        )
        .await
    {
        Ok(response) => response.into_inner().counts,
        Err(e) => {
            warn!(
                "Failed to fetch social counts for fallback (continuing with zeros): {}",
                e
            );
            std::collections::HashMap::new()
        }
    };

    // Convert to CachedFeedPost format with engagement data
    let posts: Vec<CachedFeedPost> = get_resp
        .posts
        .into_iter()
        .map(|post| {
            let counts = social_counts.get(&post.id);
            CachedFeedPost {
                id: post.id.clone(),
                user_id: post.author_id,
                content: post.content,
                created_at: post.created_at,
                ranking_score: 0.0, // Will be computed by fallback ranking
                like_count: counts.map(|c| c.like_count as u32).unwrap_or(0),
                comment_count: counts.map(|c| c.comment_count as u32).unwrap_or(0),
                share_count: counts.map(|c| c.share_count as u32).unwrap_or(0),
                bookmark_count: counts.map(|c| c.bookmark_count as u32).unwrap_or(0),
                media_urls: post.media_urls,
                media_type: post.media_type,
                thumbnail_urls: post.thumbnail_urls,
                author_account_type: if post.author_account_type.is_empty() {
                    "primary".to_string()
                } else {
                    post.author_account_type
                },
            }
        })
        .collect();

    Ok(posts)
}

/// Fallback: Fetch chronological feed when ranking service is down
/// Legacy function - now superseded by fetch_posts_with_metadata + fallback_rank_posts
async fn fetch_chronological_feed(user_id: Uuid, limit: usize) -> Result<Vec<Uuid>> {
    // Degraded fallback: rely on content-service recency and exclude self posts
    let cfg = grpc_clients::config::GrpcConfig::from_env()
        .map_err(|e| AppError::Internal(format!("load gRPC config failed: {}", e)))?;
    let channel = cfg
        .make_endpoint(&cfg.content_service.url)
        .map_err(|e| AppError::Internal(format!("content endpoint build failed: {}", e)))?
        .connect_lazy();
    let mut client =
        grpc_clients::nova::content_service::content_service_client::ContentServiceClient::new(
            channel,
        );

    let resp = client
        .list_recent_posts(ListRecentPostsRequest {
            limit: limit as i32,
            exclude_user_id: user_id.to_string(),
        })
        .await
        .map_err(|e| AppError::Internal(format!("list_recent_posts fallback failed: {}", e)))?
        .into_inner();

    let posts = resp
        .post_ids
        .into_iter()
        .filter_map(|id| Uuid::parse_str(&id).ok())
        .collect();

    Ok(posts)
}

/// GET /api/v2/recommendations/model-info
/// Get current model version information (delegated to ranking-service)
#[get("/api/v2/recommendations/model-info")]
pub async fn get_model_info(_state: web::Data<RecommendationHandlerState>) -> Result<HttpResponse> {
    debug!("Model info endpoint deprecated - ranking handled by ranking-service");

    // Return basic info indicating delegation
    Ok(HttpResponse::Ok().json(ModelInfoResponse {
        collaborative_version: "delegated-to-ranking-service".to_string(),
        content_version: "delegated-to-ranking-service".to_string(),
        onnx_version: "delegated-to-ranking-service".to_string(),
        deployed_at: chrono::Utc::now().to_rfc3339(),
    }))
}

/// POST /api/v2/recommendations/rank
/// Internal API for ranking candidates (delegated to ranking-service)
/// Requires service-to-service authentication
#[post("/api/v2/recommendations/rank")]
pub async fn rank_candidates(
    req: HttpRequest,
    _body: web::Json<RankingRequest>,
    _state: web::Data<RecommendationHandlerState>,
) -> Result<HttpResponse> {
    // Verify internal service authentication
    if !req.headers().contains_key("x-service-token") {
        return Err(AppError::Authentication(
            "Missing service authentication token".to_string(),
        ));
    }

    // Ranking is now handled by ranking-service
    // This endpoint is deprecated and should call ranking-service directly
    Err(AppError::BadRequest(
        "This endpoint is deprecated. Use ranking-service directly.".to_string(),
    ))
}

/// Request for semantic search
#[derive(Debug, Deserialize)]
pub struct SemanticSearchRequest {
    /// Post ID to find similar posts for
    pub post_id: Uuid,

    /// Number of similar posts to return (default: 10, max: 100)
    #[serde(default = "default_semantic_limit")]
    pub limit: usize,
}

fn default_semantic_limit() -> usize {
    10
}

/// Semantic search result
#[derive(Debug, Serialize)]
pub struct SemanticSearchResult {
    pub post_id: Uuid,
    pub similarity_score: f32,
    pub distance: f32,
}

/// Semantic search response
#[derive(Debug, Serialize)]
pub struct SemanticSearchResponse {
    pub results: Vec<SemanticSearchResult>,
    pub count: usize,
}

/// POST /api/v2/recommendations/semantic-search
/// Search for semantically similar posts (delegated to ranking-service or feature-store)
/// Requires service-to-service authentication
#[post("/api/v2/recommendations/semantic-search")]
pub async fn semantic_search(
    req: HttpRequest,
    _body: web::Json<SemanticSearchRequest>,
    _state: web::Data<RecommendationHandlerState>,
) -> Result<HttpResponse> {
    // Verify internal service authentication
    if !req.headers().contains_key("x-service-token") {
        return Err(AppError::Authentication(
            "Missing service authentication token".to_string(),
        ));
    }

    // Semantic search is now handled by feature-store or ranking-service
    Err(AppError::BadRequest(
        "This endpoint is deprecated. Use feature-store or ranking-service directly.".to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_limit() {
        assert_eq!(default_limit(), 20);
    }

    #[test]
    fn test_recommendation_query_limits() {
        let mut query = RecommendationQuery { limit: 200 };
        let clamped = query.limit.min(100).max(1);
        assert_eq!(clamped, 100);

        query.limit = 0;
        let clamped = query.limit.min(100).max(1);
        assert_eq!(clamped, 1);
    }
}

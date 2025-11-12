/// Recommendation API Handlers
///
/// HTTP endpoints for personalized recommendations
use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use grpc_clients::RankingServiceClient;
use grpc_clients::nova::ranking_service::v1::{RankFeedRequest, RecallConfig};

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

/// Query parameters for GET /recommendations
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
    pub db_pool: sqlx::PgPool,
}

/// GET /api/v1/recommendations
/// Get personalized recommendations for authenticated user
/// Delegates ranking to ranking-service, with chronological fallback
#[get("/api/v1/recommendations")]
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
            warn!("Ranking service unavailable: {:?}, falling back to chronological feed", err);

            // Fallback: Simple chronological ordering
            match fetch_chronological_feed(&state.db_pool, user_id, limit).await {
                Ok(posts) => {
                    let count = posts.len();
                    Ok(HttpResponse::Ok().json(RecommendationResponse { posts, count }))
                }
                Err(fallback_err) => {
                    error!("Fallback feed fetch failed: {:?}", fallback_err);
                    Err(AppError::Internal(format!("Failed to fetch feed: {:?}", fallback_err)))
                }
            }
        }
    }
}

/// Fallback: Fetch chronological feed when ranking service is down
async fn fetch_chronological_feed(
    db_pool: &sqlx::PgPool,
    user_id: Uuid,
    limit: usize,
) -> Result<Vec<Uuid>> {
    let limit = limit as i64;

    // Get posts from followed users, ordered by recency
    let rows = sqlx::query(
        "SELECT DISTINCT p.id
         FROM posts p
         JOIN follows f ON f.followee_id = p.user_id
         WHERE f.follower_id = $1
           AND p.status = 'published'
           AND p.soft_delete IS NULL
         ORDER BY p.created_at DESC
         LIMIT $2",
    )
    .bind(user_id)
    .bind(limit)
    .fetch_all(db_pool)
    .await
    .map_err(|e| AppError::Internal(format!("Database error: {}", e)))?;

    let posts: Vec<Uuid> = rows
        .into_iter()
        .filter_map(|row| row.try_get::<Uuid, _>("id").ok())
        .collect();

    Ok(posts)
}

/// GET /api/v1/recommendations/model-info
/// Get current model version information (delegated to ranking-service)
#[get("/api/v1/recommendations/model-info")]
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

/// POST /api/v1/recommendations/rank
/// Internal API for ranking candidates (delegated to ranking-service)
/// Requires service-to-service authentication
#[post("/api/v1/recommendations/rank")]
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

/// POST /api/v1/recommendations/semantic-search
/// Search for semantically similar posts (delegated to ranking-service or feature-store)
/// Requires service-to-service authentication
#[post("/api/v1/recommendations/semantic-search")]
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

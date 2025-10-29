/// Recommendation API Handlers
///
/// HTTP endpoints for personalized recommendations
use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::services::RecommendationServiceV2;

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
    pub service: Arc<RecommendationServiceV2>,
}

/// GET /api/v1/recommendations
/// Get personalized recommendations for authenticated user
#[get("/api/v1/recommendations")]
pub async fn get_recommendations(
    req: HttpRequest,
    query: web::Query<RecommendationQuery>,
    state: web::Data<RecommendationHandlerState>,
) -> Result<HttpResponse> {
    // Extract user ID from JWT token
    let user_id = req.extensions()
        .get::<UserId>()
        .cloned()
        .ok_or_else(|| AppError::Authentication("Missing user ID".to_string()))?
        .0;

    let limit = query.limit.min(100).max(1);

    debug!("Getting recommendations for user: {}, limit: {}", user_id, limit);

    match state.service.get_recommendations(user_id, limit).await {
        Ok(posts) => {
            let count = posts.len();
            Ok(HttpResponse::Ok().json(RecommendationResponse {
                posts,
                count,
            }))
        }
        Err(err) => {
            error!("Failed to get recommendations: {:?}", err);
            Err(err)
        }
    }
}

/// GET /api/v1/recommendations/model-info
/// Get current model version information
#[get("/api/v1/recommendations/model-info")]
pub async fn get_model_info(
    state: web::Data<RecommendationHandlerState>,
) -> Result<HttpResponse> {
    debug!("Getting model info");

    let info = state.service.get_model_info().await;

    Ok(HttpResponse::Ok().json(ModelInfoResponse {
        collaborative_version: info.collaborative_version,
        content_version: info.content_version,
        onnx_version: info.onnx_version,
        deployed_at: info.deployed_at.to_rfc3339(),
    }))
}

/// POST /api/v1/recommendations/rank
/// Internal API for ranking candidates (testing/debugging)
/// Requires service-to-service authentication
#[post("/api/v1/recommendations/rank")]
pub async fn rank_candidates(
    req: HttpRequest,
    body: web::Json<RankingRequest>,
    state: web::Data<RecommendationHandlerState>,
) -> Result<HttpResponse> {
    // Verify internal service authentication
    // TODO: Implement service-to-service auth (e.g., mTLS or service token)
    if !req.headers().contains_key("x-service-token") {
        return Err(AppError::Authentication(
            "Missing service authentication token".to_string(),
        ));
    }

    let limit = body.limit.min(100).max(1);

    debug!(
        "Ranking {} candidates for user: {}, limit: {}",
        body.candidates.len(),
        body.user_id,
        limit
    );

    if body.candidates.is_empty() {
        return Err(AppError::BadRequest(
            "No candidates provided".to_string(),
        ));
    }

    // Create default user context (no recent posts/profile)
    let context = crate::services::UserContext::default();

    match state.service
        .rank_with_context(body.user_id, context, body.candidates.clone(), limit)
        .await
    {
        Ok(posts) => {
            let count = posts.len();
            Ok(HttpResponse::Ok().json(RecommendationResponse {
                posts,
                count,
            }))
        }
        Err(err) => {
            error!("Failed to rank candidates: {:?}", err);
            Err(err)
        }
    }
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
/// Search for semantically similar posts using vector embeddings
/// Requires service-to-service authentication
#[post("/api/v1/recommendations/semantic-search")]
pub async fn semantic_search(
    req: HttpRequest,
    body: web::Json<SemanticSearchRequest>,
    state: web::Data<RecommendationHandlerState>,
) -> Result<HttpResponse> {
    // Verify internal service authentication
    if !req.headers().contains_key("x-service-token") {
        return Err(AppError::Authentication(
            "Missing service authentication token".to_string(),
        ));
    }

    let limit = body.limit.min(100).max(1);

    debug!(
        "Semantic search for post: {}, limit: {}",
        body.post_id, limit
    );

    match state.service
        .search_semantically_similar(body.post_id, limit)
        .await
    {
        Ok(results) => {
            let count = results.len();
            let semantic_results = results
                .into_iter()
                .map(|r| SemanticSearchResult {
                    post_id: r.post_id,
                    similarity_score: r.similarity_score,
                    distance: r.distance,
                })
                .collect();

            Ok(HttpResponse::Ok().json(SemanticSearchResponse {
                results: semantic_results,
                count,
            }))
        }
        Err(err) => {
            error!("Failed to perform semantic search: {:?}", err);
            Err(err)
        }
    }
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

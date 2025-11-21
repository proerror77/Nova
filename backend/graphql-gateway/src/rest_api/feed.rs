/// Feed API endpoints
///
/// GET /api/v2/feed - Get personalized feed for current user
use actix_web::{web, HttpRequest, HttpResponse, Result};
use awc::Client;
use tracing::{error, info};

use super::models::{ErrorResponse, FeedPost, GetFeedResponse};
use crate::clients::proto::feed::GetFeedRequest as ProtoGetFeedRequest;
use crate::clients::ServiceClients;

/// GET /api/v2/feed
/// Returns personalized feed for the authenticated user
/// Query parameters:
///   - user_id: The user ID to fetch feed for (required)
///   - limit: Number of posts to return (default: 20, max: 100)
///   - cursor: Pagination cursor for next page (optional)
///   - algorithm: Algorithm variant - "ch", "v2", "hybrid" (default: "v2")
pub async fn get_feed(
    _req: HttpRequest,
    _clients: web::Data<ServiceClients>,
    query: web::Query<FeedQueryParams>,
) -> Result<HttpResponse> {
    let user_id = query.user_id.clone();
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

    // HTTP fallback: forward to feed-service REST endpoint to bypass gRPC/TLS issues
    let mut url = format!(
        "http://feed-service:8084/api/v2/feed?user_id={}&limit={}",
        user_id, limit
    );
    if !cursor.is_empty() {
        url.push_str(&format!("&cursor={}", cursor));
    }
    if !algorithm.is_empty() {
        url.push_str(&format!("&algorithm={}", algorithm));
    }

    let client = Client::new();
    let mut req_builder = client.get(url);
    if let Some(auth) = _req.headers().get("Authorization") {
        req_builder = req_builder.insert_header(("Authorization", auth.clone()));
    }

    let mut resp = match req_builder.send().await {
        Ok(r) => r,
        Err(e) => {
            error!(user_id=%user_id, error=%e, "HTTP call to feed-service failed");
            return Ok(HttpResponse::BadGateway().json(ErrorResponse::with_message(
                "Upstream error",
                "feed-service unreachable",
            )));
        }
    };

    let status = resp.status();
    let body = match resp.body().await {
        Ok(b) => b,
        Err(e) => {
            error!(user_id=%user_id, error=%e, "Failed to read response from feed-service");
            return Ok(HttpResponse::BadGateway().json(ErrorResponse::with_message(
                "Upstream error",
                "Failed to read feed response",
            )));
        }
    };

    let mut builder = HttpResponse::build(status);
    if let Some(ct) = resp.headers().get("Content-Type") {
        builder.insert_header(("Content-Type", ct.clone()));
    }
    Ok(builder.body(body))
}

#[derive(Debug, serde::Deserialize)]
pub struct FeedQueryParams {
    pub user_id: String,
    pub limit: Option<u32>,
    pub cursor: Option<String>,
    pub algorithm: Option<String>,
}

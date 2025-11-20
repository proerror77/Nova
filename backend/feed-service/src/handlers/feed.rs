use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, info};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::grpc::clients::{ContentServiceClient, GraphServiceClient};
use crate::middleware::jwt_auth::UserId;
use crate::models::FeedResponse;
use grpc_clients::nova::graph_service::v2::GetFollowingRequest;
use grpc_clients::nova::content_service::v2::GetPostsByAuthorRequest;

#[derive(Debug, Deserialize)]
pub struct FeedQueryParams {
    #[serde(default = "default_algo")]
    pub algo: String,
    #[serde(default = "default_limit")]
    pub limit: u32,
    pub cursor: Option<String>,
}

fn default_algo() -> String {
    "ch".to_string()
}

fn default_limit() -> u32 {
    20
}

impl FeedQueryParams {
    fn decode_cursor(&self) -> Result<usize> {
        match &self.cursor {
            Some(cursor) if !cursor.is_empty() => {
                let decoded = general_purpose::STANDARD
                    .decode(cursor)
                    .map_err(|_| AppError::BadRequest("Invalid cursor format".to_string()))?;
                let offset_str = String::from_utf8(decoded)
                    .map_err(|_| AppError::BadRequest("Invalid cursor encoding".to_string()))?;
                offset_str
                    .parse::<usize>()
                    .map_err(|_| AppError::BadRequest("Invalid cursor value".to_string()))
            }
            _ => Ok(0),
        }
    }

    fn encode_cursor(offset: usize) -> String {
        general_purpose::STANDARD.encode(offset.to_string())
    }
}

pub struct FeedHandlerState {
    pub content_client: Arc<ContentServiceClient>,
    pub graph_client: Arc<GraphServiceClient>,
}

#[get("")]
pub async fn get_feed(
    query: web::Query<FeedQueryParams>,
    http_req: HttpRequest,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    if query.algo != "ch" && query.algo != "time" {
        return Err(AppError::BadRequest(
            "Invalid algo parameter. Must be 'ch' or 'time'".to_string(),
        ));
    }

    let limit = query.limit.min(100).max(1);
    let offset = query.decode_cursor()?;

    debug!(
        "Getting feed for user: user={} algo={} limit={} offset={}",
        user_id, query.algo, limit, offset
    );

    // Step 1: Get user's following list via graph-service gRPC
    let following_resp = state
        .graph_client
        .pool
        .graph()
        .get_following(GetFollowingRequest {
            user_id: user_id.to_string(),
            limit: 1000,
            offset: 0,
        })
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch following list: {}", e)))?
        .into_inner();

    // Step 2: Get posts from followed users via batch gRPC call
    let followed_user_ids: Vec<String> = following_resp
        .user_ids
        .into_iter()
        .take(100) // Limit to prevent huge batch requests
        .collect();

    if followed_user_ids.is_empty() {
        // User doesn't follow anyone, return empty feed
        return Ok(HttpResponse::Ok().json(FeedResponse {
            posts: vec![],
            cursor: None,
            has_more: false,
            total_count: 0,
        }));
    }

    // Fetch posts from each followed user and aggregate them
    // Note: In production, would use ranking/recommendation service for ordering
    let mut all_posts: Vec<Uuid> = vec![];

    for user_id in followed_user_ids.iter() {
        match state
            .content_client
            .get_posts_by_author(GetPostsByAuthorRequest {
                author_id: user_id.clone(),
                status: "".to_string(), // Empty string means all statuses
                limit: limit as i32,
                offset: offset as i32,
            })
            .await
        {
            Ok(resp) => {
                for post in resp.posts {
                    if let Ok(post_id) = Uuid::parse_str(&post.id) {
                        all_posts.push(post_id);
                    }
                }
            }
            Err(e) => {
                debug!("Failed to fetch posts from user {}: {}", user_id, e);
                // Continue fetching other users' posts on partial failure
            }
        }
    }

    // Apply pagination on aggregated posts
    let start = offset;
    let end = (offset + limit as usize).min(all_posts.len());
    let posts: Vec<Uuid> = all_posts[start..end].to_vec();
    let posts_count = posts.len();
    let total_count = all_posts.len();

    let cursor = FeedQueryParams::encode_cursor(offset + limit as usize);

    info!(
        "Feed generated for user: {} (followers: {}, posts: {})",
        user_id,
        followed_user_ids.len(),
        posts_count
    );

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts,
        cursor: Some(cursor),
        has_more: posts_count == limit as usize,
        total_count: posts_count,
    }))
}

/// Cache invalidation is handled through Redis/Kafka events in production.
/// Manual invalidation endpoint would trigger cache refresh for user's feed.
/// TODO: Implement Redis cache invalidation layer (Phase 1 Stage 1.4 Week 13-14)

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cursor_roundtrip() {
        let offset = 42;
        let encoded = FeedQueryParams::encode_cursor(offset);
        let params = FeedQueryParams {
            algo: default_algo(),
            limit: default_limit(),
            cursor: Some(encoded),
        };
        assert_eq!(params.decode_cursor().unwrap(), offset);
    }

    #[test]
    fn test_cursor_none_defaults_zero() {
        let params = FeedQueryParams {
            algo: default_algo(),
            limit: default_limit(),
            cursor: None,
        };
        assert_eq!(params.decode_cursor().unwrap(), 0);
    }
}

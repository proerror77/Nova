use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::grpc::clients::{ContentServiceClient, GraphServiceClient};
use crate::middleware::jwt_auth::UserId;
use crate::models::FeedResponse;
use grpc_clients::nova::content_service::v2::{ContentStatus, GetUserPostsRequest, ListRecentPostsRequest};
use grpc_clients::nova::graph_service::v2::GetFollowingRequest;

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

    // Step 1: Try to get user's following list via graph-service gRPC
    // If graph-service is unavailable, fall back to global/recent posts (graceful degradation)
    let following_result = state
        .graph_client
        .pool
        .graph()
        .get_following(GetFollowingRequest {
            user_id: user_id.to_string(),
            limit: 1000,
            offset: 0,
        })
        .await;

    let (posts, posts_count, total_count, has_more) = match following_result {
        Ok(following_resp) => {
            // Step 2: Get posts from followed users via batch gRPC call
            let followed_user_ids: Vec<String> = following_resp
                .into_inner()
                .user_ids
                .into_iter()
                .take(100) // Limit to prevent huge batch requests
                .collect();

            if followed_user_ids.is_empty() {
                // User doesn't follow anyone - fall back to global feed
                warn!(
                    "User {} follows no one, falling back to global feed",
                    user_id
                );
                fetch_global_posts(&state.content_client, limit, offset).await?
            } else {
                // Fetch posts from followed users and respect pagination (offset/cursor)
                // Note: For now we do a simple round-robin scan; ranking-service can be plugged in later.
                let mut posts: Vec<Uuid> = Vec::new();
                let mut skipped = offset; // apply cursor across aggregated stream
                let mut remaining = limit as usize;

                for uid in followed_user_ids.iter() {
                    if remaining == 0 {
                        break;
                    }

                    match state
                        .content_client
                        .get_user_posts(GetUserPostsRequest {
                            user_id: uid.clone(),
                            limit: remaining as i32, // bound fetch to what's still needed
                            offset: 0,
                            status: ContentStatus::Published as i32,
                        })
                        .await
                    {
                        Ok(resp) => {
                            for post in resp.posts {
                                if remaining == 0 {
                                    break;
                                }
                                if skipped > 0 {
                                    skipped -= 1;
                                    continue;
                                }
                                if let Ok(post_id) = Uuid::parse_str(&post.id) {
                                    posts.push(post_id);
                                    remaining -= 1;
                                }
                            }
                        }
                        Err(e) => {
                            debug!("Failed to fetch posts from user {}: {}", uid, e);
                            // Continue fetching other users' posts on partial failure
                        }
                    }
                }

                let posts_count = posts.len();
                let total_count = offset + posts_count; // best-effort; exact total would need a count query
                let has_more = remaining == 0;

                info!(
                    "Feed generated for user: {} (followers: {}, posts: {})",
                    user_id,
                    followed_user_ids.len(),
                    posts_count
                );

                (posts, posts_count, total_count, has_more)
            }
        }
        Err(e) => {
            // Graph-service unavailable - graceful degradation to global feed
            warn!(
                "Graph-service unavailable ({}), falling back to global feed for user {}",
                e, user_id
            );
            fetch_global_posts(&state.content_client, limit, offset).await?
        }
    };

    let cursor = if has_more {
        Some(FeedQueryParams::encode_cursor(offset + posts_count))
    } else {
        None
    };

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts,
        cursor,
        has_more,
        total_count,
    }))
}

/// Fetch global/recent posts as a fallback when graph-service is unavailable
/// or user doesn't follow anyone
async fn fetch_global_posts(
    content_client: &ContentServiceClient,
    limit: u32,
    offset: usize,
) -> Result<(Vec<Uuid>, usize, usize, bool)> {
    let resp = content_client
        .list_recent_posts(ListRecentPostsRequest {
            limit: limit as i32,
            offset: offset as i32,
            status: ContentStatus::Published as i32,
        })
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch recent posts: {}", e)))?;

    let posts: Vec<Uuid> = resp
        .posts
        .into_iter()
        .filter_map(|p| Uuid::parse_str(&p.id).ok())
        .collect();

    let posts_count = posts.len();
    let total_count = offset + posts_count;
    let has_more = posts_count == limit as usize;

    info!(
        "Global feed generated (fallback): posts={}, offset={}, has_more={}",
        posts_count, offset, has_more
    );

    Ok((posts, posts_count, total_count, has_more))
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

use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::grpc::clients::{ContentServiceClient, GraphServiceClient};
use crate::middleware::jwt_auth::UserId;
use crate::models::{FeedPostFull, FeedResponse};
use grpc_clients::nova::content_service::v2::{
    ContentStatus, GetPostsByIdsRequest, GetUserPostsRequest, ListRecentPostsRequest,
};
use grpc_clients::nova::graph_service::v2::GetFollowingRequest;
use grpc_clients::nova::identity_service::v2::GetUserProfilesByIdsRequest;
use grpc_clients::nova::social_service::v2::BatchGetCountsRequest;

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
    50 // Increased from 20 for better user experience
}

/// Cursor format for timestamp-based pagination: "timestamp:post_id"
#[derive(Debug, Clone, Default)]
pub struct FeedCursor {
    pub timestamp: i64,
    pub post_id: String,
}

impl FeedQueryParams {
    /// Decode cursor - supports both legacy offset format and new timestamp:post_id format
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

    /// Decode timestamp-based cursor for proper pagination
    fn decode_timestamp_cursor(&self) -> Result<FeedCursor> {
        match &self.cursor {
            Some(cursor) if !cursor.is_empty() => {
                let decoded = general_purpose::STANDARD
                    .decode(cursor)
                    .map_err(|_| AppError::BadRequest("Invalid cursor format".to_string()))?;
                let cursor_str = String::from_utf8(decoded)
                    .map_err(|_| AppError::BadRequest("Invalid cursor encoding".to_string()))?;

                // New format: "timestamp:post_id"
                if let Some((ts_str, post_id)) = cursor_str.split_once(':') {
                    let timestamp = ts_str.parse::<i64>()
                        .map_err(|_| AppError::BadRequest("Invalid cursor timestamp".to_string()))?;
                    Ok(FeedCursor {
                        timestamp,
                        post_id: post_id.to_string(),
                    })
                } else {
                    // Legacy format: just an offset number - convert to empty cursor
                    Ok(FeedCursor::default())
                }
            }
            _ => Ok(FeedCursor::default()),
        }
    }

    fn encode_cursor(offset: usize) -> String {
        general_purpose::STANDARD.encode(offset.to_string())
    }

    /// Encode timestamp-based cursor
    fn encode_timestamp_cursor(timestamp: i64, post_id: &str) -> String {
        let cursor_str = format!("{}:{}", timestamp, post_id);
        general_purpose::STANDARD.encode(cursor_str)
    }
}

pub struct FeedHandlerState {
    pub content_client: Arc<ContentServiceClient>,
    pub graph_client: Arc<GraphServiceClient>,
    pub grpc_pool: Arc<grpc_clients::GrpcClientPool>,
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
            viewer_id: String::new(), // Not needed for feed
        })
        .await;

    // Decode timestamp-based cursor for proper pagination
    let feed_cursor = query.decode_timestamp_cursor()?;

    let (posts, posts_count, total_count, has_more, next_cursor_ts, next_cursor_post_id) = match following_result {
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
                let (posts, count, total, more) = fetch_global_posts(&state.content_client, user_id, limit, offset).await?;
                (posts, count, total, more, 0i64, String::new())
            } else {
                // Use new ListPostsByUsers API with timestamp-based pagination
                use grpc_clients::nova::content_service::v2::ListPostsByUsersRequest;

                let list_request = ListPostsByUsersRequest {
                    user_ids: followed_user_ids.clone(),
                    limit: limit as i32,
                    before_timestamp: feed_cursor.timestamp,
                    before_post_id: feed_cursor.post_id.clone(),
                };

                match state.content_client.list_posts_by_users(list_request).await {
                    Ok(resp) => {
                        let posts: Vec<Uuid> = resp.posts
                            .iter()
                            .filter_map(|p| Uuid::parse_str(&p.post_id).ok())
                            .collect();

                        let posts_count = posts.len();
                        let total_count = posts_count; // Approximate
                        let has_more = resp.has_more;
                        let next_ts = resp.next_cursor_timestamp;
                        let next_post_id = resp.next_cursor_post_id.clone();

                        info!(
                            "Feed generated for user: {} (followers: {}, posts: {}, has_more: {})",
                            user_id,
                            followed_user_ids.len(),
                            posts_count,
                            has_more
                        );

                        (posts, posts_count, total_count, has_more, next_ts, next_post_id)
                    }
                    Err(e) => {
                        // Fallback to legacy round-robin if new API fails
                        warn!(
                            "ListPostsByUsers failed ({}), falling back to round-robin for user {}",
                            e, user_id
                        );

                        // Legacy round-robin logic for backward compatibility
                        let mut posts: Vec<Uuid> = Vec::new();
                        let mut skipped = offset;
                        let mut remaining = limit as usize;

                        for uid in followed_user_ids.iter() {
                            if remaining == 0 {
                                break;
                            }

                            match state
                                .content_client
                                .get_user_posts(GetUserPostsRequest {
                                    user_id: uid.clone(),
                                    limit: remaining as i32,
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
                                }
                            }
                        }

                        let posts_count = posts.len();
                        let total_count = offset + posts_count;
                        let has_more = remaining == 0;

                        (posts, posts_count, total_count, has_more, 0i64, String::new())
                    }
                }
            }
        }
        Err(e) => {
            // Graph-service unavailable - graceful degradation to global feed
            warn!(
                "Graph-service unavailable ({}), falling back to global feed for user {}",
                e, user_id
            );
            let (posts, count, total, more) = fetch_global_posts(&state.content_client, user_id, limit, offset).await?;
            (posts, count, total, more, 0i64, String::new())
        }
    };

    // Use timestamp-based cursor if available, otherwise fall back to offset-based
    let cursor = if has_more {
        if next_cursor_ts > 0 && !next_cursor_post_id.is_empty() {
            Some(FeedQueryParams::encode_timestamp_cursor(next_cursor_ts, &next_cursor_post_id))
        } else {
            Some(FeedQueryParams::encode_cursor(offset + posts_count))
        }
    } else {
        None
    };

    // Step: Fetch full post details from content-service
    let full_posts = fetch_full_posts(&state, &posts).await?;

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts: full_posts,
        cursor,
        has_more,
        total_count,
    }))
}

/// Fetch full post details from content-service and social stats
async fn fetch_full_posts(
    state: &FeedHandlerState,
    post_ids: &[Uuid],
) -> Result<Vec<FeedPostFull>> {
    if post_ids.is_empty() {
        return Ok(vec![]);
    }

    let post_id_strings: Vec<String> = post_ids.iter().map(|id| id.to_string()).collect();

    // Fetch full post details from content-service
    let posts_resp = state
        .content_client
        .get_posts_by_ids(GetPostsByIdsRequest {
            post_ids: post_id_strings.clone(),
        })
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch post details: {}", e)))?;

    // Batch fetch author profiles from identity-service (graceful degradation if unavailable)
    let author_ids: Vec<String> = posts_resp
        .posts
        .iter()
        .map(|p| p.author_id.clone())
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();

    let author_profiles: HashMap<String, grpc_clients::nova::identity_service::v2::UserProfile> = if author_ids.is_empty() {
        HashMap::new()
    } else {
        let mut auth_client = state.grpc_pool.auth();
        match auth_client
            .get_user_profiles_by_ids(tonic::Request::new(GetUserProfilesByIdsRequest {
                user_ids: author_ids,
            }))
            .await
        {
            Ok(resp) => resp
                .into_inner()
                .profiles
                .into_iter()
                .map(|p| (p.user_id.clone(), p))
                .collect(),
            Err(e) => {
                warn!(
                    "Failed to fetch author profiles from identity-service (continuing without author info): {}",
                    e
                );
                HashMap::new()
            }
        }
    };

    // Fetch social stats from social-service (graceful degradation if unavailable)
    let mut social_client = state.grpc_pool.social();
    let social_counts = match social_client
        .batch_get_counts(BatchGetCountsRequest {
            post_ids: post_id_strings.clone(),
        })
        .await
    {
        Ok(resp) => resp.into_inner().counts,
        Err(e) => {
            warn!("Failed to fetch social counts (continuing with zeros): {}", e);
            std::collections::HashMap::new()
        }
    };

    // Convert to FeedPostFull with social stats
    let full_posts: Vec<FeedPostFull> = posts_resp
        .posts
        .into_iter()
        .enumerate()
        .map(|(idx, post)| {
            let counts = social_counts.get(&post.id);
            let mut thumbnail_urls = post.thumbnail_urls.clone();
            let media_urls = post.media_urls.clone();

            // Fall back to media_urls if no thumbnails
            if thumbnail_urls.is_empty() {
                thumbnail_urls = media_urls.clone();
            }

            let profile = author_profiles.get(&post.author_id);
            let author_username = profile.map(|p| p.username.clone());
            let author_display_name = profile.and_then(|p| {
                let display = p.display_name.clone().unwrap_or_default();
                if display.is_empty() {
                    Some(p.username.clone())
                } else {
                    Some(display)
                }
            });
            let author_avatar = profile.and_then(|p| p.avatar_url.clone());

            FeedPostFull {
                id: post.id.clone(),
                user_id: post.author_id.clone(),
                content: post.content.clone(),
                created_at: post.created_at,
                ranking_score: 1.0 - (idx as f64 * 0.01),
                like_count: counts.map(|c| c.like_count as u32).unwrap_or(0),
                comment_count: counts.map(|c| c.comment_count as u32).unwrap_or(0),
                share_count: counts.map(|c| c.share_count as u32).unwrap_or(0),
                bookmark_count: counts.map(|c| c.bookmark_count as u32).unwrap_or(0),
                media_urls,
                thumbnail_urls,
                media_type: post.media_type.clone(),
                author_username,
                author_display_name,
                author_avatar,
            }
        })
        .collect();

    info!("Fetched {} full posts with social stats", full_posts.len());
    Ok(full_posts)
}

/// Fetch global/recent posts as a fallback when graph-service is unavailable
/// or user doesn't follow anyone
async fn fetch_global_posts(
    content_client: &ContentServiceClient,
    _user_id: Uuid,
    limit: u32,
    offset: usize,
) -> Result<(Vec<Uuid>, usize, usize, bool)> {
    // Prevent unbounded requests in degraded mode
    let page_limit = limit.min(100).max(1);
    let request_limit = ((page_limit as usize).saturating_add(offset)).min(500) as i32;

    let resp = content_client
        .list_recent_posts(ListRecentPostsRequest {
            limit: request_limit,
            // Do NOT exclude the current user; we want to return something even if the user
            // only has their own posts. This avoids empty feeds when graph data is missing.
            exclude_user_id: String::new(),
        })
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch recent posts: {}", e)))?;

    let all_posts: Vec<Uuid> = resp
        .post_ids
        .into_iter()
        .filter_map(|id| Uuid::parse_str(&id).ok())
        .collect();

    // Debug visibility into fallback result size
    info!(
        "Global fallback posts fetched: total_received={} request_limit={} page_limit={}",
        all_posts.len(),
        request_limit,
        page_limit
    );

    let start = offset.min(all_posts.len());
    let end = (start + page_limit as usize).min(all_posts.len());
    let posts = all_posts[start..end].to_vec();

    let posts_count = posts.len();
    let total_count = offset + posts_count;
    // Best-effort has_more: assume more items may exist if we received a full page
    let has_more = (all_posts.len() as i32) == request_limit && posts_count == page_limit as usize;

    info!(
        "Global feed generated (fallback): posts_page={}, offset={}, requested_limit={}, has_more={}",
        posts_count, offset, page_limit, has_more
    );

    Ok((posts, posts_count, total_count, has_more))
}

/// Cache invalidation is handled through Redis/Kafka events in production.
/// Manual invalidation endpoint would trigger cache refresh for user's feed.
/// TODO: Implement Redis cache invalidation layer (Phase 1 Stage 1.4 Week 13-14)

/// Guest Feed endpoint - returns trending/recent posts without authentication.
/// This enables the "Guest Mode" UX where users can browse content before signing up.
///
/// Algorithm: Returns recent published posts sorted by recency (time-based).
/// Future improvement: Add engagement-based ranking (likes * 1 + comments * 2 + shares * 3).
#[get("/trending")]
pub async fn get_guest_feed(
    query: web::Query<FeedQueryParams>,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    let limit = query.limit.min(50).max(1); // Stricter limit for guest feed
    let offset = query.decode_cursor()?;

    info!("Guest feed request: limit={} offset={}", limit, offset);

    // Fetch global/recent posts - no user exclusion for guest mode
    let request_limit = ((limit as usize).saturating_add(offset)).min(200) as i32;

    let resp = state
        .content_client
        .list_recent_posts(ListRecentPostsRequest {
            limit: request_limit,
            exclude_user_id: String::new(), // Don't exclude any user
        })
        .await
        .map_err(|e| AppError::Internal(format!("Failed to fetch trending posts: {}", e)))?;

    let all_posts: Vec<Uuid> = resp
        .post_ids
        .into_iter()
        .filter_map(|id| Uuid::parse_str(&id).ok())
        .collect();

    let start = offset.min(all_posts.len());
    let end = (start + limit as usize).min(all_posts.len());
    let posts = all_posts[start..end].to_vec();

    let posts_count = posts.len();
    let total_count = offset + posts_count;
    let has_more = (all_posts.len() as i32) == request_limit && posts_count == limit as usize;

    let cursor = if has_more {
        Some(FeedQueryParams::encode_cursor(offset + posts_count))
    } else {
        None
    };

    info!(
        "Guest feed generated: posts={}, offset={}, has_more={}",
        posts_count, offset, has_more
    );

    // Fetch full post details from content-service
    let full_posts = fetch_full_posts(&state, &posts).await?;

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts: full_posts,
        cursor,
        has_more,
        total_count,
    }))
}

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

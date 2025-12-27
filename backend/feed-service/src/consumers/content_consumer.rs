use crate::cache::FeedCache;
use crate::error::Result;
use grpc_clients::GrpcClientPool;
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, info, warn};

/// Maximum number of followers to fan-out cache invalidation to.
/// Beyond this threshold, we let caches expire naturally to avoid
/// overwhelming Redis during high-traffic events.
const MAX_FANOUT_FOLLOWERS: i32 = 10_000;

/// Payload shape for a PostCreated event as emitted by content-service.
/// This matches the JSON we currently publish via transactional-outbox.
#[derive(Debug, Deserialize)]
pub struct PostCreatedEvent {
    pub post_id: String,
    pub user_id: String,
    pub caption: Option<String>,
    #[serde(default)]
    pub content_type: String,
    #[serde(default)]
    pub media_type: String,
    pub status: String,
}

/// Handle a PostCreated event by invalidating the author's feed cache
/// AND all followers' feed caches (fan-out invalidation).
///
/// When a user publishes a new post, we need to:
/// 1. Invalidate the author's own feed cache
/// 2. Invalidate all followers' feed caches so they see the new post
///
/// This ensures feed freshness without requiring TTL-based expiration.
pub async fn handle_post_created(
    cache: &FeedCache,
    grpc_pool: Option<&Arc<GrpcClientPool>>,
    event: PostCreatedEvent,
) -> Result<()> {
    info!(
        post_id = %event.post_id,
        user_id = %event.user_id,
        "Handling PostCreated event - starting fan-out invalidation"
    );

    // 1. Invalidate author's own feed cache
    cache.invalidate_feed(&event.user_id).await?;
    debug!(user_id = %event.user_id, "Invalidated author's feed cache");

    // 2. Fan-out: Invalidate all followers' feed caches
    if let Some(pool) = grpc_pool {
        match fan_out_invalidate_followers(cache, pool, &event.user_id).await {
            Ok(count) => {
                info!(
                    user_id = %event.user_id,
                    followers_invalidated = count,
                    "Fan-out cache invalidation completed"
                );
            }
            Err(e) => {
                // Log but don't fail - cache will expire naturally
                warn!(
                    user_id = %event.user_id,
                    error = %e,
                    "Fan-out cache invalidation failed (caches will expire via TTL)"
                );
            }
        }
    } else {
        debug!(
            user_id = %event.user_id,
            "Skipping fan-out invalidation - no gRPC pool available"
        );
    }

    Ok(())
}

/// Fetch followers from graph-service and invalidate their feed caches.
///
/// Uses pagination to handle users with many followers efficiently.
/// Caps at MAX_FANOUT_FOLLOWERS to prevent resource exhaustion for
/// extremely popular users (celebrities, brands).
async fn fan_out_invalidate_followers(
    cache: &FeedCache,
    grpc_pool: &Arc<GrpcClientPool>,
    author_id: &str,
) -> Result<usize> {
    use grpc_clients::nova::graph_service::v2::GetFollowersRequest;

    let mut total_invalidated = 0;
    let mut offset = 0;
    let page_size = 500; // Batch size for pagination

    loop {
        // Check if we've reached the fan-out limit
        if total_invalidated >= MAX_FANOUT_FOLLOWERS as usize {
            info!(
                author_id = %author_id,
                limit = MAX_FANOUT_FOLLOWERS,
                "Reached fan-out limit, remaining followers will use TTL expiration"
            );
            break;
        }

        // Fetch a page of followers
        let mut client = grpc_pool.graph();
        let response = client
            .get_followers(GetFollowersRequest {
                user_id: author_id.to_string(),
                limit: page_size,
                offset,
                viewer_id: String::new(),
            })
            .await
            .map_err(|e| crate::error::AppError::Internal(format!("gRPC error: {}", e)))?
            .into_inner();

        let followers = response.user_ids;
        let batch_size = followers.len();

        if batch_size == 0 {
            break;
        }

        // Collect follower IDs for batch invalidation
        let follower_refs: Vec<&str> = followers.iter().map(|s| s.as_str()).collect();

        // Batch invalidate all followers' feed caches
        cache.batch_invalidate_feeds(&follower_refs).await?;

        total_invalidated += batch_size;
        offset += page_size;

        debug!(
            author_id = %author_id,
            batch_size = batch_size,
            total_invalidated = total_invalidated,
            "Invalidated batch of follower feed caches"
        );

        // Check if we've processed all followers
        if batch_size < page_size as usize {
            break;
        }
    }

    Ok(total_invalidated)
}

/// Handle a PostDeleted event by invalidating related caches.
#[derive(Debug, Deserialize)]
pub struct PostDeletedEvent {
    pub post_id: String,
    pub user_id: String,
}

pub async fn handle_post_deleted(
    cache: &FeedCache,
    grpc_pool: Option<&Arc<GrpcClientPool>>,
    event: PostDeletedEvent,
) -> Result<()> {
    info!(
        post_id = %event.post_id,
        user_id = %event.user_id,
        "Handling PostDeleted event"
    );

    // Invalidate author's feed cache
    cache.invalidate_feed(&event.user_id).await?;

    // Fan-out to followers (same logic as post created)
    if let Some(pool) = grpc_pool {
        if let Err(e) = fan_out_invalidate_followers(cache, pool, &event.user_id).await {
            warn!(
                user_id = %event.user_id,
                error = %e,
                "Fan-out cache invalidation failed for deleted post"
            );
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_post_created_event_deserialize() {
        let json = r#"{
            "post_id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "987fcdeb-51a2-3bc4-d567-890123456789",
            "caption": "Test caption",
            "content_type": "image",
            "status": "published"
        }"#;

        let event: PostCreatedEvent = serde_json::from_str(json).unwrap();
        assert_eq!(event.post_id, "123e4567-e89b-12d3-a456-426614174000");
        assert_eq!(event.user_id, "987fcdeb-51a2-3bc4-d567-890123456789");
        assert_eq!(event.caption, Some("Test caption".to_string()));
        assert_eq!(event.status, "published");
    }

    #[test]
    fn test_post_created_event_deserialize_minimal() {
        // Test with optional fields missing
        let json = r#"{
            "post_id": "123",
            "user_id": "456",
            "status": "published"
        }"#;

        let event: PostCreatedEvent = serde_json::from_str(json).unwrap();
        assert_eq!(event.post_id, "123");
        assert_eq!(event.caption, None);
        assert_eq!(event.content_type, ""); // default
    }
}

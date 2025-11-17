use crate::cache::FeedCache;
use crate::error::Result;
use serde::Deserialize;
use tracing::info;

/// Payload shape for a PostCreated event as emitted by content-service.
/// This matches the JSON we currently publish via transactional-outbox.
#[derive(Debug, Deserialize)]
pub struct PostCreatedEvent {
    pub post_id: String,
    pub user_id: String,
    pub caption: Option<String>,
    pub content_type: String,
    pub status: String,
}

/// Handle a PostCreated event by invalidating the author's feed cache.
///
/// In the current architecture feed composition and ranking are delegated
/// to ranking-service. Feed-service primarily maintains cached feeds in Redis.
/// When a user發表新貼文, 我們讓該 user 的 feed cache 失效,
/// 讓下一次 GetFeed 時重新透過 ranking-service 計算。
pub async fn handle_post_created(cache: &FeedCache, event: PostCreatedEvent) -> Result<()> {
    info!(
        "Handling PostCreated event: post_id={}, user_id={}",
        event.post_id, event.user_id
    );

    // Invalidate all cached feeds for this author.
    // Downstream ranking-service will compute updated results on next request.
    cache.invalidate_feed(&event.user_id).await?;

    Ok(())
}

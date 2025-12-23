use crate::models::Post;
use serde_json::json;
use sqlx::{Postgres, Transaction};
use transactional_outbox::{publish_event, OutboxResult, SqlxOutboxRepository};
use uuid::Uuid;

/// Publish a PostCreated-style event into the transactional outbox.
/// This is a thin wrapper around the shared outbox macros so that
/// all content-related Kafka events are defined in a single place.
pub async fn publish_post_created(
    tx: &mut Transaction<'_, Postgres>,
    outbox: &SqlxOutboxRepository,
    post: &Post,
) -> OutboxResult<()> {
    publish_event!(
        tx,
        outbox,
        "content",
        post.id,
        "content.post.created",
        json!({
            "post_id": post.id.to_string(),
            "user_id": post.user_id.to_string(),
            "caption": post.caption,
            "media_type": post.media_type,
            "status": post.status,
            "created_at": post.created_at,
        })
    )
}

/// Publish a PostUpdated-style status event into the transactional outbox.
pub async fn publish_post_status_updated(
    tx: &mut Transaction<'_, Postgres>,
    outbox: &SqlxOutboxRepository,
    post_id: Uuid,
    user_id: Uuid,
    new_status: &str,
) -> OutboxResult<()> {
    publish_event!(
        tx,
        outbox,
        "content",
        post_id,
        "content.post.status_updated",
        json!({
            "post_id": post_id.to_string(),
            "user_id": user_id.to_string(),
            "new_status": new_status,
            "updated_at": chrono::Utc::now(),
        })
    )
}

/// Publish a PostDeleted-style event into the transactional outbox.
pub async fn publish_post_deleted(
    tx: &mut Transaction<'_, Postgres>,
    outbox: &SqlxOutboxRepository,
    post_id: Uuid,
    user_id: Uuid,
) -> OutboxResult<()> {
    publish_event!(
        tx,
        outbox,
        "content",
        post_id,
        "content.post.deleted",
        json!({
            "post_id": post_id.to_string(),
            "user_id": user_id.to_string(),
            "deleted_at": chrono::Utc::now(),
        })
    )
}

/// Publish an event to trigger VLM analysis for a post with images.
/// This event is consumed by the vlm-service for automatic image tagging.
pub async fn publish_post_created_for_vlm(
    tx: &mut Transaction<'_, Postgres>,
    outbox: &SqlxOutboxRepository,
    post: &Post,
    image_urls: &[String],
    auto_assign_channels: bool,
) -> OutboxResult<()> {
    // Only publish if there are images to analyze
    if image_urls.is_empty() {
        return Ok(());
    }

    publish_event!(
        tx,
        outbox,
        "vlm",  // aggregate type for vlm events
        post.id,
        "vlm.post.created",  // Topic: vlm.post.created
        json!({
            "event_id": Uuid::new_v4().to_string(),
            "post_id": post.id.to_string(),
            "creator_id": post.user_id.to_string(),
            "image_urls": image_urls,
            "auto_assign_channels": auto_assign_channels,
            "max_tags": 15,
            "timestamp": chrono::Utc::now().timestamp_millis(),
        })
    )
}

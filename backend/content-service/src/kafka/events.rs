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
            "content_type": post.content_type,
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

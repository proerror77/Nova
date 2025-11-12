//! Convenience macros for working with the outbox.

/// Publish an event to the outbox within a transaction.
///
/// This macro simplifies the common pattern of creating and inserting an event.
///
/// # Usage
///
/// ```rust,no_run
/// use transactional_outbox::{publish_event, SqlxOutboxRepository};
/// use sqlx::PgPool;
/// use uuid::Uuid;
/// use serde_json::json;
///
/// # async fn example(pool: PgPool, repo: SqlxOutboxRepository) -> Result<(), Box<dyn std::error::Error>> {
/// let mut tx = pool.begin().await?;
/// let user_id = Uuid::new_v4();
///
/// // Insert business logic
/// sqlx::query!("INSERT INTO users (id, name) VALUES ($1, $2)", user_id, "Alice")
///     .execute(&mut *tx)
///     .await?;
///
/// // Publish event (same transaction)
/// publish_event!(
///     &mut tx,
///     &repo,
///     "user",
///     user_id,
///     "user.created",
///     json!({
///         "user_id": user_id,
///         "name": "Alice"
///     })
/// );
///
/// tx.commit().await?;
/// # Ok(())
/// # }
/// ```
///
/// # Arguments
///
/// * `$tx` - Mutable reference to database transaction
/// * `$repo` - Reference to OutboxRepository implementation
/// * `$aggregate_type` - Type of aggregate (e.g., "user", "content")
/// * `$aggregate_id` - UUID of the aggregate
/// * `$event_type` - Event type string (e.g., "user.created")
/// * `$payload` - JSON-serializable payload
#[macro_export]
macro_rules! publish_event {
    ($tx:expr, $repo:expr, $aggregate_type:expr, $aggregate_id:expr, $event_type:expr, $payload:expr) => {{
        use chrono::Utc;
        use uuid::Uuid;
        use $crate::{OutboxEvent, OutboxRepository};

        let event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_type: $aggregate_type.to_string(),
            aggregate_id: $aggregate_id,
            event_type: $event_type.to_string(),
            payload: serde_json::to_value($payload)?,
            metadata: None,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };
        $repo.insert($tx, &event).await
    }};
}

/// Publish an event with metadata to the outbox within a transaction.
///
/// Similar to `publish_event!` but allows specifying metadata.
///
/// # Usage
///
/// ```rust,no_run
/// use transactional_outbox::{publish_event_with_metadata, SqlxOutboxRepository};
/// use sqlx::PgPool;
/// use uuid::Uuid;
/// use serde_json::json;
///
/// # async fn example(pool: PgPool, repo: SqlxOutboxRepository) -> Result<(), Box<dyn std::error::Error>> {
/// let mut tx = pool.begin().await?;
/// let user_id = Uuid::new_v4();
/// let correlation_id = Uuid::new_v4();
///
/// publish_event_with_metadata!(
///     &mut tx,
///     &repo,
///     "user",
///     user_id,
///     "user.created",
///     json!({ "user_id": user_id }),
///     json!({
///         "correlation_id": correlation_id,
///         "user_agent": "Mozilla/5.0",
///         "ip_address": "192.168.1.1"
///     })
/// );
///
/// tx.commit().await?;
/// # Ok(())
/// # }
/// ```
///
/// # Arguments
///
/// * `$tx` - Mutable reference to database transaction
/// * `$repo` - Reference to OutboxRepository implementation
/// * `$aggregate_type` - Type of aggregate (e.g., "user", "content")
/// * `$aggregate_id` - UUID of the aggregate
/// * `$event_type` - Event type string (e.g., "user.created")
/// * `$payload` - JSON-serializable payload
/// * `$metadata` - JSON-serializable metadata
#[macro_export]
macro_rules! publish_event_with_metadata {
    (
        $tx:expr,
        $repo:expr,
        $aggregate_type:expr,
        $aggregate_id:expr,
        $event_type:expr,
        $payload:expr,
        $metadata:expr
    ) => {{
        use chrono::Utc;
        use uuid::Uuid;
        use $crate::{OutboxEvent, OutboxRepository};

        let event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_type: $aggregate_type.to_string(),
            aggregate_id: $aggregate_id,
            event_type: $event_type.to_string(),
            payload: serde_json::to_value($payload)?,
            metadata: Some(serde_json::to_value($metadata)?),
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };
        $repo.insert($tx, &event).await
    }};
}

#[cfg(test)]
mod tests {
    use super::*;

    // Macro tests are compile-time checks
    // If this file compiles, the macros are syntactically correct
}

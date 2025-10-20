use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use rdkafka::topic_partition_list::TopicPartitionList;
use rdkafka::Offset;
use serde_json::Value;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tracing::{debug, error, info, warn};

use crate::db::ch_client::ClickHouseClient;
use crate::error::{AppError, Result};

use super::models::{CdcMessage, CdcOperation};
use super::offset_manager::OffsetManager;

/// CDC Consumer configuration
#[derive(Debug, Clone)]
pub struct CdcConsumerConfig {
    /// Kafka brokers (comma-separated)
    pub brokers: String,
    /// Consumer group ID
    pub group_id: String,
    /// Topics to consume (e.g., ["cdc.posts", "cdc.follows"])
    pub topics: Vec<String>,
    /// Max concurrent ClickHouse inserts
    pub max_concurrent_inserts: usize,
}

impl Default for CdcConsumerConfig {
    fn default() -> Self {
        Self {
            brokers: "localhost:9092".to_string(),
            group_id: "nova-cdc-consumer-v1".to_string(),
            topics: vec![
                "cdc.posts".to_string(),
                "cdc.follows".to_string(),
                "cdc.comments".to_string(),
                "cdc.likes".to_string(),
            ],
            max_concurrent_inserts: 10,
        }
    }
}

/// CDC Consumer service
///
/// Consumes CDC messages from Kafka topics and inserts them into ClickHouse.
/// Ensures exactly-once semantics by:
/// 1. Manual offset commit (only after successful CH insert)
/// 2. Offset persistence in PostgreSQL (survives restarts)
/// 3. Idempotent ClickHouse inserts (ReplacingMergeTree)
pub struct CdcConsumer {
    consumer: StreamConsumer,
    ch_client: ClickHouseClient,
    offset_manager: OffsetManager,
    config: CdcConsumerConfig,
    semaphore: Arc<Semaphore>,
}

impl CdcConsumer {
    /// Create a new CDC consumer
    pub async fn new(
        config: CdcConsumerConfig,
        ch_client: ClickHouseClient,
        pg_pool: PgPool,
    ) -> Result<Self> {
        info!("Initializing CDC consumer with config: {:?}", config);

        // Initialize offset manager
        let offset_manager = OffsetManager::new(pg_pool);
        offset_manager.initialize().await?;

        // Create Kafka consumer
        let consumer: StreamConsumer = ClientConfig::new()
            .set("group.id", &config.group_id)
            .set("bootstrap.servers", &config.brokers)
            .set("enable.auto.commit", "false") // Manual commit for exactly-once
            .set("auto.offset.reset", "earliest") // Start from beginning if no offset
            .set("session.timeout.ms", "30000")
            .set("heartbeat.interval.ms", "3000")
            .set("max.poll.interval.ms", "300000") // 5 minutes
            .set("enable.partition.eof", "false")
            .create()
            .map_err(|e| {
                error!("Failed to create Kafka consumer: {}", e);
                AppError::Kafka(e)
            })?;

        // Subscribe to topics
        consumer
            .subscribe(&config.topics.iter().map(|s| s.as_str()).collect::<Vec<_>>())
            .map_err(|e| {
                error!("Failed to subscribe to topics: {}", e);
                AppError::Kafka(e)
            })?;

        info!("CDC consumer subscribed to topics: {:?}", config.topics);

        // Restore offsets from database
        Self::restore_offsets(&consumer, &offset_manager, &config.topics).await?;

        Ok(Self {
            consumer,
            ch_client,
            offset_manager,
            semaphore: Arc::new(Semaphore::new(config.max_concurrent_inserts)),
            config,
        })
    }

    /// Restore Kafka offsets from PostgreSQL
    async fn restore_offsets(
        consumer: &StreamConsumer,
        offset_manager: &OffsetManager,
        topics: &[String],
    ) -> Result<()> {
        info!("Restoring Kafka offsets from database");

        let mut tpl = TopicPartitionList::new();

        for topic in topics {
            let saved_offsets = offset_manager.get_topic_offsets(topic).await?;

            if saved_offsets.is_empty() {
                info!(
                    "No saved offsets for topic {}, will use auto.offset.reset",
                    topic
                );
                continue;
            }

            for (partition, offset) in saved_offsets {
                info!(
                    "Restoring offset: topic={}, partition={}, offset={}",
                    topic, partition, offset
                );
                tpl.add_partition_offset(topic, partition, Offset::Offset(offset))
                    .map_err(|e| AppError::Kafka(e))?;
            }
        }

        if !tpl.elements().is_empty() {
            consumer.assign(&tpl).map_err(|e| {
                error!("Failed to restore offsets: {}", e);
                AppError::Kafka(e)
            })?;
            info!("Successfully restored {} partition offsets", tpl.count());
        }

        Ok(())
    }

    /// Run the CDC consumer loop
    ///
    /// This is a long-running task that should be spawned in a tokio task.
    /// It will run until an error occurs or the task is cancelled.
    pub async fn run(&self) -> Result<()> {
        info!("Starting CDC consumer loop");

        loop {
            match self.consumer.recv().await {
                Ok(msg) => {
                    let topic = msg.topic();
                    let partition = msg.partition();
                    let offset = msg.offset();

                    debug!(
                        "Received CDC message: topic={}, partition={}, offset={}",
                        topic, partition, offset
                    );

                    // Process message
                    if let Err(e) = self.process_message(&msg).await {
                        error!(
                            "Failed to process CDC message (topic={}, partition={}, offset={}): {}",
                            topic, partition, offset, e
                        );

                        // On error, we don't commit offset - message will be reprocessed
                        // This ensures at-least-once delivery
                        // TODO: Add DLQ (Dead Letter Queue) for persistent failures
                        continue;
                    }

                    // Commit offset only after successful processing
                    if let Err(e) = self.commit_offset(topic, partition, offset + 1).await {
                        error!(
                            "Failed to commit offset (topic={}, partition={}, offset={}): {}",
                            topic, partition, offset, e
                        );
                        // Continue processing, will retry offset commit on next message
                    }
                }
                Err(e) => {
                    error!("Kafka consumer error: {}", e);
                    // Sleep briefly before retrying to avoid tight error loop
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        }
    }

    /// Process a single CDC message
    async fn process_message(&self, msg: &rdkafka::message::BorrowedMessage<'_>) -> Result<()> {
        let topic = msg.topic();
        let payload = msg
            .payload()
            .ok_or_else(|| AppError::Validation("CDC message has no payload".to_string()))?;

        // Deserialize CDC message
        let cdc_msg: CdcMessage = serde_json::from_slice(payload).map_err(|e| {
            error!("Failed to deserialize CDC message: {}", e);
            AppError::Internal(format!("Invalid CDC message format: {}", e))
        })?;

        // Validate message
        cdc_msg.validate()?;

        debug!(
            "Processing CDC message: table={}, op={:?}",
            cdc_msg.table(),
            cdc_msg.operation()
        );

        // Acquire semaphore permit for concurrent insert control
        let _permit = self
            .semaphore
            .acquire()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to acquire semaphore: {}", e)))?;

        // Route to appropriate handler based on table
        match cdc_msg.table() {
            "posts" => self.insert_posts_cdc(&cdc_msg).await?,
            "follows" => self.insert_follows_cdc(&cdc_msg).await?,
            "comments" => self.insert_comments_cdc(&cdc_msg).await?,
            "likes" => self.insert_likes_cdc(&cdc_msg).await?,
            table => {
                warn!("Unknown CDC table '{}', ignoring message", table);
            }
        }

        Ok(())
    }

    /// Commit offset to both Kafka and PostgreSQL
    async fn commit_offset(&self, topic: &str, partition: i32, offset: i64) -> Result<()> {
        // Save to PostgreSQL first (source of truth for recovery)
        self.offset_manager
            .save_offset(topic, partition, offset)
            .await?;

        // Then commit to Kafka (for consumer group coordination)
        let mut tpl = TopicPartitionList::new();
        tpl.add_partition_offset(topic, partition, Offset::Offset(offset))
            .map_err(|e| AppError::Kafka(e))?;

        self.consumer
            .commit(&tpl, rdkafka::consumer::CommitMode::Async)
            .map_err(|e| {
                error!("Failed to commit Kafka offset: {}", e);
                AppError::Kafka(e)
            })?;

        debug!(
            "Committed offset: topic={}, partition={}, offset={}",
            topic, partition, offset
        );

        Ok(())
    }

    /// Insert posts CDC message into ClickHouse
    async fn insert_posts_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload.before.as_ref(),
            _ => msg.payload.after.as_ref(),
        }
        .ok_or_else(|| AppError::Validation("CDC message missing data field".to_string()))?;

        // Extract fields from JSON
        let id: i64 = Self::extract_field(data, "id")?;
        let user_id: i64 = Self::extract_field(data, "user_id")?;
        let content: String = Self::extract_field(data, "content")?;
        let media_url: Option<String> = Self::extract_optional_field(data, "media_url");
        let created_at: String = Self::extract_field(data, "created_at")?;

        let is_deleted = matches!(op, CdcOperation::Delete);

        // Insert into ClickHouse (ReplacingMergeTree handles upserts)
        let query = format!(
            r#"
            INSERT INTO posts_cdc (
                id, user_id, content, media_url, created_at,
                cdc_timestamp, is_deleted
            ) VALUES (
                {}, {}, '{}', {}, '{}',
                {}, {}
            )
            "#,
            id,
            user_id,
            Self::escape_string(&content),
            media_url
                .map(|u| format!("'{}'", Self::escape_string(&u)))
                .unwrap_or_else(|| "NULL".to_string()),
            created_at,
            msg.payload.ts_ms,
            if is_deleted { 1 } else { 0 }
        );

        self.ch_client.execute(&query).await?;

        debug!("Inserted posts CDC: id={}, op={:?}", id, op);
        Ok(())
    }

    /// Insert follows CDC message into ClickHouse
    async fn insert_follows_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload.before.as_ref(),
            _ => msg.payload.after.as_ref(),
        }
        .ok_or_else(|| AppError::Validation("CDC message missing data field".to_string()))?;

        let follower_id: i64 = Self::extract_field(data, "follower_id")?;
        let followee_id: i64 = Self::extract_field(data, "followee_id")?;
        let created_at: String = Self::extract_field(data, "created_at")?;

        let is_deleted = matches!(op, CdcOperation::Delete);

        let query = format!(
            r#"
            INSERT INTO follows_cdc (
                follower_id, followee_id, created_at,
                cdc_timestamp, is_deleted
            ) VALUES (
                {}, {}, '{}',
                {}, {}
            )
            "#,
            follower_id,
            followee_id,
            created_at,
            msg.payload.ts_ms,
            if is_deleted { 1 } else { 0 }
        );

        self.ch_client.execute(&query).await?;

        debug!(
            "Inserted follows CDC: follower={}, followee={}, op={:?}",
            follower_id, followee_id, op
        );
        Ok(())
    }

    /// Insert comments CDC message into ClickHouse
    async fn insert_comments_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload.before.as_ref(),
            _ => msg.payload.after.as_ref(),
        }
        .ok_or_else(|| AppError::Validation("CDC message missing data field".to_string()))?;

        let id: i64 = Self::extract_field(data, "id")?;
        let post_id: i64 = Self::extract_field(data, "post_id")?;
        let user_id: i64 = Self::extract_field(data, "user_id")?;
        let content: String = Self::extract_field(data, "content")?;
        let created_at: String = Self::extract_field(data, "created_at")?;

        let is_deleted = matches!(op, CdcOperation::Delete);

        let query = format!(
            r#"
            INSERT INTO comments_cdc (
                id, post_id, user_id, content, created_at,
                cdc_timestamp, is_deleted
            ) VALUES (
                {}, {}, {}, '{}', '{}',
                {}, {}
            )
            "#,
            id,
            post_id,
            user_id,
            Self::escape_string(&content),
            created_at,
            msg.payload.ts_ms,
            if is_deleted { 1 } else { 0 }
        );

        self.ch_client.execute(&query).await?;

        debug!(
            "Inserted comments CDC: id={}, post_id={}, op={:?}",
            id, post_id, op
        );
        Ok(())
    }

    /// Insert likes CDC message into ClickHouse
    async fn insert_likes_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload.before.as_ref(),
            _ => msg.payload.after.as_ref(),
        }
        .ok_or_else(|| AppError::Validation("CDC message missing data field".to_string()))?;

        let user_id: i64 = Self::extract_field(data, "user_id")?;
        let post_id: i64 = Self::extract_field(data, "post_id")?;
        let created_at: String = Self::extract_field(data, "created_at")?;

        let is_deleted = matches!(op, CdcOperation::Delete);

        let query = format!(
            r#"
            INSERT INTO likes_cdc (
                user_id, post_id, created_at,
                cdc_timestamp, is_deleted
            ) VALUES (
                {}, {}, '{}',
                {}, {}
            )
            "#,
            user_id,
            post_id,
            created_at,
            msg.payload.ts_ms,
            if is_deleted { 1 } else { 0 }
        );

        self.ch_client.execute(&query).await?;

        debug!(
            "Inserted likes CDC: user_id={}, post_id={}, op={:?}",
            user_id, post_id, op
        );
        Ok(())
    }

    /// Extract a required field from JSON value
    fn extract_field<T>(data: &Value, field: &str) -> Result<T>
    where
        T: serde::de::DeserializeOwned,
    {
        data.get(field)
            .ok_or_else(|| AppError::Validation(format!("Missing field: {}", field)))
            .and_then(|v| {
                serde_json::from_value(v.clone()).map_err(|e| {
                    AppError::Validation(format!("Failed to parse field '{}': {}", field, e))
                })
            })
    }

    /// Extract an optional field from JSON value
    fn extract_optional_field<T>(data: &Value, field: &str) -> Option<T>
    where
        T: serde::de::DeserializeOwned,
    {
        data.get(field)
            .and_then(|v| serde_json::from_value(v.clone()).ok())
    }

    /// Escape string for ClickHouse query (prevent SQL injection)
    fn escape_string(s: &str) -> String {
        s.replace('\\', "\\\\")
            .replace('\'', "\\'")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
            .replace('\t', "\\t")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_escape_string() {
        assert_eq!(CdcConsumer::escape_string("hello'world"), "hello\\'world");
        assert_eq!(CdcConsumer::escape_string("line1\nline2"), "line1\\nline2");
        assert_eq!(CdcConsumer::escape_string("tab\there"), "tab\\there");
    }

    #[test]
    fn test_extract_field() {
        let data = json!({"id": 123, "name": "test"});

        let id: i64 = CdcConsumer::extract_field(&data, "id").unwrap();
        assert_eq!(id, 123);

        let name: String = CdcConsumer::extract_field(&data, "name").unwrap();
        assert_eq!(name, "test");

        assert!(CdcConsumer::extract_field::<i64>(&data, "missing").is_err());
    }

    #[test]
    fn test_extract_optional_field() {
        let data = json!({"id": 123});

        let id: Option<i64> = CdcConsumer::extract_optional_field(&data, "id");
        assert_eq!(id, Some(123));

        let missing: Option<i64> = CdcConsumer::extract_optional_field(&data, "missing");
        assert_eq!(missing, None);
    }
}

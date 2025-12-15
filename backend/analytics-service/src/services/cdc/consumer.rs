use chrono::{DateTime, NaiveDateTime, TimeZone, Utc};
use clickhouse::Client as ClickHouseClient;
use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use serde_json::Value;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use crate::error::{AnalyticsError, Result};

use super::models::{CdcMessage, CdcOperation};

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
    /// ClickHouse URL
    pub clickhouse_url: String,
    /// ClickHouse database
    pub clickhouse_database: String,
    /// ClickHouse user
    pub clickhouse_user: String,
    /// ClickHouse password
    pub clickhouse_password: String,
}

impl CdcConsumerConfig {
    pub fn from_env() -> Self {
        Self {
            brokers: std::env::var("KAFKA_BROKERS").unwrap_or_else(|_| "kafka:9092".to_string()),
            group_id: std::env::var("CDC_CONSUMER_GROUP")
                .unwrap_or_else(|_| "analytics-cdc-consumer-v1".to_string()),
            topics: std::env::var("CDC_TOPICS")
                .unwrap_or_else(|_| "cdc.posts,cdc.follows,cdc.comments,cdc.likes".to_string())
                .split(',')
                .map(|s| s.trim().to_string())
                .collect(),
            max_concurrent_inserts: std::env::var("CDC_MAX_CONCURRENT_INSERTS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(10),
            clickhouse_url: std::env::var("CLICKHOUSE_URL")
                .unwrap_or_else(|_| "http://clickhouse:8123".to_string()),
            clickhouse_database: std::env::var("CLICKHOUSE_DATABASE")
                .unwrap_or_else(|_| "nova_feed".to_string()),
            clickhouse_user: std::env::var("CLICKHOUSE_USER")
                .unwrap_or_else(|_| "default".to_string()),
            clickhouse_password: std::env::var("CLICKHOUSE_PASSWORD").unwrap_or_default(),
        }
    }
}

/// CDC Consumer service
///
/// Consumes CDC messages from Kafka topics and inserts them into ClickHouse.
pub struct CdcConsumer {
    consumer: StreamConsumer,
    ch_client: ClickHouseClient,
    #[allow(dead_code)]
    config: CdcConsumerConfig,
    semaphore: Arc<Semaphore>,
}

impl CdcConsumer {
    /// Create a new CDC consumer
    pub fn new(config: CdcConsumerConfig) -> Result<Self> {
        info!("Initializing CDC consumer with config: {:?}", config);

        // Create Kafka consumer
        let consumer: StreamConsumer = ClientConfig::new()
            .set("group.id", &config.group_id)
            .set("bootstrap.servers", &config.brokers)
            .set("enable.auto.commit", "true")
            .set("auto.commit.interval.ms", "5000")
            .set("auto.offset.reset", "earliest")
            .set("session.timeout.ms", "30000")
            .set("heartbeat.interval.ms", "3000")
            .set("max.poll.interval.ms", "300000")
            .set("enable.partition.eof", "false")
            .create()
            .map_err(|e| {
                error!("Failed to create Kafka consumer: {}", e);
                AnalyticsError::Kafka(e.to_string())
            })?;

        // Subscribe to topics
        consumer
            .subscribe(&config.topics.iter().map(|s| s.as_str()).collect::<Vec<_>>())
            .map_err(|e| {
                error!("Failed to subscribe to topics: {}", e);
                AnalyticsError::Kafka(e.to_string())
            })?;

        info!("CDC consumer subscribed to topics: {:?}", config.topics);

        // Create ClickHouse client with authentication
        let ch_client = ClickHouseClient::default()
            .with_url(&config.clickhouse_url)
            .with_database(&config.clickhouse_database)
            .with_user(&config.clickhouse_user)
            .with_password(&config.clickhouse_password);

        Ok(Self {
            consumer,
            ch_client,
            semaphore: Arc::new(Semaphore::new(config.max_concurrent_inserts)),
            config,
        })
    }

    /// Run the CDC consumer loop
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

                    if let Err(e) = self.process_message(&msg).await {
                        error!(
                            "Failed to process CDC message (topic={}, partition={}, offset={}): {}",
                            topic, partition, offset, e
                        );
                        // Continue processing, Kafka auto-commit handles offset
                    }
                }
                Err(e) => {
                    error!("Kafka consumer error: {}", e);
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        }
    }

    /// Process a single CDC message
    async fn process_message(&self, msg: &rdkafka::message::BorrowedMessage<'_>) -> Result<()> {
        let payload = msg
            .payload()
            .ok_or_else(|| AnalyticsError::Validation("CDC message has no payload".to_string()))?;

        let cdc_msg: CdcMessage = serde_json::from_slice(payload).map_err(|e| {
            error!("Failed to deserialize CDC message: {}", e);
            AnalyticsError::Validation(format!("Invalid CDC message format: {}", e))
        })?;

        cdc_msg.validate()?;

        debug!(
            "Processing CDC message: table={}, op={:?}",
            cdc_msg.table(),
            cdc_msg.operation()
        );

        let _permit =
            self.semaphore.acquire().await.map_err(|e| {
                AnalyticsError::Internal(format!("Failed to acquire semaphore: {}", e))
            })?;

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

    /// Insert posts CDC message into ClickHouse
    async fn insert_posts_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let id_raw: String = Self::extract_field(data, "id")?;
        let user_id_raw: String = Self::extract_field(data, "user_id")?;
        let post_id = Uuid::parse_str(&id_raw).map_err(|e| {
            AnalyticsError::Validation(format!("Invalid post UUID '{}': {}", id_raw, e))
        })?;
        let author_id = Uuid::parse_str(&user_id_raw).map_err(|e| {
            AnalyticsError::Validation(format!("Invalid user UUID '{}': {}", user_id_raw, e))
        })?;
        let content: String = Self::extract_field(data, "content").unwrap_or_default();
        let media_url: Option<String> = Self::extract_optional_field(data, "media_url");
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;

        let is_deleted: u8 = if matches!(op, CdcOperation::Delete) {
            1
        } else {
            0
        };
        let cdc_timestamp = Self::ts_ms_u64(msg.payload().ts_ms)?;

        let query = format!(
            "INSERT INTO posts_cdc (id, user_id, content, media_url, created_at, cdc_timestamp, is_deleted) VALUES ('{}', '{}', '{}', {}, '{}', {}, {})",
            post_id,
            author_id,
            Self::escape_clickhouse_str(&content),
            media_url.map(|u| format!("'{}'", Self::escape_clickhouse_str(&u))).unwrap_or_else(|| "NULL".to_string()),
            created_at.format("%Y-%m-%d %H:%M:%S"),
            cdc_timestamp,
            is_deleted
        );

        self.ch_client.query(&query).execute().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        debug!("Inserted posts CDC: id={}, op={:?}", post_id, op);
        Ok(())
    }

    /// Insert follows CDC message into ClickHouse
    async fn insert_follows_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let follower_raw: String = Self::extract_field(data, "follower_id")?;
        // PostgreSQL table uses "following_id", but ClickHouse expects "followee_id"
        let following_raw: String = Self::extract_field(data, "following_id")?;
        let follower_id = Uuid::parse_str(&follower_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid follower UUID: {}", e)))?;
        let followee_id = Uuid::parse_str(&following_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid followee UUID: {}", e)))?;
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;

        // Match actual ClickHouse table schema (nova_feed.follows_cdc):
        // followed_id (not followee_id), cdc_operation (not is_deleted), follow_count
        let cdc_operation = if *op == CdcOperation::Delete { 2 } else { 1 };  // 1=INSERT, 2=DELETE
        let follow_count: i8 = if *op == CdcOperation::Delete { -1 } else { 1 };  // For SummingMergeTree

        let query = format!(
            "INSERT INTO follows_cdc (follower_id, followed_id, created_at, cdc_operation, cdc_timestamp, follow_count) VALUES ('{}', '{}', '{}', {}, '{}', {})",
            follower_id,
            followee_id,  // Variable is still named followee_id, but column is followed_id
            created_at.format("%Y-%m-%d %H:%M:%S"),  // DateTime format (no milliseconds)
            cdc_operation,
            created_at.format("%Y-%m-%d %H:%M:%S"),  // cdc_timestamp DateTime format
            follow_count
        );

        self.ch_client.query(&query).execute().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

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
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let id_raw: String = Self::extract_field(data, "id")?;
        let post_raw: String = Self::extract_field(data, "post_id")?;
        let user_raw: String = Self::extract_field(data, "user_id")?;
        let comment_id = Uuid::parse_str(&id_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid comment UUID: {}", e)))?;
        let post_id = Uuid::parse_str(&post_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid post UUID: {}", e)))?;
        let user_id = Uuid::parse_str(&user_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid user UUID: {}", e)))?;
        let content: String = Self::extract_field(data, "content")?;
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;

        let is_deleted: u8 = if matches!(op, CdcOperation::Delete) {
            1
        } else {
            0
        };
        let cdc_timestamp = Self::ts_ms_u64(msg.payload().ts_ms)?;

        let query = format!(
            "INSERT INTO comments_cdc (id, post_id, user_id, content, created_at, cdc_timestamp, is_deleted) VALUES ('{}', '{}', '{}', '{}', '{}', {}, {})",
            comment_id,
            post_id,
            user_id,
            Self::escape_clickhouse_str(&content),
            created_at.format("%Y-%m-%d %H:%M:%S"),
            cdc_timestamp,
            is_deleted
        );

        self.ch_client.query(&query).execute().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        debug!("Inserted comments CDC: id={}, op={:?}", comment_id, op);
        Ok(())
    }

    /// Insert likes CDC message into ClickHouse
    async fn insert_likes_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let user_raw: String = Self::extract_field(data, "user_id")?;
        let post_raw: String = Self::extract_field(data, "post_id")?;
        let user_id = Uuid::parse_str(&user_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid user UUID: {}", e)))?;
        let post_id = Uuid::parse_str(&post_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid post UUID: {}", e)))?;
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;

        let is_deleted: u8 = if matches!(op, CdcOperation::Delete) {
            1
        } else {
            0
        };
        let cdc_timestamp = Self::ts_ms_u64(msg.payload().ts_ms)?;

        let query = format!(
            "INSERT INTO likes_cdc (user_id, post_id, created_at, cdc_timestamp, is_deleted) VALUES ('{}', '{}', '{}', {}, {})",
            user_id,
            post_id,
            created_at.format("%Y-%m-%d %H:%M:%S"),
            cdc_timestamp,
            is_deleted
        );

        self.ch_client.query(&query).execute().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        debug!(
            "Inserted likes CDC: user={}, post={}, op={:?}",
            user_id, post_id, op
        );
        Ok(())
    }

    /// Escape a string for ClickHouse SQL queries.
    /// Escapes single quotes (') and question marks (?) which are interpreted
    /// as parameter placeholders by the clickhouse crate.
    fn escape_clickhouse_str(s: &str) -> String {
        s.replace('\'', "''").replace('?', "\\?")
    }

    fn extract_field<T>(data: &Value, field: &str) -> Result<T>
    where
        T: serde::de::DeserializeOwned,
    {
        data.get(field)
            .ok_or_else(|| AnalyticsError::Validation(format!("Missing field: {}", field)))
            .and_then(|v| {
                serde_json::from_value(v.clone()).map_err(|e| {
                    AnalyticsError::Validation(format!("Failed to parse field '{}': {}", field, e))
                })
            })
    }

    fn extract_optional_field<T>(data: &Value, field: &str) -> Option<T>
    where
        T: serde::de::DeserializeOwned,
    {
        data.get(field)
            .and_then(|v| serde_json::from_value(v.clone()).ok())
    }

    fn ts_ms_u64(ts: i64) -> Result<u64> {
        if ts < 0 {
            return Err(AnalyticsError::Validation(format!(
                "Invalid negative timestamp: {}",
                ts
            )));
        }
        Ok(ts as u64)
    }

    fn parse_datetime_best_effort(s: &str) -> Result<DateTime<Utc>> {
        if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
            return Ok(dt.with_timezone(&Utc));
        }
        if let Ok(dt) = DateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S%.f %z") {
            return Ok(dt.with_timezone(&Utc));
        }
        if let Ok(ndt) = NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S%.fZ") {
            return Ok(Utc.from_utc_datetime(&ndt));
        }
        if let Ok(ndt) = NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S%.f") {
            return Ok(Utc.from_utc_datetime(&ndt));
        }
        if let Ok(ndt) = NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M:%S") {
            return Ok(Utc.from_utc_datetime(&ndt));
        }
        Err(AnalyticsError::Validation(format!(
            "Unsupported datetime format: {}",
            s
        )))
    }
}

use chrono::{DateTime, NaiveDateTime, TimeZone, Utc};
use clickhouse::Client as ClickHouseClient;
use clickhouse::Row;
use prometheus::{IntCounter, IntGauge};
use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use crate::error::{AnalyticsError, Result};

/// Metrics for CDC consumer monitoring
#[derive(Clone)]
pub struct CdcConsumerMetrics {
    /// Total number of Kafka consumer errors
    pub consumer_errors_total: IntCounter,
    /// Current consecutive error count (resets on success)
    pub consecutive_errors: IntGauge,
    /// Total messages successfully processed
    pub messages_processed_total: IntCounter,
    /// Total messages that failed processing
    pub messages_failed_total: IntCounter,
    /// Consumer health status (1 = healthy, 0 = unhealthy)
    pub consumer_healthy: IntGauge,
    /// Current backoff duration in seconds
    pub backoff_seconds: IntGauge,
}

impl CdcConsumerMetrics {
    pub fn new() -> Self {
        let registry = prometheus::default_registry();

        let consumer_errors_total = IntCounter::new(
            "cdc_consumer_errors_total",
            "Total number of Kafka consumer errors encountered",
        )
        .expect("valid metric for cdc_consumer_errors_total");

        let consecutive_errors = IntGauge::new(
            "cdc_consumer_consecutive_errors",
            "Current number of consecutive Kafka consumer errors",
        )
        .expect("valid metric for cdc_consumer_consecutive_errors");

        let messages_processed_total = IntCounter::new(
            "cdc_messages_processed_total",
            "Total number of CDC messages successfully processed",
        )
        .expect("valid metric for cdc_messages_processed_total");

        let messages_failed_total = IntCounter::new(
            "cdc_messages_failed_total",
            "Total number of CDC messages that failed processing",
        )
        .expect("valid metric for cdc_messages_failed_total");

        let consumer_healthy = IntGauge::new(
            "cdc_consumer_healthy",
            "CDC consumer health status (1 = healthy, 0 = unhealthy)",
        )
        .expect("valid metric for cdc_consumer_healthy");

        let backoff_seconds = IntGauge::new(
            "cdc_consumer_backoff_seconds",
            "Current backoff duration in seconds",
        )
        .expect("valid metric for cdc_consumer_backoff_seconds");

        // Register all metrics
        for metric in [
            Box::new(consumer_errors_total.clone()) as Box<dyn prometheus::core::Collector>,
            Box::new(consecutive_errors.clone()),
            Box::new(messages_processed_total.clone()),
            Box::new(messages_failed_total.clone()),
            Box::new(consumer_healthy.clone()),
            Box::new(backoff_seconds.clone()),
        ] {
            let _ = registry.register(metric);
        }

        // Start as healthy
        consumer_healthy.set(1);

        Self {
            consumer_errors_total,
            consecutive_errors,
            messages_processed_total,
            messages_failed_total,
            consumer_healthy,
            backoff_seconds,
        }
    }
}

impl Default for CdcConsumerMetrics {
    fn default() -> Self {
        Self::new()
    }
}

/// Error handling state for the CDC consumer
pub struct ConsumerErrorState {
    /// Number of consecutive errors
    consecutive_count: AtomicU32,
    /// Timestamp of last successful operation (Unix millis)
    last_success_ms: AtomicU64,
}

impl ConsumerErrorState {
    pub fn new() -> Self {
        Self {
            consecutive_count: AtomicU32::new(0),
            last_success_ms: AtomicU64::new(
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis() as u64,
            ),
        }
    }

    /// Record a successful operation, resetting error count
    pub fn record_success(&self) {
        self.consecutive_count.store(0, Ordering::SeqCst);
        self.last_success_ms.store(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            Ordering::SeqCst,
        );
    }

    /// Record an error, incrementing consecutive count
    pub fn record_error(&self) -> u32 {
        self.consecutive_count.fetch_add(1, Ordering::SeqCst) + 1
    }

    /// Get current consecutive error count
    pub fn consecutive_errors(&self) -> u32 {
        self.consecutive_count.load(Ordering::SeqCst)
    }

    /// Get duration since last success
    pub fn time_since_success(&self) -> Duration {
        let last = self.last_success_ms.load(Ordering::SeqCst);
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        Duration::from_millis(now.saturating_sub(last))
    }

    /// Calculate backoff duration based on consecutive errors (exponential with cap)
    pub fn calculate_backoff(&self) -> Duration {
        const MIN_BACKOFF_SECS: u64 = 1;
        const MAX_BACKOFF_SECS: u64 = 60;

        let errors = self.consecutive_errors();
        if errors == 0 {
            return Duration::from_secs(MIN_BACKOFF_SECS);
        }

        // Exponential backoff: 2^(errors-1) seconds, capped at MAX_BACKOFF_SECS
        let backoff_secs = 2u64
            .saturating_pow(errors.saturating_sub(1))
            .min(MAX_BACKOFF_SECS);
        Duration::from_secs(backoff_secs)
    }
}

impl Default for ConsumerErrorState {
    fn default() -> Self {
        Self::new()
    }
}

/// Status information for the CDC consumer
#[derive(Debug, Clone)]
pub struct ConsumerStatus {
    /// Whether the consumer is currently healthy
    pub healthy: bool,
    /// Current number of consecutive errors
    pub consecutive_errors: u32,
    /// Time since last successful operation
    pub time_since_last_success: Duration,
    /// Current backoff duration being applied
    pub current_backoff: Duration,
}

/// Row struct for posts_cdc table - used for type-safe ClickHouse inserts
/// Uses String for UUIDs and u32 for DateTime to avoid clickhouse-rs serialization issues
/// Note: deleted_at uses Option<u32> for Nullable(DateTime64) compatibility
#[derive(Debug, Clone, Row, Serialize, Deserialize)]
pub struct PostsCdcRow {
    pub id: String,
    pub user_id: String,
    pub content: String,
    pub media_key: String,
    pub media_type: String,
    pub created_at: u32,
    pub updated_at: u32,
    pub deleted_at: Option<u32>,
    pub cdc_operation: i8,
    pub cdc_timestamp: u32,
}

/// Row struct for follows_cdc table - used for type-safe ClickHouse inserts
/// Note: Uses `followee_id` to match ClickHouse schema (PostgreSQL uses `following_id`)
/// Uses String for UUIDs to avoid clickhouse-rs serialization issues with Uuid type
#[derive(Debug, Clone, Row, Serialize, Deserialize)]
pub struct FollowsCdcRow {
    pub follower_id: String,
    pub followee_id: String,
    pub created_at: u32, // Unix timestamp for ClickHouse DateTime
    pub cdc_operation: i8,
    pub cdc_timestamp: u32, // Unix timestamp for ClickHouse DateTime
    pub follow_count: i8,
}

/// Row struct for comments_cdc table - used for type-safe ClickHouse inserts
/// Uses String for UUIDs and u32 for DateTime to avoid clickhouse-rs serialization issues
#[derive(Debug, Clone, Row, Serialize, Deserialize)]
pub struct CommentsCdcRow {
    pub id: String,
    pub post_id: String,
    pub user_id: String,
    pub content: String,
    pub parent_comment_id: String, // Empty string for None
    pub created_at: u32,
    pub updated_at: u32,
    pub soft_delete: u32, // 0 for None
    pub cdc_operation: i8,
    pub cdc_timestamp: u32,
}

/// Row struct for likes_cdc table - used for type-safe ClickHouse inserts
/// Uses String for UUIDs and u32 for DateTime to avoid clickhouse-rs serialization issues
#[derive(Debug, Clone, Row, Serialize, Deserialize)]
pub struct LikesCdcRow {
    pub post_id: String,
    pub user_id: String,
    pub created_at: u32,
    pub cdc_operation: i8,
    pub cdc_timestamp: u32,
    pub like_count: i8,
}

/// Row struct for users_cdc table - used for type-safe ClickHouse inserts
/// Note: Captures user profile changes for analytics (username, display_name, avatar_url, bio)
#[derive(Debug, Clone, Row, Serialize, Deserialize)]
pub struct UsersCdcRow {
    pub id: Uuid,
    pub username: String,
    pub display_name: String,
    pub email: String,
    pub avatar_url: String,
    pub bio: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
    pub cdc_operation: i8,
    pub cdc_timestamp: DateTime<Utc>,
}

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
                .unwrap_or_else(|_| {
                    "cdc.posts,cdc.follows,cdc.comments,cdc.likes,cdc.users".to_string()
                })
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

/// Threshold for consecutive errors before marking consumer as unhealthy
const UNHEALTHY_ERROR_THRESHOLD: u32 = 5;

/// Threshold for consecutive errors before emitting critical warning
const CRITICAL_ERROR_THRESHOLD: u32 = 10;

/// CDC Consumer service
///
/// Consumes CDC messages from Kafka topics and inserts them into ClickHouse.
/// Includes comprehensive error handling with exponential backoff and metrics.
pub struct CdcConsumer {
    consumer: StreamConsumer,
    ch_client: ClickHouseClient,
    #[allow(dead_code)]
    config: CdcConsumerConfig,
    semaphore: Arc<Semaphore>,
    /// Metrics for monitoring consumer health and performance
    metrics: CdcConsumerMetrics,
    /// Error state tracking for backoff and health checks
    error_state: Arc<ConsumerErrorState>,
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

        let metrics = CdcConsumerMetrics::new();
        let error_state = Arc::new(ConsumerErrorState::new());

        info!("CDC consumer initialized with metrics and error handling");

        Ok(Self {
            consumer,
            ch_client,
            semaphore: Arc::new(Semaphore::new(config.max_concurrent_inserts)),
            config,
            metrics,
            error_state,
        })
    }

    /// Check if the consumer is healthy
    /// Returns false if consecutive errors exceed threshold or no success for too long
    pub fn is_healthy(&self) -> bool {
        let errors = self.error_state.consecutive_errors();
        let time_since_success = self.error_state.time_since_success();

        // Unhealthy if too many consecutive errors
        if errors >= UNHEALTHY_ERROR_THRESHOLD {
            return false;
        }

        // Unhealthy if no success for more than 5 minutes
        if time_since_success > Duration::from_secs(300) && errors > 0 {
            return false;
        }

        true
    }

    /// Get current consumer status for health checks
    pub fn status(&self) -> ConsumerStatus {
        ConsumerStatus {
            healthy: self.is_healthy(),
            consecutive_errors: self.error_state.consecutive_errors(),
            time_since_last_success: self.error_state.time_since_success(),
            current_backoff: self.error_state.calculate_backoff(),
        }
    }

    /// Run the CDC consumer loop with comprehensive error handling
    ///
    /// Features:
    /// - Exponential backoff on consecutive errors (1s -> 2s -> 4s -> ... -> 60s max)
    /// - Prometheus metrics for monitoring
    /// - Health status tracking
    /// - Warning alerts when error threshold is exceeded
    pub async fn run(&self) -> Result<()> {
        info!("Starting CDC consumer loop with error handling");

        loop {
            match self.consumer.recv().await {
                Ok(msg) => {
                    // Reset error state on successful receive
                    self.error_state.record_success();
                    self.metrics.consecutive_errors.set(0);
                    self.metrics.consumer_healthy.set(1);
                    self.metrics.backoff_seconds.set(0);

                    let topic = msg.topic();
                    let partition = msg.partition();
                    let offset = msg.offset();

                    debug!(
                        "Received CDC message: topic={}, partition={}, offset={}",
                        topic, partition, offset
                    );

                    match self.process_message(&msg).await {
                        Ok(()) => {
                            self.metrics.messages_processed_total.inc();
                        }
                        Err(e) => {
                            self.metrics.messages_failed_total.inc();
                            error!(
                                "Failed to process CDC message (topic={}, partition={}, offset={}): {}",
                                topic, partition, offset, e
                            );
                            // Continue processing, Kafka auto-commit handles offset
                        }
                    }
                }
                Err(e) => {
                    // Record the error and update metrics
                    let consecutive = self.error_state.record_error();
                    self.metrics.consumer_errors_total.inc();
                    self.metrics.consecutive_errors.set(consecutive as i64);

                    // Calculate backoff duration
                    let backoff = self.error_state.calculate_backoff();
                    self.metrics.backoff_seconds.set(backoff.as_secs() as i64);

                    // Update health status
                    let is_healthy = self.is_healthy();
                    self.metrics
                        .consumer_healthy
                        .set(if is_healthy { 1 } else { 0 });

                    // Log with appropriate severity based on consecutive errors
                    if consecutive >= CRITICAL_ERROR_THRESHOLD {
                        error!(
                            consecutive_errors = consecutive,
                            backoff_secs = backoff.as_secs(),
                            time_since_success_secs =
                                self.error_state.time_since_success().as_secs(),
                            "CRITICAL: Kafka consumer experiencing persistent failures. \
                             Manual intervention may be required. Error: {}",
                            e
                        );
                    } else if consecutive >= UNHEALTHY_ERROR_THRESHOLD {
                        warn!(
                            consecutive_errors = consecutive,
                            backoff_secs = backoff.as_secs(),
                            "Kafka consumer unhealthy - multiple consecutive errors. Error: {}",
                            e
                        );
                    } else {
                        error!(
                            consecutive_errors = consecutive,
                            backoff_secs = backoff.as_secs(),
                            "Kafka consumer error (will retry with backoff): {}",
                            e
                        );
                    }

                    // Apply exponential backoff before retry
                    tokio::time::sleep(backoff).await;
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
            "users" => self.insert_users_cdc(&cdc_msg).await?,
            table => {
                warn!("Unknown CDC table '{}', ignoring message", table);
            }
        }

        Ok(())
    }

    /// Insert posts CDC message into ClickHouse using type-safe parameterized insert
    async fn insert_posts_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let id_raw: String = Self::extract_field(data, "id")?;
        let user_id_raw: String = Self::extract_field(data, "user_id")?;
        // Validate UUIDs but keep as strings for ClickHouse compatibility
        let _ = Uuid::parse_str(&id_raw).map_err(|e| {
            AnalyticsError::Validation(format!("Invalid post UUID '{}': {}", id_raw, e))
        })?;
        let _ = Uuid::parse_str(&user_id_raw).map_err(|e| {
            AnalyticsError::Validation(format!("Invalid user UUID '{}': {}", user_id_raw, e))
        })?;
        let content: String = Self::extract_field(data, "content").unwrap_or_default();
        let media_key: String = Self::extract_field(data, "media_key").unwrap_or_default();
        let media_type: String = Self::extract_field(data, "media_type").unwrap_or_default();
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;
        let updated_at_raw: String = Self::extract_field(data, "updated_at")?;
        let updated_at = Self::parse_datetime_best_effort(&updated_at_raw)?;
        let deleted_at_raw: Option<String> = Self::extract_optional_field(data, "deleted_at");
        let deleted_at = deleted_at_raw
            .as_deref()
            .map(Self::parse_datetime_best_effort)
            .transpose()?;

        let cdc_operation: i8 = match op {
            CdcOperation::Insert | CdcOperation::Read => 1,
            CdcOperation::Update => 2,
            CdcOperation::Delete => 3,
        };
        let cdc_op_name = match cdc_operation {
            1 => "INSERT",
            2 => "UPDATE",
            _ => "DELETE",
        };
        let cdc_timestamp = msg.timestamp();

        // Format deleted_at for SQL - NULL or timestamp string
        let deleted_at_sql = match deleted_at {
            Some(dt) => format!("'{}'", dt.format("%Y-%m-%d %H:%M:%S%.3f")),
            None => "NULL".to_string(),
        };

        // Escape single quotes in content for SQL safety
        let escaped_content = content.replace('\'', "''");
        let escaped_media_key = media_key.replace('\'', "''");
        let escaped_media_type = media_type.replace('\'', "''");

        // Use raw SQL INSERT to bypass Row serialization issues with UUID and DateTime types
        let insert_sql = format!(
            "INSERT INTO posts_cdc (id, user_id, content, media_key, media_type, created_at, updated_at, deleted_at, cdc_operation, cdc_timestamp) VALUES ('{}', '{}', '{}', '{}', '{}', '{}', '{}', {}, '{}', '{}')",
            id_raw,
            user_id_raw,
            escaped_content,
            escaped_media_key,
            escaped_media_type,
            created_at.format("%Y-%m-%d %H:%M:%S%.3f"),
            updated_at.format("%Y-%m-%d %H:%M:%S%.3f"),
            deleted_at_sql,
            cdc_op_name,
            cdc_timestamp.format("%Y-%m-%d %H:%M:%S%.3f"),
        );

        self.ch_client
            .query(&insert_sql)
            .execute()
            .await
            .map_err(|e| {
                error!("ClickHouse insert error: {}", e);
                AnalyticsError::ClickHouse(e.to_string())
            })?;

        debug!("Inserted posts CDC: id={}, op={:?}", id_raw, op);
        Ok(())
    }

    /// Insert follows CDC message into ClickHouse using type-safe parameterized insert
    async fn insert_follows_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let follower_raw: String = Self::extract_field(data, "follower_id")?;
        // PostgreSQL table uses "following_id", ClickHouse uses "followee_id"
        let following_raw: String = Self::extract_field(data, "following_id")?;
        // Validate UUIDs but keep as strings for ClickHouse compatibility
        let _ = Uuid::parse_str(&follower_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid follower UUID: {}", e)))?;
        let _ = Uuid::parse_str(&following_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid followee UUID: {}", e)))?;
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;

        let cdc_operation: i8 = match op {
            CdcOperation::Delete => 2,
            CdcOperation::Insert | CdcOperation::Read | CdcOperation::Update => 1,
        };
        let follow_count: i8 = if *op == CdcOperation::Delete { -1 } else { 1 };
        let cdc_timestamp = msg.timestamp();

        // Use type-safe parameterized insert to prevent SQL injection
        // Convert DateTime to unix timestamp (u32) for ClickHouse DateTime compatibility
        let row = FollowsCdcRow {
            follower_id: follower_raw.clone(),
            followee_id: following_raw.clone(),
            created_at: created_at.timestamp() as u32,
            cdc_operation,
            cdc_timestamp: cdc_timestamp.timestamp() as u32,
            follow_count,
        };

        let mut insert = self.ch_client.insert("follows_cdc").map_err(|e| {
            error!("ClickHouse insert preparation error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.write(&row).await.map_err(|e| {
            error!("ClickHouse row write error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.end().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        debug!(
            "Inserted follows CDC: follower={}, followee={}, op={:?}",
            follower_raw, following_raw, op
        );
        Ok(())
    }

    /// Insert comments CDC message into ClickHouse using type-safe parameterized insert
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
        // Validate UUIDs but keep as strings for ClickHouse compatibility
        let _ = Uuid::parse_str(&id_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid comment UUID: {}", e)))?;
        let _ = Uuid::parse_str(&post_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid post UUID: {}", e)))?;
        let _ = Uuid::parse_str(&user_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid user UUID: {}", e)))?;
        let content: String = Self::extract_field(data, "content")?;
        let parent_comment_id_raw: Option<String> =
            Self::extract_optional_field(data, "parent_comment_id");
        // Validate parent_comment_id if present
        if let Some(ref parent_id) = parent_comment_id_raw {
            let _ = Uuid::parse_str(parent_id).map_err(|e| {
                AnalyticsError::Validation(format!("Invalid parent_comment_id UUID: {}", e))
            })?;
        }
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;
        let updated_at_raw: String = Self::extract_field(data, "updated_at")?;
        let updated_at = Self::parse_datetime_best_effort(&updated_at_raw)?;
        let soft_delete_raw: Option<String> = Self::extract_optional_field(data, "soft_delete");
        let soft_delete = soft_delete_raw
            .as_deref()
            .map(Self::parse_datetime_best_effort)
            .transpose()?;

        let cdc_operation: i8 = match op {
            CdcOperation::Insert | CdcOperation::Read => 1,
            CdcOperation::Update => 2,
            CdcOperation::Delete => 3,
        };
        let cdc_timestamp = msg.timestamp();

        // Use type-safe parameterized insert to prevent SQL injection
        // Convert DateTime to unix timestamp (u32) for ClickHouse DateTime compatibility
        let row = CommentsCdcRow {
            id: id_raw.clone(),
            post_id: post_raw,
            user_id: user_raw,
            content,
            parent_comment_id: parent_comment_id_raw.unwrap_or_default(),
            created_at: created_at.timestamp() as u32,
            updated_at: updated_at.timestamp() as u32,
            soft_delete: soft_delete.map(|dt| dt.timestamp() as u32).unwrap_or(0),
            cdc_operation,
            cdc_timestamp: cdc_timestamp.timestamp() as u32,
        };

        let mut insert = self.ch_client.insert("comments_cdc").map_err(|e| {
            error!("ClickHouse insert preparation error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.write(&row).await.map_err(|e| {
            error!("ClickHouse row write error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.end().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        debug!("Inserted comments CDC: id={}, op={:?}", id_raw, op);
        Ok(())
    }

    /// Insert likes CDC message into ClickHouse using type-safe parameterized insert
    async fn insert_likes_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let user_raw: String = Self::extract_field(data, "user_id")?;
        let post_raw: String = Self::extract_field(data, "post_id")?;
        // Validate UUIDs but store as strings for clickhouse-rs compatibility
        Uuid::parse_str(&user_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid user UUID: {}", e)))?;
        Uuid::parse_str(&post_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid post UUID: {}", e)))?;
        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;

        let cdc_operation: i8 = match op {
            CdcOperation::Delete => 2,
            CdcOperation::Insert | CdcOperation::Read | CdcOperation::Update => 1,
        };
        let like_count: i8 = if *op == CdcOperation::Delete { -1 } else { 1 };
        let cdc_timestamp = msg.timestamp();

        // Use type-safe parameterized insert to prevent SQL injection
        // Uses String for UUIDs and u32 for DateTime to avoid clickhouse-rs serialization issues
        let row = LikesCdcRow {
            post_id: post_raw.clone(),
            user_id: user_raw.clone(),
            created_at: created_at.timestamp() as u32,
            cdc_operation,
            cdc_timestamp: cdc_timestamp.timestamp() as u32,
            like_count,
        };

        let mut insert = self.ch_client.insert("likes_cdc").map_err(|e| {
            error!("ClickHouse insert preparation error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.write(&row).await.map_err(|e| {
            error!("ClickHouse row write error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.end().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        debug!(
            "Inserted likes CDC: user={}, post={}, op={:?}",
            user_raw, post_raw, op
        );
        Ok(())
    }

    /// Insert users CDC message into ClickHouse using type-safe parameterized insert
    async fn insert_users_cdc(&self, msg: &CdcMessage) -> Result<()> {
        let op = msg.operation();
        let data = match op {
            CdcOperation::Delete => msg.payload().before.as_ref(),
            _ => msg.payload().after.as_ref(),
        }
        .ok_or_else(|| AnalyticsError::Validation("CDC message missing data field".to_string()))?;

        let id_raw: String = Self::extract_field(data, "id")?;
        let user_id = Uuid::parse_str(&id_raw)
            .map_err(|e| AnalyticsError::Validation(format!("Invalid user UUID: {}", e)))?;

        let username: String = Self::extract_field(data, "username")?;
        let display_name: String =
            Self::extract_optional_field(data, "display_name").unwrap_or_default();
        let email: String = Self::extract_optional_field(data, "email").unwrap_or_default();
        let avatar_url: String =
            Self::extract_optional_field(data, "avatar_url").unwrap_or_default();
        let bio: String = Self::extract_optional_field(data, "bio").unwrap_or_default();

        let created_at_raw: String = Self::extract_field(data, "created_at")?;
        let created_at = Self::parse_datetime_best_effort(&created_at_raw)?;
        let updated_at_raw: String = Self::extract_field(data, "updated_at")?;
        let updated_at = Self::parse_datetime_best_effort(&updated_at_raw)?;
        let deleted_at_raw: Option<String> = Self::extract_optional_field(data, "deleted_at");
        let deleted_at = deleted_at_raw
            .as_deref()
            .map(Self::parse_datetime_best_effort)
            .transpose()?;

        let cdc_operation: i8 = match op {
            CdcOperation::Insert | CdcOperation::Read => 1,
            CdcOperation::Update => 2,
            CdcOperation::Delete => 3,
        };
        let cdc_timestamp = msg.timestamp();

        // Use type-safe parameterized insert to prevent SQL injection
        let row = UsersCdcRow {
            id: user_id,
            username,
            display_name,
            email,
            avatar_url,
            bio,
            created_at,
            updated_at,
            deleted_at,
            cdc_operation,
            cdc_timestamp,
        };

        let mut insert = self.ch_client.insert("users_cdc").map_err(|e| {
            error!("ClickHouse insert preparation error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.write(&row).await.map_err(|e| {
            error!("ClickHouse row write error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        insert.end().await.map_err(|e| {
            error!("ClickHouse insert error: {}", e);
            AnalyticsError::ClickHouse(e.to_string())
        })?;

        debug!(
            "Inserted users CDC: id={}, username={}, op={:?}",
            user_id, row.username, op
        );
        Ok(())
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

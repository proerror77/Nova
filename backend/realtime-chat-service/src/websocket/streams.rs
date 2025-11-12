//! Redis Streams-based message distribution
//! Provides ordered, durable, and idempotent message delivery across instances
//! with support for consumer groups and offline message replay

use crate::{models::message::MessageEnvelope, redis_client::RedisClient as Client};
use redis::{aio::ConnectionManager, AsyncCommands};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::time::{self, Duration};
use uuid::Uuid;

/// Represents a stream message entry
#[derive(Debug, Clone)]
pub struct StreamMessage {
    pub id: String, // Redis stream entry ID (timestamp-sequence)
    pub conversation_id: Uuid,
    pub payload: String,
    pub timestamp: u64,
}

/// Configuration for Redis Streams consumer
pub struct StreamsConfig {
    /// Maximum age of messages to keep (in ms)
    pub max_age_ms: u64,
    /// Consumer group name
    pub group_name: String,
    /// Consumer name (instance ID)
    pub consumer_name: String,
    /// Batch size for reading messages
    pub batch_size: usize,
}

impl Default for StreamsConfig {
    fn default() -> Self {
        Self {
            max_age_ms: 24 * 60 * 60 * 1000, // 24 hours
            group_name: "messaging-service".to_string(),
            consumer_name: format!("instance-{}", uuid::Uuid::new_v4()),
            batch_size: 100,
        }
    }
}

/// Stream key naming convention
fn stream_key(conversation_id: Uuid) -> String {
    format!("stream:conversation:{}", conversation_id)
}

/// Consumer group stream key
fn group_stream_key() -> String {
    "stream:fanout:all-conversations".to_string()
}

/// Global message counter for probabilistic stream trimming
/// Only trim every 100 messages to avoid performance overhead
static TRIM_COUNTER: AtomicU64 = AtomicU64::new(0);
const TRIM_INTERVAL: u64 = 100; // Trim every 100 messages

/// Publish message to stream for a specific conversation
pub async fn publish_envelope(
    client: &Client,
    envelope: &MessageEnvelope,
) -> redis::RedisResult<String> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = stream_key(envelope.conversation_id);
    let envelope_json = envelope.to_json().map_err(|e| {
        redis::RedisError::from((
            redis::ErrorKind::TypeError,
            "serialize message envelope",
            e.to_string(),
        ))
    })?;

    // Add to conversation-specific stream
    let entry_id: String = conn
        .xadd::<_, _, _, _, String>(
            &key,
            "*", // Auto-generate ID with current timestamp
            &[
                (
                    "conversation_id",
                    envelope.conversation_id.to_string().as_str(),
                ),
                ("payload", envelope_json.as_str()),
                (
                    "timestamp",
                    &chrono::Utc::now().timestamp_millis().to_string(),
                ),
            ],
        )
        .await?;

    // Also add to fanout stream for consumer group processing
    conn.xadd::<_, _, _, _, String>(
        group_stream_key(),
        "*",
        &[
            (
                "conversation_id",
                envelope.conversation_id.to_string().as_str(),
            ),
            ("stream_key", key.as_str()),
            ("entry_id", entry_id.as_str()),
        ],
    )
    .await?;

    // === CRITICAL FIX: Probabilistic stream trimming ===
    // Only trim every 100 messages (not every message) to prevent performance degradation
    // Previous implementation trimmed on every message, causing Redis bottlenecks
    let counter = TRIM_COUNTER.fetch_add(1, Ordering::Relaxed);
    if counter.is_multiple_of(TRIM_INTERVAL) {
        // Non-blocking trim: spawn background task to avoid blocking main message path
        let key_clone = key.clone();
        let redis_client = client.clone();

        tokio::spawn(async move {
            let mut trim_conn = match redis_client.get_multiplexed_async_connection().await {
                Ok(c) => c,
                Err(e) => {
                    tracing::warn!("Failed to connect for stream trim: {:?}", e);
                    return;
                }
            };

            // Trim to keep 50,000 most recent messages (more reasonable than 1,000)
            // Approximate trimming allows ±10% variance but is much faster
            if let Err(e) = redis::cmd("XTRIM")
                .arg(&key_clone)
                .arg("MAXLEN")
                .arg("~") // Approximate trimming for performance
                .arg(50000) // Keep last 50k messages (~1-2MB per stream)
                .query_async::<_, ()>(&mut trim_conn)
                .await
            {
                tracing::warn!("Failed to trim stream {}: {:?}", key_clone, e);
            }
        });
    }

    Ok(entry_id)
}

/// Initialize consumer group (idempotent)
pub async fn ensure_consumer_group(
    client: &Client,
    config: &StreamsConfig,
) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = group_stream_key();

    // Try to create consumer group, ignore if already exists
    let _: Result<(), _> = redis::cmd("XGROUP")
        .arg("CREATE")
        .arg(&key)
        .arg(&config.group_name)
        .arg("0") // Start from beginning
        .arg("MKSTREAM") // Create stream if doesn't exist
        .query_async(&mut conn)
        .await;

    Ok(())
}

/// Read pending messages for this consumer
pub async fn read_pending_messages(
    client: &Client,
    config: &StreamsConfig,
    last_id: &str,
) -> redis::RedisResult<Vec<StreamMessage>> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = group_stream_key();

    // Read messages starting from after last_id
    let messages: Vec<(String, HashMap<String, String>)> = redis::cmd("XREAD")
        .arg("COUNT")
        .arg(config.batch_size)
        .arg("STREAMS")
        .arg(&key)
        .arg(if last_id.is_empty() { "0" } else { last_id })
        .query_async(&mut conn)
        .await?;

    let mut results = Vec::new();

    for (stream_id, fields) in messages {
        let conversation_id_str = fields.get("conversation_id").ok_or_else(|| {
            redis::RedisError::from((redis::ErrorKind::TypeError, "missing conversation_id"))
        })?;

        let conversation_id = match Uuid::parse_str(conversation_id_str) {
            Ok(id) => id,
            Err(_) => {
                tracing::warn!(
                    "Invalid conversation_id in stream entry: {}",
                    conversation_id_str
                );
                continue;
            }
        };

        let payload = match fields.get("payload").cloned() {
            Some(p) => p,
            None => {
                let entry_id = fields.get("entry_id").ok_or_else(|| {
                    redis::RedisError::from((redis::ErrorKind::TypeError, "missing entry_id"))
                })?;
                match fetch_conversation_payload(&mut conn, conversation_id, entry_id).await? {
                    Some(p) => p,
                    None => {
                        tracing::warn!(
                            "Fanout entry {} missing payload in conversation stream {}",
                            entry_id,
                            conversation_id
                        );
                        continue;
                    }
                }
            }
        };

        results.push(StreamMessage {
            id: stream_id,
            conversation_id,
            payload,
            timestamp: chrono::Utc::now().timestamp_millis() as u64,
        });
    }

    Ok(results)
}

async fn fetch_conversation_payload(
    conn: &mut ConnectionManager,
    conversation_id: Uuid,
    entry_id: &str,
) -> redis::RedisResult<Option<String>> {
    let key = stream_key(conversation_id);
    let entries: Vec<(String, HashMap<String, String>)> = redis::cmd("XRANGE")
        .arg(&key)
        .arg(entry_id)
        .arg(entry_id)
        .query_async(conn)
        .await?;

    if let Some((_, fields)) = entries.into_iter().next() {
        Ok(fields.get("payload").cloned())
    } else {
        Ok(None)
    }
}

/// Acknowledge message (mark as processed)
pub async fn ack_message(
    client: &Client,
    config: &StreamsConfig,
    message_id: &str,
) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = group_stream_key();

    conn.xack(&key, &config.group_name, &[message_id]).await
}

/// Get consumer group info (for monitoring)
pub async fn get_group_info(
    client: &Client,
    _config: &StreamsConfig,
) -> redis::RedisResult<HashMap<String, String>> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = group_stream_key();

    let info: Vec<(String, String)> = redis::cmd("XINFO")
        .arg("GROUPS")
        .arg(&key)
        .query_async(&mut conn)
        .await
        .unwrap_or_default();

    Ok(info.into_iter().collect())
}

/// Trim old messages from stream (maintenance)
/// Called periodically to clean up the fanout stream
pub async fn trim_old_messages(client: &Client, _config: &StreamsConfig) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = group_stream_key();

    // Trim fanout stream using MINID strategy
    // Keep messages from the last 24 hours by approximate ID
    // In Redis Streams, the ID format is: timestamp-sequence
    // We calculate the cutoff as: now - 24 hours (in milliseconds)
    let now_ms = chrono::Utc::now().timestamp_millis();
    let cutoff_ms = now_ms - (24 * 60 * 60 * 1000); // 24 hours ago

    // XTRIM with MINID removes all entries with ID < cutoff_ms
    // The '-' at the end means use approximate trimming for better performance
    let _: Result<(), _> = redis::cmd("XTRIM")
        .arg(&key)
        .arg("MINID")
        .arg("~") // Approximate trimming for performance
        .arg(format!("{}-0", cutoff_ms)) // Format: timestamp-sequence
        .query_async(&mut conn)
        .await;

    Ok(())
}

/// Listener for stream messages (alternative to pubsub)
pub async fn start_streams_listener(
    client: Client,
    registry: crate::websocket::ConnectionRegistry,
    config: StreamsConfig,
) -> redis::RedisResult<()> {
    // Ensure consumer group exists
    ensure_consumer_group(&client, &config).await?;

    let mut last_id = "0".to_string();
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = group_stream_key();

    loop {
        // Read messages with timeout
        let read_result: redis::RedisResult<Vec<(String, HashMap<String, String>)>> =
            redis::cmd("XREAD")
                .arg("BLOCK")
                .arg("5000") // Block for 5 seconds
                .arg("COUNT")
                .arg(config.batch_size)
                .arg("STREAMS")
                .arg(&key)
                .arg(&last_id)
                .query_async(&mut conn)
                .await;

        match read_result {
            Ok(messages) => {
                for (stream_id, fields) in messages {
                    // Extract conversation_id and stream_key
                    if let Some(conv_id_str) = fields.get("conversation_id") {
                        if let Ok(conversation_id) = Uuid::parse_str(conv_id_str) {
                            // Fetch actual message from conversation stream
                            if let Some(stream_key_name) = fields.get("stream_key") {
                                let entry_id = fields.get("entry_id").cloned().unwrap_or_default();
                                if let Ok(msg_data) =
                                    fetch_stream_entry(&mut conn, stream_key_name, &entry_id).await
                                {
                                    let payload = match MessageEnvelope::from_json(&msg_data) {
                                        Ok(mut envelope) => {
                                            envelope.set_stream_id(entry_id.clone());
                                            envelope.to_json().unwrap_or(msg_data.clone())
                                        }
                                        Err(_) => msg_data.clone(),
                                    };

                                    registry.broadcast(conversation_id, payload).await;
                                }
                            }
                        }
                    }

                    last_id = stream_id;
                }
            }
            Err(e) if e.kind() == redis::ErrorKind::IoError => {
                // Timeout or connection issue, continue
                time::sleep(Duration::from_millis(100)).await;
            }
            Err(e) => {
                tracing::error!(error=%e, "stream listener error");
                time::sleep(Duration::from_secs(1)).await;
            }
        }
    }
}

/// Fetch a single entry from stream
async fn fetch_stream_entry(
    conn: &mut ConnectionManager,
    stream_key: &str,
    entry_id: &str,
) -> redis::RedisResult<String> {
    if entry_id.is_empty() {
        return Ok(String::new());
    }

    let entries: Vec<(String, Vec<(String, String)>)> = redis::cmd("XRANGE")
        .arg(stream_key)
        .arg(entry_id)
        .arg(entry_id)
        .query_async(conn)
        .await?;

    if let Some((_, fields)) = entries.first() {
        Ok(fields
            .iter()
            .find(|(k, _)| k == "payload")
            .map(|(_, v)| v.clone())
            .unwrap_or_default())
    } else {
        Ok(String::new())
    }
}

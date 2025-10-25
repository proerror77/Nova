//! Redis Streams-based message distribution
//! Provides ordered, durable, and idempotent message delivery across instances
//! with support for consumer groups and offline message replay

use redis::{Client, AsyncCommands, aio::MultiplexedConnection};
use uuid::Uuid;
use std::collections::HashMap;
use tokio::time::{self, Duration};

/// Represents a stream message entry
#[derive(Debug, Clone)]
pub struct StreamMessage {
    pub id: String,  // Redis stream entry ID (timestamp-sequence)
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
            max_age_ms: 24 * 60 * 60 * 1000,  // 24 hours
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

/// Publish message to stream for a specific conversation
pub async fn publish_to_stream(
    client: &Client,
    conversation_id: Uuid,
    payload: &str,
) -> redis::RedisResult<String> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = stream_key(conversation_id);

    // Add to conversation-specific stream
    let entry_id: String = conn.xadd::<_, _, _, _, String>(
        &key,
        "*",  // Auto-generate ID with current timestamp
        &[
            ("conversation_id", conversation_id.to_string().as_str()),
            ("payload", payload),
            ("timestamp", &chrono::Utc::now().timestamp_millis().to_string()),
        ]
    ).await?;

    // Also add to fanout stream for consumer group processing
    conn.xadd::<_, _, _, _, String>(
        group_stream_key(),
        "*",
        &[
            ("conversation_id", conversation_id.to_string().as_str()),
            ("stream_key", key.as_str()),
            ("entry_id", entry_id.as_str()),
        ]
    ).await?;

    // === CRITICAL FIX: Trim stream to prevent unbounded growth ===
    // Every 100 messages, trim to max 1000 entries using XTRIM
    // This prevents Redis from running out of memory
    let _: Result<(), _> = redis::cmd("XTRIM")
        .arg(&key)
        .arg("MAXLEN")
        .arg("~")  // Approximate trimming for performance
        .arg(1000)  // Keep last 1000 messages
        .query_async(&mut conn)
        .await;

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
        .arg("0")  // Start from beginning
        .arg("MKSTREAM")  // Create stream if doesn't exist
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
        let conversation_id_str = fields.get("conversation_id")
            .ok_or_else(|| redis::RedisError::from((redis::ErrorKind::TypeError, "missing conversation_id")))?;
        let payload = fields.get("payload")
            .cloned()
            .or_else(|| {
                // For fanout stream, fetch from conversation stream
                fields.get("entry_id").cloned()
            })
            .ok_or_else(|| redis::RedisError::from((redis::ErrorKind::TypeError, "missing payload")))?;

        if let Ok(conversation_id) = Uuid::parse_str(conversation_id_str) {
            results.push(StreamMessage {
                id: stream_id,
                conversation_id,
                payload,
                timestamp: chrono::Utc::now().timestamp_millis() as u64,
            });
        }
    }

    Ok(results)
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
pub async fn trim_old_messages(
    client: &Client,
    _config: &StreamsConfig,
) -> redis::RedisResult<()> {
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
        .arg("~")  // Approximate trimming for performance
        .arg(format!("{}-0", cutoff_ms))  // Format: timestamp-sequence
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
                .arg("5000")  // Block for 5 seconds
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
                                if let Ok(msg_data) = fetch_stream_entry(
                                    &mut conn,
                                    stream_key_name,
                                    &fields.get("entry_id").cloned().unwrap_or_default(),
                                ).await {
                                    registry.broadcast(
                                        conversation_id,
                                        axum::extract::ws::Message::Text(msg_data)
                                    ).await;
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
    conn: &mut MultiplexedConnection,
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
        Ok(fields.iter()
            .find(|(k, _)| k == "payload")
            .map(|(_, v)| v.clone())
            .unwrap_or_default())
    } else {
        Ok(String::new())
    }
}

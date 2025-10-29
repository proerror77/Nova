//! Offline message queue for clients
//! Implements "sync from last known ID" pattern for message recovery
//! Allows clients to resume from where they left off when reconnecting

use redis::{AsyncCommands, Client, FromRedisValue, RedisResult, Value as RedisValue};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;
use crate::models::message::MessageEnvelope;

/// Represents a client's position in the message stream
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientSyncState {
    pub client_id: Uuid,
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    /// Last message ID received (Redis stream ID format: timestamp-sequence)
    pub last_message_id: String,
    /// Timestamp of last sync
    pub last_sync_at: i64,
}

/// Key pattern for storing client sync state
fn client_state_key(user_id: Uuid, client_id: Uuid) -> String {
    format!("client:sync:{}:{}", user_id, client_id)
}

/// Key pattern for conversation-specific client state
fn conversation_clients_key(conversation_id: Uuid) -> String {
    format!("conversation:clients:{}", conversation_id)
}

fn conversation_stream_key(conversation_id: Uuid) -> String {
    format!("stream:conversation:{}", conversation_id)
}

fn conversation_group_name(conversation_id: Uuid) -> String {
    format!("ws:{}", conversation_id)
}

fn consumer_name(user_id: Uuid, client_id: Uuid) -> String {
    format!("{}:{}", user_id, client_id)
}

fn flatten_read_entries(
    raw: RedisValue,
    conversation_id: Uuid,
) -> RedisResult<Vec<(String, HashMap<String, String>)>> {
    if raw == RedisValue::Nil {
        return Ok(Vec::new());
    }

    let parsed: Vec<(String, Vec<(String, Vec<(String, String)>)>)> =
        FromRedisValue::from_redis_value(&raw)?;

    Ok(parsed
        .into_iter()
        .flat_map(|(_, entries)| entries)
        .map(|(id, fields)| convert_entry(conversation_id, id, fields))
        .collect())
}

fn convert_entry(
    conversation_id: Uuid,
    entry_id: String,
    fields: Vec<(String, String)>,
) -> (String, HashMap<String, String>) {
    let mut map = HashMap::new();
    for (k, v) in fields {
        map.insert(k, v);
    }

    map.entry("conversation_id".to_string())
        .or_insert(conversation_id.to_string());

    if let Some(payload) = map.get_mut("payload") {
        if let Ok(mut envelope) = MessageEnvelope::from_json(payload) {
            envelope.set_stream_id(entry_id.clone());
            if let Ok(serialized) = envelope.to_json() {
                *payload = serialized;
            }
        }
    }

    (entry_id, map)
}

/// Record client sync state after receiving messages
pub async fn update_client_sync_state(
    client: &Client,
    state: &ClientSyncState,
) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = client_state_key(state.user_id, state.client_id);

    // Store with TTL (30 days) - clients should sync regularly
    let json = serde_json::to_string(&state)
        .map_err(|_| redis::RedisError::from((redis::ErrorKind::TypeError, "serialize failed")))?;

    conn.set_ex::<_, _, ()>(
        key,
        json,
        30 * 24 * 60 * 60, // 30 days TTL
    )
    .await?;

    // Also track in per-conversation index for bulk operations
    let conv_key = conversation_clients_key(state.conversation_id);
    conn.sadd::<_, _, ()>(conv_key, state.client_id.to_string())
        .await?;

    Ok(())
}

/// Get client sync state (last known position)
pub async fn get_client_sync_state(
    client: &Client,
    user_id: Uuid,
    client_id: Uuid,
) -> redis::RedisResult<Option<ClientSyncState>> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = client_state_key(user_id, client_id);

    let json: Option<String> = conn.get(&key).await?;

    Ok(json.and_then(|j| serde_json::from_str(&j).ok()))
}

/// Get all clients in a conversation (for broadcast tracking)
pub async fn get_conversation_clients(
    client: &Client,
    conversation_id: Uuid,
) -> redis::RedisResult<Vec<Uuid>> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = conversation_clients_key(conversation_id);

    let clients: Vec<String> = conn.smembers(&key).await?;

    Ok(clients
        .into_iter()
        .filter_map(|id| Uuid::parse_str(&id).ok())
        .collect())
}

/// Clear client sync state (when client logs out)
pub async fn clear_client_sync_state(
    client: &Client,
    user_id: Uuid,
    client_id: Uuid,
) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = client_state_key(user_id, client_id);

    conn.del::<_, ()>(&key).await?;

    Ok(())
}

/// Find offline messages for a user in specific conversations
pub async fn get_messages_since(
    client: &Client,
    conversation_id: Uuid,
    since_id: &str,
) -> redis::RedisResult<Vec<(String, HashMap<String, String>)>> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let stream_key = format!("stream:conversation:{}", conversation_id);

    // Create the range start value with proper lifetime
    let range_start = if since_id.is_empty() {
        "0".to_string()
    } else {
        format!("({}", since_id)
    };

    // Get all messages after since_id
    let messages: Vec<(String, HashMap<String, String>)> = redis::cmd("XRANGE")
        .arg(&stream_key)
        .arg(&range_start) // Exclusive range start
        .arg("+") // To the latest
        .query_async(&mut conn)
        .await
        .unwrap_or_default();

    Ok(messages)
}

/// Store offline message notification
pub async fn queue_offline_notification(
    client: &Client,
    user_id: Uuid,
    conversation_id: Uuid,
    message_count: usize,
) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = format!("offline:{}:{}", user_id, conversation_id);

    conn.set_ex::<_, _, ()>(
        key,
        message_count.to_string(),
        24 * 60 * 60, // 24 hour TTL
    )
    .await?;

    Ok(())
}

/// Get offline message count for conversation
pub async fn get_offline_message_count(
    client: &Client,
    user_id: Uuid,
    conversation_id: Uuid,
) -> redis::RedisResult<usize> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let key = format!("offline:{}:{}", user_id, conversation_id);

    let count: Option<String> = conn.get(&key).await?;

    Ok(count.and_then(|c| c.parse::<usize>().ok()).unwrap_or(0))
}

/// Batch clear offline notifications for user
pub async fn clear_offline_notifications(
    client: &Client,
    user_id: Uuid,
    conversation_ids: &[Uuid],
) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;

    for conv_id in conversation_ids {
        let key = format!("offline:{}:{}", user_id, conv_id);
        conn.del::<_, ()>(&key).await?;
    }

    Ok(())
}

// ============================================
// Wrapper functions for Redis Streams API
// (Bridges handlers.rs to streams.rs)
// ============================================

/// Initialize consumer group for a conversation (wrapper)
pub async fn init_consumer_group(
    client: &Client,
    conversation_id: Uuid,
) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let stream_key = conversation_stream_key(conversation_id);
    let group = conversation_group_name(conversation_id);

    let _: Result<(), _> = redis::cmd("XGROUP")
        .arg("CREATE")
        .arg(&stream_key)
        .arg(&group)
        .arg("0")
        .arg("MKSTREAM")
        .query_async(&mut conn)
        .await;

    Ok(())
}

/// Read pending messages for a consumer (wrapper)
pub async fn read_pending_messages(
    client: &Client,
    conversation_id: Uuid,
    user_id: Uuid,
    client_id: Uuid,
) -> redis::RedisResult<Vec<(String, HashMap<String, String>)>> {
    let stream_key = conversation_stream_key(conversation_id);
    let group = conversation_group_name(conversation_id);
    let consumer = consumer_name(user_id, client_id);

    let mut conn = client.get_multiplexed_async_connection().await?;
    let mut results: Vec<(String, HashMap<String, String>)> = Vec::new();

    // Claim stale pending entries
    let mut start = "0".to_string();
    loop {
        let raw: RedisValue = redis::cmd("XAUTOCLAIM")
            .arg(&stream_key)
            .arg(&group)
            .arg(&consumer)
            .arg(1000) // minimum idle (ms)
            .arg(&start)
            .arg("COUNT")
            .arg(100)
            .query_async(&mut conn)
            .await?;

        if raw == RedisValue::Nil {
            break;
        }

        let (next_start, entries): (String, Vec<(String, Vec<(String, String)>)>) =
            FromRedisValue::from_redis_value(&raw)?;

        for (entry_id, fields) in &entries {
            results.push(convert_entry(conversation_id, entry_id.clone(), fields.clone()));
        }

        if next_start == "0-0" || entries.is_empty() {
            break;
        }

        start = next_start;
    }

    // Read pending entries assigned to this consumer
    let raw_pending: RedisValue = redis::cmd("XREADGROUP")
        .arg("GROUP")
        .arg(&group)
        .arg(&consumer)
        .arg("COUNT")
        .arg(100)
        .arg("STREAMS")
        .arg(&stream_key)
        .arg("0")
        .query_async(&mut conn)
        .await
        .unwrap_or(RedisValue::Nil);

    results.extend(flatten_read_entries(raw_pending, conversation_id)?);

    Ok(results)
}

/// Read new messages (alias to read_pending_messages for now)
pub async fn read_new_messages(
    client: &Client,
    conversation_id: Uuid,
    user_id: Uuid,
    client_id: Uuid,
) -> redis::RedisResult<Vec<(String, HashMap<String, String>)>> {
    let stream_key = conversation_stream_key(conversation_id);
    let group = conversation_group_name(conversation_id);
    let consumer = consumer_name(user_id, client_id);

    let mut conn = client.get_multiplexed_async_connection().await?;
    let raw: RedisValue = redis::cmd("XREADGROUP")
        .arg("GROUP")
        .arg(&group)
        .arg(&consumer)
        .arg("COUNT")
        .arg(100)
        .arg("STREAMS")
        .arg(&stream_key)
        .arg(">")
        .query_async(&mut conn)
        .await
        .unwrap_or(RedisValue::Nil);

    flatten_read_entries(raw, conversation_id)
}

/// Acknowledge message (wrapper)
pub async fn acknowledge_message(
    client: &Client,
    conversation_id: Uuid,
    stream_id: &str,
) -> redis::RedisResult<()> {
    let stream_key = conversation_stream_key(conversation_id);
    let group = conversation_group_name(conversation_id);
    let mut conn = client.get_multiplexed_async_connection().await?;

    redis::cmd("XACK")
        .arg(&stream_key)
        .arg(&group)
        .arg(stream_id)
        .query_async::<_, ()>(&mut conn)
        .await?;

    Ok(())
}

/// Trim stream to keep recent messages (wrapper)
pub async fn trim_stream(
    client: &Client,
    _conversation_id: Uuid,
    _max_len: usize,
) -> redis::RedisResult<()> {
    use crate::websocket::streams::{trim_old_messages, StreamsConfig};
    let config = StreamsConfig::default();
    trim_old_messages(client, &config).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_state_key_format() {
        let user = Uuid::new_v4();
        let client = Uuid::new_v4();
        let key = client_state_key(user, client);
        assert!(key.starts_with("client:sync:"));
    }

    #[test]
    fn test_sync_state_serialization() {
        let state = ClientSyncState {
            client_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            last_message_id: "1234567890-0".to_string(),
            last_sync_at: 1234567890,
        };

        let json = serde_json::to_string(&state).unwrap();
        let deserialized: ClientSyncState = serde_json::from_str(&json).unwrap();

        assert_eq!(state.client_id, deserialized.client_id);
        assert_eq!(state.last_message_id, deserialized.last_message_id);
    }
}

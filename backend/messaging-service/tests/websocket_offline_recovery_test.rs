/// WebSocket Offline Message Recovery Integration Tests
///
/// Tests the complete flow of offline message recovery:
/// 1. Client disconnects
/// 2. Messages arrive while disconnected
/// 3. Client reconnects and receives offline messages
/// 4. New messages continue to arrive

use uuid::Uuid;
use redis::Client;
use serde_json::json;

#[tokio::test]
async fn test_offline_message_recovery_basic_flow() {
    // Setup Redis connection
    let client = Client::open("redis://127.0.0.1/").expect("Failed to open Redis client");
    let mut conn = client.get_multiplexed_async_connection().await.expect("Failed to get connection");

    let user_id = Uuid::new_v4();
    let client_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    // === STEP 1: Create initial client sync state (simulating first connection) ===
    let initial_state_key = format!("client:sync:{}:{}", user_id, client_id);
    let initial_state = json!({
        "client_id": client_id.to_string(),
        "user_id": user_id.to_string(),
        "conversation_id": conversation_id.to_string(),
        "last_message_id": "0",
        "last_sync_at": 1000000
    });

    use redis::AsyncCommands;
    let _: () = conn.set_ex(
        &initial_state_key,
        initial_state.to_string(),
        30 * 24 * 3600, // 30 days
    ).await.expect("Failed to set initial state");

    // === STEP 2: Publish messages to stream (simulating messages while client is offline) ===
    let stream_key = format!("stream:conversation:{}", conversation_id);

    let msg1_id: String = conn.xadd(
        &stream_key,
        "*",
        &[
            ("payload", r#"{"type":"message","text":"offline msg 1"}"#),
            ("user_id", &user_id.to_string()),
            ("timestamp", "1000001"),
        ],
    ).await.expect("Failed to add first message");

    let msg2_id: String = conn.xadd(
        &stream_key,
        "*",
        &[
            ("payload", r#"{"type":"message","text":"offline msg 2"}"#),
            ("user_id", &user_id.to_string()),
            ("timestamp", "1000002"),
        ],
    ).await.expect("Failed to add second message");

    // === STEP 3: Verify messages exist in stream ===
    let range_result: Vec<(String, Vec<(String, String)>)> = conn.xrange(
        &stream_key,
        "-",
        "+",
    ).await.expect("Failed to get messages");

    assert!(
        range_result.len() >= 2,
        "Expected at least 2 messages in stream, got {}",
        range_result.len()
    );

    // === STEP 4: Simulate client reconnection - query offline messages ===
    // This is what the WebSocket handler would do in step 2 of offline recovery
    let messages_since: Vec<(String, Vec<(String, String)>)> = conn.xrange(
        &stream_key,
        "(0",  // Exclusive of "0"
        "+",
    ).await.expect("Failed to get messages since");

    // Verify we got the offline messages
    assert_eq!(messages_since.len(), 2, "Expected 2 offline messages for recovery");

    // Extract first message payload
    let first_msg_entry = &messages_since[0];
    let first_payload = first_msg_entry.1.iter()
        .find(|(k, _)| k == "payload")
        .map(|(_, v)| v.clone())
        .expect("Message missing payload");

    assert!(first_payload.contains("offline msg 1"), "First message payload incorrect");

    // === STEP 5: Update sync state with latest message ID ===
    let updated_state = json!({
        "client_id": client_id.to_string(),
        "user_id": user_id.to_string(),
        "conversation_id": conversation_id.to_string(),
        "last_message_id": msg2_id.clone(),
        "last_sync_at": 1000002
    });

    let _: () = conn.set_ex(
        &initial_state_key,
        updated_state.to_string(),
        30 * 24 * 3600,
    ).await.expect("Failed to update sync state");

    // === STEP 6: Verify subsequent messages won't be resent ===
    let no_messages: Vec<(String, Vec<(String, String)>)> = conn.xrange(
        &stream_key,
        &format!("({}",msg2_id),  // Exclusive of msg2_id
        "+",
    ).await.expect("Failed to check for newer messages");

    assert_eq!(no_messages.len(), 0, "Should have no messages after last known ID");

    // Cleanup
    let _: redis::RedisResult<()> = conn.del(&initial_state_key).await;
    let _: redis::RedisResult<()> = conn.del(&stream_key).await;
}

#[tokio::test]
async fn test_offline_message_recovery_with_no_previous_state() {
    let client = Client::open("redis://127.0.0.1/").expect("Failed to open Redis client");
    let mut conn = client.get_multiplexed_async_connection().await.expect("Failed to get connection");

    let user_id = Uuid::new_v4();
    let client_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    // === STEP 1: No previous sync state (first time connection) ===
    // Handler would use "0" as starting point

    // === STEP 2: Publish some messages ===
    let stream_key = format!("stream:conversation:{}", conversation_id);

    use redis::AsyncCommands;
    let _msg1: String = conn.xadd(
        &stream_key,
        "*",
        &[
            ("payload", r#"{"type":"message","text":"msg 1"}"#),
            ("user_id", &user_id.to_string()),
        ],
    ).await.expect("Failed to add message");

    // === STEP 3: Verify new client gets all messages ===
    let all_messages: Vec<(String, Vec<(String, String)>)> = conn.xrange(
        &stream_key,
        "(0",
        "+",
    ).await.expect("Failed to get messages");

    assert_eq!(all_messages.len(), 1, "New client should get all messages from stream");

    // Cleanup
    let _: redis::RedisResult<()> = conn.del(&stream_key).await;
}

#[tokio::test]
async fn test_multiple_clients_same_conversation_independent_recovery() {
    let client = Client::open("redis://127.0.0.1/").expect("Failed to open Redis client");
    let mut conn = client.get_multiplexed_async_connection().await.expect("Failed to get connection");

    let user_id = Uuid::new_v4();
    let client_id_1 = Uuid::new_v4();
    let client_id_2 = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    // === STEP 1: Two different clients with different last message IDs ===
    let state_key_1 = format!("client:sync:{}:{}", user_id, client_id_1);
    let state_key_2 = format!("client:sync:{}:{}", user_id, client_id_2);

    use redis::AsyncCommands;
    let state_1 = json!({
        "client_id": client_id_1.to_string(),
        "user_id": user_id.to_string(),
        "conversation_id": conversation_id.to_string(),
        "last_message_id": "1000-0",  // Client 1 already read up to here
        "last_sync_at": 1000000
    });

    let state_2 = json!({
        "client_id": client_id_2.to_string(),
        "user_id": user_id.to_string(),
        "conversation_id": conversation_id.to_string(),
        "last_message_id": "0",  // Client 2 hasn't read anything
        "last_sync_at": 1000000
    });

    let _: redis::RedisResult<()> = conn.set_ex(&state_key_1, state_1.to_string(), 30 * 24 * 3600).await;
    let _: redis::RedisResult<()> = conn.set_ex(&state_key_2, state_2.to_string(), 30 * 24 * 3600).await;

    // === STEP 2: Publish messages ===
    let stream_key = format!("stream:conversation:{}", conversation_id);

    let _: String = conn.xadd(
        &stream_key,
        "1000-0",
        &[("payload", r#"{"type":"message","text":"old msg"}"#)],
    ).await.ok().unwrap_or_default();

    let new_msg_id: String = conn.xadd(
        &stream_key,
        "*",
        &[("payload", r#"{"type":"message","text":"new msg"}"#)],
    ).await.expect("Failed to add new message");

    // === STEP 3: Client 1 should only get messages after "1000-0" ===
    let client1_messages: Vec<(String, Vec<(String, String)>)> = conn.xrange(
        &stream_key,
        "(1000-0",
        "+",
    ).await.expect("Failed to get client 1 messages");

    assert_eq!(client1_messages.len(), 1, "Client 1 should get only new message");

    // === STEP 4: Client 2 should get all messages ===
    let client2_messages: Vec<(String, Vec<(String, String)>)> = conn.xrange(
        &stream_key,
        "(0",
        "+",
    ).await.expect("Failed to get client 2 messages");

    assert_eq!(client2_messages.len(), 2, "Client 2 should get all messages");

    // Cleanup
    let _: redis::RedisResult<()> = conn.del(&state_key_1).await;
    let _: redis::RedisResult<()> = conn.del(&state_key_2).await;
    let _: redis::RedisResult<()> = conn.del(&stream_key).await;
}

#[tokio::test]
async fn test_client_sync_state_persistence_and_ttl() {
    let client = Client::open("redis://127.0.0.1/").expect("Failed to open Redis client");
    let mut conn = client.get_multiplexed_async_connection().await.expect("Failed to get connection");

    let user_id = Uuid::new_v4();
    let client_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    let state_key = format!("client:sync:{}:{}", user_id, client_id);

    use redis::AsyncCommands;
    let state = json!({
        "client_id": client_id.to_string(),
        "user_id": user_id.to_string(),
        "conversation_id": conversation_id.to_string(),
        "last_message_id": "1234-0",
        "last_sync_at": 1000000
    });

    // Set with 30-day TTL (same as production code)
    let _: () = conn.set_ex(
        &state_key,
        state.to_string(),
        30 * 24 * 3600,
    ).await.expect("Failed to set state with TTL");

    // Verify it exists
    let exists: bool = conn.exists(&state_key).await.expect("Failed to check existence");
    assert!(exists, "State should exist immediately after creation");

    // Verify TTL is approximately 30 days
    let ttl: i64 = conn.ttl(&state_key).await.expect("Failed to get TTL");
    let thirty_days_secs = 30 * 24 * 3600;
    assert!(ttl > 0 && ttl <= thirty_days_secs, "TTL should be between 0 and 30 days, got {}", ttl);

    // Update the state
    let updated_state = json!({
        "client_id": client_id.to_string(),
        "user_id": user_id.to_string(),
        "conversation_id": conversation_id.to_string(),
        "last_message_id": "5678-0",
        "last_sync_at": 1000010
    });

    let _: () = conn.set_ex(
        &state_key,
        updated_state.to_string(),
        30 * 24 * 3600,
    ).await.expect("Failed to update state");

    // Verify update works
    let stored: String = conn.get(&state_key).await.expect("Failed to retrieve state");
    let parsed: serde_json::Value = serde_json::from_str(&stored).expect("Failed to parse JSON");

    assert_eq!(
        parsed.get("last_message_id").and_then(|v| v.as_str()),
        Some("5678-0"),
        "State update should preserve new message ID"
    );

    // Cleanup
    let _: redis::RedisResult<()> = conn.del(&state_key).await;
}

// WebSocket Load and Stress Tests
// Phase 7A Week 2: T203.4 - WebSocket Handler Testing
//
// Validates:
// - 1k+ concurrent connections
// - Rapid connect/disconnect cycles
// - Message broadcast latency <100ms
// - Message ordering guarantees

use tokio::sync::mpsc;
use user_service::services::notifications::websocket_hub::{
    ConnectionState, Message, WebSocketHub,
};
use uuid::Uuid;

#[tokio::test]
async fn test_load_1k_concurrent_connections() {
    // Create hub with capacity for 2k messages
    let hub = WebSocketHub::new(2000);

    // Create 1000 concurrent connections
    let mut connection_ids = Vec::new();
    let mut receivers = Vec::new();

    for i in 0..1000 {
        let user_id = Uuid::new_v4();
        let (tx, rx) = mpsc::unbounded_channel();

        let connection_id = hub.accept_connection(user_id, tx).await;
        connection_ids.push(connection_id);
        receivers.push(rx);

        // Progress report every 100 connections
        if (i + 1) % 100 == 0 {
            println!("Created {} connections", i + 1);
        }
    }

    // Verify all connections are active
    assert_eq!(hub.connection_count().await, 1000);
    println!("✓ Successfully created 1000 concurrent connections");

    // Cleanup
    for connection_id in connection_ids {
        hub.remove_connection(connection_id).await;
    }

    assert_eq!(hub.connection_count().await, 0);
    println!("✓ Successfully cleaned up all connections");
}

#[tokio::test]
async fn test_stress_rapid_connect_disconnect() {
    let hub = WebSocketHub::new(1000);

    // Simulate rapid connect/disconnect cycles
    for cycle in 0..100 {
        // Connect 10 clients
        let mut connection_ids = Vec::new();

        for _ in 0..10 {
            let user_id = Uuid::new_v4();
            let (tx, _rx) = mpsc::unbounded_channel();
            let connection_id = hub.accept_connection(user_id, tx).await;
            connection_ids.push(connection_id);
        }

        assert_eq!(hub.connection_count().await, 10);

        // Immediately disconnect all
        for connection_id in connection_ids {
            hub.remove_connection(connection_id).await;
        }

        assert_eq!(hub.connection_count().await, 0);

        if (cycle + 1) % 20 == 0 {
            println!("Completed {} connect/disconnect cycles", cycle + 1);
        }
    }

    println!("✓ Successfully handled 100 rapid connect/disconnect cycles");
}

#[tokio::test]
async fn test_broadcast_latency_under_load() {
    let hub = WebSocketHub::new(2000);
    let connection_count = 1000;

    // Create 1000 concurrent connections
    let mut receivers = Vec::new();

    for _ in 0..connection_count {
        let user_id = Uuid::new_v4();
        let (tx, rx) = mpsc::unbounded_channel();
        hub.accept_connection(user_id, tx).await;
        receivers.push(rx);
    }

    println!("Created {} connections for latency test", connection_count);

    // Broadcast a message and measure latency
    let message = Message {
        message_type: "latency_test".to_string(),
        payload: serde_json::json!({"test": "broadcast performance"}),
        timestamp: chrono::Utc::now(),
    };

    let start = std::time::Instant::now();
    let sent_count = hub.broadcast(message.clone()).await;
    let broadcast_time = start.elapsed();

    assert_eq!(sent_count, connection_count);
    println!(
        "✓ Broadcast to {} clients in {:?}",
        connection_count, broadcast_time
    );

    // Verify latency target: <100ms for broadcast operation
    assert!(
        broadcast_time.as_millis() < 100,
        "Broadcast took {}ms, expected <100ms",
        broadcast_time.as_millis()
    );

    // Sample a few receivers to verify they got the message
    for (i, mut rx) in receivers.into_iter().enumerate().take(10) {
        match tokio::time::timeout(std::time::Duration::from_millis(50), rx.recv()).await {
            Ok(Some(msg)) => {
                assert_eq!(msg.message_type, "latency_test");
            }
            Ok(None) => panic!("Receiver {} channel closed unexpectedly", i),
            Err(_) => panic!("Receiver {} timed out waiting for message", i),
        }
    }

    println!("✓ Verified message delivery to sample receivers");
}

#[tokio::test]
async fn test_broadcast_message_ordering() {
    let hub = WebSocketHub::new(1000);

    // Create single connection
    let user_id = Uuid::new_v4();
    let (tx, mut rx) = mpsc::unbounded_channel();
    hub.accept_connection(user_id, tx).await;

    // Send 100 messages in sequence
    for i in 0..100 {
        let message = Message {
            message_type: "sequence_test".to_string(),
            payload: serde_json::json!({"sequence": i}),
            timestamp: chrono::Utc::now(),
        };
        hub.broadcast(message).await;
    }

    // Verify messages arrive in order
    for i in 0..100 {
        match tokio::time::timeout(std::time::Duration::from_millis(10), rx.recv()).await {
            Ok(Some(msg)) => {
                let sequence = msg.payload["sequence"].as_u64().unwrap();
                assert_eq!(
                    sequence, i,
                    "Message out of order: expected {}, got {}",
                    i, sequence
                );
            }
            Ok(None) => panic!("Channel closed at message {}", i),
            Err(_) => panic!("Timeout waiting for message {}", i),
        }
    }

    println!("✓ All 100 messages received in correct order");
}

#[tokio::test]
async fn test_connection_pool_exhaustion_graceful() {
    // Create hub with small capacity
    let hub = WebSocketHub::new(100);

    // Create many connections (more than typical capacity)
    let mut connection_ids = Vec::new();

    for _ in 0..150 {
        let user_id = Uuid::new_v4();
        let (tx, _rx) = mpsc::unbounded_channel();
        let connection_id = hub.accept_connection(user_id, tx).await;
        connection_ids.push(connection_id);
    }

    // Hub should handle gracefully without panicking
    assert_eq!(hub.connection_count().await, 150);
    println!("✓ Hub gracefully handled 150 connections (broadcast capacity: 100)");

    // Cleanup
    for connection_id in connection_ids {
        hub.remove_connection(connection_id).await;
    }
}

#[tokio::test]
async fn test_concurrent_broadcast_operations() {
    let hub = std::sync::Arc::new(WebSocketHub::new(1000));

    // Create 100 connections
    let mut receivers = Vec::new();
    for _ in 0..100 {
        let user_id = Uuid::new_v4();
        let (tx, rx) = mpsc::unbounded_channel();
        hub.accept_connection(user_id, tx).await;
        receivers.push(rx);
    }

    // Spawn 10 concurrent broadcast tasks
    let mut tasks = Vec::new();

    for task_id in 0..10 {
        let hub_clone = hub.clone();
        let task = tokio::spawn(async move {
            for i in 0..10 {
                let message = Message {
                    message_type: format!("task_{}", task_id),
                    payload: serde_json::json!({"message": i}),
                    timestamp: chrono::Utc::now(),
                };
                hub_clone.broadcast(message).await;
            }
        });
        tasks.push(task);
    }

    // Wait for all tasks to complete
    for task in tasks {
        task.await.unwrap();
    }

    println!("✓ Successfully completed 10 concurrent broadcast tasks (100 messages total)");

    // Each receiver should have gotten 100 messages
    for (i, mut rx) in receivers.into_iter().enumerate().take(5) {
        let mut count = 0;
        while let Ok(Some(_)) =
            tokio::time::timeout(std::time::Duration::from_millis(100), rx.recv()).await
        {
            count += 1;
        }
        assert_eq!(
            count, 100,
            "Receiver {} got {} messages, expected 100",
            i, count
        );
    }

    println!("✓ Verified all receivers got 100 messages");
}

#[tokio::test]
async fn test_mixed_broadcast_and_direct_messages() {
    let hub = WebSocketHub::new(1000);

    // Create 3 users with 2 connections each
    let user1 = Uuid::new_v4();
    let user2 = Uuid::new_v4();
    let user3 = Uuid::new_v4();

    let (tx1a, mut rx1a) = mpsc::unbounded_channel();
    let (tx1b, mut rx1b) = mpsc::unbounded_channel();
    let (tx2a, mut rx2a) = mpsc::unbounded_channel();
    let (tx2b, _rx2b) = mpsc::unbounded_channel();
    let (tx3a, _rx3a) = mpsc::unbounded_channel();
    let (tx3b, _rx3b) = mpsc::unbounded_channel();

    hub.accept_connection(user1, tx1a).await;
    hub.accept_connection(user1, tx1b).await;
    hub.accept_connection(user2, tx2a).await;
    hub.accept_connection(user2, tx2b).await;
    hub.accept_connection(user3, tx3a).await;
    hub.accept_connection(user3, tx3b).await;

    // Send broadcast message
    let broadcast_msg = Message {
        message_type: "broadcast".to_string(),
        payload: serde_json::json!({"content": "to all"}),
        timestamp: chrono::Utc::now(),
    };
    hub.broadcast(broadcast_msg).await;

    // Send direct message to user1
    let direct_msg = Message {
        message_type: "direct".to_string(),
        payload: serde_json::json!({"content": "to user1 only"}),
        timestamp: chrono::Utc::now(),
    };
    hub.send_to_user(user1, direct_msg).await;

    // User1 should receive both messages on both connections
    let msg1 = rx1a.recv().await.unwrap();
    assert_eq!(msg1.message_type, "broadcast");

    let msg2 = rx1a.recv().await.unwrap();
    assert_eq!(msg2.message_type, "direct");

    let msg3 = rx1b.recv().await.unwrap();
    assert_eq!(msg3.message_type, "broadcast");

    let msg4 = rx1b.recv().await.unwrap();
    assert_eq!(msg4.message_type, "direct");

    // User2 should only receive broadcast
    let msg5 = rx2a.recv().await.unwrap();
    assert_eq!(msg5.message_type, "broadcast");

    // User2 should not receive direct message
    match tokio::time::timeout(std::time::Duration::from_millis(10), rx2a.recv()).await {
        Ok(_) => panic!("User2 should not receive direct message for user1"),
        Err(_) => {} // Expected timeout
    }

    println!("✓ Mixed broadcast and direct messages routed correctly");
}

#[tokio::test]
async fn test_disconnected_clients_skip_broadcast() {
    let hub = WebSocketHub::new(1000);

    // Create 3 connections
    let (tx1, mut rx1) = mpsc::unbounded_channel();
    let (tx2, mut rx2) = mpsc::unbounded_channel();
    let (tx3, mut rx3) = mpsc::unbounded_channel();

    let user1 = Uuid::new_v4();
    let user2 = Uuid::new_v4();
    let user3 = Uuid::new_v4();

    let _conn1 = hub.accept_connection(user1, tx1).await;
    let conn2 = hub.accept_connection(user2, tx2).await;
    let _conn3 = hub.accept_connection(user3, tx3).await;

    // Mark conn2 as disconnected
    hub.update_connection_state(conn2, ConnectionState::Disconnected)
        .await;

    // Broadcast message
    let message = Message {
        message_type: "test".to_string(),
        payload: serde_json::json!({}),
        timestamp: chrono::Utc::now(),
    };

    let sent_count = hub.broadcast(message).await;
    assert_eq!(sent_count, 2); // Only conn1 and conn3 should receive

    // Verify conn1 received
    let msg1 = rx1.recv().await.unwrap();
    assert_eq!(msg1.message_type, "test");

    // Verify conn2 (disconnected) did not receive
    match tokio::time::timeout(std::time::Duration::from_millis(10), rx2.recv()).await {
        Ok(_) => panic!("Disconnected connection should not receive broadcast"),
        Err(_) => {} // Expected timeout
    }

    // Verify conn3 received
    let msg3 = rx3.recv().await.unwrap();
    assert_eq!(msg3.message_type, "test");

    println!("✓ Disconnected clients correctly skipped during broadcast");
}

#[tokio::test]
async fn test_performance_10k_connections() {
    // This is an extreme load test - may take longer
    let hub = WebSocketHub::new(20000);

    println!("Starting 10k connection test...");

    let start = std::time::Instant::now();

    // Create 10,000 connections
    let mut connection_ids = Vec::new();

    for i in 0..10000 {
        let user_id = Uuid::new_v4();
        let (tx, _rx) = mpsc::unbounded_channel();
        let connection_id = hub.accept_connection(user_id, tx).await;
        connection_ids.push(connection_id);

        if (i + 1) % 1000 == 0 {
            println!("Created {} connections", i + 1);
        }
    }

    let creation_time = start.elapsed();
    println!(
        "✓ Created 10,000 connections in {:?} ({:.2} connections/sec)",
        creation_time,
        10000.0 / creation_time.as_secs_f64()
    );

    assert_eq!(hub.connection_count().await, 10000);

    // Cleanup
    let start = std::time::Instant::now();
    for (i, connection_id) in connection_ids.into_iter().enumerate() {
        hub.remove_connection(connection_id).await;

        if (i + 1) % 1000 == 0 {
            println!("Cleaned up {} connections", i + 1);
        }
    }

    let cleanup_time = start.elapsed();
    println!("✓ Cleaned up 10,000 connections in {:?}", cleanup_time);

    assert_eq!(hub.connection_count().await, 0);
}

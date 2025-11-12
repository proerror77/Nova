//! Integration tests for cache invalidation library
//!
//! These tests require a running Redis instance.
//! Run with: cargo test --test integration_test -- --ignored

use cache_invalidation::{
    build_cache_key, parse_cache_key, EntityType, InvalidationAction, InvalidationMessage,
    InvalidationPublisher, InvalidationSubscriber,
};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

const REDIS_URL: &str = "redis://127.0.0.1:6379";

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_publish_and_receive_delete_message() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let received_messages = Arc::new(Mutex::new(Vec::new()));
    let messages_clone = Arc::clone(&received_messages);

    let handle = subscriber
        .subscribe(move |msg| {
            let messages = Arc::clone(&messages_clone);
            async move {
                messages.lock().await.push(msg);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    // Give subscriber time to connect
    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish message
    let subscriber_count = publisher
        .invalidate_user("test_user_123")
        .await
        .expect("Failed to publish");
    assert!(subscriber_count > 0, "No subscribers received the message");

    // Wait for message to be received
    tokio::time::sleep(Duration::from_millis(200)).await;

    // Verify message received
    let messages = received_messages.lock().await;
    assert_eq!(messages.len(), 1);

    let msg = &messages[0];
    assert_eq!(msg.entity_type, EntityType::User);
    assert_eq!(msg.entity_id, Some("test_user_123".to_string()));
    assert_eq!(msg.action, InvalidationAction::Delete);
    assert_eq!(msg.source_service, "test-service");

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_publish_pattern_invalidation() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let received_messages = Arc::new(Mutex::new(Vec::new()));
    let messages_clone = Arc::clone(&received_messages);

    let handle = subscriber
        .subscribe(move |msg| {
            let messages = Arc::clone(&messages_clone);
            async move {
                messages.lock().await.push(msg);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish pattern invalidation
    publisher
        .invalidate_pattern("user:*")
        .await
        .expect("Failed to publish pattern");

    tokio::time::sleep(Duration::from_millis(200)).await;

    let messages = received_messages.lock().await;
    assert_eq!(messages.len(), 1);

    let msg = &messages[0];
    assert_eq!(msg.pattern, Some("user:*".to_string()));
    assert_eq!(msg.action, InvalidationAction::Pattern);

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_publish_batch_invalidation() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let received_messages = Arc::new(Mutex::new(Vec::new()));
    let messages_clone = Arc::clone(&received_messages);

    let handle = subscriber
        .subscribe(move |msg| {
            let messages = Arc::clone(&messages_clone);
            async move {
                messages.lock().await.push(msg);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish batch invalidation
    let cache_keys = vec![
        "user:1".to_string(),
        "user:2".to_string(),
        "user:3".to_string(),
    ];
    publisher
        .invalidate_batch(cache_keys.clone())
        .await
        .expect("Failed to publish batch");

    tokio::time::sleep(Duration::from_millis(200)).await;

    let messages = received_messages.lock().await;
    assert_eq!(messages.len(), 1);

    let msg = &messages[0];
    assert_eq!(msg.entity_ids, Some(cache_keys));
    assert_eq!(msg.action, InvalidationAction::Batch);

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_multiple_entity_types() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let received_messages = Arc::new(Mutex::new(Vec::new()));
    let messages_clone = Arc::clone(&received_messages);

    let handle = subscriber
        .subscribe(move |msg| {
            let messages = Arc::clone(&messages_clone);
            async move {
                messages.lock().await.push(msg);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish different entity types
    publisher.invalidate_user("user_1").await.unwrap();
    publisher.invalidate_post("post_1").await.unwrap();
    publisher.invalidate_comment("comment_1").await.unwrap();
    publisher.invalidate_notification("notif_1").await.unwrap();

    tokio::time::sleep(Duration::from_millis(300)).await;

    let messages = received_messages.lock().await;
    assert_eq!(messages.len(), 4);

    // Verify all entity types received
    let entity_types: Vec<EntityType> = messages.iter().map(|m| m.entity_type.clone()).collect();
    assert!(entity_types.contains(&EntityType::User));
    assert!(entity_types.contains(&EntityType::Post));
    assert!(entity_types.contains(&EntityType::Comment));
    assert!(entity_types.contains(&EntityType::Notification));

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_message_ordering() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let received_messages = Arc::new(Mutex::new(Vec::new()));
    let messages_clone = Arc::clone(&received_messages);

    let handle = subscriber
        .subscribe(move |msg| {
            let messages = Arc::clone(&messages_clone);
            async move {
                messages.lock().await.push(msg);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish messages in sequence
    for i in 1..=10 {
        publisher
            .invalidate_user(&format!("user_{}", i))
            .await
            .unwrap();
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    tokio::time::sleep(Duration::from_millis(200)).await;

    let messages = received_messages.lock().await;
    assert_eq!(messages.len(), 10);

    // Verify message ordering (should be in sequence)
    let timestamps: Vec<_> = messages.iter().map(|m| m.timestamp).collect();
    for i in 1..timestamps.len() {
        assert!(timestamps[i] >= timestamps[i - 1], "Messages not in order");
    }

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_concurrent_publishers() {
    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let received_messages = Arc::new(Mutex::new(Vec::new()));
    let messages_clone = Arc::clone(&received_messages);

    let handle = subscriber
        .subscribe(move |msg| {
            let messages = Arc::clone(&messages_clone);
            async move {
                messages.lock().await.push(msg);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Spawn multiple concurrent publishers
    let mut handles = Vec::new();
    for i in 1..=5 {
        let h = tokio::spawn(async move {
            let publisher = InvalidationPublisher::new(REDIS_URL, format!("service_{}", i))
                .await
                .expect("Failed to create publisher");

            for j in 1..=5 {
                publisher
                    .invalidate_user(&format!("user_{}_{}", i, j))
                    .await
                    .unwrap();
            }
        });
        handles.push(h);
    }

    // Wait for all publishers to complete
    for h in handles {
        h.await.unwrap();
    }

    tokio::time::sleep(Duration::from_millis(300)).await;

    let messages = received_messages.lock().await;
    assert_eq!(messages.len(), 25); // 5 publishers * 5 messages each

    // Verify all messages from different services
    let services: std::collections::HashSet<_> =
        messages.iter().map(|m| &m.source_service).collect();
    assert_eq!(services.len(), 5);

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_error_handling_invalid_callback() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let error_count = Arc::new(Mutex::new(0));
    let error_count_clone = Arc::clone(&error_count);

    let handle = subscriber
        .subscribe(move |_msg| {
            let error_count = Arc::clone(&error_count_clone);
            async move {
                *error_count.lock().await += 1;
                // Simulate callback error
                Err(cache_invalidation::InvalidationError::CallbackFailed(
                    "Test error".to_string(),
                ))
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish message that will trigger error
    publisher.invalidate_user("test_user").await.unwrap();

    tokio::time::sleep(Duration::from_millis(200)).await;

    // Verify callback was called despite error
    let errors = error_count.lock().await;
    assert_eq!(*errors, 1);

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_custom_entity_type() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let received_messages = Arc::new(Mutex::new(Vec::new()));
    let messages_clone = Arc::clone(&received_messages);

    let handle = subscriber
        .subscribe(move |msg| {
            let messages = Arc::clone(&messages_clone);
            async move {
                messages.lock().await.push(msg);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish custom entity type
    publisher
        .invalidate_custom("custom_type", "custom_id_123")
        .await
        .unwrap();

    tokio::time::sleep(Duration::from_millis(200)).await;

    let messages = received_messages.lock().await;
    assert_eq!(messages.len(), 1);

    let msg = &messages[0];
    assert_eq!(
        msg.entity_type,
        EntityType::Custom("custom_type".to_string())
    );
    assert_eq!(msg.entity_id, Some("custom_id_123".to_string()));

    handle.abort();
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_helper_functions() {
    // Test build_cache_key
    let key = build_cache_key(&EntityType::User, "123");
    assert_eq!(key, "user:123");

    // Test parse_cache_key
    let (entity_type, entity_id) = parse_cache_key(&key).unwrap();
    assert_eq!(entity_type, EntityType::User);
    assert_eq!(entity_id, "123");

    // Test with custom entity
    let key = build_cache_key(&EntityType::Custom("session".into()), "abc123");
    assert_eq!(key, "session:abc123");

    let (entity_type, entity_id) = parse_cache_key(&key).unwrap();
    assert_eq!(entity_type, EntityType::Custom("session".into()));
    assert_eq!(entity_id, "abc123");
}

#[tokio::test]
#[ignore] // Requires Redis server
async fn test_performance_latency() {
    let publisher = InvalidationPublisher::new(REDIS_URL, "test-service".to_string())
        .await
        .expect("Failed to create publisher");

    let subscriber = InvalidationSubscriber::new(REDIS_URL)
        .await
        .expect("Failed to create subscriber");

    let latencies = Arc::new(Mutex::new(Vec::new()));
    let latencies_clone = Arc::clone(&latencies);

    let handle = subscriber
        .subscribe(move |msg| {
            let latencies = Arc::clone(&latencies_clone);
            async move {
                let received_at = chrono::Utc::now();
                let latency = (received_at - msg.timestamp).num_milliseconds() as f64;
                latencies.lock().await.push(latency);
                Ok(())
            }
        })
        .await
        .expect("Failed to subscribe");

    tokio::time::sleep(Duration::from_millis(100)).await;

    // Publish 100 messages and measure latency
    for i in 0..100 {
        publisher
            .invalidate_user(&format!("user_{}", i))
            .await
            .unwrap();
    }

    tokio::time::sleep(Duration::from_millis(500)).await;

    let latencies = latencies.lock().await;
    assert_eq!(latencies.len(), 100);

    // Calculate average latency
    let avg_latency: f64 = latencies.iter().sum::<f64>() / latencies.len() as f64;
    println!("Average latency: {:.2}ms", avg_latency);

    // Latency should be very low (< 10ms typical)
    assert!(
        avg_latency < 100.0,
        "Average latency too high: {}ms",
        avg_latency
    );

    handle.abort();
}

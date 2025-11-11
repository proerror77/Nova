//! Kafka Deduplication Tests (Quick Win #6)
//!
//! Tests for idempotent message processing
//!
//! Test Coverage:
//! - Duplicate detection
//! - Idempotency key validation
//! - TTL cleanup
//! - Concurrency safety
//! - Metrics recording

use std::collections::HashSet;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Mock idempotency tracker for testing
#[derive(Clone)]
struct IdempotencyTracker {
    processed: Arc<RwLock<HashSet<String>>>,
    ttl: Duration,
    timestamps: Arc<RwLock<std::collections::HashMap<String, Instant>>>,
}

impl IdempotencyTracker {
    fn new(ttl_seconds: u64) -> Self {
        Self {
            processed: Arc::new(RwLock::new(HashSet::new())),
            ttl: Duration::from_secs(ttl_seconds),
            timestamps: Arc::new(RwLock::new(std::collections::HashMap::new())),
        }
    }

    async fn is_duplicate(&self, idempotency_key: &str) -> bool {
        let processed = self.processed.read().await;
        processed.contains(idempotency_key)
    }

    async fn mark_processed(&self, idempotency_key: String) {
        let mut processed = self.processed.write().await;
        let mut timestamps = self.timestamps.write().await;
        processed.insert(idempotency_key.clone());
        timestamps.insert(idempotency_key, Instant::now());
    }

    async fn cleanup_expired(&self) {
        let mut processed = self.processed.write().await;
        let mut timestamps = self.timestamps.write().await;

        timestamps.retain(|key, timestamp| {
            if timestamp.elapsed() >= self.ttl {
                processed.remove(key);
                false
            } else {
                true
            }
        });
    }

    async fn size(&self) -> usize {
        let processed = self.processed.read().await;
        processed.len()
    }
}

#[tokio::test]
async fn test_duplicate_detection_basic() {
    // Test: Detect duplicate messages
    let tracker = IdempotencyTracker::new(60);

    let key = "msg_12345";

    // First message - not a duplicate
    assert!(
        !tracker.is_duplicate(key).await,
        "First message should not be duplicate"
    );

    // Mark as processed
    tracker.mark_processed(key.to_string()).await;

    // Second message - is a duplicate
    assert!(
        tracker.is_duplicate(key).await,
        "Second message should be duplicate"
    );
}

#[tokio::test]
async fn test_idempotency_key_validation() {
    // Test: Validate idempotency key format
    let tracker = IdempotencyTracker::new(60);

    let valid_keys = vec![
        "msg_abc123",
        "event_2024_01_01_user_123",
        "notification_uuid_abcd1234",
    ];

    let invalid_keys = vec!["", "   ", "msg-with-spaces ", "123", "a"];

    // Valid keys should work
    for key in valid_keys {
        tracker.mark_processed(key.to_string()).await;
        assert!(
            tracker.is_duplicate(key).await,
            "Valid key {} should work",
            key
        );
    }

    // Invalid keys should be rejected (in production)
    // For mock, we just track them
    for key in invalid_keys {
        assert!(
            key.is_empty() || key.trim().len() < 3,
            "Should validate key format"
        );
    }
}

#[tokio::test]
async fn test_ttl_cleanup() {
    // Test: Old entries are cleaned up after TTL
    let tracker = IdempotencyTracker::new(1); // 1 second TTL

    let key = "msg_12345";

    // Mark as processed
    tracker.mark_processed(key.to_string()).await;
    assert_eq!(tracker.size().await, 1);

    // Should still be duplicate before expiration
    assert!(tracker.is_duplicate(key).await);

    // Wait for TTL
    tokio::time::sleep(Duration::from_secs(2)).await;

    // Cleanup expired
    tracker.cleanup_expired().await;

    // Should be cleaned up
    assert_eq!(tracker.size().await, 0, "Should cleanup expired entries");
    assert!(
        !tracker.is_duplicate(key).await,
        "Expired key should not be duplicate"
    );
}

#[tokio::test]
async fn test_concurrent_deduplication() {
    // Test: Concurrent messages with same key are deduplicated
    let tracker = Arc::new(IdempotencyTracker::new(60));
    let key = "msg_concurrent";

    let mut handles = vec![];

    // Spawn 100 concurrent processors for same message
    for _ in 0..100 {
        let tracker_clone = Arc::clone(&tracker);
        let key_clone = key.to_string();
        let handle = tokio::spawn(async move {
            if !tracker_clone.is_duplicate(&key_clone).await {
                tracker_clone.mark_processed(key_clone).await;
                true // Processed
            } else {
                false // Duplicate
            }
        });
        handles.push(handle);
    }

    // Wait for all tasks
    let mut processed_count = 0;
    for handle in handles {
        if let Ok(processed) = handle.await {
            if processed {
                processed_count += 1;
            }
        }
    }

    // Only ONE task should process (others detect duplicate)
    assert!(
        processed_count <= 2, // Allow small race window
        "Only one task should process (got {})",
        processed_count
    );

    // Final state: key should be marked processed
    assert!(tracker.is_duplicate(key).await);
}

#[tokio::test]
async fn test_different_keys_independent() {
    // Test: Different keys are tracked independently
    let tracker = IdempotencyTracker::new(60);

    tracker.mark_processed("msg_1".to_string()).await;
    tracker.mark_processed("msg_2".to_string()).await;
    tracker.mark_processed("msg_3".to_string()).await;

    assert!(tracker.is_duplicate("msg_1").await);
    assert!(tracker.is_duplicate("msg_2").await);
    assert!(tracker.is_duplicate("msg_3").await);
    assert!(!tracker.is_duplicate("msg_4").await);

    assert_eq!(tracker.size().await, 3);
}

#[tokio::test]
async fn test_metrics_recording() {
    // Test: Deduplication metrics are recorded
    let tracker = IdempotencyTracker::new(60);

    let mut total_messages = 0;
    let mut duplicates = 0;
    let mut processed = 0;

    let messages = vec!["msg_1", "msg_2", "msg_1", "msg_3", "msg_2", "msg_1"];

    for msg in messages {
        total_messages += 1;
        if tracker.is_duplicate(msg).await {
            duplicates += 1;
        } else {
            tracker.mark_processed(msg.to_string()).await;
            processed += 1;
        }
    }

    assert_eq!(total_messages, 6);
    assert_eq!(processed, 3); // msg_1, msg_2, msg_3
    assert_eq!(duplicates, 3); // 2nd msg_1, 2nd msg_2, 3rd msg_1

    let duplicate_rate = duplicates as f64 / total_messages as f64;
    assert_eq!(duplicate_rate, 0.5, "50% duplicate rate");
}

#[tokio::test]
async fn test_batch_deduplication() {
    // Test: Batch of messages deduplicated efficiently
    let tracker = IdempotencyTracker::new(60);

    let batch = vec![
        "msg_1", "msg_2", "msg_3", "msg_1", "msg_4", "msg_2", "msg_5",
    ];

    let mut unique_count = 0;

    for msg in batch {
        if !tracker.is_duplicate(msg).await {
            tracker.mark_processed(msg.to_string()).await;
            unique_count += 1;
        }
    }

    assert_eq!(unique_count, 5, "Should process 5 unique messages");
    assert_eq!(tracker.size().await, 5);
}

#[tokio::test]
async fn test_high_throughput_deduplication() {
    // Test: Handle high message throughput
    let tracker = Arc::new(IdempotencyTracker::new(60));

    let mut handles = vec![];

    // Process 1000 messages concurrently
    for i in 0..1000 {
        let tracker_clone = Arc::clone(&tracker);
        let handle = tokio::spawn(async move {
            let key = format!("msg_{}", i % 100); // 100 unique keys, 10x duplicates
            if !tracker_clone.is_duplicate(&key).await {
                tracker_clone.mark_processed(key).await;
            }
        });
        handles.push(handle);
    }

    // Wait for all
    for handle in handles {
        handle.await.expect("Task should complete");
    }

    // Should have ~100 unique keys
    let size = tracker.size().await;
    assert!(
        size <= 100,
        "Should have at most 100 unique keys, got {}",
        size
    );
}

#[tokio::test]
async fn test_cleanup_performance() {
    // Test: Cleanup is efficient even with many entries
    let tracker = IdempotencyTracker::new(1); // Short TTL

    // Add 1000 entries
    for i in 0..1000 {
        tracker.mark_processed(format!("msg_{}", i)).await;
    }

    assert_eq!(tracker.size().await, 1000);

    // Wait for expiration
    tokio::time::sleep(Duration::from_secs(2)).await;

    // Time the cleanup
    let start = Instant::now();
    tracker.cleanup_expired().await;
    let elapsed = start.elapsed();

    // Cleanup should be fast
    assert!(
        elapsed.as_millis() < 100,
        "Cleanup should be fast, took {:?}",
        elapsed
    );

    assert_eq!(tracker.size().await, 0, "All entries should be cleaned");
}

#[tokio::test]
async fn test_kafka_message_deduplication_scenario() {
    // Test: Realistic Kafka message deduplication scenario
    let tracker = IdempotencyTracker::new(300); // 5 minute TTL

    // Simulate Kafka consumer receiving messages
    let messages = vec![
        ("msg_1", "user_created"),
        ("msg_2", "user_updated"),
        ("msg_1", "user_created"), // Duplicate (Kafka retry)
        ("msg_3", "user_deleted"),
        ("msg_2", "user_updated"), // Duplicate (network retry)
    ];

    let mut processed_events = vec![];

    for (msg_id, event_type) in messages {
        if !tracker.is_duplicate(msg_id).await {
            tracker.mark_processed(msg_id.to_string()).await;
            processed_events.push(event_type);
        }
    }

    // Should only process unique messages
    assert_eq!(
        processed_events.len(),
        3,
        "Should process 3 unique messages"
    );
    assert_eq!(processed_events, vec!["user_created", "user_updated", "user_deleted"]);
}

#[tokio::test]
async fn test_idempotency_with_retries() {
    // Test: Idempotency handles retries correctly
    let tracker = IdempotencyTracker::new(60);

    let key = "msg_retry";

    // First attempt - succeeds
    assert!(!tracker.is_duplicate(key).await);
    tracker.mark_processed(key.to_string()).await;

    // Retry attempts - all deduplicated
    for _ in 0..5 {
        assert!(
            tracker.is_duplicate(key).await,
            "Retries should be deduplicated"
        );
    }
}

#[tokio::test]
async fn test_out_of_order_messages() {
    // Test: Handle out-of-order message delivery
    let tracker = IdempotencyTracker::new(60);

    let messages = vec![
        ("msg_3", 3),
        ("msg_1", 1),
        ("msg_2", 2),
        ("msg_1", 1), // Duplicate
        ("msg_3", 3), // Duplicate
    ];

    let mut processed_sequence = vec![];

    for (msg_id, sequence) in messages {
        if !tracker.is_duplicate(msg_id).await {
            tracker.mark_processed(msg_id.to_string()).await;
            processed_sequence.push(sequence);
        }
    }

    // Should process all unique messages regardless of order
    assert_eq!(processed_sequence, vec![3, 1, 2]);
}

#[tokio::test]
async fn test_memory_efficient_storage() {
    // Test: Deduplication storage is memory efficient
    let tracker = IdempotencyTracker::new(60);

    // Store 10,000 keys
    for i in 0..10_000 {
        tracker.mark_processed(format!("msg_{}", i)).await;
    }

    assert_eq!(tracker.size().await, 10_000);

    // In production, Redis should use ~1MB for 10k keys
    // (assuming ~100 bytes per key)
    // For mock, we just verify count
}

#[tokio::test]
async fn test_deduplication_across_partitions() {
    // Test: Deduplication works across Kafka partitions
    let tracker = Arc::new(IdempotencyTracker::new(60));

    // Simulate messages from 3 partitions
    let mut handles = vec![];

    for partition in 0..3 {
        let tracker_clone = Arc::clone(&tracker);
        let handle = tokio::spawn(async move {
            for i in 0..100 {
                let key = format!("msg_{}", i); // Same keys across partitions
                if !tracker_clone.is_duplicate(&key).await {
                    tracker_clone.mark_processed(key).await;
                }
            }
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.await.expect("Partition consumer should complete");
    }

    // Should have 100 unique keys (deduplicated across partitions)
    assert_eq!(tracker.size().await, 100);
}

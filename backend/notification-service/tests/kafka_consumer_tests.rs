/// Unit tests for Kafka consumer functionality
///
/// This test module covers:
/// - Notification batch operations
/// - Message validation
/// - Event type conversion
/// - Retry policy logic

use notification_service::services::kafka_consumer::*;
use uuid::Uuid;
use chrono::Utc;
use std::time::Duration;

#[test]
fn test_notification_batch_creation() {
    let batch = NotificationBatch::new();
    assert!(batch.is_empty());
    assert_eq!(batch.len(), 0);
    assert!(!batch.batch_id.is_empty());
}

#[test]
fn test_notification_batch_add_single() {
    let mut batch = NotificationBatch::new();
    let notification = KafkaNotification {
        id: "test-1".to_string(),
        user_id: Uuid::new_v4(),
        event_type: NotificationEventType::Like,
        title: "New Like".to_string(),
        body: "Someone liked your post".to_string(),
        data: None,
        timestamp: Utc::now().timestamp(),
    };

    batch.add(notification);
    assert_eq!(batch.len(), 1);
    assert!(!batch.is_empty());
}

#[test]
fn test_notification_batch_add_multiple() {
    let mut batch = NotificationBatch::new();
    for i in 0..50 {
        let notification = KafkaNotification {
            id: format!("test-{}", i),
            user_id: Uuid::new_v4(),
            event_type: NotificationEventType::Comment,
            title: format!("Comment {}", i),
            body: format!("User commented on your post {}", i),
            data: None,
            timestamp: Utc::now().timestamp(),
        };
        batch.add(notification);
    }

    assert_eq!(batch.len(), 50);
    assert!(!batch.is_empty());
}

#[test]
fn test_notification_batch_clear() {
    let mut batch = NotificationBatch::new();
    for i in 0..10 {
        let notification = KafkaNotification {
            id: format!("test-{}", i),
            user_id: Uuid::new_v4(),
            event_type: NotificationEventType::Follow,
            title: "New Follower".to_string(),
            body: "Someone started following you".to_string(),
            data: None,
            timestamp: Utc::now().timestamp(),
        };
        batch.add(notification);
    }

    assert_eq!(batch.len(), 10);
    batch.clear();
    assert_eq!(batch.len(), 0);
    assert!(batch.is_empty());
}

#[test]
fn test_batch_should_flush_by_size() {
    let mut batch = NotificationBatch::new();

    // Add 99 notifications
    for i in 0..99 {
        batch.add(KafkaNotification {
            id: format!("test-{}", i),
            user_id: Uuid::new_v4(),
            event_type: NotificationEventType::Like,
            title: "Test".to_string(),
            body: "Test notification".to_string(),
            data: None,
            timestamp: Utc::now().timestamp(),
        });
    }

    // Should not flush at 99 with max_size=100
    assert!(!batch.should_flush_by_size(100));

    // Add one more to reach 100
    batch.add(KafkaNotification {
        id: "test-100".to_string(),
        user_id: Uuid::new_v4(),
        event_type: NotificationEventType::Like,
        title: "Test".to_string(),
        body: "Test notification".to_string(),
        data: None,
        timestamp: Utc::now().timestamp(),
    });

    // Should flush at 100 with max_size=100
    assert!(batch.should_flush_by_size(100));
    // Should also flush with smaller max_size
    assert!(batch.should_flush_by_size(50));
}

#[test]
fn test_batch_should_flush_by_time() {
    let mut batch = NotificationBatch::new();
    batch.add(KafkaNotification {
        id: "test-1".to_string(),
        user_id: Uuid::new_v4(),
        event_type: NotificationEventType::Message,
        title: "Test Message".to_string(),
        body: "Test message body".to_string(),
        data: None,
        timestamp: Utc::now().timestamp(),
    });

    // Should not flush with fresh batch
    assert!(!batch.should_flush_by_time(Duration::from_secs(10)));

    // Simulate time passage by checking behavior
    // (Note: In real tests with time mocking, we would test with actual elapsed time)
    assert!(!batch.should_flush_by_time(Duration::from_secs(5)));
}

#[test]
fn test_retry_policy_default() {
    let policy = RetryPolicy::default();
    assert_eq!(policy.max_retries, 3);
    assert_eq!(policy.backoff_ms, 100);
    assert_eq!(policy.max_backoff_ms, 5000);
}

#[test]
fn test_retry_policy_exponential_backoff() {
    let policy = RetryPolicy::default();

    let backoff0 = policy.get_backoff(0);
    let backoff1 = policy.get_backoff(1);
    let backoff2 = policy.get_backoff(2);

    // Verify exponential backoff: 100ms * 2^n
    assert_eq!(backoff0.as_millis(), 100); // 100 * 2^0 = 100
    assert_eq!(backoff1.as_millis(), 200); // 100 * 2^1 = 200
    assert_eq!(backoff2.as_millis(), 400); // 100 * 2^2 = 400

    // Verify increasing progression
    assert!(backoff0 < backoff1);
    assert!(backoff1 < backoff2);
}

#[test]
fn test_retry_policy_max_backoff_cap() {
    let policy = RetryPolicy {
        max_retries: 10,
        backoff_ms: 100,
        max_backoff_ms: 500,
    };

    // At high retry counts, backoff should be capped at max_backoff_ms
    let backoff_high = policy.get_backoff(10);
    assert!(backoff_high.as_millis() <= 500);
}

#[test]
fn test_retry_policy_should_retry() {
    let policy = RetryPolicy::default();

    assert!(policy.should_retry(0));
    assert!(policy.should_retry(1));
    assert!(policy.should_retry(2));
    assert!(!policy.should_retry(3)); // max_retries = 3, so 3 should fail
    assert!(!policy.should_retry(4));
}

#[test]
fn test_kafka_notification_event_type_conversion() {
    // Test all event types
    let event_types = vec![
        (NotificationEventType::Like, "like"),
        (NotificationEventType::Comment, "comment"),
        (NotificationEventType::Follow, "follow"),
        (NotificationEventType::LiveStart, "live_start"),
        (NotificationEventType::Message, "message"),
        (NotificationEventType::MentionPost, "mention_post"),
        (NotificationEventType::MentionComment, "mention_comment"),
    ];

    for (event_type, expected_str) in event_types {
        assert_eq!(event_type.to_string(), expected_str);
    }
}

#[test]
fn test_kafka_consumer_creation() {
    let consumer = KafkaNotificationConsumer::new(
        "localhost:9092".to_string(),
        "notifications".to_string(),
    );

    assert_eq!(consumer.broker, "localhost:9092");
    assert_eq!(consumer.topic, "notifications");
    assert_eq!(consumer.batch_size, 100);
    assert_eq!(consumer.flush_interval_ms, 5000);
}

#[test]
fn test_kafka_consumer_configuration() {
    let consumer = KafkaNotificationConsumer::new(
        "kafka-broker:9092".to_string(),
        "user-events".to_string(),
    );

    assert_eq!(consumer.group_id, "notifications-consumer");
    assert_eq!(consumer.batch_size, 100);
    assert_eq!(consumer.flush_interval_ms, 5000);

    // Verify retry policy is initialized with defaults
    assert_eq!(consumer.retry_policy.max_retries, 3);
    assert_eq!(consumer.retry_policy.backoff_ms, 100);
}

#[test]
fn test_kafka_notification_creation_with_data() {
    let user_id = Uuid::new_v4();
    let sender_id = Uuid::new_v4();
    let object_id = Uuid::new_v4();

    let metadata = serde_json::json!({
        "sender_id": sender_id.to_string(),
        "object_id": object_id.to_string(),
        "image_url": "https://example.com/image.jpg",
        "object_type": "post"
    });

    let notification = KafkaNotification {
        id: "notification-123".to_string(),
        user_id,
        event_type: NotificationEventType::Like,
        title: "New Like".to_string(),
        body: "User liked your post".to_string(),
        data: Some(metadata),
        timestamp: Utc::now().timestamp(),
    };

    assert_eq!(notification.user_id, user_id);
    assert_eq!(notification.event_type, NotificationEventType::Like);
    assert!(notification.data.is_some());
}

#[test]
fn test_batch_add_with_mixed_event_types() {
    let mut batch = NotificationBatch::new();

    let event_types = vec![
        NotificationEventType::Like,
        NotificationEventType::Comment,
        NotificationEventType::Follow,
        NotificationEventType::Message,
    ];

    for (i, event_type) in event_types.iter().enumerate() {
        batch.add(KafkaNotification {
            id: format!("notification-{}", i),
            user_id: Uuid::new_v4(),
            event_type: event_type.clone(),
            title: format!("Event {}", i),
            body: format!("Event body {}", i),
            data: None,
            timestamp: Utc::now().timestamp(),
        });
    }

    assert_eq!(batch.len(), 4);
    assert_eq!(batch.notifications[0].event_type, NotificationEventType::Like);
    assert_eq!(batch.notifications[1].event_type, NotificationEventType::Comment);
    assert_eq!(batch.notifications[2].event_type, NotificationEventType::Follow);
    assert_eq!(batch.notifications[3].event_type, NotificationEventType::Message);
}

#[test]
fn test_notification_batch_immutability_of_created_at() {
    let batch = NotificationBatch::new();
    let created_at_1 = batch.created_at;

    // Small delay
    std::thread::sleep(Duration::from_millis(10));

    // created_at should remain the same for the same batch instance
    assert_eq!(batch.created_at, created_at_1);
}

#[test]
fn test_retry_policy_custom() {
    let policy = RetryPolicy {
        max_retries: 5,
        backoff_ms: 200,
        max_backoff_ms: 10000,
    };

    assert_eq!(policy.max_retries, 5);
    assert_eq!(policy.backoff_ms, 200);

    // Custom backoff calculation
    let backoff0 = policy.get_backoff(0);
    let backoff1 = policy.get_backoff(1);

    assert_eq!(backoff0.as_millis(), 200); // 200 * 2^0
    assert_eq!(backoff1.as_millis(), 400); // 200 * 2^1
}

#[tokio::test]
async fn test_batch_flush_empty() {
    let batch = NotificationBatch::new();
    let result = batch.flush().await;

    assert!(result.is_ok());
    assert_eq!(result.unwrap(), 0);
}

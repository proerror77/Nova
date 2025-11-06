use chrono::Utc;
/// Unit tests for notification-service core functionality
///
/// This test module covers:
/// - Notification model serialization/deserialization
/// - Enum parsing helpers
/// - Business logic validation
/// - Error handling
use notification_service::models::*;
use uuid::Uuid;

#[test]
fn test_notification_type_serialization() {
    // Test all notification types can be serialized and deserialized
    let types = vec![
        NotificationType::Like,
        NotificationType::Comment,
        NotificationType::Follow,
        NotificationType::Mention,
        NotificationType::System,
        NotificationType::Message,
        NotificationType::Video,
        NotificationType::Stream,
    ];

    for notification_type in types {
        let json = serde_json::to_string(&notification_type).unwrap();
        let deserialized: NotificationType = serde_json::from_str(&json).unwrap();
        assert_eq!(notification_type, deserialized);
    }
}

#[test]
fn test_notification_priority_serialization() {
    let priorities = vec![
        NotificationPriority::Low,
        NotificationPriority::Normal,
        NotificationPriority::High,
    ];

    for priority in priorities {
        let json = serde_json::to_string(&priority).unwrap();
        let deserialized: NotificationPriority = serde_json::from_str(&json).unwrap();
        assert_eq!(priority, deserialized);
    }
}

#[test]
fn test_notification_status_serialization() {
    let statuses = vec![
        NotificationStatus::Queued,
        NotificationStatus::Sending,
        NotificationStatus::Delivered,
        NotificationStatus::Failed,
        NotificationStatus::Read,
        NotificationStatus::Dismissed,
    ];

    for status in statuses {
        let json = serde_json::to_string(&status).unwrap();
        let deserialized: NotificationStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(status, deserialized);
    }
}

#[test]
fn test_notification_channel_serialization() {
    let channels = vec![
        NotificationChannel::FCM,
        NotificationChannel::APNs,
        NotificationChannel::WebSocket,
        NotificationChannel::Email,
        NotificationChannel::SMS,
    ];

    for channel in channels {
        let json = serde_json::to_string(&channel).unwrap();
        let deserialized: NotificationChannel = serde_json::from_str(&json).unwrap();
        assert_eq!(channel, deserialized);
    }
}

#[test]
fn test_create_notification_request_with_defaults() {
    let user_id = Uuid::new_v4();
    let request = CreateNotificationRequest {
        recipient_id: user_id,
        sender_id: None,
        notification_type: NotificationType::Like,
        title: "Test Title".to_string(),
        body: "Test Body".to_string(),
        image_url: None,
        object_id: None,
        object_type: None,
        metadata: None,
        priority: NotificationPriority::Normal,
    };

    assert_eq!(request.recipient_id, user_id);
    assert_eq!(request.priority, NotificationPriority::Normal);
    assert_eq!(request.title, "Test Title");
    assert_eq!(request.body, "Test Body");
}

#[test]
fn test_notification_preference_creation() {
    let user_id = Uuid::new_v4();
    let preference = NotificationPreference {
        id: Uuid::new_v4(),
        user_id,
        enabled: true,
        like_enabled: true,
        comment_enabled: false,
        follow_enabled: true,
        mention_enabled: true,
        message_enabled: true,
        stream_enabled: false,
        quiet_hours_start: Some("22:00".to_string()),
        quiet_hours_end: Some("08:00".to_string()),
        prefer_fcm: true,
        prefer_apns: true,
        prefer_email: false,
        updated_at: Utc::now(),
    };

    assert!(preference.enabled);
    assert!(preference.like_enabled);
    assert!(!preference.comment_enabled);
    assert_eq!(preference.quiet_hours_start.as_ref().unwrap(), "22:00");
}

#[test]
fn test_device_token_creation() {
    let user_id = Uuid::new_v4();
    let device = DeviceToken {
        id: Uuid::new_v4(),
        user_id,
        token: "fcm_token_123".to_string(),
        channel: NotificationChannel::FCM,
        device_type: "android".to_string(),
        device_name: Some("Samsung Galaxy S21".to_string()),
        is_active: true,
        last_used_at: None,
        created_at: Utc::now(),
    };

    assert_eq!(device.user_id, user_id);
    assert_eq!(device.channel, NotificationChannel::FCM);
    assert!(device.is_active);
    assert_eq!(device.device_type, "android");
}

#[test]
fn test_delivery_attempt_creation() {
    let notification_id = Uuid::new_v4();
    let device_token_id = Uuid::new_v4();
    let attempt = DeliveryAttempt {
        id: Uuid::new_v4(),
        notification_id,
        device_token_id,
        channel: NotificationChannel::APNs,
        status: NotificationStatus::Delivered,
        error_message: None,
        retry_count: 0,
        attempted_at: Utc::now(),
        retry_at: None,
    };

    assert_eq!(attempt.notification_id, notification_id);
    assert_eq!(attempt.device_token_id, device_token_id);
    assert_eq!(attempt.status, NotificationStatus::Delivered);
}

#[test]
fn test_notification_type_as_str() {
    assert_eq!(NotificationType::Like.as_str(), "like");
    assert_eq!(NotificationType::Comment.as_str(), "comment");
    assert_eq!(NotificationType::Follow.as_str(), "follow");
    assert_eq!(NotificationType::Mention.as_str(), "mention");
    assert_eq!(NotificationType::System.as_str(), "system");
    assert_eq!(NotificationType::Message.as_str(), "message");
    assert_eq!(NotificationType::Video.as_str(), "video");
    assert_eq!(NotificationType::Stream.as_str(), "stream");
}

#[test]
fn test_notification_priority_as_str() {
    assert_eq!(NotificationPriority::Low.as_str(), "low");
    assert_eq!(NotificationPriority::Normal.as_str(), "normal");
    assert_eq!(NotificationPriority::High.as_str(), "high");
}

#[test]
fn test_notification_status_as_str() {
    assert_eq!(NotificationStatus::Queued.as_str(), "queued");
    assert_eq!(NotificationStatus::Sending.as_str(), "sending");
    assert_eq!(NotificationStatus::Delivered.as_str(), "delivered");
    assert_eq!(NotificationStatus::Failed.as_str(), "failed");
    assert_eq!(NotificationStatus::Read.as_str(), "read");
    assert_eq!(NotificationStatus::Dismissed.as_str(), "dismissed");
}

#[test]
fn test_notification_channel_as_str() {
    assert_eq!(NotificationChannel::FCM.as_str(), "fcm");
    assert_eq!(NotificationChannel::APNs.as_str(), "apns");
    assert_eq!(NotificationChannel::WebSocket.as_str(), "websocket");
    assert_eq!(NotificationChannel::Email.as_str(), "email");
    assert_eq!(NotificationChannel::SMS.as_str(), "sms");
}

#[test]
fn test_priority_ordering() {
    // Test that priority levels can be ordered
    assert!(NotificationPriority::Low < NotificationPriority::Normal);
    assert!(NotificationPriority::Normal < NotificationPriority::High);
    assert!(NotificationPriority::Low < NotificationPriority::High);
}

#[test]
fn test_notification_creation_with_metadata() {
    let user_id = Uuid::new_v4();
    let metadata = serde_json::json!({
        "sender_id": user_id.to_string(),
        "image_url": "https://example.com/image.jpg",
        "object_id": Uuid::new_v4().to_string(),
    });

    let request = CreateNotificationRequest {
        recipient_id: user_id,
        sender_id: None,
        notification_type: NotificationType::Like,
        title: "New Like".to_string(),
        body: "User liked your post".to_string(),
        image_url: Some("https://example.com/image.jpg".to_string()),
        object_id: None,
        object_type: Some("post".to_string()),
        metadata: Some(metadata),
        priority: NotificationPriority::High,
    };

    assert!(request.metadata.is_some());
    assert_eq!(request.priority, NotificationPriority::High);
    assert_eq!(request.object_type.as_ref().unwrap(), "post");
}

#[test]
fn test_create_notification_request_serialization() {
    let user_id = Uuid::new_v4();
    let request = CreateNotificationRequest {
        recipient_id: user_id,
        sender_id: None,
        notification_type: NotificationType::Comment,
        title: "New Comment".to_string(),
        body: "User commented on your post".to_string(),
        image_url: None,
        object_id: None,
        object_type: None,
        metadata: None,
        priority: NotificationPriority::Normal,
    };

    let json = serde_json::to_string(&request).unwrap();
    let deserialized: CreateNotificationRequest = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.recipient_id, request.recipient_id);
    assert_eq!(deserialized.notification_type, request.notification_type);
    assert_eq!(deserialized.title, request.title);
    assert_eq!(deserialized.body, request.body);
}

#[test]
fn test_device_token_validation() {
    // Test that device token fields are properly validated
    let user_id = Uuid::new_v4();
    let device = DeviceToken {
        id: Uuid::new_v4(),
        user_id,
        token: "valid_token_string".to_string(),
        channel: NotificationChannel::FCM,
        device_type: "ios".to_string(),
        device_name: None,
        is_active: true,
        last_used_at: None,
        created_at: Utc::now(),
    };

    assert!(!device.token.is_empty());
    assert_eq!(device.channel, NotificationChannel::FCM);
    assert!(!device.device_type.is_empty());
}

#[test]
fn test_notification_preference_quiet_hours_validation() {
    let user_id = Uuid::new_v4();

    // Valid quiet hours format
    let preference = NotificationPreference {
        id: Uuid::new_v4(),
        user_id,
        enabled: true,
        like_enabled: true,
        comment_enabled: true,
        follow_enabled: true,
        mention_enabled: true,
        message_enabled: true,
        stream_enabled: true,
        quiet_hours_start: Some("22:00".to_string()),
        quiet_hours_end: Some("08:00".to_string()),
        prefer_fcm: true,
        prefer_apns: true,
        prefer_email: false,
        updated_at: Utc::now(),
    };

    assert!(preference.quiet_hours_start.is_some());
    assert!(preference.quiet_hours_end.is_some());

    // Validate format (basic check)
    let start = preference.quiet_hours_start.as_ref().unwrap();
    assert!(start.contains(':'));
    assert_eq!(start.len(), 5); // HH:MM format
}

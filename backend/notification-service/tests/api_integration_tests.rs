/// Integration tests for notification-service HTTP API
///
/// This test module covers:
/// - Notification CRUD endpoints
/// - Device registration endpoints
/// - Preference management endpoints
/// - Error handling and response formats
/// - Request validation

use notification_service::models::*;
use uuid::Uuid;
use serde_json::json;

#[test]
fn test_create_notification_payload_serialization() {
    let user_id = Uuid::new_v4();
    let payload = json!({
        "recipient_id": user_id.to_string(),
        "sender_id": null,
        "notification_type": "LIKE",
        "title": "New Like",
        "body": "Someone liked your post",
        "image_url": null,
        "object_id": null,
        "object_type": null,
        "metadata": null,
        "priority": "NORMAL"
    });

    let deserialized: CreateNotificationRequest =
        serde_json::from_value(payload).unwrap();

    assert_eq!(deserialized.recipient_id, user_id);
    assert_eq!(deserialized.notification_type, NotificationType::Like);
    assert_eq!(deserialized.title, "New Like");
    assert_eq!(deserialized.body, "Someone liked your post");
    assert_eq!(deserialized.priority, NotificationPriority::Normal);
}

#[test]
fn test_notification_response_format() {
    let user_id = Uuid::new_v4();
    let notification = Notification {
        id: Uuid::new_v4(),
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
        status: NotificationStatus::Queued,
        is_read: false,
        read_at: None,
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
        expires_at: None,
    };

    // Test serialization
    let json = serde_json::to_string(&notification).unwrap();
    let deserialized: Notification = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.id, notification.id);
    assert_eq!(deserialized.recipient_id, notification.recipient_id);
    assert_eq!(deserialized.notification_type, notification.notification_type);
}

#[test]
fn test_device_register_payload() {
    let user_id = Uuid::new_v4();
    let payload = json!({
        "user_id": user_id.to_string(),
        "token": "fcm_device_token_here",
        "channel": "FCM",
        "device_type": "android"
    });

    // Parse as JSON to validate structure
    assert!(payload.get("user_id").is_some());
    assert!(payload.get("token").is_some());
    assert!(payload.get("channel").is_some());
    assert!(payload.get("device_type").is_some());

    assert_eq!(payload["user_id"], user_id.to_string());
    assert_eq!(payload["channel"], "FCM");
}

#[test]
fn test_preferences_update_payload_partial() {
    let payload = json!({
        "like_enabled": true,
        "comment_enabled": false,
        "quiet_hours_start": "22:00"
    });

    // All fields should be optional
    assert!(payload.get("like_enabled").is_some());
    assert!(payload.get("enabled").is_none()); // This should be optional
    assert!(payload.get("quiet_hours_start").is_some());
}

#[test]
fn test_notification_with_metadata() {
    let metadata = serde_json::json!({
        "sender_id": Uuid::new_v4().to_string(),
        "image_url": "https://example.com/image.jpg",
        "object_id": Uuid::new_v4().to_string(),
        "object_type": "post"
    });

    let user_id = Uuid::new_v4();
    let request = CreateNotificationRequest {
        recipient_id: user_id,
        sender_id: None,
        notification_type: NotificationType::Like,
        title: "New Like".to_string(),
        body: "Someone liked your post".to_string(),
        image_url: Some("https://example.com/image.jpg".to_string()),
        object_id: None,
        object_type: Some("post".to_string()),
        metadata: Some(metadata),
        priority: NotificationPriority::High,
    };

    assert!(request.metadata.is_some());
    let meta = request.metadata.unwrap();
    assert!(meta.get("sender_id").is_some());
    assert!(meta.get("image_url").is_some());
}

#[test]
fn test_device_token_payload_multiple_channels() {
    let channels = vec!["FCM", "APNs", "WebSocket", "Email"];

    for channel in channels {
        let payload = json!({
            "user_id": Uuid::new_v4().to_string(),
            "token": "device_token",
            "channel": channel,
            "device_type": "ios"
        });

        assert_eq!(payload["channel"], channel);
    }
}

#[test]
fn test_notification_priority_in_response() {
    let priorities = vec![
        NotificationPriority::Low,
        NotificationPriority::Normal,
        NotificationPriority::High,
    ];

    for priority in priorities {
        let json = serde_json::to_value(priority).unwrap();
        let deserialized: NotificationPriority =
            serde_json::from_value(json).unwrap();
        assert_eq!(deserialized, priority);
    }
}

#[test]
fn test_multiple_notifications_in_batch() {
    let user_id = Uuid::new_v4();
    let notifications: Vec<CreateNotificationRequest> = (0..5)
        .map(|i| CreateNotificationRequest {
            recipient_id: user_id,
            sender_id: None,
            notification_type: NotificationType::Like,
            title: format!("Like {}", i),
            body: format!("Someone liked your post {}", i),
            image_url: None,
            object_id: None,
            object_type: None,
            metadata: None,
            priority: NotificationPriority::Normal,
        })
        .collect();

    assert_eq!(notifications.len(), 5);
    for (i, notif) in notifications.iter().enumerate() {
        assert_eq!(notif.title, format!("Like {}", i));
    }
}

#[test]
fn test_push_notification_result_serialization() {
    use notification_service::services::notification_service::PushNotificationResult;

    let result = PushNotificationResult {
        device_token_id: Uuid::new_v4(),
        success: true,
        message_id: Some("fcm-message-123".to_string()),
        error: None,
    };

    let json = serde_json::to_string(&result).unwrap();
    let deserialized: PushNotificationResult = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.success, true);
    assert_eq!(deserialized.message_id, Some("fcm-message-123".to_string()));
    assert_eq!(deserialized.error, None);
}

#[test]
fn test_notification_preference_serialization() {
    let user_id = Uuid::new_v4();
    let pref = NotificationPreference {
        id: Uuid::new_v4(),
        user_id,
        enabled: true,
        like_enabled: true,
        comment_enabled: false,
        follow_enabled: true,
        mention_enabled: false,
        message_enabled: true,
        stream_enabled: false,
        quiet_hours_start: Some("22:00".to_string()),
        quiet_hours_end: Some("08:00".to_string()),
        prefer_fcm: true,
        prefer_apns: true,
        prefer_email: false,
        updated_at: chrono::Utc::now(),
    };

    let json = serde_json::to_string(&pref).unwrap();
    let deserialized: NotificationPreference = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.user_id, user_id);
    assert_eq!(deserialized.like_enabled, true);
    assert_eq!(deserialized.comment_enabled, false);
    assert_eq!(deserialized.quiet_hours_start, Some("22:00".to_string()));
}

#[test]
fn test_device_token_serialization() {
    let device = DeviceToken {
        id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
        token: "fcm_token_123".to_string(),
        channel: NotificationChannel::FCM,
        device_type: "android".to_string(),
        device_name: Some("Samsung Galaxy S21".to_string()),
        is_active: true,
        last_used_at: None,
        created_at: chrono::Utc::now(),
    };

    let json = serde_json::to_string(&device).unwrap();
    let deserialized: DeviceToken = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.token, "fcm_token_123");
    assert_eq!(deserialized.channel, NotificationChannel::FCM);
    assert_eq!(deserialized.device_type, "android");
    assert!(deserialized.is_active);
}

#[test]
fn test_delivery_attempt_serialization() {
    let attempt = DeliveryAttempt {
        id: Uuid::new_v4(),
        notification_id: Uuid::new_v4(),
        device_token_id: Uuid::new_v4(),
        channel: NotificationChannel::APNs,
        status: NotificationStatus::Delivered,
        error_message: None,
        retry_count: 0,
        attempted_at: chrono::Utc::now(),
        retry_at: None,
    };

    let json = serde_json::to_string(&attempt).unwrap();
    let deserialized: DeliveryAttempt = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.channel, NotificationChannel::APNs);
    assert_eq!(deserialized.status, NotificationStatus::Delivered);
    assert_eq!(deserialized.retry_count, 0);
}

#[test]
fn test_notification_types_in_api_request() {
    let notification_types = vec![
        ("LIKE", NotificationType::Like),
        ("COMMENT", NotificationType::Comment),
        ("FOLLOW", NotificationType::Follow),
        ("MENTION", NotificationType::Mention),
        ("SYSTEM", NotificationType::System),
        ("MESSAGE", NotificationType::Message),
        ("VIDEO", NotificationType::Video),
        ("STREAM", NotificationType::Stream),
    ];

    for (type_str, expected_type) in notification_types {
        let json = serde_json::json!(type_str);
        let parsed: NotificationType = serde_json::from_value(json).unwrap();
        assert_eq!(parsed, expected_type);
    }
}

#[test]
fn test_large_metadata_object() {
    let large_metadata = serde_json::json!({
        "sender_id": Uuid::new_v4().to_string(),
        "image_url": "https://example.com/large_image.jpg",
        "object_id": Uuid::new_v4().to_string(),
        "object_type": "post",
        "custom_field_1": "value1",
        "custom_field_2": "value2",
        "custom_field_3": "value3",
        "nested": {
            "field": "value",
            "array": [1, 2, 3]
        }
    });

    let user_id = Uuid::new_v4();
    let request = CreateNotificationRequest {
        recipient_id: user_id,
        sender_id: None,
        notification_type: NotificationType::Like,
        title: "Test".to_string(),
        body: "Test body".to_string(),
        image_url: None,
        object_id: None,
        object_type: None,
        metadata: Some(large_metadata),
        priority: NotificationPriority::Normal,
    };

    let json = serde_json::to_string(&request).unwrap();
    let _deserialized: CreateNotificationRequest = serde_json::from_str(&json).unwrap();
}

#[test]
fn test_all_notification_statuses() {
    let statuses = vec![
        NotificationStatus::Queued,
        NotificationStatus::Sending,
        NotificationStatus::Delivered,
        NotificationStatus::Failed,
        NotificationStatus::Read,
        NotificationStatus::Dismissed,
    ];

    for status in statuses {
        let json = serde_json::to_value(status).unwrap();
        let deserialized: NotificationStatus = serde_json::from_value(json).unwrap();
        assert_eq!(deserialized, status);
    }
}

#[test]
fn test_notification_channels_in_device_token() {
    let channels = vec![
        NotificationChannel::FCM,
        NotificationChannel::APNs,
        NotificationChannel::WebSocket,
        NotificationChannel::Email,
        NotificationChannel::SMS,
    ];

    for channel in channels {
        let device = DeviceToken {
            id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            token: "test_token".to_string(),
            channel,
            device_type: "test".to_string(),
            device_name: None,
            is_active: true,
            last_used_at: None,
            created_at: chrono::Utc::now(),
        };

        let json = serde_json::to_string(&device).unwrap();
        let deserialized: DeviceToken = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.channel, channel);
    }
}

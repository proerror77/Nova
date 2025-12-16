use chrono::Utc;
use event_schema::{priority, DomainEvent, OutboxEvent};
use uuid::Uuid;

fn main() {
    println!("=== Outbox Pattern Usage Examples ===\n");

    // Example 1: Create a MessageCreated event
    println!("1. Creating a MessageCreated event:");
    let message_id = Uuid::new_v4();
    let domain_event = DomainEvent::MessageCreated {
        message_id,
        conversation_id: Uuid::new_v4(),
        sender_id: Uuid::new_v4(),
        content: "Hello, World!".to_string(),
        message_type: "text".to_string(),
        created_at: Utc::now(),
    };

    let outbox_event = OutboxEvent::new(
        domain_event.aggregate_id(),
        domain_event.event_type(),
        &domain_event,
        domain_event.priority(),
    )
    .expect("Failed to create outbox event");

    println!("  Event ID: {}", outbox_event.id);
    println!("  Aggregate ID: {}", outbox_event.aggregate_id);
    println!("  Event Type: {}", outbox_event.event_type);
    println!("  Priority: {} (CRITICAL)", outbox_event.priority);
    println!("  Kafka Topic: {}", outbox_event.kafka_topic());
    println!("  Partition Key: {}", outbox_event.partition_key());
    println!();

    // Example 2: Create a PostCreated event
    println!("2. Creating a PostCreated event:");
    let post_id = Uuid::new_v4();
    let post_event = DomainEvent::PostCreated {
        post_id,
        user_id: Uuid::new_v4(),
        content: "Check out my new post!".to_string(),
        content_type: "text".to_string(),
        media_ids: vec![],
        created_at: Utc::now(),
    };

    let post_outbox = OutboxEvent::new(
        post_event.aggregate_id(),
        post_event.event_type(),
        &post_event,
        post_event.priority(),
    )
    .expect("Failed to create outbox event");

    println!("  Event ID: {}", post_outbox.id);
    println!("  Priority: {} (HIGH)", post_outbox.priority);
    println!("  Kafka Topic: {}", post_outbox.kafka_topic());
    println!("  Affects Feed: {}", post_event.affects_feed());
    println!(
        "  Requires Search Indexing: {}",
        post_event.requires_search_indexing()
    );
    println!();

    // Example 3: Generate Kafka message
    println!("3. Generating Kafka message:");
    let kafka_msg = outbox_event.to_kafka_message();
    println!("  Key: {}", kafka_msg.key);
    println!("  Value length: {} bytes", kafka_msg.value.len());
    println!("  Headers:");
    for (key, value) in &kafka_msg.headers {
        println!("    {}: {}", key, value);
    }
    println!();

    // Example 4: Priority-based routing
    println!("4. Priority-based event examples:");
    let events = vec![
        (
            "MessageCreated",
            DomainEvent::MessageCreated {
                message_id: Uuid::new_v4(),
                conversation_id: Uuid::new_v4(),
                sender_id: Uuid::new_v4(),
                content: "Urgent message".to_string(),
                message_type: "text".to_string(),
                created_at: Utc::now(),
            },
        ),
        (
            "PostUpdated",
            DomainEvent::PostUpdated {
                post_id: Uuid::new_v4(),
                user_id: Uuid::new_v4(),
                new_content: "Updated content".to_string(),
                updated_at: Utc::now(),
            },
        ),
        (
            "SearchIndexUpdated",
            DomainEvent::SearchIndexUpdated {
                index_id: Uuid::new_v4(),
                entity_id: Uuid::new_v4(),
                entity_type: "post".to_string(),
                operation: "update".to_string(),
                updated_at: Utc::now(),
            },
        ),
    ];

    for (name, event) in events {
        let priority_str = match event.priority() {
            p if p == priority::CRITICAL => "CRITICAL",
            p if p == priority::HIGH => "HIGH",
            p if p == priority::NORMAL => "NORMAL",
            p if p == priority::LOW => "LOW",
            _ => "UNKNOWN",
        };
        println!("  {} -> Priority: {}", name, priority_str);
    }
    println!();

    // Example 5: Event lifecycle
    println!("5. Event lifecycle simulation:");
    let mut lifecycle_event = OutboxEvent::new(
        Uuid::new_v4(),
        "TestEvent",
        &serde_json::json!({"test": "data"}),
        priority::NORMAL,
    )
    .expect("Failed to create event");

    println!("  Initial state:");
    println!("    Published: {}", lifecycle_event.published_at.is_some());
    println!("    Retry count: {}", lifecycle_event.retry_count);

    // Simulate failure
    lifecycle_event.mark_failed("Connection timeout");
    println!("  After first failure:");
    println!("    Retry count: {}", lifecycle_event.retry_count);
    println!("    Last error: {:?}", lifecycle_event.last_error);

    // Simulate success
    lifecycle_event.mark_published();
    println!("  After successful publish:");
    println!("    Published: {}", lifecycle_event.published_at.is_some());
    println!("    Should retry: {}", lifecycle_event.should_retry(5));

    println!("\n=== End of Examples ===");
}

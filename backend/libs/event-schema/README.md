# Event Schema Library

Transactional Outbox Pattern implementation for Nova microservices.

## Features

- **Outbox Pattern**: Ensures atomicity between database writes and event publishing
- **Domain Events**: Type-safe enumeration of all business events (15+ event types)
- **Priority System**: 4-level priority (CRITICAL/HIGH/NORMAL/LOW)
- **Kafka Integration**: Automatic topic routing and partition key generation
- **Retry Logic**: Exponential backoff with configurable max retries
- **Event Expiration**: Automatic cleanup of stale events

## Usage

### Creating Outbox Events

```rust
use event_schema::{DomainEvent, OutboxEvent, priority};
use uuid::Uuid;
use chrono::Utc;

// Create a domain event
let event = DomainEvent::MessageCreated {
    message_id: Uuid::new_v4(),
    conversation_id: Uuid::new_v4(),
    sender_id: Uuid::new_v4(),
    content: "Hello!".to_string(),
    message_type: "text".to_string(),
    created_at: Utc::now(),
};

// Wrap in outbox event
let outbox = OutboxEvent::new(
    event.aggregate_id(),
    event.event_type(),
    &event,
    event.priority(),
)?;

// Generate Kafka message
let kafka_msg = outbox.to_kafka_message();
println!("Topic: {}", outbox.kafka_topic());
println!("Key: {}", kafka_msg.key);
```

### Priority Levels

- `priority::CRITICAL (0)`: Real-time messages, notifications, stream starts
- `priority::HIGH (1)`: User actions (posts, reactions, follows)
- `priority::NORMAL (2)`: Updates and modifications
- `priority::LOW (3)`: Deletions and index updates

### Event Types

- **Messaging**: MessageCreated, MessageEdited, MessageDeleted
- **Content**: PostCreated, PostUpdated, PostDeleted, ReactionAdded/Removed
- **Social**: FollowAdded, FollowRemoved
- **Notifications**: NotificationCreated
- **Search**: SearchIndexUpdated
- **Streaming**: StreamStarted, StreamEnded, StreamMessagePosted

### Retry Logic

```rust
// Check if event should be retried
if outbox.should_retry(max_retries) {
    // Publish to Kafka
    match publish(&kafka_msg) {
        Ok(_) => outbox.mark_published(),
        Err(e) => outbox.mark_failed(e.to_string()),
    }
}

// Check expiration
if outbox.is_expired(24) {
    // Delete event after 24 hours
}
```

## Kafka Topics

Topics follow the pattern: `nova.<service>.<aggregate>.<action>`

Examples:
- `nova.messaging.message.created`
- `nova.content.post.created`
- `nova.auth.user.deleted`

## Testing

```bash
cargo test -p event-schema
cargo run --example outbox_usage -p event-schema
```

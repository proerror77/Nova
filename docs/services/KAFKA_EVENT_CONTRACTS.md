# Kafka Event Contracts - Nova Architecture Phase 0

**Version**: 1.0
**Date**: 2025-11-04
**Status**: Phase 0 Task 0.3 Deliverable

---

## 📋 Overview

This document defines all domain events that flow through the Nova system via Kafka. These events enable:
- **Eventual consistency** across services
- **Event-driven architecture** foundation for Phase 2
- **Notification triggers** for Phase 1
- **Outbox pattern** implementation

**Key Principle**: Each service publishes events for important domain changes. Other services subscribe to relevant events and update their caches/data accordingly.

---

## 🎯 Event Taxonomy

### Event Naming Convention

```
<aggregate_type>.<event_type>

Examples:
  - user.created
  - user.updated
  - post.published
  - message.sent
  - video.processing_complete
```

### Event Structure (Protobuf)

```protobuf
message DomainEvent {
  string id = 1;                      // UUID of event
  string event_type = 2;              // "user.created", "post.published", etc.
  string aggregate_id = 3;            // ID of affected entity (user_id, post_id, etc.)
  string aggregate_type = 4;          // "user", "post", "message", etc.
  int32 version = 5;                  // Event version for schema evolution
  string data = 6;                    // JSON event payload
  string metadata = 7;                // JSON metadata
  string correlation_id = 8;          // For tracing related events
  string causation_id = 9;            // ID of triggering event
  string created_at = 10;             // ISO 8601 timestamp
  string created_by = 11;             // User who triggered event
}
```

---

## 👤 Auth Service Events

Published by: **Auth Service**
Owned by: **Auth Service**

### user.created
**Trigger**: New user registration
**Data**:
```json
{
  "user_id": "uuid",
  "email": "user@example.com",
  "username": "username",
  "created_at": "2025-01-15T10:30:00Z",
  "source": "web|mobile|api"
}
```
**Subscribers**: Notification Service, Analytics

### user.updated
**Trigger**: User profile change
**Data**:
```json
{
  "user_id": "uuid",
  "changed_fields": ["email", "username"],
  "old_values": {"email": "old@example.com"},
  "new_values": {"email": "new@example.com"},
  "updated_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Search Service, Feed Service, Messaging Service

### user.deleted
**Trigger**: User account deletion
**Data**:
```json
{
  "user_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z",
  "reason": "user_requested|admin|suspension",
  "cleanup_required": ["posts", "messages", "followers"]
}
```
**Subscribers**: Content Service, Messaging Service, User Service (cleanup)

### user.verified
**Trigger**: Email verification complete
**Data**:
```json
{
  "user_id": "uuid",
  "verified_at": "2025-01-15T10:30:00Z",
  "verification_method": "email|phone|oauth"
}
```
**Subscribers**: Notification Service

### user.login
**Trigger**: Successful login
**Data**:
```json
{
  "user_id": "uuid",
  "login_at": "2025-01-15T10:30:00Z",
  "ip_address": "192.168.1.1",
  "user_agent": "Mozilla/5.0...",
  "device_id": "uuid",
  "location": {"city": "SF", "country": "US"}
}
```
**Subscribers**: Analytics, Security monitoring

### user.failed_login
**Trigger**: Failed login attempt
**Data**:
```json
{
  "user_id": "uuid",
  "failed_at": "2025-01-15T10:30:00Z",
  "attempt_count": 3,
  "ip_address": "192.168.1.1",
  "reason": "invalid_password|user_not_found|account_locked"
}
```
**Subscribers**: Security monitoring, Rate limiting

### user.password_changed
**Trigger**: User changes password
**Data**:
```json
{
  "user_id": "uuid",
  "changed_at": "2025-01-15T10:30:00Z",
  "method": "self_service|admin|password_reset"
}
```
**Subscribers**: Notification Service, Security

---

## 👥 User Service Events

Published by: **User Service**
Owned by: **User Service**

### user.followed
**Trigger**: User follows another user
**Data**:
```json
{
  "follower_id": "uuid",
  "followee_id": "uuid",
  "followed_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Feed Service, Notification Service

### user.unfollowed
**Trigger**: User unfollows
**Data**:
```json
{
  "follower_id": "uuid",
  "followee_id": "uuid",
  "unfollowed_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Feed Service, Notification Service

### user.blocked
**Trigger**: User blocks another
**Data**:
```json
{
  "blocker_id": "uuid",
  "blocked_id": "uuid",
  "blocked_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Messaging Service, Feed Service

### user.unblocked
**Trigger**: User unblocks
**Data**:
```json
{
  "blocker_id": "uuid",
  "blocked_id": "uuid",
  "unblocked_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Messaging Service, Feed Service

---

## 💬 Messaging Service Events

Published by: **Messaging Service**
Owned by: **Messaging Service**

### message.sent
**Trigger**: New message created
**Data**:
```json
{
  "message_id": "uuid",
  "conversation_id": "uuid",
  "sender_id": "uuid",
  "content": "message text",
  "encrypted": true,
  "created_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Notification Service, Search Service

### message.edited
**Trigger**: Message edited
**Data**:
```json
{
  "message_id": "uuid",
  "conversation_id": "uuid",
  "edited_at": "2025-01-15T10:30:00Z",
  "old_content": "original text",
  "new_content": "edited text"
}
```
**Subscribers**: Search Service

### message.deleted
**Trigger**: Message deleted/recalled
**Data**:
```json
{
  "message_id": "uuid",
  "conversation_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z",
  "deleted_by_id": "uuid",
  "reason": "user_deleted|recalled|moderated"
}
```
**Subscribers**: Search Service

### conversation.created
**Trigger**: New conversation started
**Data**:
```json
{
  "conversation_id": "uuid",
  "type": "direct|group",
  "member_ids": ["uuid1", "uuid2"],
  "created_at": "2025-01-15T10:30:00Z",
  "created_by_id": "uuid"
}
```
**Subscribers**: Notification Service

### conversation.member_added
**Trigger**: User added to group conversation
**Data**:
```json
{
  "conversation_id": "uuid",
  "user_id": "uuid",
  "added_at": "2025-01-15T10:30:00Z",
  "added_by_id": "uuid"
}
```
**Subscribers**: Notification Service

### message.read
**Trigger**: Message marked as read
**Data**:
```json
{
  "message_id": "uuid",
  "conversation_id": "uuid",
  "reader_id": "uuid",
  "read_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: (local only, no subscribers)

---

## 📝 Content Service Events

Published by: **Content Service**
Owned by: **Content Service**

### post.created
**Trigger**: New post published
**Data**:
```json
{
  "post_id": "uuid",
  "author_id": "uuid",
  "title": "Post title",
  "content": "Post content",
  "status": "published|draft",
  "privacy": "public|private|friends",
  "created_at": "2025-01-15T10:30:00Z",
  "tags": ["tag1", "tag2"],
  "media_ids": ["uuid1", "uuid2"]
}
```
**Subscribers**: Feed Service, Search Service, Notification Service

### post.updated
**Trigger**: Post edited
**Data**:
```json
{
  "post_id": "uuid",
  "author_id": "uuid",
  "changed_fields": ["title", "content"],
  "old_values": {"title": "Old"},
  "new_values": {"title": "New"},
  "updated_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Feed Service, Search Service

### post.deleted
**Trigger**: Post deleted
**Data**:
```json
{
  "post_id": "uuid",
  "author_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z",
  "reason": "user|admin|content_policy"
}
```
**Subscribers**: Feed Service, Search Service

### post.liked
**Trigger**: User likes post
**Data**:
```json
{
  "post_id": "uuid",
  "user_id": "uuid",
  "liked_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Notification Service

### post.unliked
**Trigger**: User unlikes post
**Data**:
```json
{
  "post_id": "uuid",
  "user_id": "uuid",
  "unliked_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: (local update)

### comment.created
**Trigger**: New comment on post
**Data**:
```json
{
  "comment_id": "uuid",
  "post_id": "uuid",
  "author_id": "uuid",
  "content": "comment text",
  "created_at": "2025-01-15T10:30:00Z",
  "parent_comment_id": "uuid|null"
}
```
**Subscribers**: Notification Service, Search Service

### comment.deleted
**Trigger**: Comment deleted
**Data**:
```json
{
  "comment_id": "uuid",
  "post_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Search Service

### post.shared
**Trigger**: User shares/reposts
**Data**:
```json
{
  "share_id": "uuid",
  "post_id": "uuid",
  "shared_by_id": "uuid",
  "shared_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Notification Service, Feed Service

---

## 🎬 Video Service Events

Published by: **Video Service**
Owned by: **Video Service**

### video.uploaded
**Trigger**: Video upload completed
**Data**:
```json
{
  "video_id": "uuid",
  "owner_id": "uuid",
  "filename": "video.mp4",
  "file_size": 1024000,
  "duration": 300,
  "uploaded_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Notification Service

### video.processing_started
**Trigger**: Transcoding/processing begins
**Data**:
```json
{
  "video_id": "uuid",
  "owner_id": "uuid",
  "started_at": "2025-01-15T10:30:00Z",
  "formats": ["1080p", "720p", "480p"]
}
```
**Subscribers**: (internal)

### video.processing_complete
**Trigger**: Transcoding finished
**Data**:
```json
{
  "video_id": "uuid",
  "owner_id": "uuid",
  "completed_at": "2025-01-15T10:30:00Z",
  "variants": [
    {"resolution": "1080p", "bitrate": 5000},
    {"resolution": "720p", "bitrate": 2500}
  ]
}
```
**Subscribers**: Notification Service, Feed Service

### video.published
**Trigger**: Video made public
**Data**:
```json
{
  "video_id": "uuid",
  "owner_id": "uuid",
  "title": "Video title",
  "published_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Feed Service, Search Service

### video.viewed
**Trigger**: User watches video
**Data**:
```json
{
  "video_id": "uuid",
  "viewer_id": "uuid",
  "watch_duration": 120,
  "completion_percentage": 75,
  "viewed_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: Analytics, Video Service (update stats)

---

## 🎥 Streaming Service Events

Published by: **Streaming Service**
Owned by: **Streaming Service**

### stream.started
**Trigger**: Live stream begins
**Data**:
```json
{
  "stream_id": "uuid",
  "creator_id": "uuid",
  "title": "Stream title",
  "started_at": "2025-01-15T10:30:00Z",
  "category": "gaming"
}
```
**Subscribers**: Feed Service, Notification Service

### stream.ended
**Trigger**: Live stream ends
**Data**:
```json
{
  "stream_id": "uuid",
  "creator_id": "uuid",
  "ended_at": "2025-01-15T10:30:00Z",
  "total_viewers": 150,
  "peak_concurrent": 75,
  "duration": 3600
}
```
**Subscribers**: Analytics

### stream.viewer_joined
**Trigger**: Viewer joins stream
**Data**:
```json
{
  "stream_id": "uuid",
  "viewer_id": "uuid",
  "joined_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: (internal)

### stream.viewer_left
**Trigger**: Viewer leaves stream
**Data**:
```json
{
  "stream_id": "uuid",
  "viewer_id": "uuid",
  "left_at": "2025-01-15T10:30:00Z",
  "watch_duration": 1200
}
```
**Subscribers**: (internal)

---

## 📸 Media Service Events

Published by: **Media Service**
Owned by: **Media Service**

### media.uploaded
**Trigger**: Media file uploaded
**Data**:
```json
{
  "media_id": "uuid",
  "owner_id": "uuid",
  "filename": "image.jpg",
  "media_type": "image",
  "mime_type": "image/jpeg",
  "file_size": 524288,
  "uploaded_at": "2025-01-15T10:30:00Z"
}
```
**Subscribers**: CDN Service, Content Service

### media.processing_complete
**Trigger**: Image/video processing done
**Data**:
```json
{
  "media_id": "uuid",
  "completed_at": "2025-01-15T10:30:00Z",
  "variants": [
    {"name": "thumbnail", "size": 51200},
    {"name": "small", "size": 102400}
  ]
}
```
**Subscribers**: CDN Service, Content Service

### media.deleted
**Trigger**: Media deleted
**Data**:
```json
{
  "media_id": "uuid",
  "owner_id": "uuid",
  "deleted_at": "2025-01-15T10:30:00Z",
  "s3_key": "uploads/uuid/image.jpg"
}
```
**Subscribers**: CDN Service

---

## 🔔 Notification Service Events

Published by: **Notification Service** (consumes events from other services)
Subscribers: **All services** publish events that trigger notifications

### Event Mapping for Notifications

```
user.created                → Welcome email
post.created (by followed)  → Push/email notification
post.liked                  → Push/email notification
message.sent               → Push/email notification
comment.created            → Push/email notification
user.followed              → Push notification
stream.started             → Push notification
video.processing_complete  → Email notification
```

---

## 📊 Analytics Events

These events are for analytics/observability (all services publish):

### service.call
**Trigger**: gRPC call made
**Data**:
```json
{
  "caller_service": "content-service",
  "called_service": "auth-service",
  "method": "GetUser",
  "status": "success|error",
  "latency_ms": 45,
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### cache.hit
**Trigger**: Cache hit on gRPC response
**Data**:
```json
{
  "service": "content-service",
  "cache_key": "user_123",
  "hit": true,
  "ttl_remaining": 3600,
  "timestamp": "2025-01-15T10:30:00Z"
}
```

---

## 🏗️ Kafka Topic Structure

### Topic Naming Convention
```
nova.<aggregate_type>.<event_type>

Examples:
  nova.user.created
  nova.user.updated
  nova.post.published
  nova.message.sent
  nova.stream.started
```

### Topic Configuration

| Topic | Partitions | Retention | Format | Key |
|-------|-----------|-----------|--------|-----|
| nova.user.* | 3 | 30 days | JSON | user_id |
| nova.post.* | 5 | 30 days | JSON | post_id |
| nova.message.* | 3 | 30 days | JSON | conversation_id |
| nova.video.* | 3 | 30 days | JSON | video_id |
| nova.stream.* | 3 | 30 days | JSON | stream_id |
| nova.media.* | 2 | 30 days | JSON | media_id |

**Partitioning Strategy**: Partition by aggregate ID to ensure ordering within an aggregate

---

## 🔄 Subscription Model

### Consumer Groups per Service

```
Auth Service:
  - Publishes: user.*, no subscriptions

User Service:
  - Publishes: user.followed, user.blocked
  - Subscribes: user.created (new followers)

Messaging Service:
  - Publishes: message.*, conversation.*
  - Subscribes: user.blocked (update conversation access)

Content Service:
  - Publishes: post.*, comment.*, post.liked
  - Subscribes: user.deleted (cleanup posts)

Video Service:
  - Publishes: video.*
  - Subscribes: none

Streaming Service:
  - Publishes: stream.*
  - Subscribes: none

Media Service:
  - Publishes: media.*
  - Subscribes: none

Feed Service:
  - Publishes: none
  - Subscribes: post.*, user.followed (invalidate caches)

Search Service:
  - Publishes: none
  - Subscribes: post.*, message.*, comment.*, user.updated

Notification Service:
  - Publishes: none
  - Subscribes: ALL (triggers notifications)
```

---

## 📋 Event Processing Guidelines

### Idempotency
- All event handlers must be **idempotent**
- Processing same event twice = same result
- Use deduplication key: `event.id`

### Ordering
- Events for same aggregate must be processed in order
- Use same partition key for related events
- Kafka guarantees ordering within partition

### Error Handling
- Failed processing: Retry with exponential backoff
- Max retries: 3 attempts, then move to dead-letter queue
- Log errors for manual investigation

### Latency SLO
- 95th percentile: < 5 seconds from publish to process
- Target: Real-time processing for most events
- Async processing OK for analytics events

---

## 🚀 Implementation Notes

### Phase 1: Outbox Pattern
1. Service writes to database
2. Service writes event to `outbox_events` table (same transaction)
3. Events Service polls `outbox_events` every 5 seconds
4. Events Service publishes to Kafka
5. Other services consume and update caches

### Phase 2: Full Event-Driven
1. Keep outbox pattern for consistency
2. Services listen to Kafka directly
3. Update caches in real-time
4. Remove direct SQL dependencies

---

## 📚 Schema Evolution

### Versioning Events

Use `version` field for schema changes:

```json
{
  "event_type": "user.updated",
  "version": 2,  // Schema version
  "data": {...}
}
```

### Backwards Compatibility

- **v1**: Initial event structure
- **v2**: Add optional field (new services can use it, old services ignore)
- **v3**: Remove deprecated field (with grace period first)

---

## ✅ Checklist for Event Implementation

- [ ] Define all domain events for each service
- [ ] Create Kafka topics
- [ ] Implement event publishing in services
- [ ] Implement event consumption in subscribers
- [ ] Add idempotency checks
- [ ] Test event ordering
- [ ] Monitor event lag (Kafka consumer lag)
- [ ] Set up alerting for failures
- [ ] Document event schema in Schema Registry

---

**Status**: Phase 0 Task 0.3 Complete ✅
**Next Task**: Task 0.4 - Plan Phase 1 Detailed Schedule

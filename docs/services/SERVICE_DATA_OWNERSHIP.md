# Service Data Ownership - Nova Architecture Phase 0

**Version**: 1.2
**Date**: 2025-12-28
**Status**: Phase 0 Task 0.2 Deliverable (Updated)

> **Update 2025-12-28 (v1.2)**: Fixed E2EE documentation - removed non-existent
> encryption tables from Auth, added detailed Olm/Megolm table documentation
> for Messaging Service with vodozemac encryption strategy.
>
> **Update 2025-12-28 (v1.1)**: Clarified per-service outbox pattern (not centralized).
> Each service owns its own outbox_events table and processor.

---

## 📋 Overview

This document maps each table in the current `nova_content` PostgreSQL database to the owning microservice. This mapping is **critical** for Phase 1 implementation as it defines which service will own each table after database separation.

**Key Principle**: A service "owns" a table if it writes to that table. Services can **read** from any table (via gRPC), but only the owning service should **write**.

---

## 🎯 Service Ownership Matrix

### 1. **Auth Service** ✅
**Owned Tables**: User identity and authentication

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `users` | Core user accounts | ALL | Auth Service | Email, username, password_hash |
| `sessions` | Active login sessions | Auth Service | Auth Service | JWT validation |
| `refresh_tokens` | Long-lived tokens | Auth Service | Auth Service | Token refresh |
| `email_verifications` | Email verification tokens | Auth Service | Auth Service | Email confirmation flow |
| `password_resets` | Password reset tokens | Auth Service | Auth Service | Password recovery |
| `two_fa_sessions` | 2FA sessions | Auth Service | Auth Service | 2FA verification |
| `two_fa_backup_codes` | 2FA backup codes | Auth Service | Auth Service | Account recovery |
| `jwt_signing_keys` | JWT key rotation | Auth Service | Auth Service | Token signing |
| `auth_logs` | Login attempt logs | Auth Service | Auth Service | Security audit |
| `user_settings` | User preferences | Auth Service | Auth Service | App settings |
| `invite_codes` | Invite system | Auth Service | Auth Service | User invitations |
| `oauth_connections` | OAuth provider links | Auth Service | Auth Service | Social login |
| `passkey_credentials` | WebAuthn passkeys | Auth Service | Auth Service | Passwordless auth |
| `outbox_events` | Transactional outbox | Auth Service | Auth Service | Event publishing |

**Dependencies**: None (Auth Service is foundational)

**Read Access Required From**:
- All other services read user info via `GetUser()` RPC
- All services validate tokens via `VerifyToken()` RPC

---

### 2. **User Service** 👤
**Owned Tables**: User profiles and relationships

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `follows` | User follow relationships | User/Feed/Search Services | User Service | Follow/unfollow tracking |
| `social_metadata` | User social stats | User/Feed Services | User Service | Follower counts |

**Dependencies**:
- `users` table (Auth Service) - read via `GetUser()` RPC

**Read Access Required From**:
- Feed Service - to show follower info
- Search Service - for user search/discovery
- Content Service - for post author info

**Notes**: User profiles are stored in Auth Service's `users` table. This service manages the social graph (follows, blocks, etc.)

---

### 3. **Messaging Service** 💬
**Owned Tables**: Direct messages, conversations, and E2EE infrastructure

#### Core Messaging Tables

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `conversations` | Direct message threads | Messaging/Notification Services | Messaging Service | 1:1 and group chats |
| `conversation_members` | Conversation participants | Messaging Service | Messaging Service | Member list |
| `conversation_counters` | Sequence number tracking | Messaging Service | Messaging Service | Message ordering |
| `messages` | Message content | Messaging/Notification Services | Messaging Service | Supports E2EE via Megolm |
| `message_reactions` | Message emoji reactions | Messaging Service | Messaging Service | User reactions |
| `message_attachments` | Files/media in messages | Messaging Service | Messaging Service | File references |
| `message_edit_history` | Message edit tracking | Messaging Service | Messaging Service | Audit trail |
| `message_recalls` | Recalled messages | Messaging Service | Messaging Service | Message deletion |

#### E2EE Tables (vodozemac Olm/Megolm)

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `user_devices` | Multi-device key management | Messaging Service | Messaging Service | Curve25519 + Ed25519 keys |
| `olm_accounts` | Pickled Olm accounts | Messaging Service | Messaging Service | Per-device encrypted state |
| `olm_one_time_keys` | Forward secrecy OTKs | Messaging Service | Messaging Service | Ephemeral session keys |
| `olm_sessions` | 1:1 encrypted channels | Messaging Service | Messaging Service | Device-to-device Olm |
| `megolm_outbound_sessions` | Room encryption (send) | Messaging Service | Messaging Service | Group session keys |
| `megolm_inbound_sessions` | Room decryption (recv) | Messaging Service | Messaging Service | Imported room keys |
| `to_device_messages` | Key sharing queue | Messaging Service | Messaging Service | Olm-encrypted key delivery |
| `room_key_history` | Late-joiner key access | Messaging Service | Messaging Service | Historical key export |

#### Other Messaging Tables

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `call_sessions` | Video/audio calls | Messaging Service | Messaging Service | WebRTC call state |
| `call_participants` | Call participants | Messaging Service | Messaging Service | Active call members |
| `user_locations` | Location sharing | Messaging Service | Messaging Service | Real-time location |
| `blocks` | User blocks | Messaging Service | Messaging Service | Block relationships |
| `message_requests` | DM permissions | Messaging Service | Messaging Service | Request-based DMs |

**Encryption Strategy**: Uses vodozemac library implementing Matrix Olm/Megolm protocols.
- **Olm**: Double Ratchet for 1:1 device sessions (key exchange)
- **Megolm**: Efficient group encryption for rooms (message encryption)
- Server stores encrypted pickles; **cannot decrypt message content**

**Dependencies**:
- `users` table (Auth Service) - read via `GetUser()` RPC
- `media` (via Media Service) - for attachments

**Read Access Required From**:
- Notification Service - to send message notifications
- Search Service - for message search (encrypted content not searchable)

---

### 4. **Content Service** 📝
**Owned Tables**: Posts and post-related data

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `posts` | User posts/articles | ALL | Content Service | Title, content, status |
| `post_metadata` | Post metadata (likes, comments) | ALL | Content Service | Engagement counts |
| `comments` | Post comments | Content Service | Content Service | Comment threads |
| `post_images` | Post images | Content Service | Content Service | Image associations |
| `post_videos` | Post video associations | Content Service | Content Service | Video references |
| `post_shares` | Post shares/reposts | Content Service | Content Service | Share tracking |
| `likes` | Post likes | Content Service | Content Service | Like tracking |
| `bookmarks` | User bookmarks | Content Service | Content Service | Saved posts |
| `bookmark_collections` | Bookmark folders | Content Service | Content Service | Bookmark organization |

**Dependencies**:
- `users` table (Auth Service) - read via `GetUser()` RPC
- `videos` table (Media Service) - read via `GetVideo()` RPC
- `media` (via Media Service)

**Read Access Required From**:
- Feed Service - to show posts in feed
- Search Service - for full-text search
- Notification Service - for post notifications
- User Service - for author info

---

### 5. **Feed Service** 📰
**Owned Tables**: Feed generation and caching

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `user_feed_preferences` | Per-user feed settings | Feed Service | Feed Service | Personalization settings |

**Dependencies**:
- `posts` (Content Service) - read via `GetPost()` RPC
- `users` (Auth Service) - read via `GetUser()` RPC
- `follows` (User Service) - read via `GetUserFollowing()` RPC

**Notes**: Feed generation is compute-heavy but stateless. Results can be cached. Most data comes from other services via gRPC.

---

### 6. **Search Service** 🔍
**Owned Tables**: Search indexes and cache

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| (None - uses read replicas) | - | - | - | Search uses read-only replicas from other services |

**Dependencies**:
- All tables (via read replicas)
- All services via gRPC RPC calls

**Notes**:
- Search Service maintains read-only copies of data from other services
- Can be served from read replicas or Elasticsearch
- No write ownership of any table
- Consumes Kafka events to keep indexes updated

---

### 7. **Media Service** 🖼️
**Owned Tables**: Media assets and processing

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `uploads` | Completed uploads | Media Service | Media Service | Upload history |
| `upload_sessions` | Active uploads | Media Service | Media Service | Upload progress |
| `upload_chunks` | Multipart upload chunks | Media Service | Media Service | Chunk tracking |
| `videos` | Video metadata | ALL | Media Service | Title, duration, codec |
| `video_embeddings` | Video vector embeddings | Media Service | Media Service | Recommendation system |
| `video_pipeline_state` | Pipeline status | Media Service | Media Service | Processing state |
| `video_engagement` | Video view stats | Media Service | Media Service | Engagement metrics |
| `reels` | Short-form video (reels) | Media Service | Media Service | Reels metadata |
| `reel_transcode_jobs` | Video encoding jobs | Media Service | Media Service | Processing queue |
| `reel_variants` | Video transcoded versions | Media Service | Media Service | Multiple resolutions |

**Dependencies**:
- `users` (Auth Service) - read via `GetUser()` RPC
- Object storage (S3/GCS)

**Read Access Required From**:
- Content Service - for post images
- Messaging Service - for message attachments
- All services - for media display

---

### 8. **Notification Service** 🔔
**Owned Tables**: Notifications and preferences

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `notifications` | In-app notifications | Notification Service | Notification Service | Read/seen state |
| `push_tokens` | Device push tokens | Notification Service | Notification Service | FCM/APNs tokens |
| `push_delivery_logs` | Push delivery attempts | Notification Service | Notification Service | Retry + error tracking |
| `notification_preferences` | Notification preferences | Notification Service | Notification Service | Per-type toggles |
| `notification_dedup` | Deduplication window | Notification Service | Notification Service | 1-minute window |

**Dependencies**:
- `users` (Auth Service) - read via `GetUser()` RPC
- `posts` (Content Service) - read via `GetPost()` RPC
- `messages` (Messaging Service) - read via `GetMessage()` RPC
- All other services via events

**Notes**:
- Subscribes to Kafka events for all notifications
- Notifications are persisted in `notifications`
- Notification preferences stored in `notification_preferences`
- Legacy `notification_jobs` table exists in pending migrations only

---

### 9. **Streaming Service** 🎥
**Owned Tables**: Live streaming data

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `streams` | Live streams | Streaming Service | Streaming Service | Stream metadata |
| `stream_keys` | RTMP ingest keys | Streaming Service | Streaming Service | Stream secrets |
| `viewer_sessions` | Viewer watch sessions | Streaming Service | Streaming Service | Viewer tracking |
| `stream_metrics` | Stream performance data | Streaming Service | Streaming Service | Partitioned by month |
| `quality_levels` | Video quality options | Streaming Service | Streaming Service | Stream quality config |

**Dependencies**:
- `users` (Auth Service) - read via `GetUser()` RPC

**Read Access Required From**:
- Feed Service - to show live streams
- Notification Service - for stream notifications

---

### 10. **Video Service** 🎬 (Deprecated)
**Owned Tables**: None (merged into Media Service)

**Notes**:
- Video-related tables are now owned by Media Service
- Keep this section for historical context only

---

### 11. **CDN Service** 🌍
**Owned Tables**: CDN configuration (implied, no direct tables)

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| (No direct DB tables) | Configuration stored in cache/config | CDN Service | CDN Service | Edge location management |

**Dependencies**:
- Media Service - to get media URLs
- Media Service - to get video URLs (video tables merged)

**Notes**: CDN configuration is typically stored in external CDN provider or config management system, not in application database.

---

### 12. **Outbox Pattern** 📡
**Architecture**: Per-service (Decentralized)

Each service owns its own `outbox_events` table in its database:

| Service | Outbox Table Location | Processor |
|---------|----------------------|-----------|
| identity-service | identity DB | `spawn_outbox_consumer()` |
| content-service | content DB | `OutboxProcessor::start()` |
| social-service | social DB | `OutboxProcessor` + circuit breaker |
| graph-service | graph DB | `OutboxProcessor` |

**Shared Library**: `transactional-outbox` in `backend/libs/transactional-outbox/`

**Schema** (library standard):
```sql
outbox_events (
  id UUID PRIMARY KEY,
  aggregate_type VARCHAR(255),  -- e.g., "user", "content"
  aggregate_id UUID,
  event_type VARCHAR(255),      -- e.g., "user.created"
  payload JSONB,                -- event data
  metadata JSONB,               -- correlation_id, trace_id
  published_at TIMESTAMPTZ,     -- NULL until published
  retry_count INT,
  last_error TEXT
)
```

**Notes**:
- Each service writes to its **own** outbox_events table (same transaction as business logic)
- Each service runs its **own** background processor to publish to Kafka
- No centralized "Events Service" - services produce directly to Kafka
- Enables independent deployment and scaling per service

---

### 13. **Experiments/Analytics** 📊
**Owned Tables**: A/B testing and analytics (can be owned by a dedicated Analytics Service)

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `experiments` | A/B test definitions | Experiments Service | Experiments Service | Test configuration |
| `experiment_variants` | Test variants | Experiments Service | Experiments Service | Variant definitions |
| `experiment_assignments` | User-variant assignments | Experiments Service | Experiments Service | Assignment tracking |
| `experiment_results_cache` | Cached results | Experiments Service | Experiments Service | Results aggregation |
| `experiment_metrics` | Metrics data | Experiments Service | Experiments Service | Performance data |

**Dependencies**:
- `users` (Auth Service) - read via `GetUser()` RPC

**Notes**: This can be a separate Analytics Service, or folded into another service.

---

## 📊 Cross-Service Data Flow

### Write Patterns (Service Ownership)

```
Auth Service:        users, sessions, refresh_tokens, outbox_events (own DB)
User Service:        follows, social_metadata
Messaging Service:   conversations, messages, outbox_events (own DB)
Content Service:     posts, comments, likes, bookmarks, outbox_events (own DB)
Streaming Service:   streams, viewer_sessions, stream_metrics
Media Service:       uploads, videos, reels, variants, (metadata in object storage)
Notification Service: notifications, tokens, delivery_logs, preferences, dedup
Feed Service:        user_feed_preferences
Search Service:      (none - read-only)
CDN Service:         (none - external config)
Graph Service:       follows, blocks, outbox_events (own DB)
```

### Read Patterns (Data Dependencies)

```
┌─────────────┐
│ Auth        │ ← All services depend on this
│ (users)     │
└──────┬──────┘
       │
       ├─→ User Service (reads users, writes follows)
       ├─→ Messaging Service (reads users, writes messages)
       ├─→ Content Service (reads users, writes posts)
       ├─→ Media Service (reads users, writes videos/uploads)
       ├─→ Streaming Service (reads users, writes streams)
       └─→ Feed/Search/Notification (reads via gRPC)

┌────────────────────────────────────────┐
│ Data Owned by Content/User/Messaging   │
└────────────────────────────────────────┘
       │
       ├─→ Feed Service (reads via gRPC)
       ├─→ Search Service (reads via gRPC + events)
       └─→ Notification Service (reads via events)
```

---

## 🔄 Outbox Pattern for Consistency

Each service has its **own** `outbox_events` table (per-service pattern):

1. **When** a service writes to its tables, it also inserts an event into **its own** `outbox_events`
2. **Background processor** (in same service) polls and publishes to Kafka
3. **Other services** subscribe to Kafka topics and update their read copies
4. **Advantages**:
   - Transactional consistency (write happens atomically)
   - No data loss (guaranteed delivery via retry + DLQ)
   - Independent deployment (no central bottleneck)
   - Service owns its events end-to-end

**Example**: When Content Service creates a post:
```sql
-- In content-service database
BEGIN;
  INSERT INTO posts (...) VALUES (...);
  INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
    VALUES ('post', post_id, 'post.created', {...});
COMMIT;
-- Content service's OutboxProcessor publishes to Kafka topic: nova.post.events
```

**Shared Library**: All services use `transactional-outbox` library for consistent implementation.

---

## 📈 Phase 1 Database Separation Plan

After Phase 1 (application layer decoupling with gRPC), we can separate databases:

```
Current (Nov 2025):
┌─────────────────────────────────────┐
│ Single nova_content PostgreSQL       │
│ - All 12 services write to same DB   │
│ - 56+ foreign key constraints        │
└─────────────────────────────────────┘

Target (Jan 2026 - Phase 1 Complete):
┌──────────────┬──────────────┬──────────────┐
│ nova_auth    │ nova_users   │ nova_content │
├──────────────┼──────────────┼──────────────┤
│ Auth Service │ User Service │ Content Svc  │
└──────────────┴──────────────┴──────────────┘

│ nova_messaging │ nova_video   │ nova_streaming │
├────────────────┼──────────────┼────────────────┤
│ Messaging Svc  │ Video Svc    │ Streaming Svc  │
└────────────────┴──────────────┴────────────────┘

(Media, CDN, Events, Feed, Search can be separate or co-located)
```

---

## ✅ Key Rules for Phase 1 Implementation

### Rule 1: Single Write Owner
- Each table has exactly one service that writes to it
- This service owns the table

### Rule 2: Read-Only Access
- Other services **read** via gRPC RPCs, not direct SQL
- Example: Instead of `SELECT * FROM users WHERE id = ?`
  - Use: `await auth_client.get_user(user_id)`

### Rule 3: Transactional Consistency
- Use outbox_events table for multi-service consistency
- Each service publishes via its own outbox processor (transactional-outbox)

### Rule 4: No Direct Foreign Keys Across Services
- Foreign keys within a service: ✅ OK
- Foreign keys across services: ❌ NOT OK (breaks separation)
- Use aggregate references instead (IDs, not FK constraints)

### Rule 5: Event-Driven Updates
- When one service needs another's data:
  - For reads: Use gRPC RPC call
  - For reactions: Subscribe to Kafka events
- Example: Messaging Service doesn't query users table directly
  - Instead, it calls `auth_client.get_user()` or caches user info

---

## 📋 Table Ownership Summary

| Service | Tables Owned | Count | Dependencies |
|---------|-------------|-------|--------------|
| Auth (identity-service) | users, sessions, tokens, settings, oauth, passkeys, outbox_events | 15 | None (foundational) |
| User (graph-service) | follows, social_metadata, outbox_events | 3 | Auth (read via gRPC) |
| Messaging (realtime-chat-service) | conversations, messages, Olm/Megolm E2EE (8 tables), calls, locations | 22 | Auth (read via gRPC) |
| Content | posts, comments, likes, bookmarks, outbox_events | 10 | Auth, Media (read) |
| Media | uploads, sessions, chunks, videos, reels, variants, pipelines | 11 | Auth (read) |
| Video (deprecated) | (merged into Media) | 0 | Media |
| Streaming | streams, viewers, metrics, quality | 5 | Auth (read) |
| Feed | user_feed_preferences | 1 | Content, User (read) |
| Experiments | experiments, variants, assignments | 4 | Auth (read) |
| Notification | notifications, push_tokens, delivery_logs, preferences, dedup | 5 | All services (read events) |
| Search | (none - read-only) | 0 | All services (read replicas) |
| CDN | (none - external) | 0 | None |

**Total**: ~71 tables, clear ownership boundaries ✅

**Notes**:
- Each service with outbox_events has its **own** table in its **own** database
- The `transactional-outbox` library provides a shared implementation
- Messaging E2EE uses vodozemac (Olm/Megolm) - server cannot decrypt messages

---

## 🚀 Next Steps

1. **Validate this mapping** against your codebase
2. **Create foreign key removal plan**: Identify all cross-service FKs to remove
3. **Design gRPC endpoints**: Already done in Task 0.1 ✅
4. **Plan Kafka events**: Task 0.3 will detail this
5. **Execute Phase 1**: Week-by-week implementation in Task 0.4

---

## 📝 Notes

- This mapping assumes the current database schema structure
- Table names may differ from your implementation
- Adjust based on actual table names in your codebase
- Validation should happen in Phase 0 (this document)

---

**Status**: Phase 0 Task 0.2 Complete ✅
**Next Task**: Task 0.3 - Define Kafka Event Contracts

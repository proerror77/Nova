# Service Data Ownership - Nova Architecture Phase 0

**Version**: 1.0
**Date**: 2025-11-04
**Status**: Phase 0 Task 0.2 Deliverable

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
| `device_keys` | Device encryption keys | Auth Service | Auth Service | Device-specific keys |
| `key_exchanges` | Key exchange records | Auth Service | Auth Service | Encryption setup |
| `encryption_keys` | General encryption keys | Auth Service | Auth Service | Data encryption |
| `encryption_audit_log` | Encryption audit trail | Auth Service | Auth Service | Security compliance |

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
**Owned Tables**: Direct messages and conversations

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `conversations` | Direct message threads | Messaging/Notification Services | Messaging Service | 1:1 and group chats |
| `conversation_members` | Conversation participants | Messaging Service | Messaging Service | Member list |
| `conversation_counters` | Unread message counts | Messaging Service | Messaging Service | Unread tracking |
| `messages` | Message content | Messaging/Notification Services | Messaging Service | Plaintext + encrypted |
| `message_reactions` | Message emoji reactions | Messaging Service | Messaging Service | User reactions |
| `message_attachments` | Files/media in messages | Messaging Service | Messaging Service | File references |
| `message_edit_history` | Message edit tracking | Messaging Service | Messaging Service | Audit trail |
| `message_recalls` | Recalled messages | Messaging Service | Messaging Service | Message deletion |
| `message_search_index` | Message FTS index | Messaging/Search Services | Messaging Service | Search optimization |

**Dependencies**:
- `users` table (Auth Service) - read via `GetUser()` RPC
- `media` (implied, via Media Service)

**Read Access Required From**:
- Notification Service - to send message notifications
- Search Service - for message search

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
- `videos` table (Video Service) - read via `GetVideo()` RPC
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
| (S3-based, no DB tables) | Media metadata (implied) | ALL | Media Service | File storage in S3 |
| `upload_sessions` | Active uploads | Media Service | Media Service | Upload progress |
| `upload_chunks` | Multipart upload chunks | Media Service | Media Service | Chunk tracking |
| `uploads` | Completed uploads | Media Service | Media Service | Upload history |

**Dependencies**:
- `users` (Auth Service) - read via `GetUser()` RPC
- S3 storage

**Read Access Required From**:
- Content Service - for post images
- Messaging Service - for message attachments
- Video Service - for thumbnails
- All services - for media display

---

### 8. **Notification Service** 🔔
**Owned Tables**: Notifications and preferences

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `notification_jobs` | Push notification queue | Notification Service | Notification Service | Background job tracking |

**Dependencies**:
- `users` (Auth Service) - read via `GetUser()` RPC
- `posts` (Content Service) - read via `GetPost()` RPC
- `messages` (Messaging Service) - read via `GetMessage()` RPC
- All other services via events

**Notes**:
- Subscribes to Kafka events for all notifications
- No persistent notification storage in DB
- Notification preferences stored in Auth Service user profile

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

### 10. **Video Service** 🎬
**Owned Tables**: Video content and processing

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| `videos` | Video metadata | ALL | Video Service | Title, duration, codec |
| `reel_variants` | Video transcoded versions | Video Service | Video Service | Multiple resolutions |
| `reel_transcode_jobs` | Video encoding jobs | Video Service | Video Service | Processing queue |
| `video_pipeline_state` | Pipeline status | Video Service | Video Service | Processing state |
| `video_engagement` | Video view stats | Video Service | Video Service | Engagement metrics |
| `video_embeddings` | Video vector embeddings | Video Service | Video Service | Recommendation system |
| `video_webhooks` | Video service webhooks | Video Service | Video Service | Event webhooks |
| `reels` | Short-form video (reels) | Video Service | Video Service | Reels metadata |
| `webhook_deliveries` | Webhook delivery tracking | Video Service | Video Service | Delivery audit |

**Dependencies**:
- `users` (Auth Service) - read via `GetUser()` RPC
- `media` (Media Service) - read via `GetMedia()` RPC

**Read Access Required From**:
- Content Service - for post videos
- Feed Service - for video recommendations
- Search Service - for video search
- Streaming Service - for live video

---

### 11. **CDN Service** 🌍
**Owned Tables**: CDN configuration (implied, no direct tables)

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|----------|-------|
| (No direct DB tables) | Configuration stored in cache/config | CDN Service | CDN Service | Edge location management |

**Dependencies**:
- Media Service - to get media URLs
- Video Service - to get video URLs

**Notes**: CDN configuration is typically stored in external CDN provider or config management system, not in application database.

---

### 12. **Events Service** 📡
**Owned Tables**: Event streaming and outbox

| Table | Purpose | Read By | Write By | Notes |
|-------|---------|---------|---------|-------|
| `outbox_events` | Transactional event publishing | Events Service | ALL SERVICES | Outbox pattern |

**Dependencies**: None (central event hub)

**Writes From**: All other services

**Notes**:
- ALL services write to `outbox_events` for their domain events
- Events Service publishes these to Kafka
- Enables transactional consistency (write to DB + outbox in same transaction)

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
Auth Service:        users, sessions, refresh_tokens, ...
User Service:        follows, social_metadata
Messaging Service:   conversations, messages, ...
Content Service:     posts, comments, likes, bookmarks, ...
Video Service:       videos, reels, reel_variants, ...
Streaming Service:   streams, viewer_sessions, stream_metrics
Media Service:       uploads, (metadata in S3)
Notification Service: (none - consumes events)
Feed Service:        user_feed_preferences
Search Service:      (none - read-only)
CDN Service:         (none - external config)
Events Service:      outbox_events (written by ALL)
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
       ├─→ Video Service (reads users, writes videos)
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

The **outbox_events** table is central to Phase 2 implementation:

1. **When** a service writes to its tables, it also inserts an event into `outbox_events`
2. **Events Service** polls `outbox_events` and publishes to Kafka
3. **Other services** subscribe to events and update their read copies
4. **Advantages**:
   - Transactional consistency (write happens atomically)
   - No data loss (guaranteed delivery)
   - Event-driven architecture foundation

**Example**: When Content Service creates a post:
```sql
BEGIN;
  INSERT INTO posts (...) VALUES (...);
  INSERT INTO outbox_events (event_type, data) VALUES ('post.created', {...});
COMMIT;
```

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
- All domain events flow through Events Service → Kafka

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
| Auth | users, sessions, tokens, keys, auth_logs, etc. | 13 | None |
| User | follows, social_metadata | 2 | Auth (read) |
| Messaging | conversations, messages, reactions, etc. | 9 | Auth (read) |
| Content | posts, comments, likes, bookmarks, etc. | 9 | Auth, Video (read) |
| Video | videos, reels, variants, pipelines, etc. | 8 | Auth (read) |
| Streaming | streams, viewers, metrics, quality | 5 | Auth (read) |
| Media | uploads, sessions, chunks | 3 | Auth (read) |
| Feed | user_feed_preferences | 1 | Content, User (read) |
| Events | outbox_events | 1 | (all write) |
| Experiments | experiments, variants, assignments | 4 | Auth (read) |
| Notification | (none - stateless) | 0 | All services (read events) |
| Search | (none - read-only) | 0 | All services (read replicas) |
| CDN | (none - external) | 0 | None |

**Total**: ~58 tables, clear ownership boundaries ✅

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

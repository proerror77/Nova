# Nova Database Data Dictionary

**Date**: 2025-11-05
**Spec**: [007 Database Schema Consolidation](../../specs/007-p1-db-schema-consolidation/)
**Status**: Phase 0 - Inventory Complete

## Overview

This document provides a complete inventory of Nova's database schema as of Nov 5, 2025, identifying duplicate tables, inconsistent soft-delete patterns, and redundant counters that require consolidation.

---

## Core Tables by Domain

### Authentication & Identity

| Table | Owner | Primary Key | Soft Delete | Status | Notes |
|-------|-------|-------------|-------------|--------|-------|
| `users` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | **CANONICAL** | Single source of truth. Duplicated in messaging-service, user-service. Must consolidate. |
| `sessions` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Web/mobile session storage. FK to users. |
| `refresh_tokens` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | JWT refresh token persistence. FK to users. |
| `password_resets` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Password reset tokens. FK to users. |
| `email_verifications` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Email verification codes. FK to users. |
| `two_fa_backup_codes` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | 2FA recovery codes. FK to users. |
| `two_fa_sessions` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | 2FA verification state. FK to users. |

### OAuth & External Auth

| Table | Owner | Primary Key | Soft Delete | Status | Notes |
|-------|-------|-------------|-------------|--------|-------|
| `oauth_accounts` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Google, Apple, Facebook, WeChat links. FK to users. |
| `oauth_tokens` | auth-service | `id UUID` | `deleted_at TIMESTAMPTZ` | ⚠️ ENCRYPTED | Provider tokens stored encrypted. FK to oauth_accounts. |

### Social Features

| Table | Owner | Primary Key | Soft Delete | Status | Notes |
|-------|-------|-------------|-------------|--------|-------|
| `follows` | user-service | `(follower_id, following_id)` | `deleted_at TIMESTAMPTZ` | OK | Social graph. Denormalized counters in users table. |
| `likes` | content-service | `(user_id, post_id)` | `deleted_at TIMESTAMPTZ` | ⚠️ DUPLICATE | `posts.like_count` also exists. Must use single source. |
| `comments` | content-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Post comments. FK to posts and users. |
| `replies` | content-service | `id UUID` | `deleted_at TIMESTAMPTZ` | ⚠️ DUPLICATE | `comments.reply_count` also exists. Must consolidate. |

### Content & Posts

| Table | Owner | Primary Key | Soft Delete | Status | Notes |
|-------|-------|-------------|-------------|--------|-------|
| `posts` | content-service | `id UUID` | `deleted_at TIMESTAMPTZ` | ⚠️ DENORM | Has `like_count`, `comment_count`, `share_count`. Use aggregates. |
| `post_images` | content-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Image attachments. FK to posts. |
| `post_metadata` | content-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | SEO, tags, mentions. FK to posts. |
| `post_videos` | content-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Video attachments. FK to posts and videos. |
| `bookmarks` | content-service | `(user_id, post_id)` | `deleted_at TIMESTAMPTZ` | OK | User bookmarks. FK to users and posts. |
| `shares` | content-service | `(user_id, post_id)` | `deleted_at TIMESTAMPTZ` | OK | Post shares. FK to users and posts. |

### Video & Streaming

| Table | Owner | Primary Key | Soft Delete | Status | Notes |
|-------|-------|-------------|-------------|--------|-------|
| `videos` | media-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Video metadata. FK to users (uploader). |
| `video_embeddings` | media-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | pgvector embeddings for search. FK to videos. |
| `video_pipeline_state` | media-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Transcoding/processing state. FK to videos. |
| `video_engagement` | media-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Views, likes, comments per video. FK to videos. |
| `streams` | streaming-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Live streams. FK to users (streamer). |
| `stream_keys` | streaming-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | RTMP/HLS keys. FK to streams. |
| `stream_metrics` | streaming-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Viewer count, bitrate. FK to streams. |
| `viewer_sessions` | streaming-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Per-stream viewer tracking. FK to streams and users. |

### Messaging

| Table | Owner | Primary Key | Soft Delete | Status | Notes |
|-------|-------|-------------|-------------|--------|-------|
| `conversations` | messaging-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | 1-to-1 or group chats. FK to users (participants). |
| `conversation_members` | messaging-service | `(conversation_id, user_id)` | `deleted_at TIMESTAMPTZ` | OK | Chat membership. FK to conversations and users. |
| `messages` | messaging-service | `id UUID` | `deleted_at TIMESTAMPTZ` | ⚠️ CASCADE ISSUE | Hard-delete on conversation removal. Should soft-delete. |
| `message_attachments` | messaging-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Files, images in messages. FK to messages. |
| `message_reactions` | messaging-service | `(message_id, user_id, emoji)` | `deleted_at TIMESTAMPTZ` | OK | Emoji reactions. FK to messages and users. |
| `message_search_index` | messaging-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Full-text search index. FK to messages. |

### Feed & Recommendations

| Table | Owner | Primary Key | Soft Delete | Status | Notes |
|-------|-------|-------------|-------------|--------|-------|
| `user_feed_preferences` | feed-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Per-user feed ranking weights. FK to users. |
| `notification_jobs` | feed-service | `id UUID` | `deleted_at TIMESTAMPTZ` | OK | Outbox-pattern notifications. FK to users. |

---

## Duplicate Tables (MUST CONSOLIDATE)

### Users Table Duplication

**Problem**: Three services define their own `users` table, breaking single-source-of-truth principle.

```
backend/migrations/001_initial_schema.sql
├── CREATE TABLE users (id UUID PRIMARY KEY, ...)

backend/auth-service/migrations/001_create_users_table.sql
├── CREATE TABLE users (id UUID PRIMARY KEY, ...)  ← SHADOW

backend/messaging-service/migrations/0001_create_users.sql
├── CREATE TABLE users (...)  ← SHADOW

backend/user-service/migrations/...
├── Implied users table or reference
```

**Solution (Spec 007)**:
1. Designate `auth-service.users` as **canonical**
2. Drop shadow tables in messaging-service and user-service
3. All queries via gRPC or service API to auth-service
4. Store only `user_id` (UUID) in downstream services

**Phase**: Phase 1 (Weeks 3-4)

---

## Soft Delete Inconsistencies

### Problem: Multiple Patterns

- `deleted_at TIMESTAMPTZ NULL` - Standard (PREFERRED)
- `deleted BOOLEAN DEFAULT false` - Legacy
- `soft_delete BOOLEAN` - Inconsistent naming

### Current Status

Most tables migrated to `deleted_at` via migrations 066, 070:
- ✅ `users`, `posts`, `comments`, `messages` - Using `deleted_at`
- ❌ Some legacy tables may still use `deleted BOOLEAN`

### Solution (Spec 007)

Standardize ALL entities to `deleted_at TIMESTAMPTZ NULL`:
```sql
-- Pattern for all new tables
deleted_at TIMESTAMPTZ DEFAULT NULL,
```

Add query predicate everywhere:
```sql
WHERE deleted_at IS NULL
```

Disable hard-delete cascades; use soft-delete orphans or triggers.

**Phase**: Phase 2 (Weeks 5-6)

---

## Redundant Counters (DENORMALIZATION)

### Problem: Dual Source of Truth

| Table | Denormalized Column | Source Table | Status |
|-------|---------------------|--------------|--------|
| `posts` | `like_count` | `likes` | ⚠️ Inconsistent |
| `posts` | `comment_count` | `comments` | ⚠️ Inconsistent |
| `posts` | `share_count` | `shares` | ⚠️ Inconsistent |
| `comments` | `reply_count` | `replies` | ⚠️ Inconsistent |
| `users` | `follower_count` | `follows` | ⚠️ Inconsistent |

**Risk**: Updates race condition; cache invalidation required on every like/comment/follow.

### Solution (Spec 007)

**Option A: Materialized Views (Read-Heavy Workload)**
```sql
CREATE MATERIALIZED VIEW mv_post_stats AS
  SELECT
    p.id,
    COUNT(DISTINCT l.id) as like_count,
    COUNT(DISTINCT c.id) as comment_count,
    COUNT(DISTINCT s.id) as share_count
  FROM posts p
  LEFT JOIN likes l ON l.post_id = p.id AND l.deleted_at IS NULL
  LEFT JOIN comments c ON c.post_id = p.id AND c.deleted_at IS NULL
  LEFT JOIN shares s ON s.post_id = p.id AND s.deleted_at IS NULL
  WHERE p.deleted_at IS NULL
  GROUP BY p.id;

-- Refresh on schedule:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_post_stats;
```

**Option B: Aggregate Table + Triggers (Write-Heavy)**
```sql
CREATE TABLE post_aggregates (
  post_id UUID PRIMARY KEY,
  like_count INT DEFAULT 0,
  comment_count INT DEFAULT 0,
  share_count INT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger on likes INSERT/DELETE updates post_aggregates
CREATE OR REPLACE FUNCTION update_post_like_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE post_aggregates SET like_count = like_count + (NEW IS NOT NULL)::int - (OLD IS NOT NULL)::int
  WHERE post_id = COALESCE(NEW.post_id, OLD.post_id);
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

**Decision**: Use **Option A (Materialized Views)** for simplicity and consistency.

**Phase**: Phase 3 (Weeks 7-8)

---

## Foreign Key & Index Strategy

### Current Issues

1. **Missing Composite Indexes** on hot paths:
   - `(user_id, created_at DESC)` on `posts`, `comments`, `messages`
   - `(conversation_id, created_at DESC)` on `messages`
   - `(post_id, deleted_at)` for filtering soft-deleted items

2. **Cascade Behavior Unclear**:
   - Some FKs use `ON DELETE CASCADE` (hard delete)
   - Should be `ON DELETE SET NULL` or `ON DELETE RESTRICT` (soft delete)

3. **Missing Indexes** on soft-delete predicates:
   - Queries filter `WHERE deleted_at IS NULL` - need partial indexes

### Solution (Spec 007)

**Add Partial Indexes** for soft-delete:
```sql
CREATE INDEX idx_posts_not_deleted ON posts (user_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_comments_not_deleted ON comments (post_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_messages_not_deleted ON messages (conversation_id, created_at DESC)
  WHERE deleted_at IS NULL;
```

**Disable Cascade Deletes** (use soft delete):
```sql
-- Before: ON DELETE CASCADE
-- After: ON DELETE RESTRICT + Application soft-delete logic
ALTER TABLE posts
  DROP CONSTRAINT posts_user_id_fkey,
  ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES users (id) ON DELETE RESTRICT;
```

**Phase**: Phase 4 (Weeks 9-10)

---

## Service Ownership Matrix

| Domain | Primary Owner | Query Patterns | Consistency Model |
|--------|---------------|-----------------|-------------------|
| **Auth** | auth-service | `SELECT * FROM users WHERE id = $1` | Strong (canonical) |
| **Social** | user-service | `SELECT DISTINCT(follower_id) FROM follows WHERE following_id = $1` | Eventual |
| **Posts** | content-service | `SELECT * FROM posts WHERE user_id = $1 ORDER BY created_at DESC` | Eventual (caching) |
| **Videos** | media-service | `SELECT * FROM videos WHERE id = $1` | Strong |
| **Messages** | messaging-service | `SELECT * FROM messages WHERE conversation_id = $1 ORDER BY created_at DESC` | Strong (within conv) |
| **Streaming** | streaming-service | `SELECT * FROM streams WHERE user_id = $1` | Eventual |

---

## Migration Path (Spec 007 Phases)

### Phase 0: Freeze & Inventory (Week 1-2) ✅
- [X] Add migration freeze note (`README.md`)
- [X] Produce data dictionary (THIS FILE)
- [ ] Create ownership matrix (NEXT)

### Phase 1: Users Consolidation (Week 3-4)
- [ ] Drop shadow `users` tables
- [ ] Create shims/views for backward compatibility
- [ ] Route all user queries through auth-service API

### Phase 2: Soft Delete Normalization (Week 5-6)
- [ ] Migrate all boolean flags to `deleted_at`
- [ ] Update application queries to use `WHERE deleted_at IS NULL`
- [ ] Add triggers for cascade-like behavior

### Phase 3: Redundancy Removal (Week 7-8)
- [ ] Create materialized views for counters
- [ ] Drop denormalized columns
- [ ] Schedule MV refresh

### Phase 4: FK & Index Strategy (Week 9-10)
- [ ] Add partial indexes
- [ ] Convert CASCADE deletes to RESTRICT
- [ ] Add application-level soft-delete logic

### Phase 5: Cutover & Validation (Week 11-12)
- [ ] Monitor perf during cutover
- [ ] Deprecate shims
- [ ] Document final schema

---

## File References

- **Migrations**: `backend/migrations/`
- **Spec**: `specs/007-p1-db-schema-consolidation/`
  - `spec.md` - Requirements
  - `plan.md` - Timeline
  - `tasks.md` - Detailed tasks
- **Auth Service**: `backend/auth-service/migrations/`
- **Messaging Service**: `backend/messaging-service/migrations/`
- **User Service**: `backend/user-service/migrations/`

---

## Next Steps

1. Create **ownership matrix** - map tables to services
2. Begin **Phase 1 migrations** - users consolidation
3. Deploy changes with **feature flags** to minimize risk

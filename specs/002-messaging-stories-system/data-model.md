# Phase 1: Data Model & Schema Design - Messaging + Stories System

**Date**: 2025-10-22 | **Status**: Complete | **Phase**: 1 (Design)

---

## Overview

This document defines the data model for Phase 7B Messaging + Stories System. All entities, relationships, and constraints are designed to support:
- 1M+ users with 100M+ daily active conversations
- 10B+ messages indexed and searchable
- 500M+ stories created daily with 24h expiration
- E2E encryption with deterministic message ordering
- 50,000+ concurrent WebSocket connections
- <200ms P95 latency for all operations

---

## Core Entities

### 1. User (Existing - Extended)

**Table**: `users`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | User identifier |
| username | VARCHAR(255) | UNIQUE, NOT NULL | Display name for @mentions |
| email | VARCHAR(255) | UNIQUE, NOT NULL | Contact email |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Account creation date |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last profile update |
| is_active | BOOLEAN | NOT NULL, DEFAULT true | Account status |
| followers_count | INTEGER | DEFAULT 0 | Cache of follower count |
| following_count | INTEGER | DEFAULT 0 | Cache of following count |

**Indexes**:
- `UNIQUE(username)` - For @mention resolution
- `UNIQUE(email)` - For login
- `created_at` - For user analytics

**Notes**:
- Extend existing users table with `followers_count`, `following_count` caches
- Update caches asynchronously on follow/unfollow

---

### 2. Conversation

**Table**: `conversations`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Conversation identifier |
| type | ENUM | NOT NULL ('direct'\|'group') | 1:1 or group chat |
| name | VARCHAR(255) | Nullable | Group name (NULL for 1:1) |
| description | TEXT | Nullable | Group description |
| created_by | UUID | NOT NULL, FK → users.id | Creator user ID |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Creation date |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Last activity |
| member_count | INTEGER | DEFAULT 0 | Cache of active members |
| last_message_id | UUID | Nullable, FK → messages.id | Most recent message |
| last_message_at | TIMESTAMP | Nullable | Most recent message time |
| is_archived | BOOLEAN | DEFAULT false | Soft delete for users |

**Indexes**:
- `created_by` - For user's conversations list
- `updated_at DESC` - For conversation feed sorting
- `type` - For filtering 1:1 vs group

**Constraints**:
- `CHECK (type = 'direct' AND name IS NULL) OR (type = 'group' AND name IS NOT NULL)` - Enforce naming consistency

**Notes**:
- `member_count` cached from conversation_members table
- `last_message_*` cached from messages table (denormalized for performance)

---

### 3. ConversationMember

**Table**: `conversation_members`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Primary key |
| conversation_id | UUID | NOT NULL, FK → conversations.id | Which conversation |
| user_id | UUID | NOT NULL, FK → users.id | Which member |
| role | ENUM | DEFAULT 'member' ('member'\|'admin') | Permission level |
| joined_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | When joined |
| last_read_at | TIMESTAMP | Nullable | Last message read marker |
| is_muted | BOOLEAN | DEFAULT false | Notification mute status |
| is_deleted | BOOLEAN | DEFAULT false | Soft delete (user left) |

**Indexes**:
- `UNIQUE(conversation_id, user_id)` - Prevent duplicates
- `(conversation_id, is_deleted)` - For active members list
- `(user_id, is_deleted)` - For user's conversations list
- `(user_id, last_read_at)` - For unread message count

**Constraints**:
- `CHECK (role IN ('member', 'admin'))` - Valid roles

**Notes**:
- `is_deleted = true` means user left but preserves message history
- `last_read_at` used for "unread count" badge
- `is_muted` prevents WebSocket notifications but keeps in conversation

---

### 4. Message

**Table**: `messages`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Message identifier |
| conversation_id | UUID | NOT NULL, FK → conversations.id | Which conversation |
| sender_id | UUID | NOT NULL, FK → users.id | Who sent it |
| content_encrypted | BYTEA | NOT NULL | Encrypted message content |
| content_nonce | BYTEA | NOT NULL | NaCl nonce (random, per-message) |
| encryption_version | INTEGER | DEFAULT 1 | Encryption algorithm version |
| type | ENUM | DEFAULT 'text' ('text'\|'image'\|'video'\|'file') | Message type |
| media_url | VARCHAR(1024) | Nullable | URL for image/video/file |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Send timestamp |
| edited_at | TIMESTAMP | Nullable | When last edited |
| deleted_at | TIMESTAMP | Nullable | When deleted (soft delete) |
| sequence_number | BIGSERIAL | NOT NULL | Per-conversation message order |
| idempotency_key | UUID | Nullable, UNIQUE | For offline queue deduplication |
| reaction_count | INTEGER | DEFAULT 0 | Cache of reaction count |

**Indexes**:
- `UNIQUE(conversation_id, sequence_number)` - Enforce ordering
- `(conversation_id, created_at DESC)` - For message history queries
- `(sender_id, created_at DESC)` - For user's message history
- `(created_at)` - For CDC to Elasticsearch
- `(conversation_id, deleted_at)` - For archive queries
- `UNIQUE(idempotency_key)` - For offline queue dedup (where idempotency_key IS NOT NULL)

**Constraints**:
- `CHECK (content_encrypted IS NOT NULL AND content_nonce IS NOT NULL)` - Require encryption
- `CHECK (LENGTH(content_nonce) = 24)` - NaCl nonce length
- `CHECK (deleted_at IS NULL OR edited_at IS NULL OR edited_at < deleted_at)` - Logical consistency
- `CHECK (media_url IS NULL OR type IN ('image', 'video', 'file'))` - Media validation

**Notes**:
- `content_encrypted`: Encrypted with recipient's public key (E2E)
- `content_nonce`: Random 24-byte nonce (prevents replay attacks)
- `sequence_number`: Auto-increment per conversation (enforces strict ordering)
- `idempotency_key`: For offline message queue deduplication
- `reaction_count`: Cached from message_reactions table
- `deleted_at IS NULL` means visible; `deleted_at IS NOT NULL` means soft-deleted

---

### 5. MessageReaction

**Table**: `message_reactions`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Reaction identifier |
| message_id | UUID | NOT NULL, FK → messages.id | Which message |
| user_id | UUID | NOT NULL, FK → users.id | Who reacted |
| emoji | VARCHAR(10) | NOT NULL | Emoji character |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | When reacted |

**Indexes**:
- `UNIQUE(message_id, user_id, emoji)` - Prevent duplicate reactions
- `(message_id)` - For reaction list queries
- `(user_id, created_at DESC)` - For user's reaction history

**Constraints**:
- `CHECK (emoji ~ '^[\p{Emoji}]$')` - Valid emoji validation

**Notes**:
- One emoji per user per message (update/delete existing)
- Emoji stored as single Unicode character (allows multi-byte)

---

### 6. Story

**Table**: `stories`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Story identifier |
| user_id | UUID | NOT NULL, FK → users.id | Story creator |
| content_type | ENUM | NOT NULL ('image'\|'video') | Media type |
| content_url | VARCHAR(1024) | NOT NULL | S3/CDN URL |
| content_size | INTEGER | NOT NULL | File size in bytes |
| caption | TEXT | Nullable | Optional caption text |
| privacy_level | ENUM | DEFAULT 'public' ('public'\|'followers'\|'close_friends') | Who can view |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Story creation time |
| expires_at | TIMESTAMP | NOT NULL | 24h expiration (created_at + 24h) |
| view_count | INTEGER | DEFAULT 0 | Cache of view count |
| is_expired | BOOLEAN | DEFAULT false | Soft flag for expiration |
| duration_seconds | INTEGER | Nullable | For videos: duration in seconds |

**Indexes**:
- `(user_id, created_at DESC)` - For user's story feed
- `(expires_at)` - For expiration cleanup job
- `(created_at DESC)` - For global story feed
- `(privacy_level, created_at DESC)` - For public stories feed

**Constraints**:
- `CHECK (created_at < expires_at)` - Expiration in future
- `CHECK (expires_at = created_at + INTERVAL '24 hours')` - Exactly 24h
- `CHECK (duration_seconds IS NULL OR content_type = 'video')` - Duration only for videos
- `CHECK (content_size > 0)` - Non-empty content

**Notes**:
- `is_expired`: Flag when expired (may be present until cleanup)
- `expires_at`: Exact expiration timestamp
- `view_count`: Cached from story_views table
- Cleanup job: Delete where `expires_at < NOW()` every 5 minutes
- Privacy: Stored in database (enforced on query-time)

---

### 7. StoryView

**Table**: `story_views`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | View record identifier |
| story_id | UUID | NOT NULL, FK → stories.id | Which story |
| viewer_id | UUID | NOT NULL, FK → users.id | Who viewed |
| viewed_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | When viewed |
| view_duration_seconds | INTEGER | Nullable | How long watched (for videos) |

**Indexes**:
- `UNIQUE(story_id, viewer_id)` - One view per user per story
- `(story_id)` - For view count queries
- `(viewer_id, viewed_at DESC)` - For user's viewing history

**Notes**:
- One view per user per story (update on re-view)
- Used for view count + analytics

---

### 8. CloseFriends

**Table**: `close_friends`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Primary key |
| user_id | UUID | NOT NULL, FK → users.id | User who maintains list |
| friend_id | UUID | NOT NULL, FK → users.id | Friend in close-friends |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | When added |

**Indexes**:
- `UNIQUE(user_id, friend_id)` - Prevent duplicates
- `(user_id)` - For user's close-friends list
- `(friend_id)` - For reverse lookups (who added me as close friend)

**Constraints**:
- `CHECK (user_id != friend_id)` - Cannot add self
- Max 100 close friends per user (enforced in application)

**Notes**:
- Separate from followers table (explicit relationship)
- Max 100 per user (for performance + UX)

---

### 9. Follower

**Table**: `followers`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Primary key |
| follower_id | UUID | NOT NULL, FK → users.id | Who follows |
| following_id | UUID | NOT NULL, FK → users.id | Who is followed |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | When followed |

**Indexes**:
- `UNIQUE(follower_id, following_id)` - Prevent duplicates
- `(follower_id)` - For user's following list
- `(following_id)` - For user's followers list

**Constraints**:
- `CHECK (follower_id != following_id)` - Cannot follow self

**Notes**:
- One-way relationship (A follows B, but B doesn't automatically follow A)
- Used for story privacy level "followers"

---

### 10. EncryptionKey

**Table**: `encryption_keys`

| Column | Type | Constraints | Purpose |
|--------|------|-------------|---------|
| id | UUID | PRIMARY KEY | Key identifier |
| conversation_id | UUID | NOT NULL, FK → conversations.id | Which conversation |
| key_material | BYTEA | NOT NULL | Encrypted key material |
| key_version | INTEGER | NOT NULL | Key rotation version |
| created_at | TIMESTAMP | NOT NULL | When generated |
| rotated_at | TIMESTAMP | Nullable | When rotated |
| is_active | BOOLEAN | DEFAULT true | Current active key |

**Indexes**:
- `(conversation_id, key_version DESC)` - For key retrieval
- `(conversation_id, is_active)` - For active key lookup

**Notes**:
- Symmetric key for conversation (shared by all members)
- Key rotation strategy: Phase 7C
- Phase 7B: Single key per conversation (static)

---

## Relationship Diagram

```
User (1) ──←── (many) ConversationMember ──→ (1) Conversation
  │                                                      │
  │                                                      │
  ├─ (many) Message ◄─────────────────────────────┤
  │          │
  │          └─ (many) MessageReaction
  │
  ├─ (many) Story
  │          │
  │          └─ (many) StoryView
  │
  ├─ (many) Followers
  │
  └─ (many) CloseFriends

Conversation (1) ─←── (1) EncryptionKey
```

---

## Data Volume & Partitioning Strategy

### Expected Data Scale (Year 1)

| Entity | Count | Storage | Notes |
|--------|-------|---------|-------|
| Users | 1M | 500 MB | User profiles |
| Conversations | 100M | 10 GB | Including archived |
| Messages | 10B | 500 GB | Encrypted content (~50 bytes average) |
| MessageReactions | 5B | 50 GB | Reaction tracking |
| Stories | 500M (daily) | 10 TB | Video/image storage on S3 |
| StoryViews | 5B | 50 GB | View tracking |
| **Total** | | **11 TB** | Excluding S3 media |

### Partitioning Strategy

**Messages Table**: Partition by conversation_id
- Reason: Most queries filtered by conversation
- Strategy: Range partition on created_at (monthly)
- Benefits: Faster queries, easier cleanup

```sql
CREATE TABLE messages (
  ...
) PARTITION BY RANGE (created_at);

CREATE TABLE messages_2025_10 PARTITION OF messages
  FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
```

**Stories Table**: Partition by expires_at
- Reason: Cleanup job targets expired stories
- Strategy: Range partition on expires_at (daily)
- Benefits: Fast deletion without scanning all stories

```sql
CREATE TABLE stories (
  ...
) PARTITION BY RANGE (expires_at);

CREATE TABLE stories_2025_10_22 PARTITION OF stories
  FOR VALUES FROM ('2025-10-22') TO ('2025-10-23');
```

**MessageReactions Table**: Partition by message_id hash
- Reason: Large table, avoid full table scans
- Strategy: Hash partition on message_id (16 partitions)
- Benefits: Parallel query execution

---

## Denormalization & Caching Strategy

### Denormalized Columns (Database)

| Column | Table | Purpose | Update Frequency |
|--------|-------|---------|-------------------|
| `conversation_members.member_count` | conversations | Performance: avoid COUNT query | On join/leave |
| `conversation.last_message_id` | conversations | Performance: recent message | After each message |
| `conversation.last_message_at` | conversations | For sorting conversations | After each message |
| `message.reaction_count` | messages | Avoid COUNT query | On reaction add/remove |
| `story.view_count` | stories | Avoid COUNT query | Async update (every 10 sec) |
| `users.followers_count` | users | For analytics | Async update |

### Cached Values (Redis)

| Key Pattern | TTL | Purpose | Size |
|-------------|-----|---------|------|
| `conversation:{id}:members` | 1 hour | Active members list | <10 KB |
| `story:{id}:views` | 24 hours (auto-expire) | Story view count | 10 bytes |
| `user:{id}:close_friends` | 1 hour | Close-friends list | 1-10 KB |
| `user:{id}:followers` | 1 hour | Followers list | 10-100 KB |
| `message:{id}:reactions` | None (expire with message) | Reaction counts by emoji | <1 KB |

---

## Transaction & Consistency Model

### Serialization Level

**DEFAULT**: Read Committed (PostgreSQL default)
- Sufficient for most operations
- Low overhead

**SERIALIZABLE** (when needed):
- Offline message deduplication (idempotency_key uniqueness)
- Story privacy enforcement (concurrent view updates)

### Idempotency

**Offline Message Dedup**:
```sql
INSERT INTO messages (...)
VALUES (...)
ON CONFLICT (idempotency_key) DO UPDATE SET ...;
```

**Reaction Duplicate Prevention**:
```sql
INSERT INTO message_reactions (...)
ON CONFLICT (message_id, user_id, emoji) DO UPDATE SET ...;
```

---

## Migration Path from Phase 7A

### Existing Infrastructure

Phase 7A provides:
- PostgreSQL with user profiles, social graph
- Redis for caching + real-time
- Elasticsearch for content search (optional)
- Kafka for event streaming

### Phase 7B Additions

1. **New tables**: Create 10 new tables (messages, stories, reactions, etc.)
2. **Schema changes**: Extend users, conversation_members tables
3. **Indexes**: Create performance-critical indexes
4. **Functions**: PostgreSQL triggers for update_at timestamps

---

## Validation & Constraints

### Application-Level Validations

| Constraint | Type | Validation |
|------------|------|-----------|
| Message length | MAX 10,000 chars | Enforce in API |
| Group member count | 3-500 members | CHECK in INSERT |
| Story size | MAX 100 MB | Check before upload |
| Close friends | MAX 100 | Enforce in INSERT |
| Emoji validation | Single character | Regex in CHECK |

### Database-Level Constraints

All constraints defined in SQL (CHECK, UNIQUE, FK) as shown in entity definitions above.

---

## Index Performance Impact

### Query Execution Times (Estimated - with indexes)

| Query | Indexes Used | Est. Time | Notes |
|-------|--------------|-----------|-------|
| GET /conversations/:id/messages | (conversation_id, created_at) | <100ms | Fetch 50 messages |
| GET /messages/search?q=hello | Elasticsearch mapping | <200ms | Full-text search |
| GET /stories/feed | (user_id, created_at) + privacy filter | <100ms | 50 stories |
| PUT /messages/:id/reactions | (message_id, user_id, emoji) | <50ms | Upsert reaction |
| DELETE stories (expired) | (expires_at) | <5s | Batch 10k stories |

---

## Data Governance

### Retention Policy

| Entity | Retention | Action |
|--------|-----------|--------|
| Messages | Indefinite | Archive to cold storage after 1 year |
| Stories | 24 hours | Auto-delete via scheduled job |
| MessageReactions | With message | Delete cascade |
| StoryViews | With story | Delete cascade |
| Followers | Indefinite | User can delete relationship |
| CloseFriends | Indefinite | User can delete relationship |
| EncryptionKeys | Indefinite | Rotate quarterly (Phase 7C) |

### Privacy & PII

- All user passwords: Hashed with bcrypt (existing)
- Message content: Encrypted E2E (cannot be accessed by server)
- User names: Plaintext (required for @mentions, searchable)
- Story metadata: Plaintext (required for privacy enforcement)

---

## Next Steps (Phase 1 Continuation)

1. ✅ **Data Model Complete** (this document)
2. ⏳ **API Contracts** (contracts/) - REST + WebSocket specs
3. ⏳ **Quickstart Guide** (quickstart.md) - Dev setup
4. ⏳ **Database Migrations** - SQL scripts for table creation
5. ⏳ **Agent Context Update** - Register technologies


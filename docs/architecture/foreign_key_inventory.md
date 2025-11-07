# Cross-Service Foreign Key Inventory

> **Created**: 2025-11-07
> **Status**: 🔴 Critical - Distributed Monolith Anti-Pattern
> **Related**: P0 Database Consolidation (spec005-spec007)

## Executive Summary
- **Total FK constraints**: 112 REFERENCES users(id)
- **Affected services**: messaging, content, streaming, stories, experiments
- **Critical issue**: Distributed monolith - all services coupled to auth-service database

## Key Migration Files Analysis

### 018_messaging_schema.sql
```sql
    conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'group')),
    name VARCHAR(255),
    created_by UUID NOT NULL REFERENCES users(id),
--
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
```

### 001_messaging_schema.sql (phase-7b)
```sql
    conversation_type VARCHAR(20) NOT NULL CHECK (conversation_type IN ('direct', 'group')),
    name VARCHAR(255),  -- Only for group conversations
    created_by UUID NOT NULL REFERENCES users(id),
--
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
```

### 019_stories_schema.sql
```sql
CREATE TABLE IF NOT EXISTS stories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--
CREATE TABLE IF NOT EXISTS story_views (
    story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--
-- 3) Close friends list (owner → friend)
CREATE TABLE IF NOT EXISTS story_close_friends (
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
```

### 003_posts_schema.sql
```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
```

### 052_add_post_share_and_bookmark.sql
```sql
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shared_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    share_via VARCHAR(50), -- 'direct_message', 'story', 'feed', 'external'
    shared_with_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
--
CREATE TABLE IF NOT EXISTS bookmarks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--
CREATE TABLE IF NOT EXISTS bookmark_collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
```

### 013_streaming_stream_table.sql
```sql
CREATE TABLE streams (
    stream_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    broadcaster_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
```

### 015_streaming_viewer_session_table.sql
```sql
CREATE TABLE viewer_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viewer_id UUID REFERENCES users(id) ON DELETE SET NULL,
```

### 033_experiments_schema.sql
```sql
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
--
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    experiment_id UUID NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
```

## Service-by-Service Impact

### messaging-service
**Tables with FK to users(id):**
- `conversations.created_by` → users(id)
- `conversation_participants.user_id` → users(id) ON DELETE CASCADE
- `messages.sender_id` → users(id)

**Impact:** Cannot deploy messaging-service independently without auth-service database access.

### content-service (posts, stories)
**Tables with FK to users(id):**
- `posts.user_id` → users(id) ON DELETE CASCADE
- `stories.user_id` → users(id) ON DELETE CASCADE
- `story_views.viewer_id` → users(id) ON DELETE CASCADE
- `story_close_friends.owner_id/friend_id` → users(id) ON DELETE CASCADE
- `post_shares.user_id/shared_with_user_id` → users(id)
- `bookmarks.user_id` → users(id) ON DELETE CASCADE
- `bookmark_collections.user_id` → users(id) ON DELETE CASCADE

**Impact:** Content creation/deletion tightly coupled to auth-service users table.

### streaming-service
**Tables with FK to users(id):**
- `streams.broadcaster_id` → users(id) ON DELETE CASCADE
- `viewer_sessions.viewer_id` → users(id) ON DELETE SET NULL

**Impact:** Live streaming features depend on auth-service database.

### experiments-service
**Tables with FK to users(id):**
- `experiments.created_by` → users(id) ON DELETE SET NULL
- `experiment_assignments.user_id` → users(id) ON DELETE CASCADE
- `experiment_events.user_id` → users(id) ON DELETE CASCADE

**Impact:** A/B testing platform coupled to auth-service.

## Remediation Plan (Task 4/4)

### Phase 1: Add gRPC Validation (Before FK Removal)
1. Implement `auth_client.user_exists(user_id)` in all services
2. Add validation before INSERT operations
3. Add circuit breaker + fallback mechanisms
4. Test with feature flags (validation parallel to FK)

### Phase 2: Remove Foreign Keys
For each service:
```sql
-- Example for messaging-service
ALTER TABLE conversations DROP CONSTRAINT conversations_created_by_fkey;
ALTER TABLE conversation_participants DROP CONSTRAINT conversation_participants_user_id_fkey;
ALTER TABLE messages DROP CONSTRAINT messages_sender_id_fkey;
```

### Phase 3: Application-Layer Validation
```rust
// Before insert
if !auth_client.user_exists(user_id).await? {
    return Err(AppError::Validation("User not found".into()));
}

// Insert without FK constraint
sqlx::query!(
    "INSERT INTO messages (sender_id, ...) VALUES ($1, ...)",
    user_id
).execute(&pool).await?;
```

### Phase 4: Eventual Consistency
- Use Kafka events for user deletion: `user_deleted` event
- Each service handles cleanup of its own orphaned records
- No cascading deletes across services

## Benefits After Remediation
✅ Independent service deployment
✅ Reduced blast radius (auth-service downtime doesn't block other services)
✅ Easier horizontal scaling
✅ True microservices architecture
✅ Simplified disaster recovery

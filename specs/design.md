# Social Platform Core - Design Document

**Feature**: Social Platform Core (Posts, Reels, Stories, Live, DM)
**Phase**: Phases 2-3
**Status**: Design Phase → Implementation Phase (72% complete)
**Architecture**: Monolithic Backend (Rust/Actix-web) → Microservices (future)
**Date**: 2025-10-21
**Last Updated**: 2025-10-21 (Code Audit Complete)

---

## 🔍 Implementation Status

**Audit Summary** (See CODE_IMPLEMENTATION_AUDIT.md for details):
- ✅ **Database schemas**: 85-90% complete (migrations exist)
- ✅ **Backend services**: 75-90% complete (business logic implemented)
- ❌ **REST API endpoints**: 30-60% complete (critical gaps in social graph)
- ❌ **Integration tests**: 35% complete (E2E flows missing)

**Critical Path**:
1. **THIS WEEK**: Create missing REST endpoints (handlers/social.rs) - 4 hours
2. **NEXT WEEK**: Add E2E integration tests - 8 hours
3. **WEEK 3**: Code quality refactoring to eliminate duplication - 56 hours

---

## Overview

Nova's design is centered on **relationships** as the primary data structure, with content forms (Posts, Reels, Stories, Live, DM) as expressions of those relationships. The architecture ensures that:

1. **Social Graph is the DNA** - Every feature is driven by user relationships (follow/block/mute)
2. **Unified Content Model** - All content types share common interactions (like, comment, share, save, tip)
3. **Real-Time First** - WebSocket broadcasts deliver social actions instantly (new follows, likes, comments, tips)
4. **Feed is the Funnel** - Discovery happens through ranked feeds that mix all content types
5. **Creator-First Monetization** - Creators earn through tips, subscriptions, and see unified analytics

---

## Architecture

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS Client (SwiftUI)                      │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS/JWT
┌──────────────────────────▼──────────────────────────────────────┐
│                    API Gateway Layer                             │
│  • Rate Limiting (100 req/min per user)                          │
│  • JWT Authentication                                            │
│  • Request Validation & Compression                              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│              User Service Monolith (Rust/Actix-web)              │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐   │
│  │ Auth Handlers  │  │ Feed Handlers  │  │ Post Handlers  │   │
│  ├────────────────┤  ├────────────────┤  ├────────────────┤   │
│  │ • Register     │  │ • Get Feed     │  │ • Create Post  │   │
│  │ • Login        │  │ • Invalidate   │  │ • Get Post     │   │
│  │ • Refresh JWT  │  │   Cache        │  │ • Delete Post  │   │
│  │ • 2FA/OAuth    │  │                │  │ • Like Post    │   │
│  └────────────────┘  └────────────────┘  └────────────────┘   │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐   │
│  │ Social Handlers│  │ Messaging      │  │ Streaming      │   │
│  ├────────────────┤  ├────────────────┤  ├────────────────┤   │
│  │ • Follow/Unf.  │  │ • Send Message │  │ • WebSocket    │   │
│  │ • Block/Mute   │  │ • Key Exchange │  │   Upgrades     │   │
│  │ • Get Follows  │  │ • Get Messages │  │ • Broadcast    │   │
│  │ • Recommend    │  │ • Mark Read    │  │   Updates      │   │
│  └────────────────┘  └────────────────┘  └────────────────┘   │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Shared Services Layer                      │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │ • FeedRankingService      - ClickHouse-based ranking   │   │
│  │ • MessageService          - E2E encryption & storage   │   │
│  │ • EventProducer           - Kafka event publishing     │   │
│  │ • StreamingHub (Actor)    - WebSocket broadcast hub    │   │
│  │ • S3ImageProcessor        - Async image transcoding    │   │
│  └─────────────────────────────────────────────────────────┘   │
└──────────────────────┬───────┬────────┬──────────────────────────┘
                       │       │        │
        ┌──────────────┘       │        └──────────────┐
        │                      │                       │
┌───────▼────────┐  ┌──────────▼────────┐  ┌──────────▼────────┐
│  PostgreSQL    │  │ ClickHouse       │  │  Redis            │
│  (OLTP Data)   │  │  (Analytics)     │  │  (Real-time)      │
│                │  │                  │  │                   │
│ • users        │  │ • events         │  │ • Feed Cache      │
│ • posts        │  │ • impressions    │  │ • Session Tokens  │
│ • follows      │  │ • user_journeys  │  │ • Rate Limits     │
│ • comments     │  │ • aggregations   │  │ • Viewer Counts   │
│ • likes        │  │                  │  │ • Trending Tags   │
│ • messages     │  │                  │  │                   │
└────────────────┘  └──────────────────┘  └───────────────────┘
        │                   ▲
        │                   │
┌───────▼───────────────────┴────────────────────────┐
│            Kafka Event Streaming                   │
│                                                    │
│  Topics:                                           │
│  • events.user (follows, unfollows, blocks)       │
│  • events.content (posts, reels, stories)         │
│  • events.engagement (likes, comments, shares)    │
│  • events.monetization (tips, subscriptions)      │
│  • cdc.* (PostgreSQL Change Data Capture)         │
└────────────────┬─────────────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼────────┐  ┌─────▼────────┐
│  CDC Consumer  │  │ Events       │
│  (PostgreSQL→  │  │ Consumer     │
│   Kafka→CH)    │  │ (Kafka→CH)   │
└────────────────┘  └──────────────┘

External Services:
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ AWS S3      │  │ CloudFront  │  │ Prometheus/ │
│ (Media)     │  │ (CDN)       │  │ Grafana     │
└─────────────┘  └─────────────┘  └─────────────┘
```

### Architectural Principles

**1. Relationship-Driven Design**
- Every user interaction flows through the social graph
- Follow relationship determines:
  - Who sees your content (followers can see your posts)
  - Who gets notified (followers notified when you go live)
  - Who you can tip/subscribe to (only following users)
  - Content visibility in feeds (followers-only content)

**2. Event-Driven Communication**
- All social actions (follows, likes, comments, tips) emit events to Kafka
- Events are consumed by:
  - Real-time subscribers (WebSocket Hub broadcasts changes)
  - Analytics processors (ClickHouse for trending/ranking)
  - Notification generators (DM to users about actions on their content)

**3. Unified Content Model**
- All content types (Posts, Reels, Stories, Live, DM) implement:
  - `IContent` interface: id, creator, visibility, created_at, updated_at
  - `IEngageable`: like, comment, share, save (where applicable)
  - `IMonetizable`: tip, subscription (Live + Posts + Reels support)
  - Stored in PostgreSQL with common metadata tables

**4. Real-Time Broadcast Pattern**
- WebSocket Hub manages per-stream connections
- Notifications pushed via Kafka Pub/Sub → Redis → WebSocket
- Fallback to polling for clients with unstable connections

**5. Monolith → Microservices Evolution Path**
- Current: Single `user-service` handles all features
- Phase 3: Split into: auth-service, feed-service, content-service, messaging-service
- Phase 4: Add dedicated streaming-service for RTMP ingestion
- Real service boundaries defined by: Data ownership, scaling needs, team org

---

## Components and Interfaces

### 1. Social Graph Component

**Responsibility**: Manage relationships and derive visibility rules

**Data Model**:
```rust
// Core relationship types
Follow {
  id: UUID,
  follower_id: UUID,
  following_id: UUID,
  created_at: DateTime,
}

Block {
  id: UUID,
  blocker_id: UUID,
  blocked_id: UUID,
  created_at: DateTime,
}

Mute {
  id: UUID,
  muter_id: UUID,
  muted_id: UUID,
  created_at: DateTime,
}
```

**Public Interfaces**:
```
POST   /api/v1/users/{id}/follow          → Follow a user
POST   /api/v1/users/{id}/unfollow        → Unfollow a user
POST   /api/v1/users/{id}/block           → Block a user
POST   /api/v1/users/{id}/unblock         → Unblock a user
POST   /api/v1/users/{id}/mute            → Mute a user
POST   /api/v1/users/{id}/unmute          → Unmute a user
GET    /api/v1/users/{id}/followers       → Get follower list
GET    /api/v1/users/{id}/following       → Get following list
GET    /api/v1/users/{id}/recommendations → Get recommended users
```

**Indexes** (PostgreSQL):
- `follows(follower_id, following_id)` - Query "who does user X follow"
- `follows(following_id, created_at DESC)` - Query "who follows user X, newest first"
- `blocks(blocker_id, blocked_id)` - Query "who has user X blocked"
- User denormalization: `users.follower_count`, `users.following_count` (updated via triggers)

**Visibility Rule**:
```
def can_see_content(viewer_id, content_creator_id, visibility):
  if viewer_id == content_creator_id:
    return True
  if is_blocked(viewer_id, content_creator_id):
    return False
  if visibility == PUBLIC:
    return True
  if visibility == FOLLOWERS_ONLY:
    return is_following(viewer_id, content_creator_id)
  if visibility == PRIVATE:
    return False
```

### 2. Unified Content Model Component

**Responsibility**: Provide common interface for all content types (Posts, Reels, Stories, Live, DM)

**Data Model**:
```rust
// Base content interface
trait Content {
  fn id(&self) -> UUID;
  fn creator_id(&self) -> UUID;
  fn visibility(&self) -> Visibility;
  fn created_at(&self) -> DateTime;
  fn engagement_stats(&self) -> EngagementStats;
}

// Specific implementations
Post {
  id: UUID,
  creator_id: UUID,
  caption: String,
  media: Vec<ImageRef>,
  visibility: Visibility,
  created_at: DateTime,
  engagement: EngagementStats,
}

Reel {
  id: UUID,
  creator_id: UUID,
  video: VideoRef,
  caption: String,
  visibility: Visibility,
  created_at: DateTime,
  engagement: EngagementStats,
  analytics: ReelAnalytics,
}

Story {
  id: UUID,
  creator_id: UUID,
  media: MediaRef,
  expires_at: DateTime,  // 24h from creation
  viewers: Vec<ViewerRecord>,
  engagement: EngagementStats,
}

Live {
  id: UUID,
  creator_id: UUID,
  stream_id: String,
  status: StreamStatus,  // starting, live, ended
  viewers: ViewerTracker,
  chat_messages: Vec<ChatMessage>,
  tips: Vec<TipTransaction>,
  engagement: EngagementStats,
}

DM {
  id: UUID,
  sender_id: UUID,
  recipient_id: UUID,
  encrypted_content: String,
  nonce: String,
  delivered: bool,
  read: bool,
  created_at: DateTime,
}

EngagementStats {
  like_count: u32,
  comment_count: u32,
  share_count: u32,
  save_count: u32,
  tip_total: Decimal,
  view_count: u32,
}
```

**Public Interfaces** (Per Content Type):
```
# Posts
POST   /api/v1/posts                      → Create post
GET    /api/v1/posts/{id}                 → Get post
DELETE /api/v1/posts/{id}                 → Delete post
POST   /api/v1/posts/{id}/like            → Like post
DELETE /api/v1/posts/{id}/like            → Unlike post
POST   /api/v1/posts/{id}/comment         → Add comment
POST   /api/v1/posts/{id}/share           → Share post
POST   /api/v1/posts/{id}/save            → Save post

# Reels (same + analytics)
GET    /api/v1/reels/{id}/analytics       → Get reel performance

# Stories (ephemeral)
POST   /api/v1/stories                    → Post story
GET    /api/v1/stories/{id}/viewers       → Who viewed your story
GET    /api/v1/stories/feed               → Get all stories from following

# Live (streams)
POST   /api/v1/live/start                 → Start live stream
GET    /api/v1/live/{stream_id}/status    → Get current stream status
POST   /api/v1/live/{stream_id}/comment   → Send comment during live
POST   /api/v1/live/{stream_id}/tip       → Send tip during live

# DM (direct messages)
POST   /api/v1/messages/send              → Send encrypted message
GET    /api/v1/messages/{id}              → Get message
```

### 3. Real-Time Interactions Component

**Responsibility**: Broadcast social actions instantly to affected users

**Event Types**:
```rust
enum SocialEvent {
  UserFollowed { follower_id, following_id },
  UserUnfollowed { follower_id, following_id },
  ContentLiked { user_id, content_id, content_type },
  ContentCommented { user_id, content_id, comment_id },
  LiveStarted { creator_id, stream_id },
  TipReceived { tipper_id, creator_id, amount },
  MessageReceived { sender_id, recipient_id, message_id },
}
```

**WebSocket Protocol**:
```json
// Client connects: GET /api/v1/ws/notifications
// Server sends initial state
{
  "event": "connected",
  "data": {
    "user_id": "uuid",
    "unread_notifications": 42
  }
}

// Real-time event broadcast
{
  "event": "user_followed",
  "data": {
    "follower_id": "uuid",
    "follower_name": "Alice",
    "follower_avatar_url": "...",
    "timestamp": "2025-10-21T10:30:45Z"
  }
}

{
  "event": "content_liked",
  "data": {
    "user_id": "uuid",
    "user_name": "Bob",
    "content_id": "uuid",
    "content_type": "post",
    "new_like_count": 42,
    "timestamp": "2025-10-21T10:30:45Z"
  }
}

{
  "event": "live_started",
  "data": {
    "creator_id": "uuid",
    "creator_name": "Creator",
    "stream_id": "uuid",
    "title": "Stream title",
    "thumbnail_url": "...",
    "timestamp": "2025-10-21T10:30:45Z"
  }
}
```

**Architecture**:
```
Event Producer (Handler Layer)
  ↓ (emits to Kafka)
Event Topic (Kafka)
  ↓ (consumed by)
Real-Time Subscriber (WebSocket Hub)
  ↓ (broadcasts to)
Connected Clients (WebSocket)
  + Redis Pub/Sub for distributed deployments
```

### 4. Feed & Discovery Component

**Responsibility**: Rank and mix all content types for personalized discovery

**Feed Ranking Algorithm**:
```
score(content, user) =
  freshness_signal(content.created_at) * 0.1 +
  relationship_signal(content.creator_id, user_id) * 0.3 +
  engagement_signal(content.likes, content.comments) * 0.3 +
  quality_signal(content.media_quality) * 0.1 +
  personalization_signal(user.interests, content.tags) * 0.2

where:
  freshness_signal = decay(now - created_at, half_life=6h)
  relationship_signal = 1.5x if following, 1.0x otherwise
  engagement_signal = (likes + comments*2) / (time_since_posted + 1)
  quality_signal = image_resolution * 0.8 + video_quality * 0.2
  personalization_signal = tfidf(user_tags, content_tags)
```

**Public Interfaces**:
```
GET    /api/v1/feed                       → Get personalized "For You" feed
  params: algo=ch|time, limit=20, cursor=...

GET    /api/v1/feed/following             → Get chronological following feed
  params: limit=20, cursor=...

GET    /api/v1/search                     → Search users/hashtags/content
  params: q=..., type=users|tags|posts, limit=20

GET    /api/v1/trending                   → Get trending content (last 24h)
  params: category=..., limit=20
```

**Data Flow**:
```
1. User requests: GET /api/v1/feed?algo=ch&limit=20
2. FeedRankingService queries:
   - ClickHouse: SELECT content_id, engagement FROM events WHERE timestamp > NOW() - 24h
   - Apply ranking formula
   - Fetch top 20 content from PostgreSQL
3. Filter by visibility rules (social graph)
4. Return mixed content (Posts + Reels + Stories + Lives)
5. Cache result in Redis with 60s TTL
```

### 5. Creator Monetization Component

**Responsibility**: Track tips, subscriptions, and provide analytics to creators

**Data Model**:
```rust
Tip {
  id: UUID,
  sender_id: UUID,
  receiver_id: UUID,
  amount: Decimal,
  content_id: UUID,  // What they tipped on (Post, Reel, Live)
  content_type: ContentType,
  created_at: DateTime,
}

Subscription {
  id: UUID,
  creator_id: UUID,
  subscriber_id: UUID,
  tier: SubscriptionTier,  // basic, premium, vip
  price_monthly: Decimal,
  starts_at: DateTime,
  expires_at: DateTime,
}

CreatorAnalytics {
  creator_id: UUID,
  period: DateRange,
  total_views: u64,
  total_engagement: u32,
  total_tips: Decimal,
  total_subscription_revenue: Decimal,
  top_content: Vec<ContentSummary>,
}
```

**Public Interfaces**:
```
POST   /api/v1/tips                       → Send tip to content
GET    /api/v1/me/analytics               → Get my analytics
GET    /api/v1/me/revenue                 → Get revenue breakdown
POST   /api/v1/subscriptions/{id}/cancel  → Cancel subscription
GET    /api/v1/subscriptions              → Get my subscriptions
```

### 6. Messaging Component

**Responsibility**: Secure direct messages with E2E encryption

**Data Model**:
```rust
PublicKey {
  user_id: UUID,
  public_key: String,  // PEM format
  registered_at: DateTime,
  rotation_interval_days: u32,
  next_rotation_at: DateTime,
}

KeyExchange {
  id: UUID,
  initiator_id: UUID,
  recipient_id: UUID,
  initiator_public_key: String,
  recipient_public_key: Option<String>,
  status: KeyExchangeStatus,  // pending, completed
  created_at: DateTime,
}

Message {
  id: UUID,
  sender_id: UUID,
  recipient_id: UUID,
  encrypted_content: String,  // NaCl encrypted
  nonce: String,
  sender_public_key: String,
  delivered: bool,
  read: bool,
  created_at: DateTime,
}
```

**Public Interfaces**:
```
POST   /api/v1/users/me/public-key       → Register/update public key
POST   /api/v1/key-exchange/initiate     → Start key exchange
POST   /api/v1/key-exchange/{id}/complete → Complete key exchange
POST   /api/v1/messages/send             → Send encrypted message
GET    /api/v1/messages/{id}             → Get message (decrypt client-side)
POST   /api/v1/messages/{id}/delivered   → Mark as delivered
POST   /api/v1/messages/{id}/read        → Mark as read
```

---

## Data Models

### PostgreSQL Schema (OLTP)

```sql
-- Already exist from Phase 1-2

users (id, username, email, password_hash, follower_count, following_count, ...)
sessions (id, user_id, token_hash, expires_at, ...)
posts (id, creator_id, caption, visibility, status, created_at, ...)
post_images (id, post_id, image_key, variant, width, height, ...)
likes (id, user_id, post_id, created_at, ...)
comments (id, post_id, user_id, content, parent_id, created_at, ...)
follows (id, follower_id, following_id, created_at, ...)

-- New tables for Phase 2-3

blocks (
  id UUID PRIMARY KEY,
  blocker_id UUID REFERENCES users(id),
  blocked_id UUID REFERENCES users(id),
  created_at TIMESTAMP,
  UNIQUE(blocker_id, blocked_id)
)

mutes (
  id UUID PRIMARY KEY,
  muter_id UUID REFERENCES users(id),
  muted_id UUID REFERENCES users(id),
  created_at TIMESTAMP,
  UNIQUE(muter_id, muted_id)
)

reels (
  id UUID PRIMARY KEY,
  creator_id UUID REFERENCES users(id),
  video_key STRING,
  caption TEXT,
  visibility ENUM,
  created_at TIMESTAMP,
  INDEX (creator_id),
  INDEX (created_at DESC)
)

stories (
  id UUID PRIMARY KEY,
  creator_id UUID REFERENCES users(id),
  media_key STRING,
  expires_at TIMESTAMP,
  created_at TIMESTAMP,
  INDEX (creator_id, expires_at)
)

story_viewers (
  id UUID PRIMARY KEY,
  story_id UUID REFERENCES stories(id),
  viewer_id UUID REFERENCES users(id),
  viewed_at TIMESTAMP,
  UNIQUE(story_id, viewer_id)
)

live_sessions (
  id UUID PRIMARY KEY,
  creator_id UUID REFERENCES users(id),
  stream_id STRING UNIQUE,
  status ENUM,  -- starting, live, ended
  started_at TIMESTAMP,
  ended_at TIMESTAMP,
  viewer_count INT,
  peak_viewers INT,
  total_tips DECIMAL,
  INDEX (creator_id, started_at DESC)
)

live_viewers (
  id UUID PRIMARY KEY,
  session_id UUID REFERENCES live_sessions(id),
  viewer_id UUID,
  joined_at TIMESTAMP,
  left_at TIMESTAMP
)

tips (
  id UUID PRIMARY KEY,
  sender_id UUID REFERENCES users(id),
  receiver_id UUID REFERENCES users(id),
  content_id UUID,
  content_type ENUM,  -- post, reel, live
  amount DECIMAL,
  created_at TIMESTAMP,
  INDEX (receiver_id, created_at DESC)
)

subscriptions (
  id UUID PRIMARY KEY,
  creator_id UUID REFERENCES users(id),
  subscriber_id UUID REFERENCES users(id),
  tier ENUM,  -- basic, premium, vip
  price_monthly DECIMAL,
  started_at TIMESTAMP,
  expires_at TIMESTAMP,
  UNIQUE(creator_id, subscriber_id)
)

public_keys (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  public_key TEXT,
  registered_at TIMESTAMP,
  rotation_interval_days INT DEFAULT 90,
  next_rotation_at TIMESTAMP
)

key_exchanges (
  id UUID PRIMARY KEY,
  initiator_id UUID REFERENCES users(id),
  recipient_id UUID REFERENCES users(id),
  initiator_public_key TEXT,
  recipient_public_key TEXT,
  status ENUM,  -- pending, completed
  created_at TIMESTAMP,
  INDEX (recipient_id, status)
)

messages (
  id UUID PRIMARY KEY,
  sender_id UUID REFERENCES users(id),
  recipient_id UUID REFERENCES users(id),
  encrypted_content TEXT,
  nonce TEXT,
  sender_public_key TEXT,
  delivered BOOLEAN DEFAULT FALSE,
  read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP,
  INDEX (recipient_id, created_at DESC)
)
```

### ClickHouse Schema (Analytics)

```sql
events (
  timestamp DateTime,
  event_type String,  -- user_followed, content_liked, etc
  actor_id UUID,
  target_user_id Nullable<UUID>,
  target_content_id Nullable<UUID>,
  content_type Nullable<String>,
  amount Nullable<Decimal>,
  PRIMARY KEY (timestamp, event_type, actor_id)
) ENGINE = MergeTree()

impressions (
  timestamp DateTime,
  viewer_id UUID,
  content_id UUID,
  content_type String,
  creator_id UUID,
  feed_algorithm String,
  position Int32,
  engagement_signal Decimal,
  PRIMARY KEY (timestamp, viewer_id)
) ENGINE = MergeTree()

user_journeys (
  user_id UUID,
  date Date,
  login_count Int32,
  content_created Int32,
  engagements Int32,
  tips_received Decimal,
  subscription_revenue Decimal,
  PRIMARY KEY (user_id, date)
) ENGINE = MergeTree()
```

### Redis Cache Schema

```
# Feed caching
feed:user:{user_id}:algo=ch          → JSON array of 20 feed items + cursor
feed:user:{user_id}:algo=time        → JSON array of following feed
feed:trending:24h                    → JSON array of trending content

# Real-time tracking
viewers:{stream_id}                  → SET of currently connected viewer UUIDs
viewer_count:{stream_id}             → INT counter
peak_viewers:{stream_id}             → INT counter

# Session management
session:{session_hash}               → JSON user session data
refresh_token:{token_hash}           → user_id (fast lookup)

# Rate limiting
ratelimit:{user_id}:requests         → INT (sliding window counter)
ratelimit:{ip}:requests              → INT (sliding window counter)

# Trending calculation
trending:posts:24h                   → SORTED SET (score=engagement)
trending:tags:24h                    → SORTED SET (score=mention_count)
```

---

## Error Handling

### Error Classification

**1. Validation Errors (400 Bad Request)**
```rust
InvalidEmail
InvalidUsername
ContentTooLong
InvalidVisibility
DuplicateFollow  // Cannot follow twice
SelfFollow       // Cannot follow yourself
```

**2. Authentication Errors (401 Unauthorized)**
```rust
InvalidCredentials
TokenExpired
InvalidToken
MissingAuthHeader
```

**3. Permission Errors (403 Forbidden)**
```rust
NotContentOwner       // Cannot delete another user's post
NotFollowing          // Cannot access followers-only content
UserBlocked           // Blocked user trying to interact
RateLimitExceeded
```

**4. Not Found Errors (404 Not Found)**
```rust
UserNotFound
ContentNotFound
KeyExchangeNotFound
PublicKeyNotFound
```

**5. Conflict Errors (409 Conflict)**
```rust
ContentAlreadyDeleted
KeyExchangeAlreadyCompleted
SubscriptionAlreadyActive
```

**6. Server Errors (500 Internal Server Error)**
```rust
DatabaseError
EncryptionError
StorageError
KafkaPublishError
```

### Error Response Format

```json
{
  "error": {
    "code": "INVALID_EMAIL",
    "message": "Email format is invalid",
    "details": {
      "field": "email",
      "value": "invalid.email"
    }
  },
  "request_id": "req_123abc",
  "timestamp": "2025-10-21T10:30:45Z"
}
```

### Retry Strategy

**Idempotent Operations** (safe to retry):
- GET requests → always safe
- POST with idempotency_key → server deduplicates
- DELETE requests → safe (deleting deleted resource = 404)

**Non-Idempotent Operations** (need care):
- Tips → stored with unique ID, retry is safe
- Follows → UNIQUE constraint prevents double-follow
- Messages → stored with unique ID before sending

---

## Testing Strategy

### Unit Testing

**Social Graph Tests**:
```rust
#[test]
fn test_cannot_follow_self()
fn test_cannot_block_self()
fn test_follow_then_unfollow_is_consistent()
fn test_blocked_user_cannot_see_content()
fn test_muted_user_content_hidden_but_relationship_exists()
fn test_recommendation_excludes_following_and_blocked()
```

**Content Model Tests**:
```rust
#[test]
fn test_post_visibility_public_visible_to_all()
fn test_post_visibility_followers_only_visible_to_followers()
fn test_post_visibility_private_only_visible_to_self()
fn test_like_idempotency_liking_twice_is_one_like()
fn test_unlike_removes_like()
fn test_comment_threading_supports_replies()
```

**Feed Ranking Tests**:
```rust
#[test]
fn test_feed_score_recency_factor()
fn test_feed_score_relationship_factor()
fn test_feed_score_engagement_factor()
fn test_feed_mixed_content_types()
fn test_feed_cursor_pagination_consistency()
```

**Messaging Tests**:
```rust
#[test]
fn test_public_key_registration()
fn test_key_exchange_protocol()
fn test_message_encryption_decryption()
fn test_message_delivery_status()
```

### Integration Testing

**Social Workflow**:
```
1. Alice creates account
2. Alice follows Bob
3. Bob creates post
4. Alice sees post in feed
5. Alice likes post (Bob notified via WebSocket)
6. Alice comments on post (Bob + followers notified)
7. Alice tips post (transaction recorded)
8. Check Bob's analytics shows all activity
```

**Messaging Workflow**:
```
1. Alice registers public key
2. Alice initiates key exchange with Bob
3. Bob completes key exchange
4. Alice sends encrypted message
5. Bob receives and decrypts
6. Verify E2E: server cannot read message
```

**Feed Ranking Test**:
```
1. Create 100 posts from various creators
2. Request feed as different users
3. Verify:
   - Each user gets personalized ranking
   - Recent posts ranked higher
   - Posts from followed users ranked higher
   - Blocked/muted content not shown
```

### Load Testing

**Concurrent User Load**:
- 10k concurrent WebSocket connections (viewer count broadcasts)
- 1000 feed requests per second
- 500 posts created per second (with image processing)
- Verify: p95 latency < 200ms, no message loss

---

## Implementation Phases

### Phase 2: Foundation (6 weeks)
- Social Graph (follows, blocks, mutes)
- Unified Content Model (Posts, Reels, Stories stored)
- Real-Time WebSocket Layer (viewer count, notifications)
- Feed Ranking Service (ClickHouse-based algorithm)

### Phase 3: Expansion (4 weeks)
- Creator Monetization (tips, subscriptions, analytics)
- Content Safety & Moderation (user reports, appeals)
- Feed Discovery (search, trending, discovery page)
- Messaging refinement (key management, delivery guarantees)

### Phase 4+: Optimization
- Microservices split (if needed for scale)
- Advanced recommendation algorithms
- Content moderation automation
- Live streaming quality optimization

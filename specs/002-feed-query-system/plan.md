# Implementation Plan: 首页动态 Feed 显示系统

**Feature Branch**: `002-feed-query-system`
**Status**: PLANNING
**Prepared**: 2025-10-18

## Phase 0: Technical Context & Research

### Technology Stack

- **Backend**: Rust + Actix-web (async)
- **Database**: PostgreSQL with advanced query patterns
- **Query Optimization**: Cursor-based pagination, composite indexes
- **Caching Layer**: Redis (optional, for hot feed caching)
- **Authentication**: JWT from 001-user-auth

### Key Architecture Decisions

1. **Cursor-based Pagination**: Use `(post.id, post.created_at)` as cursor for stable pagination even during concurrent updates
2. **Denormalized Counts**: Store like_count and comment_count directly on Post (updated atomically by Like/Comment systems)
3. **No Algorithm in Phase 1**: Feed is purely temporal (newest first), no ML recommendations
4. **Partial User Data**: Include user info inline with posts (username, avatar) to avoid N+1 queries

### Critical Dependencies

- **User Authentication** (001-user-auth): Get authenticated user_id
- **User Follow System** (004): Query all users followed by authenticated user
- **Post Publishing System** (001): Query posts from database
- **Like/Comment System** (003): Like/comment counts included in response

### Integration Points

- **Upstream**: User auth, follow relationships, post data
- **Downstream**: Like/Comment system uses same posts
- **Cross-cutting**: User search (006) may surface follow recommendations

### Database Requirements

- Index on `(user_id, created_at DESC)` for efficient post querying
- Denormalized like_count, comment_count on Post table
- Is_liked flag computed by joining Like records (or cached in Redis)

## Phase 1: Data Model & API Design

### Data Model

**Feed Query Input**:
```
user_id (UUID, from JWT)
limit (Int, default 20, max 100)
cursor? (String, from previous response for pagination)
```

**Feed Query Output** (cached by cursor):
```
posts: [
  {
    id: UUID,
    user: {
      id: UUID,
      username: String,
      avatar_url: String
    },
    image_url: String (CDN),
    thumbnail_url: String (CDN),
    caption: String,
    created_at: DateTime,
    like_count: Int,
    comment_count: Int,
    is_liked: Boolean (is current user's like)
  }
],
next_cursor?: String (for pagination)
```

### API Contracts

**1. Get Feed**
```
GET /api/v1/feed?limit=20&cursor={cursor}
Header: Authorization: Bearer {token}
Response (200): {
  posts: [
    {
      id: UUID,
      user: { id, username, avatar_url },
      image_url, medium_url, thumbnail_url,
      caption, created_at,
      like_count, comment_count,
      is_liked: Boolean
    }
  ],
  next_cursor: "base64_encoded_cursor"
}
Response (200, empty): {
  posts: [],
  next_cursor: null
}
Errors:
  - 401: Unauthorized
  - 400: Invalid cursor or limit
```

## Phase 2: Implementation Strategy

### Stage 1: Core Feed Query (Week 1)

1. **Follow List Query**
   - Query all follows where user_id = authenticated_user_id
   - Extract list of following_user_ids
   - Handle empty follow list gracefully

2. **Feed Query Implementation**
   - Query posts where user_id IN (following_ids) AND status = PUBLISHED
   - Order by created_at DESC
   - Include user data via JOIN
   - Include like_count, comment_count
   - Limit to 20 by default

3. **Is_liked Flag Computation**
   - LEFT JOIN like records where user_id = authenticated user
   - Include is_liked boolean in result

### Stage 2: Pagination & Performance (Week 2)

1. **Cursor-based Pagination**
   - Encode (post_id, created_at) as cursor
   - Decode cursor for next query
   - Query posts created_at < cursor_time AND post_id < cursor_id

2. **Index Optimization**
   - Create composite index (user_id, created_at DESC)
   - Add index on created_at for timeline queries
   - Test query plans with EXPLAIN

3. **Performance Testing**
   - Load test with 100k followers
   - Verify queries complete < 500ms
   - Monitor N+1 query issues

### Stage 3: Pull-to-refresh & Edge Cases (Week 3)

1. **Refresh Mechanism**
   - Use created_at as refresh marker
   - Query posts newer than refresh time
   - Prepend to existing feed

2. **Edge Cases**
   - Empty follow list → return empty posts
   - Deleted users → exclude their posts automatically
   - Deleted posts → exclude from feed
   - User unfollows → posts disappear on next refresh

3. **Testing**
   - Test with users following many people
   - Test concurrent follow/unfollow during feed load
   - Test eventual consistency of follow relationships

## Constitution Check

### Query Efficiency Gates

- [ ] Single query to follow table (not N+1) ✅
- [ ] Single query to posts with all needed data ✅
- [ ] Pagination is stateless and resumable ✅
- [ ] No full table scans (indexed queries only) ✅

### Consistency Guarantees

- [ ] Feed reflects current follow status ✅
- [ ] Pagination guarantees no duplicates ✅
- [ ] Deletion cascading handled properly ✅

### API Contract Validation

- [ ] Response includes all required fields ✅
- [ ] Pagination token is stateless ✅
- [ ] Error responses are consistent ✅

## Artifact Output

**Generated Files**:
- `/specs/002-feed-query-system/plan.md` (this file)
- `/src/models/feed.rs` - Feed query structs
- `/src/handlers/feed.rs` - Feed API endpoints
- `/src/services/feed_service.rs` - Feed query logic
- `/src/db/queries/feed.sql` - Raw SQL queries (validated by sqlx)
- `/tests/integration/feed_tests.rs` - Integration tests

**Next Phase**: Implementation execution via `/speckit.tasks`

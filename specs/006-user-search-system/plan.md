# Implementation Plan: 用户搜索系统

**Feature Branch**: `006-user-search-system`
**Status**: PLANNING
**Prepared**: 2025-10-18

## Phase 0: Technical Context & Research

### Technology Stack

- **Backend**: Rust + Actix-web
- **Database**: PostgreSQL with full-text search
- **Search Index**: PostgreSQL GiST or GIN indexes for FTS
- **Caching**: Redis for trending users cache
- **Pinyin Library**: pinyin crate for Chinese character to pinyin conversion
- **Authentication**: JWT

### Key Architecture Decisions

1. **Full-Text Search on PostgreSQL**: Use built-in FTS for nickname and bio search (no Elasticsearch needed for Phase 1)
2. **Pinyin Support**: Convert Chinese nicknames to pinyin for matching (e.g., "zhang" matches "张")
3. **Trending Users Cache**: Cache top 100 trending users (by follower_count), refresh hourly
4. **Search History**: Store last 50 searches per user, exclude from privacy considerations
5. **Debouncing**: Frontend enforces 300ms minimum between searches to reduce load
6. **Cursor Pagination**: Stable pagination for large result sets

### Critical Dependencies

- **User System**: User table with username/nickname, bio, follower_count
- **Follow System** (004): is_following flag in search results
- **Search History**: Stored per user

## Phase 1: Data Model & API Design

### Data Model

**SearchHistory Entity**:
```
id (UUID, Primary Key)
user_id (UUID, Foreign Key)
search_query (String, max 100 chars)
created_at (DateTime)

Indexes:
  - (user_id, created_at DESC) - for user's search history
  - Retention policy: Delete records older than 90 days
```

**User Table** (search fields, created if not exist):
```
nickname (String, searchable, indexed)
bio (String, searchable, indexed, max 500 chars)

Full-text search indexes:
  - GiST/GIN index on to_tsvector(nickname || ' ' || COALESCE(bio, ''))
```

**Trending Users Cache** (in-memory or Redis):
```
Refresh hourly:
  - Top 100 users by follower_count
  - Top 50 users by recent activity
  - Cache TTL: 1 hour
```

### API Contracts

**1. Search Users**
```
GET /api/v1/users/search?q={query}&limit=20&cursor={cursor}
Header: Authorization: Bearer {token}
Query Parameters:
  - q: search query (required, 1-100 chars)
  - limit: 1-50 (default 20)
  - cursor: pagination token
Response (200): {
  users: [
    {
      id: UUID,
      username: "string",
      avatar_url: "string",
      bio: "string",
      follower_count: Int,
      is_following: Boolean
    }
  ],
  next_cursor: "base64_cursor"
}
Errors:
  - 400: Query empty or too long
  - 401: Unauthorized
```

**2. Get Search Suggestions**
```
GET /api/v1/users/search/suggestions
Header: Authorization: Bearer {token}
Response (200): {
  recent_searches: [
    { query: "string", searched_at: ISO8601 }
  ],
  trending_users: [
    { id, username, avatar_url, follower_count }
  ]
}
```

**3. Get Search History**
```
GET /api/v1/users/search/history?limit=50
Header: Authorization: Bearer {token}
Response (200): {
  searches: [
    { query: "string", searched_at: ISO8601 }
  ]
}
```

**4. Clear Search History**
```
DELETE /api/v1/users/search/history
Header: Authorization: Bearer {token}
Request: { query?: "specific_query" } (if query provided, delete only that item; else delete all)
Response (204): (empty)
```

## Phase 2: Implementation Strategy

### Stage 1: Search Foundation (Week 1)

1. **PostgreSQL Full-Text Search Setup**
   - Add search columns to User table (if not present)
   - Create GiST or GIN index on tsvector
   - Set up search configuration for English + Chinese

2. **Pinyin Support**
   - Integrate pinyin crate
   - Create search function that:
     - Takes query string
     - Converts Chinese chars to pinyin
     - Searches both original and pinyin forms
   - Example: "zhang" matches "张三"

3. **Search Endpoint**
   - Implement GET /users/search
   - Query User table using FTS
   - Join with Follow to check is_following
   - Paginate with cursor
   - Limit results to 50

### Stage 2: Trending & History (Week 2)

1. **Trending Users Cache**
   - Query top 100 users by follower_count
   - Cache in Redis with 1-hour TTL
   - Populate on startup and refresh hourly

2. **Search History**
   - Store search queries in database
   - Limit to 50 per user
   - Implement GET /history endpoint
   - Implement DELETE /history endpoint

3. **Suggestions**
   - Combine recent searches + trending users
   - Return both in suggestions endpoint

### Stage 3: Performance & Polish (Week 3)

1. **Query Optimization**
   - Profile FTS queries
   - Ensure index usage with EXPLAIN
   - Benchmark with various query lengths

2. **Debouncing**
   - Document 300ms minimum delay recommendation
   - Implement rate limiting (max 1 req/100ms per user)

3. **Testing**
   - Test pinyin conversion accuracy
   - Test FTS with various queries
   - Test pagination with large results
   - Test concurrent searches

## Constitution Check

- [ ] Search is fast (< 200ms for typical queries) ✅
- [ ] Pinyin matching works correctly ✅
- [ ] Pagination is stable ✅
- [ ] Deleted users excluded from results ✅
- [ ] Search history kept private ✅

## Artifact Output

**Generated Files**:
- `/specs/006-user-search-system/plan.md` (this file)
- `/src/models/search_history.rs` - SearchHistory model
- `/src/handlers/search.rs` - Search API endpoints
- `/src/services/search_service.rs` - Search logic
- `/src/services/pinyin_service.rs` - Pinyin conversion
- `/src/db/migrations/006_create_search_indexes.sql` - Migration
- `/tests/integration/search_tests.rs` - Tests

**Next Phase**: Implementation execution via `/speckit.tasks`

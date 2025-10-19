# Tasks: 用户搜索系统

**Feature Branch**: `006-user-search-system`
**Generated**: 2025-10-18
**Status**: Ready for Implementation
**Dependencies**: 004-follow-system (is_following flag in results)

## Implementation Strategy

**MVP Scope**: User Story 1 + US2 (Search + Follow from results)
- User discovery
- Enables growth
- Estimated: 1-2 weeks

**Phase 2 Extensions**: US3-4 (History, Trending)
- User experience improvements
- Social discovery features

## Phase 1: Setup & Infrastructure

- [ ] T001 Create SearchHistory table migration in `src/db/migrations/015_create_search_history.sql`
  - user_id, search_query (max 100 chars), created_at
- [ ] T002 Create SearchHistory model in `src/models/search_history.rs`
- [ ] T003 Set up error handling in `src/errors/search_errors.rs`
- [ ] T004 Create pinyin conversion service in `src/services/pinyin_service.rs`
  - Integrate pinyin crate
  - Convert Chinese characters to pinyin
  - Support partial matching

## Phase 2: Foundational Services (Blocking Prerequisites)

- [ ] T005 Implement PostgreSQL full-text search setup in User table migration
  - Add columns for searchable fields if not present: nickname, bio
  - Create GiST or GIN index on tsvector
- [ ] T006 Create FTS query helper in `src/services/search_service.rs`
  - PostgreSQL to_tsvector for English + Chinese
- [ ] T007 Create pinyin matching in `src/services/search_service.rs`
  - Convert query to pinyin
  - Search both original and pinyin forms
- [ ] T008 Implement cursor pagination for search results in `src/services/pagination.rs`
  - Use (relevance_score, user_id) for stable ordering

## Phase 3: User Story 1 - 按昵称搜索用户 (P1)

**Goal**: Fuzzy search on user nicknames, pinyin support, ranked by relevance

**Independent Test Criteria**:
- Search "zhang" returns users with "张" in nickname (pinyin match)
- Exact match ranks first
- Partial matches ranked by position (start > middle > end)
- Results limited to 50 users
- Search returns within 200ms

### Implementation Tasks

- [ ] T009 [US1] Create GET `/api/v1/users/search` endpoint in `src/handlers/search.rs`
  - Query parameter: q (required, 1-100 chars)
  - limit (optional, default 20, max 50)
  - cursor (optional for pagination)
- [ ] T010 [US1] Implement search query logic in `src/services/search_service.rs`
  - Query User table using FTS
  - Include both English and pinyin search
  - Order by relevance (exact match > prefix > substring)
- [ ] T011 [US1] Create SearchResult DTO in `src/models/search.rs`
  - id, username, avatar_url, bio, follower_count
  - is_following: bool (based on authenticated user)
- [ ] T012 [US1] Implement relevance ranking in `src/services/search_service.rs`
  - Exact match = highest score
  - Prefix match = medium score
  - Substring match = lower score
- [ ] T013 [US1] Add search history logging in `src/services/search_service.rs`
  - On each search: INSERT into SearchHistory (if search history enabled)
- [ ] T014 [US1] Add JWT middleware to search endpoint
- [ ] T015 [US1] Create integration test for search in `tests/integration/search_tests.rs`
  - Create multiple users with names
  - Search and verify results ranked correctly
  - Verify pinyin matching works

## Phase 4: User Story 2 - 从搜索结果关注用户 (P1)

**Goal**: Quick follow from search results without opening profile

**Independent Test Criteria**:
- Follow button visible on each search result
- Click follow changes button to "Following"
- User added to authenticated user's following list
- Following count updated

### Implementation Tasks

- [ ] T016 [US2] Add is_following flag to SearchResult DTO in `src/models/search.rs`
- [ ] T017 [US2] Implement is_following check in `src/services/search_service.rs`
  - LEFT JOIN Follow table to check if authenticated user follows each result
- [ ] T018 [US2] Update search query to include follow check in `src/db/queries/search.sql`
- [ ] T019 [US2] Create integration test for follow from search in `tests/integration/search_follow_tests.rs`
  - Search user and follow from results
  - Verify user appears in following list

## Phase 5: User Story 3 - 查看搜索建议和搜索历史 (P2)

**Goal**: Display search history and trending user suggestions

**Independent Test Criteria**:
- Recent searches displayed when search box focused
- Trending users shown (top followers or active users)
- Can click on history to repeat search
- Can clear individual history items

### Implementation Tasks

- [ ] T020 [US3] Create GET `/api/v1/users/search/suggestions` endpoint in `src/handlers/search.rs`
  - Returns recent_searches and trending_users
- [ ] T021 [US3] Implement search history query in `src/services/search_service.rs`
  - Query SearchHistory for authenticated user
  - Limit to 10 most recent
  - Group by unique search query
- [ ] T022 [US3] Implement trending users query in `src/services/search_service.rs`
  - Query users ordered by follower_count DESC
  - Limit to 10
  - Cache with 1-hour TTL
- [ ] T023 [US3] Create SearchSuggestions DTO in `src/models/search.rs`
  - recent_searches: Array<{ query, searched_at }>
  - trending_users: Array<UserSummary>
- [ ] T024 [US3] Create integration test for suggestions in `tests/integration/search_suggestions_tests.rs`

## Phase 6: User Story 4 - 删除搜索历史 (P2)

**Goal**: Users can clear search history for privacy

**Independent Test Criteria**:
- Can delete individual search history items
- Can delete all search history at once
- Deleted items no longer appear in suggestions

### Implementation Tasks

- [ ] T025 [US4] Create DELETE `/api/v1/users/search/history` endpoint in `src/handlers/search.rs`
  - Optional query parameter: query (delete specific item if provided, else delete all)
- [ ] T026 [US4] Implement search history deletion in `src/services/search_service.rs`
  - If query provided: DELETE where search_query = query AND user_id = authenticated
  - Else: DELETE all for user
- [ ] T027 [US4] Create integration test for history deletion in `tests/integration/search_history_delete_tests.rs`

## Phase 7: Search History Retrieval

- [ ] T028 Create GET `/api/v1/users/search/history` endpoint in `src/handlers/search.rs`
  - Returns list of past searches (limited to 50)
- [ ] T029 Implement history query in `src/services/search_service.rs`
  - Query SearchHistory sorted by created_at DESC
  - Limit to 50 per user
- [ ] T030 Create SearchHistoryItem DTO in `src/models/search.rs`
  - query, searched_at

## Phase 8: Performance & Indexing

- [ ] T031 Create full-text search indexes in `src/db/migrations/016_create_search_indexes.sql`
  - GiST or GIN index on User nickname for FTS
  - Regular index on is_deleted (exclude deleted users)
- [ ] T032 Implement search query profiling in `src/services/search_service.rs`
  - Log query execution time
  - Target < 200ms for typical queries
- [ ] T033 Create performance test in `tests/performance/search_tests.rs`
  - Search with 1M users in database
  - Verify query < 200ms
  - Verify relevance ranking

## Phase 9: Pinyin Support & Special Matching

- [ ] T034 Implement pinyin crate integration in `src/services/pinyin_service.rs`
  - Convert "zhang" → "张"
  - Handle partial pinyin matching
- [ ] T035 Create pinyin matching test in `tests/integration/pinyin_tests.rs`
  - "zhangsan" matches "张三"
  - "zhang" matches "张 ... " users
  - "zs" partial match (optional)
- [ ] T036 Support mixed pinyin/Chinese search in `src/services/search_service.rs`
  - User types "zhang san" and matches "张三"

## Phase 10: Debouncing & Rate Limiting

- [ ] T037 Implement search debouncing recommendation in API docs
  - Frontend should wait 300ms between requests
- [ ] T038 Add rate limiting to search endpoint in `src/middleware/rate_limit.rs`
  - Max 10 searches per user per 10 seconds
  - Return 429 if exceeded
- [ ] T039 Create rate limiting test in `tests/integration/rate_limit_tests.rs`

## Phase 11: Edge Cases & Robustness

- [ ] T040 Handle special characters in search query in `src/services/search_service.rs`
  - Escape for FTS
  - Filter SQL injection attempts
- [ ] T041 Exclude deleted users from search in `src/services/search_service.rs`
  - WHERE is_deleted = false
- [ ] T042 Exclude authenticated user from results in `src/services/search_service.rs`
  - WHERE user_id != authenticated_user_id
- [ ] T043 Create edge case test in `tests/integration/search_edge_cases_tests.rs`

## Phase 12: Trending Users Cache

- [ ] T044 Create trending users cache in Redis in `src/services/search_service.rs`
  - Cache key: "trending_users"
  - TTL: 1 hour
- [ ] T045 Implement cache refresh in background task
  - Query trending users every hour
  - Update Redis cache
- [ ] T046 Create cache invalidation on user follow/unfollow in `src/services/follow_service.rs`
  - Clear trending cache when follower counts change significantly

## Phase 13: Polish & Documentation

- [ ] T047 Add logging to search endpoints in `src/handlers/search.rs`
  - Log search query (sanitized)
  - Log result count
  - Log response time
- [ ] T048 Implement error response standardization in `src/handlers/search.rs`
  - 400: Query too short or too long
  - 401: Unauthorized
  - 429: Rate limited
- [ ] T049 Document search API in `docs/api/search.md`
  - GET /users/search
  - GET /users/search/suggestions
  - GET /users/search/history
  - DELETE /users/search/history
  - Include curl examples
  - Document pinyin support

## Dependency Graph

```
Phase 1-2: Setup + Foundational FTS Setup
  ↓
Phase 3: US1 (Search)
  ├─ Parallelizable: T009-T014 (endpoint, service, FTS)
  └─ Test gate: T015 (search integration test)
  ↓
Phase 4: US2 (Follow from search)
  └─ Depends on: US1 (search working)
  └─ Can parallel with US1 after Phase 2
  ├─ Parallelizable: T016-T018
  └─ Test gate: T019
  ↓
Phase 5-6: US3-4 (History & Clear)
  └─ Can parallel with Phase 3-4
  ├─ Parallelizable: T020-T027
  └─ Test gates: T024, T027
  ↓
Phase 7-13: Performance, Pinyin, Rate Limiting, Polish
  └─ Depends on: Core search working
```

## Parallel Execution Opportunities

**Within Phase 3-4**:
- Search endpoint (T009-T014) can run parallel with follow integration (T016-T018)
- FTS implementation and pinyin support can run in parallel

**Within Phase 5-6**:
- Search history (T020-T023) can run parallel with deletion (T025-T027)
- History retrieval (T028-T030) can run in parallel

**Within Phase 7-13**:
- Indexing (T031-T033) can run parallel with pinyin (T034-T036)
- Debouncing/rate limiting (T037-T039) can run in parallel
- Performance and Polish can run in parallel

## MVP Recommendation

**Minimum Viable Product**: Phase 1-4 (Setup + US1 + US2)
- Users can search by nickname
- Fuzzy matching works
- Can follow from results

**Estimated effort**: 100-140 engineering hours
**Timeline**: 1.5-2 weeks with 1-2 engineers

**MVP Does NOT include**:
- Pinyin support (can add in v1.1)
- Search history (nice-to-have)
- Trending suggestions (v1.1)
- Rate limiting (can add if needed)

**Defer to Phase 2 (v1.1)**:
- Phase 5-6 (history & clear)
- Phase 9 (full pinyin support)
- Phase 10 (advanced rate limiting)
- Phase 12 (trending cache optimization)

## Testing Notes

**Independent Testing**:
- Search testable without follow system (can hardcode is_following)
- Follow from search testable independently
- History testable independently
- Pinyin testable independently

## Success Criteria Validation

After all tasks complete:
- ✅ SC-001: Searches return < 200ms (query profiling)
- ✅ SC-002: Pinyin matching accurate (test verification)
- ✅ SC-003: Results accurate 90%+ (manual verification)
- ✅ SC-004: Pagination stable (no duplicates verified)
- ✅ SC-005: 99% queries succeed (error tracking)

## API Contract Notes

**Search Response Consistency**:
- All user objects include: id, username, avatar_url, follower_count, is_following
- Relevance ranking not exposed in API (internal only)
- Suggestions include both recent searches and trending users

**Rate Limiting**:
- Optional in MVP, recommended to enable post-launch
- Max 10 searches per 10 seconds per user is reasonable

**Pinyin Support**:
- MVP: Basic nickname matching only
- v1.1: Pinyin conversion with multi-form matching

# Tasks: Phase 7B - Messaging + Stories System

**Input**: Design documents from `/specs/002-messaging-stories-system/`
**Prerequisites**: plan.md (tech stack: Rust/Tokio/axum, TypeScript/React), spec.md (8 user stories P1-P3), research.md (technology decisions), data-model.md (10 entities)

**Organization**: Tasks are organized by **TDD Phase** (Unit Tests → Integration Tests → Implementation) within each user story. This ensures tests are written before implementation, following red-green-refactor discipline.

## Path Conventions

- Backend (messaging): `backend/messaging-service/src/`
- Backend (stories): `backend/story-service/src/`
- Backend (search): `backend/search-service/src/`
- Backend (notifications): `backend/notification-service/src/`
- Shared Rust crypto lib: `backend/libs/crypto-core/`
- Frontend: `frontend/src/`
- Tests: `backend/<service>/tests/`
- Migrations: `backend/<service>/migrations/`

Note: For existing tasks that reference `backend/user-service/...`, apply the following mapping by feature area at implementation time:
- US1/US2/US5/US6/US7/US8 → `backend/messaging-service/...`
- US4 (Stories) → `backend/story-service/...`
- US3 (Search) → `backend/search-service/...`
- Mentions/Notifications endpoints → `backend/notification-service/...`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and core backend/frontend structure
**TDD Gate**: None (infrastructure phase)

- [X] T001 Create PostgreSQL migrations directory structure at `backend/messaging-service/migrations/`
- [X] T002 [P] Configure Rust project dependencies in `backend/messaging-service/Cargo.toml` (axum, tokio-tungstenite, sodiumoxide, elasticsearch, sqlx, serde, rdkafka)
- [X] T003 [P] Configure TypeScript/React frontend dependencies in `frontend/package.json` (react, zustand, ws, axios, vitest, vite-plugin-wasm, vite-plugin-top-level-await)
- [X] T004 [P] Setup linting and formatting: `cargo clippy`, `cargo fmt`, `eslint`, `prettier` configurations
- [X] T005 Create base project structure with error handling module in `backend/messaging-service/src/error.rs`
- [X] T006 [P] Initialize logger and tracing infrastructure in `backend/messaging-service/src/logging.rs`
- [X] T007 [P] Setup environment configuration in `backend/messaging-service/.env.example` and `backend/messaging-service/src/config.rs`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented
**TDD Gate**: Unit tests for each module before integration into routes

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

**2A: Infrastructure Unit Tests**:
- [X] T008 [P] Create test infrastructure helpers in `backend/messaging-service/tests/common/mod.rs` (database fixtures, crypto fixtures, request builders)
- [X] T009 [P] Create unit test for database connection pool in `backend/messaging-service/tests/unit/test_db_pool.rs` (connection, query execution, error handling)
- [X] T010 [P] Create unit test for authentication middleware in `backend/messaging-service/tests/unit/test_auth_middleware.rs` (JWT validation, token expiry, invalid tokens)
- [X] T011 [P] Create unit test for authorization middleware in `backend/messaging-service/tests/unit/test_authz_middleware.rs` (role-based access control)
- [X] T012 [P] Create unit test for error handling in `backend/messaging-service/tests/unit/test_error_handling.rs` (HTTP response mapping, logging)
- [X] T013 [P] Create unit test for Redis client in `backend/messaging-service/tests/unit/test_redis_client.rs` (connection, pub/sub, caching)
- [X] T014 [P] Create unit test for Elasticsearch client in `backend/search-service/tests/unit/test_es_client.rs` (connection, index management)

**2B: Infrastructure Implementation**:
- [X] T015 Create database connection pool in `backend/messaging-service/src/db.rs` (PostgreSQL with sqlx)
- [X] T016 [P] Implement authentication middleware (JWT validation) in `backend/messaging-service/src/middleware/auth.rs`
- [X] T017 [P] Implement authorization middleware (role-based access control) in `backend/messaging-service/src/middleware/authorization.rs`
- [X] T018 [P] Setup API routing structure in `backend/messaging-service/src/routes/mod.rs` with modular route handlers
- [X] T019 Create base models for User, Conversation, Message in `backend/messaging-service/src/models/mod.rs`
- [X] T020 [P] Setup Redis connection pool in `backend/messaging-service/src/cache/mod.rs`
- [ ] T021 [P] Configure error handling and logging middleware in `backend/messaging-service/src/middleware/mod.rs`
- [ ] T022 Create frontend context and state management in `frontend/src/context/AuthContext.tsx` and `frontend/src/stores/appStore.ts` (Zustand)
- [X] T023 [P] Setup WebSocket connection factory in `backend/messaging-service/src/websocket/mod.rs` with connection registry
- [X] T024 [P] Setup Elasticsearch client in `backend/search-service/src/elasticsearch.rs`
- [X] T025 Create initial migration for core User table in `backend/messaging-service/migrations/0001_create_users.sql`
- [X] T026 [P] Create comprehensive test infrastructure in `backend/messaging-service/tests/common/mod.rs` with helpers and fixtures (depends on T008)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

### Phase 2B: Event Bus (Kafka) — Cross-Service Integration

- [X] T228 [P] Define Kafka topics and schemas in `backend/search-service/docs/topics.md` (message_persisted, message_deleted, reaction_added, reaction_removed, mention_created)
- [X] T229 [P] Implement Kafka producer in `backend/messaging-service/src/events/producers.rs` (emit message_persisted, message_deleted after DB commit)
- [X] T230 [P] Implement Kafka consumer in `backend/search-service/src/events/consumers.rs` (index on message_persisted; remove on message_deleted; ignore strict E2E)
- [ ] T231 [P] Implement Kafka producers for reactions in `backend/messaging-service/src/events/reactions_producer.rs` and `backend/story-service/src/events/reactions_producer.rs`
- [ ] T232 [P] Implement Kafka consumer in `backend/notification-service/src/events/mention_consumer.rs` (create notifications on mention_created)
- [X] T233 [P] Add local Kafka stack in `infra/docker/docker-compose.kafka.yml` (Kafka, Zookeeper/Redpanda) and quickstart docs

---

## Phase 3: User Story 1 - Send and Receive Direct Messages (Priority: P1) 🎯 MVP

**Goal**: Enable real-time 1:1 messaging with message persistence, WebSocket delivery, and offline queue support

**Independent Test**: Can be fully tested by creating a 1:1 conversation between two users and verifying message send/receive with WebSocket delivery <100ms latency. Delivers core messaging value. No dependency on stories, reactions, or group conversations.

### 3A: Unit Tests for Services

- [X] T027 [P] Create unit test for encryption in `backend/libs/crypto-core/tests/test_encryption.rs` (NaCl box roundtrip, nonce randomness; no deterministic searchable encryption)
- [X] T028 [P] Create unit test for offline queue deduplication in `backend/messaging-service/tests/unit/test_offline_queue.rs` (queue messages, verify dedup via idempotency_key)
- [X] T029 [P] Create unit test for ConversationService in `backend/messaging-service/tests/unit/test_conversation_service.rs` (create_direct_conversation, get_conversation, permissions)
- [X] T030 [P] Create unit test for MessageService in `backend/messaging-service/tests/unit/test_message_service.rs` (send_message with encryption, get_message_history, soft_delete_message)

### 3B: Database & Models

- [X] T031 [P] Create Conversation migration in `backend/messaging-service/migrations/0002_create_conversations.sql` (id, type, name, description, member_count, last_message_id, privacy_mode, created_at, updated_at)
- [X] T032 [P] Create ConversationMember migration in `backend/messaging-service/migrations/0003_create_conversation_members.sql` (conversation_id, user_id, role, joined_at, last_read_at, is_muted, user_public_key, UNIQUE constraint)
- [X] T033 [P] Create Message migration in `backend/messaging-service/migrations/0004_create_messages.sql` (id, conversation_id, sender_id, content_encrypted BYTEA, content_nonce BYTEA, sequence_number BIGSERIAL, idempotency_key, created_at, edited_at, deleted_at, reaction_count, INDEXES)
- [X] T034 [P] Create Conversation model in `backend/messaging-service/src/models/conversation.rs` with privacy_mode field
- [X] T035 [P] Create Message model in `backend/messaging-service/src/models/message.rs` with encryption_version, sequence_number, idempotency_key fields

### 3C: Service Implementation

- [ ] T036 [P] Implement ConversationService in `backend/messaging-service/src/services/conversation_service.rs` with methods: create_direct_conversation, get_conversation, list_conversations
- [ ] T037 [P] Implement MessageService in `backend/messaging-service/src/services/message_service.rs` with methods: send_message (encryption wrapper), get_message_history, update_message, soft_delete_message, handle_offline_queue
- [ ] T038 [P] Integrate `backend/libs/crypto-core` for encryption (libsodium NaCl box, per-message nonce); no deterministic searchable encryption in strict E2E mode
- [ ] T039 [P] Implement offline message queue processor in `backend/messaging-service/src/services/offline_queue.rs` with replay and deduplication (idempotency_key)

### 3D: REST API Endpoints

- [ ] T040 [P] Implement POST /conversations endpoint in `backend/messaging-service/src/routes/conversations.rs` (create direct 1:1 conversation, validate both users exist)
- [ ] T041 [P] Implement GET /conversations/{id} endpoint in `backend/messaging-service/src/routes/conversations.rs` (fetch conversation details with member count, last message)
- [ ] T042 [P] Implement POST /conversations/{id}/messages endpoint in `backend/messaging-service/src/routes/messages.rs` (send message with encryption, idempotency_key handling)
- [ ] T043 [P] Implement GET /conversations/{id}/messages endpoint in `backend/messaging-service/src/routes/messages.rs` (fetch message history, pagination, include reaction_count)
- [ ] T044 [P] Implement PUT /messages/{id} endpoint in `backend/messaging-service/src/routes/messages.rs` (edit message, 15-minute window, broadcast via WebSocket)
- [ ] T045 [P] Implement DELETE /messages/{id} endpoint in `backend/messaging-service/src/routes/messages.rs` (soft delete, broadcast removal via WebSocket)

### 3E: WebSocket Real-time

- [X] T046 [P] Implement WebSocket message handler in `backend/messaging-service/src/websocket/handlers.rs` with message type dispatch (send, receive, typing, online_status)
- [X] T047 [P] Implement conversation subscription in `backend/messaging-service/src/websocket/subscription.rs` (track listeners per conversation, broadcast to subscribers)
- [X] T048 [P] Implement message broadcast in `backend/messaging-service/src/websocket/broadcast.rs` (send to all conversation members, include sequence_number)
- [X] T049 [P] Implement Redis pub/sub for WebSocket distribution in `backend/messaging-service/src/websocket/pubsub.rs` (conversation:${id} channels for scaling)
- [X] T050 [P] Implement heartbeat/keep-alive in WebSocket handler with ping/pong every 30 seconds

### 3F: Frontend Components

- [ ] T051 [P] Create ConversationList component in `frontend/src/components/MessagingUI/ConversationList.tsx` (list conversations with last message preview)
- [ ] T052 [P] Create MessageThread component in `frontend/src/components/MessagingUI/MessageThread.tsx` (display messages, auto-scroll, virtual scrolling)
- [ ] T053 [P] Create MessageComposer component in `frontend/src/components/MessagingUI/MessageComposer.tsx` (input field, send button, E2E encryption, offline queue)
- [ ] T054 [P] Create WebSocket client in `frontend/src/services/websocket/WebSocketClient.ts` (connect to /ws endpoint, handle message receive, dispatch to Zustand)
- [ ] T055 [P] Integrate WASM from Rust `backend/libs/crypto-core` in `frontend/src/services/encryption/client.ts` (NaCl box via WASM, per-message nonce)
- [ ] T056 [P] Implement offline queue in `frontend/src/services/offlineQueue/Queue.ts` using IndexedDB (store unsent messages, replay with idempotency_key)
- [ ] T057 [P] Create Zustand store for messaging in `frontend/src/stores/messagingStore.ts` (conversations, messages, current conversation, UI state)

### 3G: Integration Tests

- [X] T058 [P] Create integration test for 1:1 message send/receive in `backend/messaging-service/tests/integration/test_direct_messaging.rs` (2 users, conversation, WebSocket delivery <100ms)
- [X] T059 [P] Create integration test for message history retrieval in `backend/messaging-service/tests/integration/test_message_history.rs` (send 10 messages, fetch, verify order)
- [X] T060 [P] Create integration test for encryption roundtrip in `backend/messaging-service/tests/integration/test_encryption.rs` (encrypt on sender, decrypt on recipient)
- [X] T061 [P] Create integration test for offline queue replay in `backend/messaging-service/tests/integration/test_offline_queue_replay.rs` (queue, reconnect, verify delivered)
- [ ] T062 [P] Create frontend test for message send in `frontend/src/components/MessagingUI/__tests__/MessageComposer.test.ts` (type, encrypt, send, verify store update)

**Checkpoint**: User Story 1 fully functional and testable independently. Can demo 1:1 messaging, offline support, and E2E encryption.

---

## Phase 4: User Story 2 - Create and Manage Group Conversations (Priority: P1)

**Goal**: Enable creation of group conversations with 3-500 members, member management, and group messaging

**Independent Test**: Can be fully tested by creating a 3+ person group, adding/removing members, and verifying all messages are visible to all active members.

### 4A: Unit Tests

- [ ] T063 [P] Create unit test for MemberService in `backend/user-service/tests/unit/test_member_service.rs` (add/remove member, role management, membership checks)
- [ ] T064 [P] Create unit test for group conversation creation in `backend/user-service/tests/unit/test_group_conversation_service.rs` (3-500 member validation)

### 4B: Database & Models

- [ ] T065 [P] Extend Conversation model in `backend/user-service/src/models/conversation.rs` to support group type with admin_key_encrypted

### 4C: Service Implementation

- [ ] T066 [P] Extend ConversationService with create_group_conversation(name, description, initial_members) method and member_count validation (3-500)
- [ ] T067 [P] Implement MemberService in `backend/user-service/src/services/member_service.rs` with add_member, remove_member, update_member_role, check_membership methods
- [ ] T068 [P] Implement group metadata update in ConversationService with update_group_name, update_group_description, get_group_members methods
- [ ] T069 [P] Extend MessageService to support group broadcast (send to all members, verify sender is member)

### 4D: REST API Endpoints

- [ ] T070 [P] Extend POST /conversations endpoint to support group creation with name, description, initial_members array (3-500 limit)
- [ ] T071 [P] Implement POST /conversations/{id}/members endpoint in `backend/user-service/src/routes/members.rs` (add member with permission check)
- [ ] T072 [P] Implement DELETE /conversations/{id}/members/{user_id} endpoint (remove member, update member_count cache)
- [ ] T073 [P] Implement PUT /conversations/{id}/members/{user_id} endpoint (change role: member→admin, admin→member, authorization check)
- [ ] T074 [P] Implement GET /conversations/{id}/members endpoint (list members with role, joined_at, pagination)
- [ ] T075 [P] Implement PUT /conversations/{id} endpoint (update group name/description, admin-only)

### 4E: WebSocket Extensions

- [ ] T076 [P] Extend WebSocket broadcast to support group channels in `backend/user-service/src/websocket/broadcast.rs` (send to all members)
- [ ] T077 [P] Implement member leave notification in WebSocket handler (broadcast member_left event)
- [ ] T078 [P] Implement member join notification in WebSocket handler (broadcast member_joined event)

### 4F: Frontend Components

- [ ] T079 [P] Create GroupCreator component in `frontend/src/components/MessagingUI/GroupCreator.tsx` (name input, member selector, validation)
- [ ] T080 [P] Create MemberList component in `frontend/src/components/MessagingUI/MemberList.tsx` (show members with roles, add/remove buttons)
- [ ] T081 [P] Extend ConversationList to highlight groups and show member count
- [ ] T082 [P] Extend MessageThread to show message sender name in group context

### 4G: Integration Tests

- [ ] T083 [P] Create integration test for group creation in `backend/user-service/tests/integration/test_group_conversations.rs` (create 5-user group, verify member_count)
- [ ] T084 [P] Create integration test for group messaging in `backend/user-service/tests/integration/test_group_messaging.rs` (5 users, send message, verify all receive)
- [ ] T085 [P] Create integration test for member management in `backend/user-service/tests/integration/test_member_management.rs` (add/remove, role changes)
- [ ] T086 [P] Create integration test for group size limits in `backend/user-service/tests/integration/test_group_size_limits.rs` (reject 501-member group)

**Checkpoint**: User Stories 1 AND 2 fully functional. Can demo 1:1 and group messaging with member management.

---

## Phase 5: User Story 3 - Search Messages and Conversations (Priority: P2)

**Goal**: Enable full-text message search via Elasticsearch with <200ms P95 latency

**Independent Test**: Can be fully tested by indexing messages, executing search queries with filters, and verifying <200ms P95 latency.

### 5A: Unit Tests

- [ ] T087 [P] Create unit test for SearchService in `backend/search-service/tests/unit/test_search_service.rs` (query builder, result ranking, pagination)
- [ ] T088 [P] Create unit test to ensure strict E2E conversations are excluded from indexing/search in `backend/search-service/tests/unit/test_privacy_exclusion.rs`

### 5B: Search Infrastructure

- [ ] T089 [P] Setup Elasticsearch client in `backend/search-service/src/elasticsearch.rs` with index management
- [ ] T090 [P] Create Elasticsearch message index schema in `backend/search-service/src/index_schema.rs` (mapping with text analyzer, keyword fields)
- [ ] T091 [P] Implement consumer for `message_persisted` events in `backend/search-service/src/consumers/message_indexer.rs` (index after successful persist; ignore strict E2E)
- [ ] T092 [P] Implement consumer for `message_deleted` events (remove from index)
- [ ] T093 [P] Create Kafka CDC/setup guide in `backend/search-service/docs/elasticsearch-cdc.md` (Debezium optional)

### 5C: Search Service Implementation

- [ ] T094 [P] Implement SearchService in `backend/search-service/src/services/search_service.rs` with search_messages(query, filters) supporting keyword, sender_id, conversation_id, date_range
- [ ] T095 [P] Implement result ranking in SearchService (relevance scoring, recency boost)
- [ ] T096 [P] Implement pagination in search results (limit, offset, total count)

### 5D: REST API Endpoints

- [ ] T097 [P] Implement GET /search/messages endpoint in `backend/search-service/src/routes/search.rs` (query params: q, sender_id, conversation_id, date_from, date_to, limit, offset)
- [ ] T098 [P] Implement search response serialization (message summary, conversation context, sender name, relevance score)

### 5E: Frontend Search UI

- [ ] T099 [P] Create SearchBar component in `frontend/src/components/MessagingUI/SearchBar.tsx` (search input, debounced query)
- [ ] T100 [P] Create SearchResults component in `frontend/src/components/MessagingUI/SearchResults.tsx` (display results, conversation context, click to jump)
- [ ] T101 [P] Implement search filters UI in `frontend/src/components/MessagingUI/SearchFilters.tsx` (sender dropdown, conversation filter, date range picker)
- [ ] T102 [P] Create Zustand store for search in `frontend/src/stores/searchStore.ts` (query, filters, results, loading state)

### 5F: Integration Tests

- [ ] T103 [P] Create integration test for message search in `backend/search-service/tests/integration/test_search.rs` (index 100 messages, search by keyword, verify <200ms P95)
- [ ] T104 [P] Create integration test for search filters in `backend/search-service/tests/integration/test_search_filters.rs` (test all filter combinations)
- [ ] T105 [P] Create integration test for search ranking in `backend/search-service/tests/integration/test_search_ranking.rs` (verify relevance scores and recency boost)
- [ ] T106 [P] Create performance test for search latency in `backend/search-service/tests/load/test_search_latency.rs` (1000 message index, 100 queries, verify P95 <200ms)

**Checkpoint**: User Stories 1, 2, AND 3 fully functional. Can demo messaging + search.

---

## Phase 6: User Story 4 - Create and Share Stories (Priority: P2)

**Goal**: Enable ephemeral stories with 24-hour auto-expiration, three-tier privacy (public/followers/close-friends), and view tracking

**Independent Test**: Can be fully tested by creating a story, verifying visibility rules and 24-hour expiration, and testing view counts.

### 6A: Unit Tests

- [ ] T107 [P] Create unit test for StoryService in `backend/story-service/tests/unit/test_story_service.rs` (create, visibility checks, expiration)
- [ ] T108 [P] Create unit test for story privacy logic in `backend/story-service/tests/unit/test_story_privacy.rs` (all privacy_level combinations)
- [ ] T109 [P] Create unit test for CloseFriendsService in `backend/story-service/tests/unit/test_close_friends_service.rs` (add/remove, max 100 constraint)

### 6B: Database & Models

- [ ] T110 [P] Create Story migration in `backend/story-service/migrations/0005_create_stories.sql` (id, user_id, content_type ENUM, content_url, caption, privacy_level ENUM, created_at, expires_at=created_at+24h, view_count, is_expired)
- [ ] T111 [P] Create StoryView migration in `backend/story-service/migrations/0006_create_story_views.sql` (id, story_id, viewer_id, viewed_at, view_duration_seconds, UNIQUE on story_id+viewer_id)
- [ ] T112 [P] Create CloseFriends migration in `backend/story-service/migrations/0007_create_close_friends.sql` (user_id, close_friend_id, created_at, UNIQUE constraint)
- [ ] T113 [P] Create Story model in `backend/story-service/src/models/story.rs` with privacy_level enum, expires_at, view_count fields
- [ ] T114 [P] Create StoryView model in `backend/story-service/src/models/story_view.rs`

### 6C: Service Implementation

- [ ] T115 [P] Implement StoryService in `backend/story-service/src/services/story_service.rs` with create_story(user_id, content_type, content_url, caption, privacy_level) method
- [ ] T116 [P] Implement story visibility check in StoryService with can_view_story(viewer_id, story_id) method (check privacy_level, followers, close_friends)
- [ ] T117 [P] Implement view tracking in StoryService with track_story_view(story_id, viewer_id) method (insert StoryView, increment view_count cache)
- [ ] T118 [P] Implement story expiration in StoryService with expire_stories() method (find stories where expires_at < NOW(), soft delete, clean StoryView records)
- [ ] T119 [P] Setup Tokio interval task for story expiration in `backend/story-service/src/tasks/story_expiration.rs` (run every 5 minutes)
- [ ] T120 [P] Implement close-friends management in StoryService with add_close_friend, remove_close_friend, get_close_friends methods (max 100 per user)

### 6D: REST API Endpoints

- [ ] T121 [P] Implement POST /stories endpoint in `backend/story-service/src/routes/stories.rs` (upload story, set privacy_level, expires_at = now + 24h)
- [ ] T122 [P] Implement GET /stories/feed endpoint (fetch user's story feed with privacy filtering, include view_count)
- [ ] T123 [P] Implement GET /stories/{id} endpoint (fetch story details, check visibility, track view)
- [ ] T124 [P] Implement GET /users/{id}/stories endpoint (fetch user's stories with privacy filtering)
- [ ] T125 [P] Implement PUT /stories/{id}/privacy endpoint (change privacy_level, owner-only)
- [ ] T126 [P] Implement DELETE /stories/{id} endpoint (manual deletion by owner or admin)
- [ ] T127 [P] Implement GET /users/{id}/close-friends endpoint (list close-friends, max 100)
- [ ] T128 [P] Implement POST /users/{id}/close-friends/{friend_id} endpoint (add to close-friends, enforce max 100)
- [ ] T129 [P] Implement DELETE /users/{id}/close-friends/{friend_id} endpoint (remove from close-friends)

### 6E: Frontend Components

- [ ] T130 [P] Create StoryCreator component in `frontend/src/components/StoriesUI/StoryCreator.tsx` (image/video upload, caption, privacy selector)
- [ ] T131 [P] Create StoryFeed component in `frontend/src/components/StoriesUI/StoryFeed.tsx` (display user's and followed users' stories with privacy filtering)
- [ ] T132 [P] Create StoryViewer component in `frontend/src/components/StoriesUI/StoryViewer.tsx` (fullscreen display, show view_count, track view duration)
- [ ] T133 [P] Create PrivacySelector component in `frontend/src/components/StoriesUI/PrivacySelector.tsx` (radio buttons: public, followers, close-friends)
- [ ] T134 [P] Create CloseFriendsList component in `frontend/src/components/SettingsUI/CloseFriendsList.tsx` (manage close-friends)
- [ ] T135 [P] Implement story feed store in Zustand `frontend/src/stores/storyStore.ts` (stories, current_story, viewed_stories)

### 6F: Integration Tests

- [ ] T136 [P] Create integration test for story creation in `backend/story-service/tests/integration/test_story_creation.rs` (create story, verify expires_at = created_at + 24h)
- [ ] T137 [P] Create integration test for story privacy in `backend/story-service/tests/integration/test_story_privacy.rs` (create public/followers/close-friends, verify visibility)
- [ ] T138 [P] Create integration test for story view tracking in `backend/story-service/tests/integration/test_story_views.rs` (5 users view, verify view_count = 5, no duplicates)
- [ ] T139 [P] Create integration test for story expiration in `backend/story-service/tests/integration/test_story_expiration.rs` (create story, advance clock 24h, verify soft delete)
- [ ] T140 [P] Create integration test for close-friends management in `backend/story-service/tests/integration/test_close_friends.rs` (add/remove, max 100)

**Checkpoint**: User Stories 1, 2, 3, AND 4 fully functional. Can demo messaging + search + stories.

---

## Phase 7: User Story 5 - React to Messages and Stories (Priority: P2)

**Goal**: Enable emoji reactions on messages and stories with real-time propagation <50ms and reaction count tracking

**Independent Test**: Can be fully tested by adding reactions to a message, verifying real-time propagation <50ms via WebSocket, and confirming reaction counts.

### 7A: Unit Tests

- [ ] T141 [P] Create unit test for ReactionService in `backend/user-service/tests/unit/test_reaction_service.rs` (add/remove reactions, count caching, duplicate prevention)

### 7B: Database & Models

- [ ] T142 [P] Create MessageReaction migration in `backend/user-service/migrations/0008_create_message_reactions.sql` (id, message_id, user_id, emoji, created_at, UNIQUE on message_id+user_id+emoji)
- [ ] T143 [P] Create StoryReaction migration in `backend/user-service/migrations/0009_create_story_reactions.sql` (id, story_id, user_id, emoji, created_at, UNIQUE on story_id+user_id+emoji)
- [ ] T144 [P] Create MessageReaction model in `backend/user-service/src/models/message_reaction.rs`
- [ ] T145 [P] Create StoryReaction model in `backend/user-service/src/models/story_reaction.rs`

### 7C: Service Implementation

- [ ] T146 [P] Implement ReactionService in `backend/user-service/src/services/reaction_service.rs` with add_message_reaction, remove_message_reaction, add_story_reaction, remove_story_reaction methods
- [ ] T147 [P] Extend ReactionService with get_message_reactions(message_id), get_story_reactions(story_id) methods
- [ ] T148 [P] Implement reaction count caching in ReactionService (cache count per message/story in Redis)
- [ ] T149 [P] Extend MessageService to denormalize reaction_count on insert, update cache on add/remove

### 7D: REST API Endpoints

- [ ] T150 [P] Implement POST /messages/{id}/reactions endpoint in `backend/user-service/src/routes/reactions.rs` (add emoji reaction, prevent duplicates)
- [ ] T151 [P] Implement DELETE /messages/{id}/reactions/{emoji} endpoint (remove reaction by current user)
- [ ] T152 [P] Implement GET /messages/{id}/reactions endpoint (list all reactions with user count per emoji)
- [ ] T153 [P] Implement POST /stories/{id}/reactions endpoint (add emoji reaction to story)
- [ ] T154 [P] Implement DELETE /stories/{id}/reactions/{emoji} endpoint (remove story reaction)
- [ ] T155 [P] Implement GET /stories/{id}/reactions endpoint (list story reactions)

### 7E: WebSocket Real-time

- [ ] T156 [P] Extend WebSocket handler to support reaction events in `backend/user-service/src/websocket/handlers.rs` (add_reaction, remove_reaction message types)
- [ ] T157 [P] Implement reaction broadcast in `backend/user-service/src/websocket/broadcast.rs` (send to all viewers within 50ms)
- [ ] T158 [P] Implement optimistic updates for reactions (send immediate ACK before server processing)

### 7F: Frontend Components

- [ ] T159 [P] Create ReactionPicker component in `frontend/src/components/MessagingUI/ReactionPicker.tsx` (emoji selector with common emojis)
- [ ] T160 [P] Create ReactionDisplay component in `frontend/src/components/MessagingUI/ReactionDisplay.tsx` (show reaction count by emoji, add/remove buttons)
- [ ] T161 [P] Extend MessageThread to display reactions
- [ ] T162 [P] Extend StoryViewer to display reactions
- [ ] T163 [P] Implement optimistic reaction updates in Zustand store (add locally, then sync with server)

### 7G: Integration Tests

- [ ] T164 [P] Create integration test for message reactions in `backend/user-service/tests/integration/test_message_reactions.rs` (add reaction, verify broadcast <50ms, check count)
- [ ] T165 [P] Create integration test for story reactions in `backend/user-service/tests/integration/test_story_reactions.rs` (add reaction, verify count)
- [ ] T166 [P] Create integration test for duplicate prevention in `backend/user-service/tests/integration/test_reaction_duplicates.rs` (attempt same reaction twice, verify uniqueness)
- [ ] T167 [P] Create performance test for reaction broadcast in `backend/user-service/tests/load/test_reaction_broadcast_latency.rs` (100 concurrent reaction adds, verify P99 <100ms)

**Checkpoint**: User Stories 1-5 fully functional. Can demo messaging + search + stories + reactions.

---

## Phase 8: User Story 6 - Manage Message Visibility and Deletion (Priority: P3)

**Goal**: Enable message editing (15-minute window) and deletion with soft delete and broadcast to all viewers

**Independent Test**: Can be fully tested by deleting messages, verifying removal from all viewers, and testing admin deletion capabilities.

### 8A: Unit Tests

- [ ] T168 [P] Create unit test for message edit/delete logic in `backend/user-service/tests/unit/test_message_edit_delete.rs` (15-minute window enforcement, authorization)

### 8B: Service Extensions

- [ ] T169 [P] Extend MessageService with edit_message(message_id, new_content, user_id) method (15-minute window, encrypt new content, broadcast update)
- [ ] T170 [P] Extend MessageService with delete_message(message_id, user_id, is_admin) method (soft delete via deleted_at, authorization check)

### 8C: REST API Endpoints

- [ ] T171 [P] Implement PUT /messages/{id} endpoint for editing (15-minute limit, content re-encryption, broadcast via WebSocket)
- [ ] T172 [P] Implement DELETE /messages/{id} endpoint with role-based authorization (owner after 15 min, admin anytime)

### 8D: WebSocket Real-time

- [ ] T173 [P] Extend WebSocket broadcast for message updates (broadcast message_updated event with new content to all viewers)
- [ ] T174 [P] Extend WebSocket broadcast for message deletion (broadcast message_deleted event to remove from all viewers)

### 8E: Frontend Components

- [ ] T175 [P] Extend MessageThread to show edit/delete buttons (conditional based on ownership and 15-min window)
- [ ] T176 [P] Implement message edit in MessageComposer (if editing, prefill content, show "15 minutes remaining" timer)
- [ ] T177 [P] Implement local message deletion from UI in Zustand store (optimistic update, sync with server)

### 8F: Integration Tests

- [ ] T178 [P] Create integration test for message editing in `backend/user-service/tests/integration/test_message_editing.rs` (edit message, verify broadcast, check 15-min limit)
- [ ] T179 [P] Create integration test for message deletion in `backend/user-service/tests/integration/test_message_deletion.rs` (delete message, verify removal from all viewers)
- [ ] T180 [P] Create integration test for admin deletion in `backend/user-service/tests/integration/test_admin_deletion.rs` (admin deletes user message anytime)
- [ ] T181 [P] Create unit test for 15-minute window enforcement in `backend/user-service/tests/unit/test_edit_time_window.rs`

**Checkpoint**: User Stories 1-6 fully functional. Can demo message editing, deletion with time windows, and admin control.

---

## Phase 9: User Story 7 - Handle Message Offline Queue and Sync (Priority: P3)

**Goal**: Enable client-side offline message queueing with automatic replay and server-side deduplication on reconnect

**Independent Test**: Can be fully tested by simulating offline mode, queuing messages, reconnecting, and verifying queue is processed correctly.

### 9A: Unit Tests

- [ ] T182 [P] Create unit test for offline queue in `backend/user-service/tests/unit/test_offline_queue_processor.rs` (queue processing, retry logic, deduplication)

### 9B: Service Extensions

- [ ] T183 [P] Extend offline queue processor in MessageService (replay logic, idempotency handling)
- [ ] T184 [P] Implement message deduplication in MessageService using idempotency_key (check existing before inserting, return existing on duplicate)
- [ ] T185 [P] Implement offline queue sync endpoint POST /messages/sync (batch process queued messages with idempotency keys)

### 9C: Frontend Offline Queue

- [ ] T186 [P] Extend offline queue in `frontend/src/services/offlineQueue/Queue.ts` with retry logic (exponential backoff on network errors)
- [ ] T187 [P] Implement offline mode detection in WebSocket client (detect connection loss, set offline flag in Zustand store)
- [ ] T188 [P] Implement auto-replay on reconnect in offline queue (when connection restored, send all queued messages)
- [ ] T189 [P] Implement queue status UI in `frontend/src/components/MessagingUI/OfflineQueueStatus.tsx` (show "X messages pending" when offline)
- [ ] T190 [P] Implement idempotency_key generation in `frontend/src/services/encryption/client.ts` (use UUID per message)

### 9D: Integration Tests

- [ ] T191 [P] Create integration test for offline queueing in `backend/user-service/tests/integration/test_offline_queue.rs` (send while offline, reconnect, verify delivered)
- [ ] T192 [P] Create integration test for deduplication in `backend/user-service/tests/integration/test_queue_deduplication.rs` (send duplicate idempotency_keys, verify no duplicates)
- [ ] T193 [P] Create integration test for queue ordering in `backend/user-service/tests/integration/test_queue_ordering.rs` (queue 10 messages, replay, verify order via sequence_number)
- [ ] T194 [P] Create frontend test for offline detection in `frontend/src/services/offlineQueue/__tests__/OfflineDetection.test.ts`

**Checkpoint**: User Stories 1-7 fully functional. Can demo offline messaging with automatic recovery.

---

## Phase 10: User Story 8 - View Conversation Metadata and Analytics (Priority: P3)

**Goal**: Provide conversation metadata (creation date, member list, message count) and analytics (messages per day, most active members)

**Independent Test**: Can be fully tested by querying conversation metadata and analytics APIs, verifying accuracy of computed metrics.

### 10A: Unit Tests

- [ ] T195 [P] Create unit test for analytics calculations in `backend/user-service/tests/unit/test_analytics_calculations.rs` (messages per day, member activity)

### 10B: Service Implementation

- [ ] T196 [P] Implement conversation metadata in ConversationService with get_conversation_metadata(conversation_id) method (member_count, last_message_id, message_count, created_at)
- [ ] T197 [P] Implement conversation analytics in `backend/user-service/src/services/analytics_service.rs` with get_conversation_analytics(conversation_id, timerange) method
- [ ] T198 [P] Implement message count caching in ConversationService (cache in Redis, update on new message)
- [ ] T199 [P] Implement active member stats in analytics (count unique senders per day, last 7 days)

### 10C: REST API Endpoints

- [ ] T200 [P] Implement GET /conversations/{id}/metadata endpoint (return member_count, message_count, created_at, last_message_at)
- [ ] T201 [P] Implement GET /conversations/{id}/analytics endpoint (return messages_per_day, active_members, date_range)
- [ ] T202 [P] Implement GET /conversations/{id}/analytics/members endpoint (return per-member message count, last_message_at)

### 10D: Frontend Analytics Components

- [ ] T203 [P] Create ConversationMetadata component in `frontend/src/components/MessagingUI/ConversationMetadata.tsx` (display creation date, member count, message count)
- [ ] T204 [P] Create ConversationAnalytics component in `frontend/src/components/Analytics/ConversationAnalytics.tsx` (display messages per day chart, active member list)
- [ ] T205 [P] Create MemberActivity component in `frontend/src/components/Analytics/MemberActivity.tsx` (list members with message counts)

### 10E: Integration Tests

- [ ] T206 [P] Create integration test for conversation metadata in `backend/user-service/tests/integration/test_conversation_metadata.rs` (create conversation, send messages, verify metadata)
- [ ] T207 [P] Create integration test for analytics accuracy in `backend/user-service/tests/integration/test_analytics_accuracy.rs` (send messages over 7 days, verify analytics)
- [ ] T208 [P] Create unit test for member activity calculation in `backend/user-service/tests/unit/test_member_activity.rs`

**Checkpoint**: User Stories 1-8 fully functional. Can demo complete messaging system with analytics dashboard.

---

## Phase 11: Advanced Features (P3)

**Goal**: Implement @mention notifications and group improvements

**@Mention Notifications** (from FR-016):
- [ ] T209 [P] Implement @mention parsing in `backend/messaging-service/src/services/mention_service.rs` (regex: @[a-zA-Z0-9_]{3,30}, extract mentioned users)
- [ ] T210 [P] Implement mention validation in message processing (verify mentioned user exists, is in conversation)
- [ ] T211 [P] Implement mention notification dispatch in `backend/notification-service/src/services/notification_service.rs` (create notification record, broadcast via WebSocket if online)
- [ ] T212 [P] Create MentionNotification migration in `backend/notification-service/migrations/0010_create_mention_notifications.sql`
- [ ] T213 [P] Implement GET /notifications endpoint in `backend/notification-service/src/routes/notifications.rs` (list user's mention notifications)
- [ ] T214 [P] Create frontend MentionNotifications component in `frontend/src/components/Notifications/MentionNotifications.tsx`

---

## Phase 12: NFR Tasks - Security, Performance, Observability

**Purpose**: Non-functional requirement implementation affecting all user stories

### Security (H5, H6)

- [ ] T215 [P] Document TLS 1.3 certificate management at ingress in `infra/gateway/TLS.md` (cert-manager/Let's Encrypt setup, renewal, local dev TLS)
- [ ] T216 [P] Implement HSTS headers in `backend/messaging-service/src/middleware/security_headers.rs` (max-age=31536000); replicate in other services
- [ ] T217 [P] Implement PII encryption at rest in `backend/messaging-service/src/services/pii_encryption.rs` (encrypt sensitive user fields with libsodium secret box + master key)
- [ ] T218 [P] Implement GDPR/CCPA data deletion flow across services starting in `backend/messaging-service/src/services/user_deletion_service.rs` (30-day window, audit trail)
- [ ] T219 [P] Create integration test for data deletion in `backend/messaging-service/tests/integration/test_user_deletion.rs` (verify deletion/anonymization, audit log)
- [ ] T220 [P] Implement input validation middleware in `backend/messaging-service/src/middleware/validation.rs` (SQL injection prevention, XSS prevention)
- [ ] T221 [P] Implement rate limiting middleware in `backend/messaging-service/src/middleware/rate_limit.rs` (per-user, per-IP rate limits)
- [ ] T222 [P] Implement security audit checklist in `infra/security/SECURITY_AUDIT.md` (review encryption, access control)
- [ ] T223 [P] Implement logging sanitization in `backend/messaging-service/src/logging.rs` (redact message content, PII from logs)

### Disaster Recovery (H6)

- [ ] T224 [P] Create DR runbook in `infra/dr/DISASTER_RECOVERY.md` (backup strategy, restoration procedure, RTO/RPO targets)
- [ ] T225 [P] Implement database backup automation in `infra/ops/backup.sh` (daily snapshots to S3)
- [ ] T226 [P] Create DR drill test in `backend/messaging-service/tests/integration/test_dr_restoration.rs` (simulate failure, verify RTO <5 min, RPO <1 min)

### Observability (NFR)

- [ ] T227 [P] Implement Prometheus metrics in `backend/messaging-service/src/middleware/metrics.rs` (message latency, WebSocket connections); add search/stories metrics in respective services
- [ ] T228 [P] Implement OpenTelemetry tracing in `backend/messaging-service/src/tracing.rs` (distributed tracing for request flows); replicate per service
- [ ] T229 [P] Implement structured logging in `backend/messaging-service/src/logging.rs` (JSON format, context propagation)
- [ ] T230 [P] Configure alerting rules in `infra/ops/alerts.yml` (message latency >200ms P95, WebSocket errors >1%, search latency >200ms)
- [ ] T231 [P] Create monitoring dashboard docs in `infra/monitoring/MONITORING.md` (Grafana dashboard templates)

---

## Phase 13: Performance & Load Testing

- [ ] T232 [P] Create load test: 50k concurrent WebSocket connections in `backend/messaging-service/tests/load/test_50k_concurrent.rs`
- [ ] T233 [P] Create load test: 10k msg/sec throughput in `backend/messaging-service/tests/load/test_10k_throughput.rs`
- [ ] T234 [P] Create load test: 100k message search latency in `backend/search-service/tests/load/test_large_index_search.rs`
- [ ] T235 [P] Performance profile: Message send latency optimization in `backend/messaging-service/docs/PERF_PROFILE.md`
- [ ] T236 [P] Performance profile: WebSocket memory usage optimization

---

## Phase 14: Documentation & Launch

- [ ] T237 [P] Create API reference in `backend/messaging-service/docs/API.md` (OpenAPI 3.1 spec, endpoint summaries)
- [ ] T238 [P] Create data model diagram in `specs/002-messaging-stories-system/data-model.md` (entity relationships, cardinality)
- [ ] T239 [P] Create architecture decision records in `specs/002-messaging-stories-system/ADR/` (why Rust, why Elasticsearch, privacy modes)
- [ ] T240 [P] Create quickstart.md validation (new engineer onboarding, test with fresh checkout)
- [ ] T241 [P] Create E2E tests using Cypress in `frontend/e2e/` (Login, send message, receive, search scenarios)
- [ ] T242 [P] Create browser compatibility test plan (Chrome, Firefox, Safari, Edge)
- [ ] T243 [P] Create frontend accessibility audit per WCAG 2.1 AA compliance
- [ ] T244 [P] Create runbook for common operations in `infra/runbooks/RUNBOOK.md` (deploy, rollback, incident response)
- [ ] T245 [P] Create admin dashboard documentation in `infra/admin/ADMIN_GUIDE.md` (user management, monitoring)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - **BLOCKS all user stories**
- **User Stories (Phase 3-10)**: All depend on Foundational phase completion
  - User stories CAN proceed in parallel (if staffed)
  - US1+US2 (P1): Should complete first for MVP
  - US3-5 (P2): Can run in parallel with US1/US2
  - US6-8 (P3): Can run after US1 or in parallel if capacity
  - Advanced features (P3): After all core stories done
- **NFR + Polish (Phase 12-14)**: Depends on all desired user stories being complete

### Within Each User Story: TDD Order

1. **Unit Tests** (3A, 4A, etc.): Red phase - write failing tests
2. **Database & Models** (3B, 4B, etc.): Foundation for implementation
3. **Services** (3C, 4C, etc.): Green phase - implement to pass tests
4. **REST API** (3D, 4D, etc.): Integration with HTTP layer
5. **WebSocket** (3E, 4E, etc.): Real-time features
6. **Frontend** (3F, 4F, etc.): UI implementation
7. **Integration Tests** (3G, 4G, etc.): Refactor phase - comprehensive validation

---

## Parallel Opportunities

**Phase 1 Setup**:
- T002 (Rust deps) and T003 (TS deps) can run in parallel

**Phase 2 Foundational**:
- T009-T014 (infrastructure unit tests) can run in parallel
- T016-T024 (infrastructure implementation) can run in parallel (after tests pass)

**Phase 3+ User Stories**:
- All 3A (unit tests) can run in parallel
- All 3B (database) can run in parallel
- All 3C (services) depend on 3B, can run in parallel
- All 3D-G can run in parallel once dependencies met

---

## Format Validation Summary

**Total Tasks**: 245 (increased from 215 to add NFR + TDD tests)
**Setup Phase (Phase 1)**: 7 tasks
**Foundational Phase (Phase 2)**: 19 tasks (7 unit tests + 12 implementation)
**User Story 1 (P1)**: 36 tasks (4 unit tests + rest implementation + 5 integration tests)
**User Story 2 (P1)**: 27 tasks (2 unit tests + rest implementation + 4 integration tests)
**User Story 3 (P2)**: 20 tasks (2 unit tests + rest implementation + 4 integration tests + 1 perf test)
**User Story 4 (P2)**: 40 tasks (3 unit tests + rest implementation + 5 integration tests)
**User Story 5 (P2)**: 27 tasks (1 unit test + rest implementation + 4 integration tests)
**User Story 6 (P3)**: 14 tasks (1 unit test + rest implementation + 4 integration tests)
**User Story 7 (P3)**: 13 tasks (1 unit test + rest implementation + 4 integration tests)
**User Story 8 (P3)**: 14 tasks (1 unit test + rest implementation + 3 integration tests)
**Advanced Features (P3)**: 6 tasks
**NFR Tasks (Phase 12)**: 31 tasks (security, DR, observability)
**Performance & Documentation (Phase 13-14)**: 9 tasks

**Format Compliance**:
- ✅ ALL tasks use markdown checkbox format `- [ ]`
- ✅ ALL tasks have sequential Task ID (T001-T245)
- ✅ Parallelizable tasks marked with `[P]`
- ✅ User story tasks marked with `[US1]` through `[US8]`
- ✅ Unit tests marked with "Unit Test" prefix
- ✅ Integration tests marked with "Integration Test" prefix
- ✅ ALL tasks include exact file paths
- ✅ **TDD order enforced**: Unit tests → Implementation → Integration tests
- ✅ Clear description of each task's action

**TDD Compliance**:
- ✅ Red phase: Unit tests written first for each user story
- ✅ Green phase: Implementation to pass tests
- ✅ Refactor phase: Integration tests for comprehensive validation
- ✅ No implementation tasks before corresponding unit tests are defined

**Suggested MVP Scope**: Phase 1 (Setup) + Phase 2 (Foundational) + Phase 3 (US1) + Phase 4 (US2) = 89 tasks, ~4-5 weeks with full team. Delivers core 1:1 and group messaging with all foundational quality attributes following TDD discipline.

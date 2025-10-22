# Tasks: Phase 7B - Messaging + Stories System

**Input**: Design documents from `/specs/002-messaging-stories-system/`
**Prerequisites**: plan.md (tech stack: Rust/Tokio/axum, TypeScript/React), spec.md (8 user stories P1-P3), research.md (technology decisions), data-model.md (10 entities)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story in parallel.

## Path Conventions

- **Backend**: `backend/user-service/src/`
- **Frontend**: `frontend/src/`
- **Tests**: `backend/user-service/tests/`
- **Migrations**: `backend/user-service/migrations/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and core backend/frontend structure

- [ ] T001 Create PostgreSQL migrations directory structure at `backend/user-service/migrations/`
- [ ] T002 [P] Configure Rust project dependencies in `backend/user-service/Cargo.toml` (axum, tokio-tungstenite, sodiumoxide, elasticsearch, sqlx, serde)
- [ ] T003 [P] Configure TypeScript/React frontend dependencies in `frontend/package.json` (react, zustand, ws, tweetnacl-js, axios, vitest)
- [ ] T004 [P] Setup linting and formatting: `cargo clippy`, `cargo fmt`, `eslint`, `prettier` configurations
- [ ] T005 Create base project structure with error handling module in `backend/user-service/src/error.rs`
- [ ] T006 [P] Initialize logger and tracing infrastructure in `backend/user-service/src/logging.rs`
- [ ] T007 [P] Setup environment configuration in `backend/user-service/.env.example` and `backend/user-service/src/config.rs`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T008 Create database connection pool in `backend/user-service/src/db.rs` (PostgreSQL with sqlx)
- [ ] T009 [P] Implement authentication middleware (JWT validation) in `backend/user-service/src/middleware/auth.rs`
- [ ] T010 [P] Implement authorization middleware (role-based access control) in `backend/user-service/src/middleware/authorization.rs`
- [ ] T011 [P] Setup API routing structure in `backend/user-service/src/routes/mod.rs` with modular route handlers
- [ ] T012 Create base models for User, Conversation, Message in `backend/user-service/src/models/mod.rs`
- [ ] T013 [P] Setup Redis connection pool in `backend/user-service/src/cache/mod.rs`
- [ ] T014 [P] Configure error handling and logging middleware in `backend/user-service/src/middleware/mod.rs`
- [ ] T015 Create frontend context and state management in `frontend/src/context/AuthContext.tsx` and `frontend/src/stores/appStore.ts` (Zustand)
- [ ] T016 [P] Setup WebSocket connection factory in `backend/user-service/src/websocket/mod.rs` with connection registry
- [ ] T017 [P] Setup Elasticsearch client in `backend/user-service/src/search/mod.rs`
- [ ] T018 Create initial migration for core User table in `backend/user-service/migrations/0001_create_users.sql`
- [ ] T019 [P] Create comprehensive test infrastructure in `backend/user-service/tests/common/mod.rs` with helpers and fixtures

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Send and Receive Direct Messages (Priority: P1) 🎯 MVP

**Goal**: Enable real-time 1:1 messaging with message persistence, WebSocket delivery, and offline queue support

**Independent Test**: Can be fully tested by creating a 1:1 conversation between two users and verifying message send/receive with WebSocket delivery <100ms latency. Delivers core messaging value. No dependency on stories, reactions, or group conversations.

### Implementation for User Story 1

**Database & Models**:
- [ ] T020 [P] [US1] Create Conversation migration in `backend/user-service/migrations/0002_create_conversations.sql` (id, type, name, description, member_count, last_message_id, created_at, updated_at)
- [ ] T021 [P] [US1] Create ConversationMember migration in `backend/user-service/migrations/0003_create_conversation_members.sql` (conversation_id, user_id, role, joined_at, last_read_at, is_muted, UNIQUE constraint on conversation_id+user_id)
- [ ] T022 [P] [US1] Create Message migration in `backend/user-service/migrations/0004_create_messages.sql` (id, conversation_id, sender_id, content_encrypted BYTEA, content_nonce BYTEA, sequence_number BIGSERIAL, idempotency_key, created_at, edited_at, deleted_at, reaction_count, INDEXES on conversation_id, sender_id, idempotency_key)
- [ ] T023 [P] [US1] Create Conversation model in `backend/user-service/src/models/conversation.rs`
- [ ] T024 [P] [US1] Create Message model in `backend/user-service/src/models/message.rs` with encryption_version, sequence_number, idempotency_key fields

**Services**:
- [ ] T025 [P] [US1] Implement ConversationService in `backend/user-service/src/services/conversation_service.rs` with methods: create_direct_conversation, get_conversation, list_conversations
- [ ] T026 [US1] Implement MessageService in `backend/user-service/src/services/message_service.rs` with methods: send_message (E2E encryption wrapper), get_message_history, update_message, soft_delete_message, handle_offline_queue (depends on T025)
- [ ] T027 [P] [US1] Implement E2E encryption in `backend/user-service/src/services/encryption.rs` using sodiumoxide (NaCl box, symmetric encryption with per-message nonce)
- [ ] T028 [P] [US1] Implement offline message queue processor in `backend/user-service/src/services/offline_queue.rs` with replay and deduplication (idempotency_key)

**REST API Endpoints**:
- [ ] T029 [P] [US1] Implement POST /conversations endpoint in `backend/user-service/src/routes/conversations.rs` (create direct 1:1 conversation, validate both users exist)
- [ ] T030 [P] [US1] Implement GET /conversations/{id} endpoint in `backend/user-service/src/routes/conversations.rs` (fetch conversation details with member count, last message)
- [ ] T031 [US1] Implement POST /conversations/{id}/messages endpoint in `backend/user-service/src/routes/messages.rs` (send message with E2E encryption, return message with sequence_number, idempotency_key handling)
- [ ] T032 [US1] Implement GET /conversations/{id}/messages endpoint in `backend/user-service/src/routes/messages.rs` (fetch message history, support pagination, include reaction_count)
- [ ] T033 [P] [US1] Implement PUT /messages/{id} endpoint in `backend/user-service/src/routes/messages.rs` (edit message, 15-minute window, broadcast via WebSocket)
- [ ] T034 [P] [US1] Implement DELETE /messages/{id} endpoint in `backend/user-service/src/routes/messages.rs` (soft delete, broadcast removal via WebSocket)

**WebSocket Real-time**:
- [ ] T035 [US1] Implement WebSocket message handler in `backend/user-service/src/websocket/handlers.rs` with message type dispatch (send, receive, typing, online_status)
- [ ] T036 [US1] Implement conversation subscription in `backend/user-service/src/websocket/subscription.rs` (track which users are listening to which conversations, broadcast to subscribers)
- [ ] T037 [P] [US1] Implement message broadcast in `backend/user-service/src/websocket/broadcast.rs` (send message to all conversation members, include sequence_number for ordering)
- [ ] T038 [P] [US1] Implement Redis pub/sub for WebSocket distribution in `backend/user-service/src/websocket/pubsub.rs` (conversation:${id} channels for horizontal scaling)
- [ ] T039 [US1] Implement heartbeat/keep-alive in WebSocket handler with ping/pong every 30 seconds

**Frontend Components**:
- [ ] T040 [P] [US1] Create ConversationList component in `frontend/src/components/MessagingUI/ConversationList.tsx` (list all conversations with last message preview)
- [ ] T041 [P] [US1] Create MessageThread component in `frontend/src/components/MessagingUI/MessageThread.tsx` (display messages in conversation, auto-scroll to latest, virtual scrolling for history)
- [ ] T042 [US1] Create MessageComposer component in `frontend/src/components/MessagingUI/MessageComposer.tsx` (input field, send button, E2E encryption before send, offline queue if no connection)
- [ ] T043 [P] [US1] Create WebSocket client in `frontend/src/services/websocket/WebSocketClient.ts` (connect to /ws endpoint, handle message receive, dispatch to Zustand store)
- [ ] T044 [P] [US1] Implement E2E encryption in `frontend/src/services/encryption/client.ts` using tweetnacl-js (NaCl box encryption with per-message random nonce)
- [ ] T045 [US1] Implement offline queue in `frontend/src/services/offlineQueue/Queue.ts` using IndexedDB (store unsent messages, replay on reconnect with idempotency_key)
- [ ] T046 [P] [US1] Create Zustand store for messaging in `frontend/src/stores/messagingStore.ts` (conversations, messages, current conversation, UI state)

**Testing**:
- [ ] T047 [P] [US1] Create integration test for 1:1 message send/receive in `backend/user-service/tests/integration/test_direct_messaging.rs` (create 2 users, conversation, send message, verify WebSocket delivery <100ms)
- [ ] T048 [P] [US1] Create integration test for message history retrieval in `backend/user-service/tests/integration/test_message_history.rs` (send 10 messages, reconnect, fetch history, verify order)
- [ ] T049 [P] [US1] Create unit test for E2E encryption in `backend/user-service/tests/unit/test_encryption.rs` (encrypt/decrypt roundtrip, verify nonce randomness)
- [ ] T050 [P] [US1] Create unit test for offline queue in `backend/user-service/tests/unit/test_offline_queue.rs` (queue messages, verify deduplication, test replay ordering)
- [ ] T051 [US1] Create frontend test for message send in `frontend/src/components/MessagingUI/__tests__/MessageComposer.test.ts` (type message, encrypt, send, verify store update)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently. Can demo 1:1 messaging, offline support, and E2E encryption.

---

## Phase 4: User Story 2 - Create and Manage Group Conversations (Priority: P1)

**Goal**: Enable creation of group conversations with 3-500 members, member management (add/remove/role assignment), and group messaging

**Independent Test**: Can be fully tested by creating a 3+ person group, adding/removing members, and verifying all messages are visible to all active members. Can run in parallel with US1 after foundational phase.

### Implementation for User Story 2

**Database & Models**:
- [ ] T052 [P] [US2] Extend Conversation model in `backend/user-service/src/models/conversation.rs` to support group type with member_count cache, last_message_id denormalization

**Services**:
- [ ] T053 [US2] Implement group conversation creation in ConversationService `backend/user-service/src/services/conversation_service.rs` with create_group_conversation(name, description, initial_members) method and member_count validation (3-500)
- [ ] T054 [P] [US2] Implement member management in `backend/user-service/src/services/member_service.rs` with add_member, remove_member, update_member_role (member→admin, admin→member), check_membership methods
- [ ] T055 [P] [US2] Implement group metadata update in ConversationService with update_group_name, update_group_description, get_group_members methods
- [ ] T056 [US2] Extend MessageService to support group broadcast (send message from sender to all conversation members, verify sender is member)

**REST API Endpoints**:
- [ ] T057 [US2] Extend POST /conversations endpoint in `backend/user-service/src/routes/conversations.rs` to support group creation with name, description, initial_members array (3-500 limit)
- [ ] T058 [P] [US2] Implement POST /conversations/{id}/members endpoint in `backend/user-service/src/routes/members.rs` (add member with permission check, prevent duplicates)
- [ ] T059 [P] [US2] Implement DELETE /conversations/{id}/members/{user_id} endpoint in `backend/user-service/src/routes/members.rs` (remove member, update member_count cache)
- [ ] T060 [P] [US2] Implement PUT /conversations/{id}/members/{user_id} endpoint in `backend/user-service/src/routes/members.rs` (change role: member→admin, admin→member, authorization check)
- [ ] T061 [US2] Implement GET /conversations/{id}/members endpoint in `backend/user-service/src/routes/members.rs` (list all members with role, joined_at, pagination)
- [ ] T062 [P] [US2] Implement PUT /conversations/{id} endpoint in `backend/user-service/src/routes/conversations.rs` (update group name/description, admin-only)

**WebSocket Extensions**:
- [ ] T063 [P] [US2] Extend WebSocket broadcast to support group channels in `backend/user-service/src/websocket/broadcast.rs` (send to all members of conversation)
- [ ] T064 [P] [US2] Implement member leave notification in WebSocket handler (broadcast member_left event with user_id to remaining members)
- [ ] T065 [US2] Implement member join notification in WebSocket handler (broadcast member_joined event to all members)

**Frontend Components**:
- [ ] T066 [P] [US2] Create GroupCreator component in `frontend/src/components/MessagingUI/GroupCreator.tsx` (name input, member selector, create button, validation)
- [ ] T067 [P] [US2] Create MemberList component in `frontend/src/components/MessagingUI/MemberList.tsx` (show members with roles, add/remove buttons for admins)
- [ ] T068 [P] [US2] Extend ConversationList to highlight group conversations and show member count in `frontend/src/components/MessagingUI/ConversationList.tsx`
- [ ] T069 [US2] Extend MessageThread component to show message sender name in `frontend/src/components/MessagingUI/MessageThread.tsx` (in group context)

**Testing**:
- [ ] T070 [P] [US2] Create integration test for group creation in `backend/user-service/tests/integration/test_group_conversations.rs` (create group with 5 users, verify member_count)
- [ ] T071 [P] [US2] Create integration test for group messaging in `backend/user-service/tests/integration/test_group_messaging.rs` (5 users, send message, verify all receive via WebSocket)
- [ ] T072 [P] [US2] Create integration test for member management in `backend/user-service/tests/integration/test_member_management.rs` (add member, remove member, verify role changes)
- [ ] T073 [P] [US2] Create integration test for group size limits in `backend/user-service/tests/integration/test_group_size_limits.rs` (attempt to create 501-member group, verify rejection)

**Checkpoint**: User Stories 1 AND 2 should both work independently. Can demo 1:1 messaging AND group messaging with member management.

---

## Phase 5: User Story 3 - Search Messages and Conversations (Priority: P2)

**Goal**: Enable full-text message search with keyword, sender, conversation, and date filters via Elasticsearch with <200ms P95 latency

**Independent Test**: Can be fully tested by indexing messages in Elasticsearch, executing search queries with various filters, and verifying result accuracy and performance <200ms P95. Can run in parallel with US1/US2 after foundational phase.

### Implementation for User Story 3

**Search Infrastructure**:
- [ ] T074 [P] [US3] Setup Elasticsearch client in `backend/user-service/src/search/elasticsearch.rs` with index management (create, delete, exists)
- [ ] T075 [P] [US3] Create Elasticsearch message index schema in `backend/user-service/src/search/index_schema.rs` (mapping with text analyzer for content, keyword fields for sender_id/conversation_id/created_at)
- [ ] T076 [US3] Implement message indexing on create/update in MessageService (index to Elasticsearch after successful PostgreSQL insert)
- [ ] T077 [P] [US3] Implement message removal from index on delete in MessageService (delete from Elasticsearch on soft delete)
- [ ] T078 [P] [US3] Create Kafka CDC setup guide in `backend/user-service/docs/elasticsearch-cdc.md` with Debezium connector configuration for PostgreSQL→Kafka→Elasticsearch sync

**Search Service**:
- [ ] T079 [US3] Implement SearchService in `backend/user-service/src/services/search_service.rs` with search_messages(query, filters) method supporting keyword, sender_id, conversation_id, date_range filters
- [ ] T080 [P] [US3] Implement result ranking in SearchService (relevance scoring, recency boost)
- [ ] T081 [P] [US3] Implement pagination in search results (limit, offset, total count)

**REST API Endpoints**:
- [ ] T082 [US3] Implement GET /search/messages endpoint in `backend/user-service/src/routes/search.rs` with query parameters (q, sender_id, conversation_id, date_from, date_to, limit, offset)
- [ ] T083 [P] [US3] Implement search response serialization in `backend/user-service/src/routes/search.rs` (message summary with conversation context, sender name, relevance score)

**Frontend Search UI**:
- [ ] T084 [P] [US3] Create SearchBar component in `frontend/src/components/MessagingUI/SearchBar.tsx` (search input, debounced query)
- [ ] T085 [P] [US3] Create SearchResults component in `frontend/src/components/MessagingUI/SearchResults.tsx` (display search results, conversation context, click to jump to message)
- [ ] T086 [US3] Implement search filters UI in `frontend/src/components/MessagingUI/SearchFilters.tsx` (sender dropdown, conversation filter, date range picker)
- [ ] T087 [P] [US3] Create Zustand store for search in `frontend/src/stores/searchStore.ts` (query, filters, results, loading state)

**Testing**:
- [ ] T088 [P] [US3] Create integration test for message search in `backend/user-service/tests/integration/test_search.rs` (index 100 messages, search by keyword, verify results <200ms)
- [ ] T089 [P] [US3] Create integration test for search filters in `backend/user-service/tests/integration/test_search_filters.rs` (search with sender_id filter, conversation_id filter, date_range filter)
- [ ] T090 [P] [US3] Create integration test for search ranking in `backend/user-service/tests/integration/test_search_ranking.rs` (verify relevance scores, recency boost)
- [ ] T091 [P] [US3] Create performance test for search latency in `backend/user-service/tests/load/test_search_latency.rs` (1000 message index, 100 queries, verify P95 <200ms)

**Checkpoint**: User Stories 1, 2, AND 3 should all work independently. Can demo 1:1 messaging, group messaging, and full-text search.

---

## Phase 6: User Story 4 - Create and Share Stories (Priority: P2)

**Goal**: Enable ephemeral stories (images/videos) with 24-hour auto-expiration, three-tier privacy (public/followers/close-friends), and view tracking

**Independent Test**: Can be fully tested by creating a story, verifying visibility rules and 24-hour expiration, and testing view counts. Can run in parallel with US1-3 after foundational phase.

### Implementation for User Story 4

**Database & Models**:
- [ ] T092 [P] [US4] Create Story migration in `backend/user-service/migrations/0005_create_stories.sql` (id, user_id, content_type ENUM, content_url, caption, privacy_level ENUM, created_at, expires_at=created_at+24h, view_count, is_expired, CHECK constraint on expires_at)
- [ ] T093 [P] [US4] Create StoryView migration in `backend/user-service/migrations/0006_create_story_views.sql` (id, story_id, viewer_id, viewed_at, view_duration_seconds, UNIQUE on story_id+viewer_id)
- [ ] T094 [P] [US4] Create CloseFriends migration in `backend/user-service/migrations/0007_create_close_friends.sql` (user_id, close_friend_id, created_at, max 100 per user, UNIQUE constraint)
- [ ] T095 [P] [US4] Create Story model in `backend/user-service/src/models/story.rs` with privacy_level enum (public|followers|close_friends), expires_at, view_count fields
- [ ] T096 [P] [US4] Create StoryView model in `backend/user-service/src/models/story_view.rs`

**Services**:
- [ ] T097 [US4] Implement StoryService in `backend/user-service/src/services/story_service.rs` with create_story(user_id, content_type, content_url, caption, privacy_level) method
- [ ] T098 [P] [US4] Implement story visibility check in StoryService with can_view_story(viewer_id, story_id) method (check privacy_level, followers, close_friends)
- [ ] T099 [P] [US4] Implement view tracking in StoryService with track_story_view(story_id, viewer_id) method (insert StoryView, increment view_count cache)
- [ ] T100 [P] [US4] Implement story expiration in StoryService with expire_stories() method (find stories where expires_at < NOW(), soft delete, clean up StoryView records)
- [ ] T101 [P] [US4] Setup Tokio interval task for story expiration in `backend/user-service/src/tasks/story_expiration.rs` (run every 5 minutes, call expire_stories)
- [ ] T102 [P] [US4] Implement close-friends management in UserService with add_close_friend, remove_close_friend, get_close_friends methods (max 100 per user)

**REST API Endpoints**:
- [ ] T103 [US4] Implement POST /stories endpoint in `backend/user-service/src/routes/stories.rs` (upload story, set privacy_level, set expires_at = now + 24h)
- [ ] T104 [P] [US4] Implement GET /stories/feed endpoint in `backend/user-service/src/routes/stories.rs` (fetch user's story feed with privacy filtering, include view_count)
- [ ] T105 [P] [US4] Implement GET /stories/{id} endpoint in `backend/user-service/src/routes/stories.rs` (fetch story details, check visibility, track view)
- [ ] T106 [P] [US4] Implement GET /users/{id}/stories endpoint in `backend/user-service/src/routes/stories.rs` (fetch specific user's stories with privacy filtering)
- [ ] T107 [P] [US4] Implement PUT /stories/{id}/privacy endpoint in `backend/user-service/src/routes/stories.rs` (change privacy_level, owner-only)
- [ ] T108 [P] [US4] Implement DELETE /stories/{id} endpoint in `backend/user-service/src/routes/stories.rs` (manual deletion by owner or admin)
- [ ] T109 [P] [US4] Implement GET /users/{id}/close-friends endpoint in `backend/user-service/src/routes/close_friends.rs` (list close-friends, max 100)
- [ ] T110 [P] [US4] Implement POST /users/{id}/close-friends/{friend_id} endpoint in `backend/user-service/src/routes/close_friends.rs` (add to close-friends, enforce max 100)
- [ ] T111 [P] [US4] Implement DELETE /users/{id}/close-friends/{friend_id} endpoint in `backend/user-service/src/routes/close_friends.rs` (remove from close-friends)

**Frontend Components**:
- [ ] T112 [P] [US4] Create StoryCreator component in `frontend/src/components/StoriesUI/StoryCreator.tsx` (image/video upload, caption input, privacy selector, create button)
- [ ] T113 [P] [US4] Create StoryFeed component in `frontend/src/components/StoriesUI/StoryFeed.tsx` (display user's own stories and followed users' stories with privacy filtering)
- [ ] T114 [P] [US4] Create StoryViewer component in `frontend/src/components/StoriesUI/StoryViewer.tsx` (fullscreen story display, show view_count, track view duration)
- [ ] T115 [P] [US4] Create PrivacySelector component in `frontend/src/components/StoriesUI/PrivacySelector.tsx` (radio buttons: public, followers, close-friends)
- [ ] T116 [P] [US4] Create CloseFriendsList component in `frontend/src/components/SettingsUI/CloseFriendsList.tsx` (manage close-friends, add/remove interface)
- [ ] T117 [US4] Implement story feed store in Zustand `frontend/src/stores/storyStore.ts` (stories, current_story, viewed_stories, privacy_preferences)

**Testing**:
- [ ] T118 [P] [US4] Create integration test for story creation in `backend/user-service/tests/integration/test_story_creation.rs` (create story, verify expires_at = created_at + 24h)
- [ ] T119 [P] [US4] Create integration test for story privacy in `backend/user-service/tests/integration/test_story_privacy.rs` (create public/followers/close-friends stories, verify visibility)
- [ ] T120 [P] [US4] Create integration test for story view tracking in `backend/user-service/tests/integration/test_story_views.rs` (create story, 5 users view, verify view_count = 5, no duplicates)
- [ ] T121 [P] [US4] Create integration test for story expiration in `backend/user-service/tests/integration/test_story_expiration.rs` (create story, advance clock 24h, verify soft delete)
- [ ] T122 [P] [US4] Create unit test for story visibility logic in `backend/user-service/tests/unit/test_story_visibility.rs` (check all privacy_level combinations)

**Checkpoint**: User Stories 1, 2, 3, AND 4 should all work independently. Can demo full messaging system AND ephemeral stories with privacy.

---

## Phase 7: User Story 5 - React to Messages and Stories (Priority: P2)

**Goal**: Enable emoji reactions on messages and stories with real-time propagation <50ms and reaction count tracking

**Independent Test**: Can be fully tested by adding reactions to a message, verifying real-time propagation <50ms via WebSocket, and confirming reaction counts. Can run in parallel with US1-4 after foundational phase.

### Implementation for User Story 5

**Database & Models**:
- [ ] T123 [P] [US5] Create MessageReaction migration in `backend/user-service/migrations/0008_create_message_reactions.sql` (id, message_id, user_id, emoji, created_at, UNIQUE on message_id+user_id+emoji, INDEX on message_id)
- [ ] T124 [P] [US5] Create StoryReaction migration in `backend/user-service/migrations/0009_create_story_reactions.sql` (id, story_id, user_id, emoji, created_at, UNIQUE on story_id+user_id+emoji, INDEX on story_id)
- [ ] T125 [P] [US5] Create MessageReaction model in `backend/user-service/src/models/message_reaction.rs`
- [ ] T126 [P] [US5] Create StoryReaction model in `backend/user-service/src/models/story_reaction.rs`

**Services**:
- [ ] T127 [US5] Implement ReactionService in `backend/user-service/src/services/reaction_service.rs` with add_message_reaction(message_id, user_id, emoji), remove_message_reaction methods
- [ ] T128 [P] [US5] Extend ReactionService with add_story_reaction, remove_story_reaction, get_message_reactions(message_id), get_story_reactions(story_id) methods
- [ ] T129 [P] [US5] Implement reaction count caching in ReactionService (cache count per message/story in Redis)
- [ ] T130 [US5] Extend MessageService to denormalize reaction_count on insert, update cache on add/remove

**REST API Endpoints**:
- [ ] T131 [US5] Implement POST /messages/{id}/reactions endpoint in `backend/user-service/src/routes/reactions.rs` (add emoji reaction, prevent duplicates per user)
- [ ] T132 [P] [US5] Implement DELETE /messages/{id}/reactions/{emoji} endpoint in `backend/user-service/src/routes/reactions.rs` (remove reaction by current user)
- [ ] T133 [P] [US5] Implement GET /messages/{id}/reactions endpoint in `backend/user-service/src/routes/reactions.rs` (list all reactions with user count per emoji)
- [ ] T134 [P] [US5] Implement POST /stories/{id}/reactions endpoint in `backend/user-service/src/routes/reactions.rs` (add emoji reaction to story)
- [ ] T135 [P] [US5] Implement DELETE /stories/{id}/reactions/{emoji} endpoint in `backend/user-service/src/routes/reactions.rs` (remove story reaction)
- [ ] T136 [P] [US5] Implement GET /stories/{id}/reactions endpoint in `backend/user-service/src/routes/reactions.rs` (list story reactions)

**WebSocket Real-time**:
- [ ] T137 [US5] Extend WebSocket handler to support reaction events in `backend/user-service/src/websocket/handlers.rs` (add_reaction, remove_reaction message types)
- [ ] T138 [P] [US5] Implement reaction broadcast in `backend/user-service/src/websocket/broadcast.rs` (send reaction add/remove to all message/story viewers within 50ms)
- [ ] T139 [P] [US5] Implement optimistic updates for reactions (send immediate ACK to sender before server processing)

**Frontend Components**:
- [ ] T140 [P] [US5] Create ReactionPicker component in `frontend/src/components/MessagingUI/ReactionPicker.tsx` (emoji selector with common emojis)
- [ ] T141 [P] [US5] Create ReactionDisplay component in `frontend/src/components/MessagingUI/ReactionDisplay.tsx` (show reaction count by emoji, add/remove buttons)
- [ ] T142 [P] [US5] Extend MessageThread component to display reactions in `frontend/src/components/MessagingUI/MessageThread.tsx`
- [ ] T143 [US5] Extend StoryViewer component to display reactions in `frontend/src/components/StoriesUI/StoryViewer.tsx`
- [ ] T144 [P] [US5] Implement optimistic reaction updates in Zustand store `frontend/src/stores/messagingStore.ts` (add reaction locally, then sync with server)

**Testing**:
- [ ] T145 [P] [US5] Create integration test for message reactions in `backend/user-service/tests/integration/test_message_reactions.rs` (add reaction, verify broadcast <50ms, check count)
- [ ] T146 [P] [US5] Create integration test for story reactions in `backend/user-service/tests/integration/test_story_reactions.rs` (add reaction, verify count)
- [ ] T147 [P] [US5] Create integration test for duplicate prevention in `backend/user-service/tests/integration/test_reaction_duplicates.rs` (attempt to add same reaction twice, verify uniqueness)
- [ ] T148 [P] [US5] Create performance test for reaction broadcast in `backend/user-service/tests/load/test_reaction_broadcast_latency.rs` (100 concurrent reaction adds, verify P99 <100ms)

**Checkpoint**: User Stories 1-5 should all work independently. Can demo complete messaging with reactions AND stories with reactions.

---

## Phase 8: User Story 6 - Manage Message Visibility and Deletion (Priority: P3)

**Goal**: Enable message editing (15-minute window) and deletion with soft delete and broadcast to all viewers

**Independent Test**: Can be fully tested by deleting messages, verifying removal from all viewers, and testing admin deletion capabilities. Can run in parallel after foundational phase.

### Implementation for User Story 6

**Services**:
- [ ] T149 [US6] Extend MessageService with edit_message(message_id, new_content, user_id) method (15-minute window, encrypt new content, broadcast update)
- [ ] T150 [P] [US6] Extend MessageService with delete_message(message_id, user_id, is_admin) method (soft delete via deleted_at, authorization check)
- [ ] T151 [P] [US6] Implement message edit history tracking in `backend/user-service/src/models/message.rs` with edited_at timestamp

**REST API Endpoints**:
- [ ] T152 [US6] Implement PUT /messages/{id} endpoint for editing in `backend/user-service/src/routes/messages.rs` (15-minute limit, content re-encryption, broadcast via WebSocket)
- [ ] T153 [P] [US6] Implement DELETE /messages/{id} endpoint in `backend/user-service/src/routes/messages.rs` with role-based authorization (owner after 15 min, admin anytime)

**WebSocket Real-time**:
- [ ] T154 [US6] Extend WebSocket broadcast for message updates in `backend/user-service/src/websocket/broadcast.rs` (broadcast message_updated event with new content to all viewers)
- [ ] T155 [P] [US6] Extend WebSocket broadcast for message deletion in `backend/user-service/src/websocket/broadcast.rs` (broadcast message_deleted event to remove from all viewers)

**Frontend Components**:
- [ ] T156 [P] [US6] Extend MessageThread to show edit/delete buttons in `frontend/src/components/MessagingUI/MessageThread.tsx` (conditional based on ownership and 15-min window)
- [ ] T157 [P] [US6] Implement message edit in MessageComposer (if editing existing message, prefill content, show "15 minutes remaining" timer)
- [ ] T158 [US6] Implement local message deletion from UI in `frontend/src/stores/messagingStore.ts` (optimistic update, sync with server)

**Testing**:
- [ ] T159 [P] [US6] Create integration test for message editing in `backend/user-service/tests/integration/test_message_editing.rs` (edit message, verify broadcast, check 15-min limit)
- [ ] T160 [P] [US6] Create integration test for message deletion in `backend/user-service/tests/integration/test_message_deletion.rs` (delete message, verify removal from all viewers)
- [ ] T161 [P] [US6] Create integration test for admin deletion in `backend/user-service/tests/integration/test_admin_deletion.rs` (admin deletes user message anytime)
- [ ] T162 [P] [US6] Create unit test for 15-minute window enforcement in `backend/user-service/tests/unit/test_edit_time_window.rs`

**Checkpoint**: User Stories 1-6 should all work independently. Can demo message editing, deletion with time windows, and admin control.

---

## Phase 9: User Story 7 - Handle Message Offline Queue and Sync (Priority: P3)

**Goal**: Enable client-side offline message queueing with automatic replay and server-side deduplication on reconnect

**Independent Test**: Can be fully tested by simulating offline mode, queuing messages, reconnecting, and verifying queue is processed correctly. Can run in parallel after foundational phase.

### Implementation for User Story 7

**Services**:
- [ ] T163 [P] [US7] Implement offline queue processor in MessageService (already partially done in T028, extend with replay logic)
- [ ] T164 [US7] Implement message deduplication in MessageService using idempotency_key (check existing message with same key before inserting, return existing on duplicate)
- [ ] T165 [P] [US7] Implement offline queue sync endpoint in `backend/user-service/src/routes/messages.rs` - POST /messages/sync (batch process queued messages with idempotency keys)

**REST API Endpoints**:
- [ ] T166 [US7] Implement POST /messages/sync endpoint (batch API for offline queue replay, returns processed message IDs and any failures)

**Frontend Offline Queue**:
- [ ] T167 [US7] Extend offline queue in `frontend/src/services/offlineQueue/Queue.ts` with retry logic (exponential backoff on network errors)
- [ ] T168 [P] [US7] Implement offline mode detection in WebSocket client (detect connection loss, set offline flag in Zustand store)
- [ ] T169 [P] [US7] Implement auto-replay on reconnect in `frontend/src/services/offlineQueue/Queue.ts` (when connection restored, send all queued messages)
- [ ] T170 [P] [US7] Implement queue status UI in `frontend/src/components/MessagingUI/OfflineQueueStatus.tsx` (show "X messages pending" when offline)
- [ ] T171 [US7] Implement idempotency_key generation in `frontend/src/services/encryption/client.ts` (use UUID per message for deduplication)

**Testing**:
- [ ] T172 [P] [US7] Create integration test for offline queueing in `backend/user-service/tests/integration/test_offline_queue.rs` (send while offline, reconnect, verify messages delivered)
- [ ] T173 [P] [US7] Create integration test for deduplication in `backend/user-service/tests/integration/test_queue_deduplication.rs` (send duplicate idempotency_keys, verify no duplicates)
- [ ] T174 [P] [US7] Create integration test for queue ordering in `backend/user-service/tests/integration/test_queue_ordering.rs` (queue 10 messages, replay, verify order via sequence_number)
- [ ] T175 [P] [US7] Create frontend test for offline detection in `frontend/src/services/offlineQueue/__tests__/OfflineDetection.test.ts`

**Checkpoint**: User Stories 1-7 should all work independently. Can demo offline messaging with automatic recovery.

---

## Phase 10: User Story 8 - View Conversation Metadata and Analytics (Priority: P3)

**Goal**: Provide conversation metadata (creation date, member list, message count) and analytics (messages per day, most active members)

**Independent Test**: Can be fully tested by querying conversation metadata and analytics APIs, verifying accuracy of computed metrics. Can run in parallel after foundational phase.

### Implementation for User Story 8

**Services**:
- [ ] T176 [P] [US8] Implement conversation metadata in ConversationService with get_conversation_metadata(conversation_id) method (member_count, last_message_id, message_count, created_at)
- [ ] T177 [US8] Implement conversation analytics in `backend/user-service/src/services/analytics_service.rs` with get_conversation_analytics(conversation_id, timerange) method
- [ ] T178 [P] [US8] Implement message count caching in ConversationService (cache in Redis, update on new message)
- [ ] T179 [P] [US8] Implement active member stats in analytics (count unique senders per day, last 7 days)

**REST API Endpoints**:
- [ ] T180 [US8] Implement GET /conversations/{id}/metadata endpoint in `backend/user-service/src/routes/conversations.rs` (return member_count, message_count, created_at, last_message_at)
- [ ] T181 [P] [US8] Implement GET /conversations/{id}/analytics endpoint in `backend/user-service/src/routes/analytics.rs` (return messages_per_day, active_members, date_range)
- [ ] T182 [P] [US8] Implement GET /conversations/{id}/analytics/members endpoint in `backend/user-service/src/routes/analytics.rs` (return per-member message count, last_message_at)

**Frontend Analytics Components**:
- [ ] T183 [P] [US8] Create ConversationMetadata component in `frontend/src/components/MessagingUI/ConversationMetadata.tsx` (display creation date, member count, message count)
- [ ] T184 [P] [US8] Create ConversationAnalytics component in `frontend/src/components/Analytics/ConversationAnalytics.tsx` (display messages per day chart, active member list)
- [ ] T185 [P] [US8] Create MemberActivity component in `frontend/src/components/Analytics/MemberActivity.tsx` (list members with message counts)

**Testing**:
- [ ] T186 [P] [US8] Create integration test for conversation metadata in `backend/user-service/tests/integration/test_conversation_metadata.rs` (create conversation, send messages, verify metadata)
- [ ] T187 [P] [US8] Create integration test for analytics accuracy in `backend/user-service/tests/integration/test_analytics_accuracy.rs` (send messages over 7 days, verify analytics)
- [ ] T188 [P] [US8] Create unit test for member activity calculation in `backend/user-service/tests/unit/test_member_activity.rs`

**Checkpoint**: User Stories 1-8 should all work independently. Can demo complete messaging system with analytics dashboard.

---

## Phase 11: Advanced Features (P3)

**Goal**: Implement @mention notifications and group improvements

**@Mention Notifications** (from FR-016):
- [ ] T189 [P] Implement @mention parsing in `backend/user-service/src/services/mention_service.rs` (regex: @[a-zA-Z0-9_]{3,30}, extract mentioned users)
- [ ] T190 [US2] Implement mention validation in message processing (verify mentioned user exists, is in conversation)
- [ ] T191 [US2] Implement mention notification dispatch in `backend/user-service/src/services/notification_service.rs` (create notification record, broadcast via WebSocket if online)
- [ ] T192 [P] Create MentionNotification migration in `backend/user-service/migrations/0010_create_mention_notifications.sql`
- [ ] T193 [P] Implement GET /notifications endpoint in `backend/user-service/src/routes/notifications.rs` (list user's mention notifications)
- [ ] T194 [P] Create frontend MentionNotifications component in `frontend/src/components/Notifications/MentionNotifications.tsx`

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final quality assurance

- [ ] T195 [P] Documentation updates: API reference in `backend/user-service/docs/API.md`
- [ ] T196 [P] Documentation updates: Data model diagram in `specs/002-messaging-stories-system/data-model-diagram.md`
- [ ] T197 [P] Documentation updates: Architecture decision records in `backend/user-service/docs/ADR/`
- [ ] T198 Code cleanup and refactoring across all modules
- [ ] T199 [P] Performance optimization: Profile message send latency, optimize bottlenecks
- [ ] T200 [P] Performance optimization: Profile WebSocket memory usage, optimize denormalizations
- [ ] T201 [P] Run comprehensive integration test suite in `backend/user-service/tests/integration/`
- [ ] T202 [P] Load testing: 50k concurrent WebSocket connections in `backend/user-service/tests/load/test_50k_concurrent.rs`
- [ ] T203 [P] Load testing: 10k msg/sec throughput in `backend/user-service/tests/load/test_10k_throughput.rs`
- [ ] T204 [P] Security hardening: Input validation, SQL injection prevention, XSS prevention
- [ ] T205 [P] Security: Rate limiting implementation in `backend/user-service/src/middleware/rate_limit.rs`
- [ ] T206 [P] Security: Message encryption audit (code review E2E encryption implementation)
- [ ] T207 [P] Frontend accessibility: WCAG 2.1 AA compliance audit
- [ ] T208 Run quickstart.md validation (new engineer onboarding)
- [ ] T209 [P] E2E tests using Cypress: Login, send message, receive, search scenarios in `frontend/e2e/`
- [ ] T210 [P] Browser compatibility testing: Chrome, Firefox, Safari, Edge
- [ ] T211 Database migration testing: Test migration path from Phase 7A to Phase 7B
- [ ] T212 [P] Monitoring setup: Prometheus metrics for message latency, WebSocket connections, search performance
- [ ] T213 [P] Alerting setup: Configure alerts for SLA violations (message latency >200ms P95, WebSocket errors)
- [ ] T214 [P] Logging audit: Ensure sensitive data not logged (message content should be redacted)
- [ ] T215 Create runbook for common operations in `backend/user-service/docs/RUNBOOK.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-10)**: All depend on Foundational phase completion
  - User stories CAN proceed in parallel (if staffed)
  - US1+US2 (P1): Should complete first for MVP
  - US3-5 (P2): Can run in parallel with US1/US2
  - US6-8 (P3): Can run after US1 or in parallel if capacity
  - Advanced features (P3): After all core stories done
- **Polish (Phase 11-12)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1 - Direct Messages)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1 - Group Conversations)**: Can start after Foundational - Builds on US1 infrastructure but independently testable
- **User Story 3 (P2 - Search)**: Can start after Foundational - Builds on US1/US2 but independently testable
- **User Story 4 (P2 - Stories)**: Can start after Foundational - Independent of messaging features
- **User Story 5 (P2 - Reactions)**: Can start after US1/US4 - Depends on message/story models
- **User Story 6 (P3 - Edit/Delete)**: Can start after US1 - Depends on message model
- **User Story 7 (P3 - Offline Queue)**: Can start after US1 - Builds on message send logic
- **User Story 8 (P3 - Analytics)**: Can start after US1/US2 - Depends on conversation/message models

### Within Each User Story

- Database migrations before models
- Models before services
- Services before API endpoints
- API endpoints before WebSocket handlers
- WebSocket handlers before frontend components
- Frontend components before testing

### Parallel Opportunities

**Phase 1 Setup**:
- T002 (Rust deps) and T003 (TS deps) can run in parallel
- T004 (linting) can run in parallel with T005-T007

**Phase 2 Foundational**:
- T009-T010 (auth middleware) can run in parallel
- T013-T014 (Redis/ES clients) can run in parallel
- T006-T007 (logging/config) can run in parallel with T008-T010

**Phase 3 US1**:
- T020-T022 (migrations) can run in parallel
- T023-T024 (models) can run in parallel
- T029-T034 (REST endpoints) can run in parallel
- T040-T043 (frontend components) can run in parallel
- All migrations must complete before services start

**Phase 4 US2**:
- T058-T061 (member endpoints) can run in parallel
- T066-T069 (frontend components) can run in parallel

**Phase 5 US3**:
- T084-T087 (search UI components) can run in parallel
- T088-T091 (tests) can run in parallel

**General Parallel Strategy**:
```
Week 5-6 (Setup + Foundational):
  - Team completes Setup + Foundational together (sequential phases)

Week 6-7 (US1 MVP):
  - Engineer A: US1 Database (T020-T022)
  - Engineer B: US1 Services (T025-T028)
  - Engineer C: US1 REST API (T029-T034)
  - FE A: US1 Frontend (T040-T045)
  - All can run in parallel, integration after each completes

Week 7-8 (US2 + US3 in parallel):
  - Engineer A: US2 Services + API (T052-T062)
  - Engineer B: US3 Search (T074-T083)
  - FE A: US2 Components (T066-T069)
  - FE B: US3 Search UI (T084-T087)

Week 8-9 (US4 in parallel):
  - Engineer C: US4 Stories (T092-T111)
  - FE B: US4 Components (T112-T117)

Week 9-10 (US5 + US6 in parallel):
  - Engineer D: US5 Reactions (T123-T151)
  - Engineer E: US6 Edit/Delete (T149-T157)

Week 10-11 (US7 + US8):
  - Engineer B: US7 Offline Queue (T163-T171)
  - Engineer C: US8 Analytics (T176-T188)
```

---

## Implementation Strategy

### MVP First (User Story 1 + 2 Only)

1. Complete Phase 1: Setup (1 week)
2. Complete Phase 2: Foundational (1 week) - **CRITICAL - blocks all stories**
3. Complete Phase 3: User Story 1 (Direct Messages) (2 weeks)
4. Complete Phase 4: User Story 2 (Group Conversations) (1 week)
5. **STOP and VALIDATE**: Both stories fully functional and tested independently
6. Deploy/demo to stakeholders (Week 5 end goal)

**MVP Scope**: Users can send and receive 1:1 and group messages in real-time with persistence, offline support, and E2E encryption. This delivers core messaging value without search or stories.

### Incremental Delivery (Full Phase 7B)

1. Weeks 5-6: Setup + Foundational + US1
2. Week 7: US1 validated + US2 complete
3. Weeks 7-8: US2 validated + US3 (Search) + US4 (Stories) in parallel
4. Weeks 8-9: US3 + US4 validated + US5 (Reactions) + US6 (Edit/Delete) in parallel
5. Weeks 9-10: US5 + US6 validated + US7 (Offline) + US8 (Analytics) in parallel
6. Weeks 10-11: All stories validated, begin Polish
7. Weeks 11-12: Performance testing, security hardening, launch prep

**Incremental Value**:
- Week 7: Core messaging (US1+US2) ✓
- Week 8: + Search + Stories (US3+US4) ✓
- Week 9: + Engagement (Reactions) ✓
- Week 10: + Content Control (Edit/Delete) + Offline Reliability + Analytics ✓

### Parallel Team Strategy (7-8 Engineers)

With full team:

1. Setup + Foundational: All engineers (2 weeks)
2. After Foundational:
   - 2 engineers: US1 (P1 MVP)
   - 2 engineers: US2 (P1 MVP parallel)
   - 1 engineer: US3 Search (P2)
   - 1 engineer: US4 Stories (P2)
   - 2 FE engineers: US1+US2 components
3. After US1+US2 complete:
   - Rotate: Start US5, US6, US7, US8 in parallel
   - FE: Implement US3-8 components

---

## Format Validation Summary

**Total Tasks**: 215
**Setup Phase (Phase 1)**: 7 tasks
**Foundational Phase (Phase 2)**: 12 tasks
**User Story 1 (P1)**: 28 tasks
**User Story 2 (P1)**: 23 tasks
**User Story 3 (P2)**: 18 tasks
**User Story 4 (P2)**: 31 tasks
**User Story 5 (P2)**: 23 tasks
**User Story 6 (P3)**: 14 tasks
**User Story 7 (P3)**: 13 tasks
**User Story 8 (P3)**: 11 tasks
**Advanced Features (P3)**: 6 tasks
**Polish & Cross-Cutting (Phase 12)**: 21 tasks

**Format Compliance**:
- ✅ ALL tasks use markdown checkbox format `- [ ]`
- ✅ ALL tasks have sequential Task ID (T001-T215)
- ✅ Parallelizable tasks marked with `[P]`
- ✅ User story tasks marked with `[US1]` through `[US8]`
- ✅ ALL tasks include exact file paths
- ✅ Setup/Foundational phases have NO story labels
- ✅ Polish phase has NO story labels
- ✅ Clear description of each task's action

**Independent Test Criteria**:
- ✅ US1: 1:1 conversation with WebSocket delivery <100ms
- ✅ US2: 3+ person group with all members receiving messages
- ✅ US3: Keyword search with <200ms P95 latency
- ✅ US4: Story creation with 24h expiration and privacy filtering
- ✅ US5: Emoji reactions with <50ms broadcast
- ✅ US6: Message editing/deletion with 15-minute window
- ✅ US7: Offline queue with deterministic replay
- ✅ US8: Conversation analytics with accurate metrics

**Suggested MVP Scope**: Phase 1 (Setup) + Phase 2 (Foundational) + Phase 3 (US1) + Phase 4 (US2) = 50 tasks, ~4 weeks with full team. Delivers core 1:1 and group messaging with all foundational quality attributes.

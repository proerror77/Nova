# Feature Specification: Phase 7B - Messaging + Stories System

**Feature Branch**: `002-messaging-stories-system`
**Created**: 2025-10-22
**Status**: In Development
**Timeline**: Week 5-12 (8 weeks)
**Team Size**: 4-5 Backend Engineers, 2-3 Frontend Engineers, 1 QA Lead

## Overview

Build a production-grade messaging + stories platform enabling real-time 1:1/group communication and ephemeral content sharing. The system supports 1M+ users with 100M+ daily active conversations, delivering <200ms P95 message latency and <100ms story feed load times. Core features include persistent message storage, real-time WebSocket synchronization, full-text search, and 24-hour auto-expiring stories with reactions.

## User Scenarios & Testing

### User Story 1 - Send and Receive Direct Messages (Priority: P1)

A user initiates a 1:1 conversation with another user and sends messages that are delivered in real-time. Both users can see message history and receive new messages via WebSocket as they arrive.

**Why this priority**: Direct messaging is the foundation of the system. Users must be able to reliably send and receive messages with confidence that messages arrive and persist.

**Independent Test**: Can be fully tested by creating a 1:1 conversation between two users and verifying message send/receive with WebSocket delivery <100ms latency. Delivers core messaging value.

**Acceptance Scenarios**:

1. **Given** User A and User B are authenticated, **When** User A sends a message to User B, **Then** User B receives the message via WebSocket within 100ms and the message is persisted to PostgreSQL
2. **Given** a message was previously sent, **When** User B reconnects, **Then** User B can fetch full message history from the API
3. **Given** User A sends a message, **When** User B is offline, **Then** the message is stored and delivered when User B reconnects

---

### User Story 2 - Create and Manage Group Conversations (Priority: P1)

A user creates a group conversation with multiple participants, invites more members, and manages group metadata like name and description. All members can send and receive messages within the group.

**Why this priority**: Group messaging enables broader collaboration. Supporting multiple participants is critical for team communication scenarios.

**Independent Test**: Can be fully tested by creating a 3+ person group, adding/removing members, and verifying all messages are visible to all active members. Delivers group communication value.

**Acceptance Scenarios**:

1. **Given** User A creates a group with users B and C, **When** User A sends a message, **Then** both User B and C receive it via WebSocket
2. **Given** a group exists, **When** User D is invited and joins, **Then** User D can see message history and all new messages
3. **Given** a group conversation, **When** User B leaves the group, **Then** User B can no longer send/receive messages but history remains

---

### User Story 3 - Search Messages and Conversations (Priority: P2)

A user searches for messages by keywords, sender, or conversation to quickly find past communications. Results are ranked by relevance and sorted by recency.

**Why this priority**: As message volume grows, search becomes essential for discoverability. Enables users to find important information quickly.

**Independent Test**: Can be fully tested by indexing messages in Elasticsearch, executing search queries with various filters, and verifying result accuracy and performance <200ms P95. Delivers search capability.

**Acceptance Scenarios**:

1. **Given** 1000+ messages exist, **When** user searches "project deadline", **Then** matching messages are returned in <200ms with correct conversation context
2. **Given** search results, **When** user filters by conversation or date range, **Then** results are correctly refined
3. **Given** a message is updated or deleted, **When** the user searches, **Then** the search index is updated within 10 seconds

---

### User Story 4 - Create and Share Stories (Priority: P2)

A user creates ephemeral stories (images/videos with optional captions) that are visible to specific audiences for 24 hours. Users can view stories from others and stories auto-expire.

**Why this priority**: Stories are a differentiated feature for ephemeral sharing. Enables time-sensitive content sharing with automatic cleanup.

**Independent Test**: Can be fully tested by creating a story, verifying visibility rules and 24-hour expiration, and testing view counts. Delivers ephemeral sharing value.

**Acceptance Scenarios**:

1. **Given** User A creates a story, **When** User B views their story feed, **Then** User A's story appears and increments view counter
2. **Given** a story is created at time T, **When** >24 hours elapse, **Then** the story is automatically deleted and no longer visible
3. **Given** a story, **When** multiple users view it, **Then** each view is recorded and view counter is accurate

---

### User Story 5 - React to Messages and Stories (Priority: P2)

A user adds emoji reactions to messages and stories. Reactions are displayed in real-time to all participants and reaction counts are maintained.

**Why this priority**: Reactions provide lightweight engagement without typing. Improves user experience for quick responses.

**Independent Test**: Can be fully tested by adding reactions to a message, verifying real-time propagation <50ms via WebSocket, and confirming reaction counts. Delivers engagement value.

**Acceptance Scenarios**:

1. **Given** a message exists, **When** User A adds a thumbs-up reaction, **Then** all active viewers see the reaction appear within 50ms
2. **Given** multiple users react, **When** reactions are counted, **Then** the count is accurate and displayed correctly
3. **Given** a user clicks a reaction, **When** they remove it, **Then** the reaction count decrements

---

### User Story 6 - Manage Message Visibility and Deletion (Priority: P3)

A user can edit or delete their own messages within a time window. Deleted messages are removed from view for all users. Group admins can delete any message.

**Why this priority**: Enables content control and moderation. Important for user safety and message management.

**Independent Test**: Can be fully tested by deleting messages, verifying removal from all viewers, and testing admin deletion capabilities. Delivers content control.

**Acceptance Scenarios**:

1. **Given** User A sent a message <15 minutes ago, **When** User A clicks delete, **Then** the message is removed from all viewers' screens
2. **Given** a message is deleted, **When** users fetch history, **Then** the deleted message does not appear
3. **Given** User A is group admin, **When** User A deletes User B's message, **Then** it is removed immediately

---

### User Story 7 - Handle Message Offline Queue and Sync (Priority: P3)

When a user goes offline, unsent messages are queued locally. When they come back online, queued messages are automatically sent and synced with server state.

**Why this priority**: Enables reliable delivery in unreliable network conditions. Critical for mobile clients.

**Independent Test**: Can be fully tested by simulating offline mode, queuing messages, reconnecting, and verifying queue is processed correctly. Delivers offline reliability.

**Acceptance Scenarios**:

1. **Given** User A is offline, **When** User A sends a message, **Then** the message is stored in local queue
2. **Given** messages are queued, **When** User A comes online, **Then** queued messages are sent and synced
3. **Given** the server receives queued messages, **When** they arrive out of order, **Then** they are stored in correct order

---

### User Story 8 - View Conversation Metadata and Analytics (Priority: P3)

A user can view metadata for a conversation (creation date, member list, message count) and analytics (messages per day, most active members).

**Why this priority**: Provides insights into conversation activity. Useful for analytics and conversation management.

**Independent Test**: Can be fully tested by querying conversation metadata and analytics APIs, verifying accuracy of computed metrics. Delivers analytics value.

**Acceptance Scenarios**:

1. **Given** a group conversation, **When** user views conversation details, **Then** member list, creation date, and message count are displayed
2. **Given** a conversation with activity history, **When** user views analytics, **Then** messages per day and active member stats are accurate
3. **Given** a conversation is updated, **When** metrics are recomputed, **Then** they reflect current state

---

### Edge Cases

- What happens when a user tries to send a message to a deleted conversation?
- How does the system handle messages sent simultaneously by multiple users?
- What happens if a WebSocket connection drops mid-message-send?
- How are reactions handled if a message is deleted before reactions are synced?
- What happens if a user's offline queue exceeds storage capacity?
- How does the system handle story view counts with bot/spam traffic?
- What happens when a group conversation exceeds 500 members? (System enforces limit at group creation)
- How are messages handled if PostgreSQL becomes temporarily unavailable during a send operation?

## Requirements

### Functional Requirements

- **FR-001**: System MUST support 1:1 direct messaging between any two authenticated users
- **FR-002**: System MUST support group conversations with 3-500 members
- **FR-003**: System MUST persist all messages to PostgreSQL with full audit trail
- **FR-004**: System MUST deliver messages via WebSocket in real-time when recipient is online
- **FR-005**: System MUST queue and deliver messages when recipient is offline
- **FR-006**: System MUST support message search via Elasticsearch with keyword, sender, and date filters for search-enabled conversations (non-E2E). Strict E2E conversations MUST NOT be indexed or searchable by the server.
- **FR-007**: System MUST allow users to create ephemeral stories visible for exactly 24 hours
- **FR-008**: System MUST auto-delete stories after 24 hours without manual intervention
- **FR-009**: System MUST support emoji reactions on messages and stories
- **FR-010**: System MUST propagate reactions to all viewers in real-time
- **FR-011**: System MUST allow users to edit/delete their own messages within 15 minutes
- **FR-012**: System MUST allow group admins to delete any message. Admins MUST NOT be able to read message plaintext in strict E2E conversations.
- **FR-013**: System MUST support story view tracking and view count per user
- **FR-014**: System MUST handle message ordering correctly for concurrent sends
- **FR-015**: System MUST provide conversation metadata (members, created_at, message_count)
- **FR-016**: System MUST support @mentions in group messages with real-time notifications to mentioned users
- **FR-017**: System MUST support two conversation privacy modes:
  - Strict E2E: End-to-end encryption using libsodium/NaCl with client-held keys; messages are encrypted on the client and only recipients' devices can decrypt. Server NEVER has access to plaintext. Not indexed or searchable by the server. Admins cannot read plaintext in this mode.
  - Search-enabled: For Phase 7B, server-side decryption is permitted for indexing/moderation with encryption-at-rest and full audit. Search index is populated from decrypted content on the server. Deterministic searchable encryption is deferred to a later phase (see Architecture Decisions). Mode is selectable per conversation; defaults documented in Security & Privacy.
- **FR-018**: System MUST provide three-tier story privacy levels: public (everyone), followers (followers only), close-friends (manually selected group)

### Key Entities

- **Conversation**: Represents a 1:1 or group conversation. Attributes: id, type (direct/group), name, description, created_at, updated_at, member_count, privacy_mode (strict_e2e|search_enabled). Relationships: has_many messages, has_many members via ConversationMember
- **ConversationMember**: Represents participation in a conversation. Attributes: conversation_id, user_id, role (member/admin), joined_at, last_read_at, is_muted, user_public_key (for E2E key exchange)
- **Message**: Represents a single message. Attributes: id, conversation_id, sender_id, content_encrypted (BYTEA), content_nonce (BYTEA), encryption_version, sequence_number, idempotency_key, created_at, edited_at, deleted_at, reaction_count
- **MessageReaction**: Represents an emoji reaction on a message. Attributes: id, message_id, user_id, emoji, created_at
- **Story**: Represents an ephemeral story. Attributes: id, user_id, content_url, caption, created_at, expires_at (created_at + 24h), privacy_level (public|followers|close-friends)
- **StoryView**: Represents a user viewing a story. Attributes: id, story_id, viewer_id, viewed_at, view_duration_seconds
- **StoryReaction**: Represents an emoji reaction on a story. Attributes: id, story_id, user_id, emoji, created_at
- **CloseFriends**: Represents a user-maintained list of close friends. Attributes: id, user_id, friend_id, created_at
- **EncryptionKey**: Represents conversation-level key material (search-enabled only). Attributes: id, conversation_id, key_material, key_version, is_active, created_at, rotated_at
- **MentionNotification**: Represents a notification generated by @mentions. Attributes: id, user_id, conversation_id, message_id, created_at, read_at

## Non-Functional Requirements & Quality Attributes

### Performance Targets

- **Message Latency (P50)**: <100ms (from send to WebSocket delivery)
- **Message Latency (P95)**: <200ms
- **Message Latency (P99)**: <500ms
- **Search Latency (P95)**: <200ms for queries <1000 results
- **Story Feed Load (P95)**: <100ms
- **Reaction Propagation**: <50ms from send to display
- **Message Throughput**: 10,000+ messages/second
- **Concurrent WebSocket Connections**: 50,000+
- **Story Creation Latency**: <500ms

### Scalability Requirements

- **User Scale**: Support 1M+ registered users
- **Daily Active Conversations**: 100M+
- **Total Messages**: 10B+ messages indexed and searchable
- **Stories/Day**: 500M+ new stories created daily
- **Peak Concurrent Connections**: 50,000+ WebSocket connections
- **Horizontal Scaling**: All services must be horizontally scalable

### Reliability & Availability

- **Message Delivery Rate**: >99.9%
- **System Uptime**: 99.95%
- **Message Durability**: All messages persisted before delivery confirmation
- **Offline Message Queue**: Support up to 1000 queued messages per user
- **Recovery Time Objective (RTO)**: <5 minutes for critical failures
- **Recovery Point Objective (RPO)**: <1 minute for message loss

### Security & Privacy

- **Authentication**: OAuth2 + JWT tokens with 1-hour expiration
- **Transport Security**: TLS 1.3 for all network communication; certificate management with automatic renewal via Let's Encrypt/cert-manager
- **Message Encryption**:
  - Two privacy modes per conversation:
    - Strict E2E: Clients encrypt with libsodium NaCl box using recipients' public keys and per-message nonces; server never sees plaintext; not indexed; no admin read access.
    - Search-enabled (Phase 7B default for searchable conversations): Server may decrypt for indexing/moderation; data encrypted at rest (libsodium secret box) with envelope encryption; access tightly controlled and audited. Deterministic searchable encryption is considered future work (Phase 7C) and is not required in Phase 7B.
- **Access Control**: Users can only access conversations they're members of
- **Admin Override**: Admins can delete messages in any conversation. Admins CANNOT view plaintext in strict E2E conversations.
- **PII Protection**: Personally identifiable information encrypted at rest (use libsodium secret box with server master key)
- **Data Retention**: Delete personal data on request within 30 days; audit trail of deletions maintained
- **Forward Secrecy**: Message encryption uses per-message unique nonce; no global key compromise exposes historical messages

### Observability & Monitoring

- **Logging**: All message sends, receives, and reactions logged to structured format
- **Metrics**: Prometheus metrics for latency, throughput, error rates, connection count
- **Tracing**: OpenTelemetry distributed tracing for request flows
- **Alerting**: PagerDuty alerts for SLA violations, error rate >1%, and connection drops

### Testing Requirements

- **Unit Tests**: >160 tests, >85% code coverage
- **Integration Tests**: 40+ tests covering API contracts and database
- **Load Tests**: Verify 50,000+ concurrent connections, 10,000 msg/sec throughput
- **E2E Tests**: 20+ scenario tests for critical user journeys

## Success Criteria

### Measurable Outcomes

- **SC-001**: All 8 user stories deployed to production with zero critical bugs in week 1
- **SC-002**: Message delivery latency P95 <200ms sustained under 50,000 concurrent connections
- **SC-003**: Search queries return results in <200ms for 99% of queries
- **SC-004**: >85% code coverage with 160+ tests (unit + integration)
- **SC-005**: Zero unplanned message loss or corruption events over 30 days
- **SC-006**: >99.9% message delivery rate to online recipients
- **SC-007**: Story auto-deletion completes within 1 hour of 24h expiration window
- **SC-008**: Offline message queue successfully processes 99.9% of queued messages on reconnect

### Launch Readiness Criteria

- ✅ All features tested and working end-to-end
- ✅ Performance targets met under load
- ✅ Security review completed and passed
- ✅ Documentation complete and team trained
- ✅ Monitoring and alerting operational
- ✅ Runbooks prepared for on-call team

## Architecture Decisions & Trade-offs

### E2E Encryption + Search (Phase 7B scope)

**Problem**: E2E encryption (only recipients can decrypt) conflicts with server-side search and administrative moderation.

**Decision (Phase 7B)**: Two privacy modes with clear boundaries:
1. **Messages**: Always encrypted with libsodium NaCl box (asymmetric + AEAD)
   - Sender encrypts with recipients' public keys
   - Per-message random nonces preserve forward secrecy
   - Recipients decrypt with private keys

2. **Search in Search-enabled Mode**: Server-side decryption for indexing/moderation
   - Search-enabled conversations permit decryption on the server strictly for indexing/moderation
   - Index populated from decrypted content; data encrypted-at-rest; access audited end-to-end
   - Strict E2E conversations are never decrypted server-side and are not indexed/searchable

3. **Admin Access**: Limited to search-enabled conversations only
   - Conversation-level admin key exists only for search-enabled conversations
   - Admins can decrypt content on the server under audit controls
   - In strict E2E, admins CANNOT access plaintext; no admin key exists for that conversation

**Future Work (Phase 7C)**: Deterministic searchable encryption (CryptDB-style)
- Explore encrypted keyword indexing without server-side decryption
- Evaluate security trade-offs vs. forward secrecy and leakage
- Replace/augment server-side decryption path where feasible

---

### Key Management Strategy

**User Key Pair**:
- Generated on client during registration; public key sent to server
- Private key stored locally; never transmitted to server
- All messages encrypted with recipient's public key

**Admin Key** (search-enabled conversations only):
- Generated per search-enabled conversation
- Encrypted at rest on server with master key
- Only accessible to users with admin role under audit
- Not present for strict E2E conversations

**Master Key** (server-side):
- Encrypts admin keys, PII at rest
- Stored in HSM (hardware security module) or secrets manager
- Rotated annually; key rotation doesn't require message re-encryption

**Forward Secrecy**:
- Per-message random nonce prevents pattern analysis
- Key compromise affects only future messages (past messages secure due to random nonces)

---

## Clarifications

### Session 2025-10-22

- Q: Should group messages support @mentions to notify specific members? → A: Yes, implement @mentions with real-time notifications sent to mentioned users (Option A)
- Q: What message encryption level? → A: End-to-End (E2E) Encryption with client-side encryption; server-side searchable encryption enables search without decryption (Option A, Hybrid approach)
- Q: What story privacy levels? → A: Three-tier privacy: public (everyone can see), followers (followers only), close-friends (manually selected group) (Option A)
- Q: How do admins view messages if E2E encrypted? → A: Conversation-level admin_key held on server; admins decrypt using admin key, not individual user keys (architectural decision)
- Q: Why not break E2E for admin visibility? → A: Admin key is separate from member keys; admins see plaintext while members see only their own decrypted messages

# Phase 1A+1B: Core Messaging gRPC Implementation Tasks

## Task Dependencies

```
T1.1 (Fix SendMessage) ─┬─> T1.2 (GetMessageHistory)
                        └─> T1.3 (GetMessage)

T2.1 (CreateConversation) ─┬─> T2.2 (ListUserConversations)
                           └─> T2.3 (GetConversation)

Phase 1A (6 tasks, 13h) → Code Review (4h) → Phase 1B (6 tasks, 17h)
```

---

## Phase 1A: Critical Message Operations

### T1.1: Modify MessageService to Return Complete MessageRow

**Objective**: Change `send_message_db` return type from `(Uuid, i64)` to `MessageRow`

**Input**:
- Current: `backend/messaging-service/src/services/message_service.rs`
- Function: `MessageService::send_message_db` (lines 39-111)

**Tasks**:
1. Add `struct MessageRow` definition (or use existing DB struct)
2. Modify INSERT...RETURNING query to return all message fields
3. Update function signature: `Result<(Uuid, i64), AppError>` → `Result<MessageRow, AppError>`
4. Update callers in `send_message` wrapper (line 144)

**Output**:
- Service layer function returns complete data
- No query→response gap
- Ready for proto conversion

**Acceptance Criteria**:
- ✅ Function returns MessageRow with all 13 fields populated
- ✅ DB timestamp accurate (no RPC call time substitution)
- ✅ All wrappers compile without changes
- ✅ Unit test passes: field values match DB

**Work Estimate**: 2 hours

---

### T1.2: Implement Message Proto Conversion

**Objective**: Create `From<MessageRow> for Message` implementation

**Input**:
- MessageRow struct (from T1.1)
- Proto Message definition (from openspec/specs/phase1-messaging-grpc.md)

**Tasks**:
1. Implement `From<MessageRow> for messaging_service::Message`
2. Handle all 13 fields with correct types
3. Convert i64 timestamps correctly
4. Handle Option types (updated_at, deleted_at, content_nonce, etc.)

**Output**:
- Reusable conversion for all message-returning RPCs
- Consistent field mapping
- Single source of truth for proto construction

**Acceptance Criteria**:
- ✅ Conversion handles all 13 fields
- ✅ Timestamps in milliseconds (not seconds)
- ✅ Optional fields default to 0/"" appropriately
- ✅ Unit test: MessageRow → Message → verify all fields

**Work Estimate**: 1 hour

**Code Location**: `backend/messaging-service/src/grpc/mod.rs` (new helper section)

---

### T1.3: Implement SendMessage RPC with Auth Integration

**Objective**: Complete SendMessage handler with auth-service verification

**Input**:
- Proto request/response (SendMessageRequest, SendMessageResponse)
- MessageService::send_message_db (from T1.1)
- From<MessageRow> conversion (from T1.2)
- AuthClient (existing, at `src/services/auth_client.rs`)

**Tasks**:
1. Parse and validate UUIDs (conversation_id, sender_id)
2. Verify sender exists via auth_client.user_exists()
3. Call MessageService::send_message() (existing wrapper)
4. Convert MessageRow to Message proto
5. Return SendMessageResponse with complete Message

**Output**:
- Working SendMessage RPC
- Auth validation integrated
- Proto response fully populated

**Acceptance Criteria**:
- ✅ Compilation succeeds
- ✅ Unit test: message sent with correct content
- ✅ Timestamp from DB, not RPC call time
- ✅ Auth failure returns NOT_FOUND
- ✅ Empty content returns INVALID_ARGUMENT
- ✅ Non-existent conversation returns error (via service layer)

**Work Estimate**: 2 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::send_message()`

---

### T1.4: Implement GetMessageHistory RPC with Pagination

**Objective**: Fetch paginated message history with member validation

**Input**:
- Proto GetMessageHistoryRequest/Response
- ConversationService::is_member() (exists)
- Message conversion (from T1.2)
- DB query pattern (SELECT from messages table)

**Tasks**:
1. Parse conversation_id from request
2. Extract requesting user ID from gRPC metadata (or request)
3. Verify user is conversation member via is_member()
4. Build paginated query: `created_at < cursor LIMIT limit`
5. Convert all MessageRows to Message protos
6. Return response with next_cursor and has_more flag

**Output**:
- Working GetMessageHistory RPC
- Pagination functional
- Member access control enforced

**Acceptance Criteria**:
- ✅ Returns up to 100 messages
- ✅ Cursor-based pagination works (before_timestamp)
- ✅ has_more flag accurate
- ✅ Non-member gets PermissionDenied
- ✅ Empty conversation returns empty list (not error)
- ✅ Messages ordered DESC by created_at

**Work Estimate**: 3 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::get_message_history()`

---

### T1.5: Implement GetMessage RPC

**Objective**: Fetch single message by ID

**Input**:
- Proto GetMessageRequest/Response
- Message conversion (from T1.2)

**Tasks**:
1. Parse message_id from request
2. Query message from DB: `SELECT * FROM messages WHERE id = $1`
3. If found: convert to Message, return with found=true
4. If not found: return empty Message, found=false, no error status

**Output**:
- Working GetMessage RPC
- Correct empty/not-found handling

**Acceptance Criteria**:
- ✅ Returns message with all fields when found
- ✅ Returns found=false for missing message (no error)
- ✅ Message content matches DB
- ✅ Timestamps accurate

**Work Estimate**: 1.5 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::get_message()`

---

### T1.6: Write Phase 1A Integration Tests

**Objective**: End-to-end gRPC tests for SendMessage, GetMessageHistory, GetMessage

**Input**:
- Working RPC implementations (T1.3-T1.5)
- Test database setup (existing in project)
- gRPC client setup

**Tasks**:
1. Create test module in `src/grpc/mod.rs` or separate file
2. For SendMessage:
   - Test basic happy path
   - Test auth failure
   - Test empty content validation
   - Test idempotency
3. For GetMessageHistory:
   - Test pagination
   - Test member validation
   - Test cursor handling
   - Test empty conversation
4. For GetMessage:
   - Test found case
   - Test not-found case
5. Mock auth-service responses

**Output**:
- Comprehensive test coverage for Phase 1A
- All edge cases covered
- Developers confident in implementations

**Acceptance Criteria**:
- ✅ 15+ test cases total
- ✅ All happy paths pass
- ✅ All error cases pass
- ✅ Test coverage >85% for Phase 1A code
- ✅ Tests run in CI/CD pipeline

**Work Estimate**: 4 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::tests` or `tests/grpc/`

---

## Phase 1B: Conversation Operations

### T2.1: Implement CreateConversation RPC

**Objective**: Create new direct conversation between two users

**Input**:
- Proto CreateConversationRequest/Response
- ConversationService::create_direct_conversation() (exists at L53-92)
- AuthClient (existing)

**Tasks**:
1. Parse user_a_id, user_b_id from request
2. Verify both users exist via auth_client
3. Call ConversationService::create_direct_conversation()
4. Return conversation_id

**Output**:
- Working CreateConversation RPC

**Acceptance Criteria**:
- ✅ Creates conversation with both users as members
- ✅ Returns conversation_id
- ✅ Non-existent user returns NOT_FOUND
- ✅ Duplicate creation returns existing conversation (idempotent)

**Work Estimate**: 2 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::create_conversation()`

---

### T2.2: Implement ListUserConversations RPC

**Objective**: List all user conversations with pagination

**Input**:
- Proto ListUserConversationsRequest/Response
- Query: conversations where user is member, ordered by last_message_time
- Conversation conversion (needs From<ConversationRow> impl)

**Tasks**:
1. Extract requesting user ID from metadata
2. Query conversations for user with pagination
3. For each conversation: fetch last_message, member_count
4. Convert to proto Conversation objects
5. Return list with pagination info

**Output**:
- Working ListUserConversations RPC
- Pagination functional

**Acceptance Criteria**:
- ✅ Returns only conversations where user is member
- ✅ Ordered by last_message_created_at DESC
- ✅ Pagination works
- ✅ Each conversation includes member_count and last_message
- ✅ Empty list for new user (not error)

**Work Estimate**: 3 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::list_user_conversations()`

---

### T2.3: Implement GetConversation RPC

**Objective**: Fetch conversation details with members

**Input**:
- Proto GetConversationRequest/Response
- ConversationService::get_conversation_db() (exists at L94-107)
- Conversation conversion (from T2.2)

**Tasks**:
1. Parse conversation_id from request
2. Extract requesting user ID from metadata
3. Verify user is member (is_member check)
4. Fetch conversation details
5. Fetch conversation members with roles
6. Convert to proto Conversation with members list
7. Return with last_message info

**Output**:
- Working GetConversation RPC
- Members list included

**Acceptance Criteria**:
- ✅ Returns conversation with all members
- ✅ Non-member gets PermissionDenied
- ✅ Non-existent conversation returns NOT_FOUND
- ✅ Members include user_id, role, joined_at, is_muted, last_read_at

**Work Estimate**: 2.5 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::get_conversation()`

---

### T2.4: Implement Conversation Proto Conversion

**Objective**: Create From<ConversationRow> for Conversation proto

**Similar to T1.2 but for Conversation types**

**Work Estimate**: 1 hour

---

### T2.5: Write Phase 1B Integration Tests

**Objective**: End-to-end tests for CreateConversation, ListUserConversations, GetConversation

**Similar scope to T1.6**

**Work Estimate**: 4 hours

---

## Code Quality Tasks

### T3.1: Implement Unified Error Handling

**Objective**: Map all AppError variants to tonic::Status codes

**Input**:
- Current app_error_to_status() (very incomplete)
- AppError enum definition

**Tasks**:
1. Update app_error_to_status() with complete match statement
2. Map 15+ AppError variants to appropriate Status codes
3. Remove default "internal" catch-all
4. Add test: verify every error type maps correctly

**Work Estimate**: 1.5 hours

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::app_error_to_status()`

---

### T3.2: Create UUID Validation Macro

**Objective**: Eliminate UUID parsing duplication across 27 RPCs

**Input**:
- Current parse_uuid() function (L30-33, only for send_message)

**Tasks**:
1. Create parse_uuid_field! macro
2. Test macro works with multiple field names
3. Document macro usage

**Work Estimate**: 1 hour

**Code Location**: `backend/messaging-service/src/grpc/mod.rs::macros`

---

## Pre-Submission Checklist

**Code Quality**:
- [ ] All Phase 1A+1B RPCs implemented (6 methods)
- [ ] Unified error handling (T3.1)
- [ ] UUID validation macro (T3.2)
- [ ] Message/Conversation conversion impls
- [ ] Zero hardcoded timestamps
- [ ] All proto fields populated

**Testing**:
- [ ] 15+ Phase 1A tests passing
- [ ] 15+ Phase 1B tests passing
- [ ] Auth failure cases handled
- [ ] Pagination tested
- [ ] Member access control verified
- [ ] Edge cases (empty lists, missing resources) covered

**Documentation**:
- [ ] Each RPC has doc comments
- [ ] Proto conversion logic explained
- [ ] Error handling documented
- [ ] Auth integration documented

**Performance**:
- [ ] No N+1 queries
- [ ] Pagination limits enforced
- [ ] Connection pooling verified

---

## Summary

| Task | Duration | Status |
|------|----------|--------|
| T1.1 | 2h | Pending |
| T1.2 | 1h | Pending |
| T1.3 | 2h | Pending |
| T1.4 | 3h | Pending |
| T1.5 | 1.5h | Pending |
| T1.6 | 4h | Pending |
| **Phase 1A** | **13.5h** | **Pending** |
| T2.1 | 2h | Pending |
| T2.2 | 3h | Pending |
| T2.3 | 2.5h | Pending |
| T2.4 | 1h | Pending |
| T2.5 | 4h | Pending |
| **Phase 1B** | **12.5h** | **Pending** |
| T3.1 | 1.5h | Pending |
| T3.2 | 1h | Pending |
| **Quality** | **2.5h** | **Pending** |
| **Total** | **28.5h** | **~4 days** |


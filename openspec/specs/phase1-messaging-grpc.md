# Phase 1: Messaging Service gRPC Implementation Specification

## Feature Overview

Implement core gRPC message operations for Nova messaging-service with auth-service integration for user validation. Follows Linus Torvalds' "good taste" principles: eliminate special cases, focus on data structures first, and build incrementally.

## Core Principles

1. **Data Structure First** - Proto ↔ DB mapping must be consistent
2. **No Special Cases** - Unified error handling for all 27 RPC methods
3. **Service Layer Contract** - Service functions return complete data for proto construction
4. **Auth Validation** - Every operation verified against auth-service

## Phase 1A: Critical Message Operations

### Feature 1.1: SendMessage (Core Message Flow)

**What**: Send message to conversation with encryption support

**Acceptance Criteria**:
- ✅ Message persisted with correct DB timestamp (not RPC call time)
- ✅ Proto response contains all 11 message fields
- ✅ Sender verified via auth-service
- ✅ Conversation membership validated
- ✅ Idempotency key prevents duplicates
- ✅ Encryption applied per privacy mode

**Proto**:
```protobuf
message SendMessageRequest {
    string conversation_id = 1;      // UUID
    string sender_id = 2;            // UUID
    bytes content = 3;               // plaintext or encrypted
    string idempotency_key = 4;      // optional
}

message SendMessageResponse {
    string message_id = 1;           // UUID
    Message message = 2;             // full message with timestamps
}

message Message {
    string id = 1;
    string conversation_id = 2;
    string sender_id = 3;
    string content = 4;
    bytes content_encrypted = 5;
    bytes content_nonce = 6;
    int32 encryption_version = 7;
    int64 sequence_number = 8;
    string idempotency_key = 9;
    int64 created_at = 10;           // unix timestamp from DB
    int64 updated_at = 11;
    int64 deleted_at = 12;
    int32 reaction_count = 13;
}
```

**Implementation Notes**:
- Service layer returns complete MessageRow
- Proto conversion via `From<MessageRow> for Message`
- Auth validation: user_exists(sender_id)
- DB validation: is_member(conversation_id, sender_id)

### Feature 1.2: GetMessageHistory (Read Recent Messages)

**What**: Paginated message history for conversation

**Acceptance Criteria**:
- ✅ Paginated by timestamp (cursor-based)
- ✅ Requesting user must be conversation member
- ✅ Limit enforced (max 100, min 1)
- ✅ Returns messages in descending timestamp order
- ✅ has_more flag indicates more data available

**Implementation Notes**:
- Auth validation: is_member check for requesting user
- Pagination: `created_at < cursor`
- Batch conversion: `Vec<MessageRow> -> Vec<Message>`

### Feature 1.3: GetMessage (Message Details)

**What**: Fetch single message by ID

**Acceptance Criteria**:
- ✅ Returns message with all fields
- ✅ found=true when message exists
- ✅ found=false with empty message when not found
- ✅ No error thrown for missing message (OK response)

## Phase 1B: Conversation Operations

### Feature 2.1: CreateConversation (Start New Chat)

**What**: Create direct conversation between two users

**Acceptance Criteria**:
- ✅ Both users verified via auth-service
- ✅ Prevents duplicate direct conversations
- ✅ Returns conversation ID

### Feature 2.2: ListUserConversations (Inbox)

**What**: List all conversations for user with pagination

**Acceptance Criteria**:
- ✅ Paginated by last_message_timestamp
- ✅ Includes member count and last message
- ✅ Only conversations where user is member

### Feature 2.3: GetConversation (Conversation Details)

**What**: Fetch conversation metadata with members

**Acceptance Criteria**:
- ✅ Requesting user must be member
- ✅ Returns conversation with members list
- ✅ Returns last_message info

## Data Structures

### MessageRow (DB → Proto)

```rust
struct MessageRow {
    id: Uuid,
    conversation_id: Uuid,
    sender_id: Uuid,
    content: String,
    content_encrypted: Option<Vec<u8>>,
    content_nonce: Option<Vec<u8>>,
    encryption_version: i32,
    sequence_number: i64,
    idempotency_key: Option<String>,
    created_at: DateTime<Utc>,
    updated_at: Option<DateTime<Utc>>,
    deleted_at: Option<DateTime<Utc>>,
    reaction_count: i32,
}

impl From<MessageRow> for Message {
    fn from(row: MessageRow) -> Self {
        Message {
            id: row.id.to_string(),
            conversation_id: row.conversation_id.to_string(),
            sender_id: row.sender_id.to_string(),
            content: row.content,
            content_encrypted: row.content_encrypted.unwrap_or_default(),
            content_nonce: row.content_nonce.unwrap_or_default(),
            encryption_version: row.encryption_version,
            sequence_number: row.sequence_number,
            idempotency_key: row.idempotency_key.unwrap_or_default(),
            created_at: row.created_at.timestamp(),
            updated_at: row.updated_at.map(|t| t.timestamp()).unwrap_or(0),
            deleted_at: row.deleted_at.map(|t| t.timestamp()).unwrap_or(0),
            reaction_count: row.reaction_count,
        }
    }
}
```

## Error Handling

All AppError variants map to tonic::Status codes:

```
AppError::NotFound → Code::NotFound
AppError::BadRequest(msg) → Code::InvalidArgument
AppError::Unauthorized → Code::Unauthenticated
AppError::Forbidden → Code::PermissionDenied
AppError::Database(msg) → Code::Internal
AppError::AlreadyRecalled → Code::FailedPrecondition
AppError::VersionConflict → Code::Aborted
... (all 20+ variants mapped)
```

No default `internal` - every error has explicit handling.

## Testing Strategy

### Unit Tests (Service Layer)

```rust
#[sqlx::test]
async fn test_send_message_returns_full_row(pool: PgPool) {
    // Verify service returns complete MessageRow
    let row = MessageService::send_message_db(...).await.unwrap();
    assert_eq!(row.content, "test");
    assert!(row.created_at > Utc::now() - Duration::seconds(5));
}
```

### Integration Tests (gRPC)

```rust
#[tokio::test]
async fn test_send_message_grpc() {
    let mut client = MessagingServiceClient::connect(...).await.unwrap();
    let resp = client.send_message(SendMessageRequest { ... }).await.unwrap();

    let msg = resp.into_inner().message.unwrap();
    assert_eq!(msg.content, "hello");
    assert_ne!(msg.created_at, 0);  // DB timestamp, not call time
}
```

## Success Metrics

- ✅ All 6 Phase 1A/1B RPC methods implemented
- ✅ 100% field population in proto responses
- ✅ Zero hardcoded timestamps (all from DB)
- ✅ All AppError types mapped to Status codes
- ✅ 90%+ test coverage for Phase 1A/1B

## Timeline

| Phase | Duration | Tasks | Owner |
|-------|----------|-------|-------|
| 1A | 2 days | SendMessage, GetMessageHistory, GetMessage | Backend |
| 1B | 2.5 days | CreateConversation, ListUserConversations, GetConversation | Backend |
| Code Review | 1 day | Architecture review, test verification | Architect |

**Total**: 5.5 days for Phase 1A+1B

---

**Design Note**: This spec eliminates all "special cases" (hardcoded values, default behaviors, inconsistent mappings). Every field flows directly from DB through proto conversion with explicit handling.

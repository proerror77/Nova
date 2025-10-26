# Database Migrations - Messaging Service

## Migration Order

Migrations must be executed in numerical order:

1. **0001_create_users.sql** - Base users table
2. **0002_create_conversations.sql** - Conversations with types and privacy modes
3. **0003_create_conversation_members.sql** - Conversation membership
4. **0004_create_messages.sql** - Core messages table with encryption
5. **0005_add_message_content_fields.sql** - Add content, versioning, and recall tracking
6. **0006_create_message_reactions.sql** - User reactions (emoji) on messages
7. **0007_create_message_attachments.sql** - File attachments with metadata
8. **0008_create_message_recalls.sql** - Audit trail for recalled messages

## Schema Design Principles

### Data Type Consistency
- **UUIDs for all IDs** - Consistent with existing schema (not BIGINT)
- **TIMESTAMPTZ for all timestamps** - Timezone-aware dates
- **TEXT for variable content** - No arbitrary length limits
- **VARCHAR(255) for controlled types** - MIME types, etc.

### Referential Integrity
- **Foreign key constraints** - Ensure data consistency
- **ON DELETE CASCADE** - Automatic cleanup of dependent records
- **Check constraints** - Data validation at database level

### Performance Optimization
- **Composite indexes** - For common query patterns (conversation_id + created_at)
- **GIN indexes** - Full-text search on message content
- **Targeted indexes** - message_id, user_id for fast lookups

### Backward Compatibility
- **DEFAULT values** - All new columns have sensible defaults
- **IF NOT EXISTS** - Safe to re-run migrations
- **No data loss** - Down migrations provided for rollback

## Key Features

### Message Content (0005)
- **content**: Plaintext message text for search-enabled conversations
- **version_number**: Optimistic locking for concurrent message edits
- **recalled_at**: Soft delete timestamp for recalled messages
- **Full-text search index**: GIN index using PostgreSQL's tsvector

### Message Reactions (0006)
- **Composite primary key**: (user_id, message_id, reaction)
- **Multiple reactions**: Users can add different emoji to same message
- **Fast lookups**: Indexed on message_id and user_id

### Message Attachments (0007)
- **File metadata**: URL, type, size tracking
- **Upload attribution**: Track who uploaded each file
- **Type filtering**: Index on file_type for efficient queries
- **Data validation**: Positive file sizes, non-empty URLs

### Message Recalls (0008)
- **Audit trail**: Complete history of message recalls
- **Reason tracking**: Optional recall reason for compliance
- **Time-based queries**: Indexed for recent recalls and audit reports
- **User tracking**: Find all recalls by a specific user

## Running Migrations

### Apply All Migrations
```bash
# Using sqlx-cli
sqlx migrate run --database-url $DATABASE_URL

# Or manually with psql
for f in migrations/*.sql; do
  psql $DATABASE_URL -f "$f"
done
```

### Rollback Last Migration
```bash
sqlx migrate revert --database-url $DATABASE_URL
```

### Check Migration Status
```bash
sqlx migrate info --database-url $DATABASE_URL
```

## Data Validation

### Message Content
- Version numbers must be positive (>0)
- Content can be empty string (for encrypted-only messages)
- recalled_at is NULL unless message is recalled

### Reactions
- Reaction text cannot be empty or whitespace-only
- One reaction type per user per message
- Cascades delete when message or user is deleted

### Attachments
- File size must be positive
- File URL cannot be empty
- File type (MIME) cannot be empty
- Supports multiple attachments per message

### Recalls
- Tracks historical recall events (not just current state)
- Multiple recalls per message supported (re-send and re-recall)
- Cascades delete when message or user is deleted

## Performance Considerations

### Indexes Created
1. `idx_messages_conversation_created` - Message retrieval with sorting
2. `idx_messages_content_fulltext` - Full-text search (GIN)
3. `idx_reactions_message_id` - Reaction lookup by message
4. `idx_reactions_user_id` - User's reactions
5. `idx_attachments_message_id` - Message attachments
6. `idx_attachments_uploaded_by` - User's uploads
7. `idx_attachments_file_type` - Filter by file type
8. `idx_recalls_message_id` - Message recall history
9. `idx_recalls_recalled_by` - User's recalls
10. `idx_recalls_recalled_at` - Time-based audit queries
11. `idx_recalls_message_time` - Composite message+time lookup

### Query Patterns
- **Message feed**: Uses idx_messages_conversation_created
- **Search**: Uses idx_messages_content_fulltext
- **Reactions count**: Uses idx_reactions_message_id
- **Attachment list**: Uses idx_attachments_message_id
- **Recall audit**: Uses idx_recalls_recalled_at

## Security Notes

- All user-uploaded content (attachments) tracked by uploader
- Recall audit trail for compliance and moderation
- Check constraints prevent invalid data at database level
- Foreign keys ensure orphaned records cannot exist

-- Message Recall and Versioning Support
-- Adds support for:
-- 1. Message recall (unsend) functionality
-- 2. Optimistic locking via version_number
-- 3. Audit trail for message recalls

-- ============================================
-- 1. Add recall and versioning fields to messages
-- ============================================

-- Add recalled_at timestamp for soft recall
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS recalled_at TIMESTAMP WITH TIME ZONE;

-- Add version_number for optimistic locking (default 1 for existing messages)
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS version_number INT NOT NULL DEFAULT 1;

-- Add content column for plaintext content (used in update_message handler)
-- NOTE: This is for server-side search indexing, NOT a replacement for encrypted_content
-- The actual message content remains in encrypted_content for E2E security
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS content TEXT;

-- Add sequence_number for message ordering (auto-increment per conversation)
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS sequence_number BIGSERIAL;

-- Add server-side encryption fields (for encrypt-at-rest with server key)
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS encryption_version INT DEFAULT 0;

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS content_nonce BYTEA;

-- Add idempotency_key for message deduplication
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(255);

-- ============================================
-- 2. Create message_recalls audit table
-- ============================================

CREATE TABLE IF NOT EXISTS message_recalls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL,
    recalled_by_user_id UUID NOT NULL,
    recall_reason TEXT,
    recalled_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_recall_message FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT fk_recall_user FOREIGN KEY (recalled_by_user_id) REFERENCES users(id)
);

-- Indexes for audit queries
CREATE INDEX IF NOT EXISTS idx_message_recalls_message_id ON message_recalls(message_id);
CREATE INDEX IF NOT EXISTS idx_message_recalls_user_id ON message_recalls(recalled_by_user_id);
CREATE INDEX IF NOT EXISTS idx_message_recalls_recalled_at ON message_recalls(recalled_at DESC);

-- ============================================
-- 3. Create indexes for new fields
-- ============================================

-- Index for filtering recalled messages (soft delete pattern)
CREATE INDEX IF NOT EXISTS idx_messages_recalled_at ON messages(recalled_at)
    WHERE recalled_at IS NOT NULL;

-- Partial index for active (non-recalled, non-deleted) messages
CREATE INDEX IF NOT EXISTS idx_messages_active ON messages(conversation_id, created_at DESC)
    WHERE recalled_at IS NULL AND deleted_at IS NULL;

-- Unique index for idempotency_key
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_idempotency_key ON messages(idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- Composite index for version conflict queries
CREATE INDEX IF NOT EXISTS idx_messages_id_version ON messages(id, version_number);

-- ============================================
-- 4. Create message edit history table (optional)
-- ============================================

CREATE TABLE IF NOT EXISTS message_edit_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL,
    previous_content TEXT,
    previous_content_encrypted TEXT,
    version_number INT NOT NULL,
    edited_by_user_id UUID NOT NULL,
    edited_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    edit_reason TEXT,

    CONSTRAINT fk_edit_message FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT fk_edit_user FOREIGN KEY (edited_by_user_id) REFERENCES users(id)
);

-- Indexes for edit history queries
CREATE INDEX IF NOT EXISTS idx_message_edit_history_message_id ON message_edit_history(message_id, version_number DESC);
CREATE INDEX IF NOT EXISTS idx_message_edit_history_edited_at ON message_edit_history(edited_at DESC);

-- ============================================
-- 5. Create trigger for automatic edit history
-- ============================================

CREATE OR REPLACE FUNCTION record_message_edit_history()
RETURNS TRIGGER AS $$
BEGIN
    -- Only record history if content or encrypted_content changed
    IF (OLD.content IS DISTINCT FROM NEW.content) OR
       (OLD.encrypted_content IS DISTINCT FROM NEW.encrypted_content) THEN
        INSERT INTO message_edit_history (
            message_id,
            previous_content,
            previous_content_encrypted,
            version_number,
            edited_by_user_id,
            edit_reason
        ) VALUES (
            OLD.id,
            OLD.content,
            OLD.encrypted_content,
            OLD.version_number,
            OLD.sender_id,  -- Assume sender is the editor
            'Auto-recorded edit'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for edit tracking (fires BEFORE UPDATE)
DROP TRIGGER IF EXISTS trigger_record_message_edit_history ON messages;
CREATE TRIGGER trigger_record_message_edit_history
    BEFORE UPDATE ON messages
    FOR EACH ROW
    WHEN (OLD.version_number <> NEW.version_number)
    EXECUTE FUNCTION record_message_edit_history();

COMMENT ON FUNCTION record_message_edit_history() IS 'Auto-record message edit history when version_number changes';

-- ============================================
-- 6. Create message_search_index table
-- ============================================

CREATE TABLE IF NOT EXISTS message_search_index (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL UNIQUE,
    conversation_id UUID NOT NULL,
    sender_id UUID NOT NULL,
    search_text TEXT NOT NULL,
    tsv TSVECTOR,  -- Full-text search vector
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_search_message FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    CONSTRAINT fk_search_conversation FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
    CONSTRAINT fk_search_sender FOREIGN KEY (sender_id) REFERENCES users(id)
);

-- Full-text search index using GIN
CREATE INDEX IF NOT EXISTS idx_message_search_text_gin ON message_search_index USING GIN(tsv);

-- Index for conversation-scoped search
CREATE INDEX IF NOT EXISTS idx_message_search_conversation ON message_search_index(conversation_id, created_at DESC);

-- Create trigger to auto-update tsv column
CREATE OR REPLACE FUNCTION update_message_search_tsv()
RETURNS TRIGGER AS $$
BEGIN
    NEW.tsv := to_tsvector('simple', COALESCE(NEW.search_text, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_message_search_tsv ON message_search_index;
CREATE TRIGGER trigger_update_message_search_tsv
    BEFORE INSERT OR UPDATE ON message_search_index
    FOR EACH ROW
    EXECUTE FUNCTION update_message_search_tsv();

COMMENT ON TABLE message_search_index IS 'Full-text search index for messages (plaintext for search only)';
COMMENT ON COLUMN message_search_index.search_text IS 'Plaintext message content for search (NOT for display - use encrypted_content)';

-- ============================================
-- 7. Comments
-- ============================================

COMMENT ON COLUMN messages.recalled_at IS 'Timestamp when message was recalled (NULL = not recalled)';
COMMENT ON COLUMN messages.version_number IS 'Optimistic locking version (incremented on each edit)';
COMMENT ON COLUMN messages.content IS 'Plaintext content for search indexing (optional, use encrypted_content for E2E)';
COMMENT ON COLUMN messages.sequence_number IS 'Auto-incrementing sequence number per conversation';
COMMENT ON COLUMN messages.idempotency_key IS 'Client-provided idempotency key for duplicate detection';

COMMENT ON TABLE message_recalls IS 'Audit log of message recalls (unsend events)';
COMMENT ON TABLE message_edit_history IS 'Version history of message edits (for audit and rollback)';

-- ============================================
-- 8. Migration Rollback
-- ============================================

-- To rollback this migration:
-- DROP TRIGGER IF EXISTS trigger_record_message_edit_history ON messages;
-- DROP TRIGGER IF EXISTS trigger_update_message_search_tsv ON message_search_index;
-- DROP FUNCTION IF EXISTS record_message_edit_history();
-- DROP FUNCTION IF EXISTS update_message_search_tsv();
-- DROP TABLE IF EXISTS message_edit_history CASCADE;
-- DROP TABLE IF EXISTS message_recalls CASCADE;
-- DROP TABLE IF EXISTS message_search_index CASCADE;
-- ALTER TABLE messages DROP COLUMN IF EXISTS recalled_at;
-- ALTER TABLE messages DROP COLUMN IF EXISTS version_number;
-- ALTER TABLE messages DROP COLUMN IF EXISTS content;
-- ALTER TABLE messages DROP COLUMN IF EXISTS sequence_number;
-- ALTER TABLE messages DROP COLUMN IF EXISTS encryption_version;
-- ALTER TABLE messages DROP COLUMN IF EXISTS content_encrypted;
-- ALTER TABLE messages DROP COLUMN IF EXISTS content_nonce;
-- ALTER TABLE messages DROP COLUMN IF EXISTS idempotency_key;

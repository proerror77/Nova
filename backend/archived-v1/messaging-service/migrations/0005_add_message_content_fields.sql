-- Migration: Add missing content and versioning fields to messages table
-- These fields are essential for proper message functionality:
-- - content: plaintext message content (for search-enabled conversations)
-- - version_number: optimistic locking for concurrent edits
-- - recalled_at: track when messages are recalled

-- Up
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS content TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS version_number BIGINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS recalled_at TIMESTAMPTZ;

-- Create composite index for efficient message retrieval with sorting
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON messages(conversation_id, created_at DESC);

-- Create GIN index for full-text search on message content
-- This enables fast search queries on message text
CREATE INDEX IF NOT EXISTS idx_messages_content_fulltext
  ON messages USING GIN (to_tsvector('english', content));

-- Add check constraint to ensure version numbers are positive
ALTER TABLE messages
  ADD CONSTRAINT chk_messages_version_positive
  CHECK (version_number > 0);

-- Down
DROP INDEX IF EXISTS idx_messages_content_fulltext;
DROP INDEX IF EXISTS idx_messages_conversation_created;
ALTER TABLE messages DROP CONSTRAINT IF EXISTS chk_messages_version_positive;
ALTER TABLE messages DROP COLUMN IF EXISTS recalled_at;
ALTER TABLE messages DROP COLUMN IF EXISTS version_number;
ALTER TABLE messages DROP COLUMN IF EXISTS content;

-- Migration: Create message_search_index table
-- Purpose: Support efficient full-text search on message content
-- Strategy: Separate search index table with GIN index for fast lookups
--
-- This table maintains denormalized search text, allowing efficient queries without
-- scanning the large messages table multiple times.
--
-- Future optimization: Once all messages are migrated, consider using PostgreSQL's
-- native full-text search directly on messages.content with the existing GIN index.

-- Up: Create message_search_index table

CREATE TABLE IF NOT EXISTS message_search_index (
    message_id UUID PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    search_text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create index for fast conversation lookups
CREATE INDEX IF NOT EXISTS idx_search_index_conversation
ON message_search_index(conversation_id);

-- Create GIN index for full-text search on search_text field
CREATE INDEX IF NOT EXISTS idx_search_index_fulltext
ON message_search_index USING GIN (to_tsvector('english', search_text));

-- Down: Drop message_search_index table and indexes

DROP TABLE IF EXISTS message_search_index CASCADE;

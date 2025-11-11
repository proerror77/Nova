-- Migration: Add Full-Text Search index on messages.content
-- Purpose: Support efficient PostgreSQL native FTS queries without message_search_index table
-- Strategy: Create GIN index on tsvector of messages.content for fast lookups
--
-- This migration consolidates search indexing to use PostgreSQL's native full-text search
-- directly on the messages table, eliminating the need for the separate message_search_index table.
--
-- The search queries now use to_tsvector('english', m.content) @@ plainto_tsquery('english', query)
-- which benefits from the GIN index created below.

-- Up: Create GIN index for efficient FTS queries on messages.content

-- Option 1: Computed column approach (requires PostgreSQL 12+)
-- This creates a stored generated column that automatically maintains the tsvector
DO $$
BEGIN
    -- Try to add computed column if it doesn't exist
    BEGIN
        ALTER TABLE messages
        ADD COLUMN content_tsv tsvector
        GENERATED ALWAYS AS (to_tsvector('english', coalesce(content, ''))) STORED;
    EXCEPTION WHEN duplicate_column THEN
        -- Column already exists, proceed to index creation
        NULL;
    END;
END
$$;

-- Create GIN index on the tsvector column for fast FTS queries
CREATE INDEX IF NOT EXISTS idx_messages_content_tsv
ON messages USING GIN (content_tsv);

-- Alternative: Simple index on content for planning
-- This helps PostgreSQL query planner when filtering by conversation_id
CREATE INDEX IF NOT EXISTS idx_messages_conversation_content
ON messages (conversation_id)
WHERE deleted_at IS NULL;

-- Down: Remove the FTS index and computed column

-- This would be run on rollback:
-- DROP INDEX IF EXISTS idx_messages_content_tsv;
-- DROP INDEX IF EXISTS idx_messages_conversation_content;
-- ALTER TABLE messages DROP COLUMN IF EXISTS content_tsv;

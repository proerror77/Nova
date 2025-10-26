-- Migration: Drop legacy message_search_index table and related indexes
-- Purpose: Finalize cleanup of dual-path indexing after switching to native FTS

-- Drop GIN index if exists
DROP INDEX IF EXISTS idx_search_index_fulltext;

-- Drop conversation index if exists
DROP INDEX IF EXISTS idx_search_index_conversation;

-- Drop table
DROP TABLE IF EXISTS message_search_index CASCADE;


-- ============================================================================
-- Migration: Add index for conversations listing
-- Service: realtime-chat-service
-- Purpose:
--   - Improve performance for queries that order conversations by creation time
--   - Useful for admin tools or future features that list "newest conversations"
-- Safety:
--   - Purely additive index on existing column
--   - Idempotent via IF NOT EXISTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_conversations_created_at
    ON conversations (created_at DESC);


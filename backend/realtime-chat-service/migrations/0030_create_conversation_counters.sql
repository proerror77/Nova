-- Migration: 0030_create_conversation_counters
-- Description: Create sequence counter table for message ordering
-- Required by: message_service.rs:66 (atomic sequence number generation)

-- Conversation sequence counters for atomic message ordering
CREATE TABLE IF NOT EXISTS conversation_counters (
    conversation_id UUID PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    last_seq BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT conversation_counters_last_seq_positive CHECK (last_seq >= 0)
);

-- Index for faster counter lookups (covered by PK, but explicit for clarity)
COMMENT ON TABLE conversation_counters IS 'Atomic sequence counters for message ordering per conversation';

-- Backfill existing conversations with their current max sequence
-- This ensures existing data is consistent
INSERT INTO conversation_counters (conversation_id, last_seq)
SELECT
    conversation_id,
    COALESCE(MAX(sequence_number), 0) as last_seq
FROM messages
GROUP BY conversation_id
ON CONFLICT (conversation_id) DO UPDATE
    SET last_seq = GREATEST(conversation_counters.last_seq, EXCLUDED.last_seq);

-- For conversations with no messages yet, initialize to 0
INSERT INTO conversation_counters (conversation_id, last_seq)
SELECT id, 0
FROM conversations
WHERE id NOT IN (SELECT conversation_id FROM conversation_counters)
ON CONFLICT (conversation_id) DO NOTHING;

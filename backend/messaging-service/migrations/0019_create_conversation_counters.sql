-- Create per-conversation message sequence counters
-- Provides lock-free sequence generation to avoid COUNT(*) on messages

CREATE TABLE IF NOT EXISTS conversation_counters (
    conversation_id UUID PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    last_seq BIGINT NOT NULL
);

-- Ensure we always have a positive sequence
ALTER TABLE conversation_counters
    ADD CONSTRAINT conversation_counters_last_seq_positive CHECK (last_seq >= 0);

-- Backfill existing conversations based on current message count
WITH sequenced AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY created_at) AS seq
    FROM messages
)
UPDATE messages m
SET sequence_number = s.seq
FROM sequenced s
WHERE m.id = s.id;

INSERT INTO conversation_counters (conversation_id, last_seq)
SELECT conversation_id, COALESCE(MAX(sequence_number), COUNT(*))
FROM messages
GROUP BY conversation_id
ON CONFLICT (conversation_id) DO NOTHING;

-- Down migration
DROP TABLE IF EXISTS conversation_counters;

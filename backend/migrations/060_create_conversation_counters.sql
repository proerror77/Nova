-- Global migration to ensure messaging sequence counters exist

CREATE TABLE IF NOT EXISTS conversation_counters (
    conversation_id UUID PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    last_seq BIGINT NOT NULL DEFAULT 0
);

ALTER TABLE conversation_counters
    ADD CONSTRAINT conversation_counters_last_seq_positive CHECK (last_seq >= 0);

WITH sequenced AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY created_at) AS seq
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

-- Down
DROP TABLE IF EXISTS conversation_counters;

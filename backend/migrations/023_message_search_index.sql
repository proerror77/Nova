-- Message search index table (opt-in plaintext indexing for SearchEnabled conversations)
-- This table stores plaintext provided by clients for searchable conversations.
-- Server does not decrypt encrypted_content.

CREATE TABLE IF NOT EXISTS message_search_index (
    message_id UUID PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL,
    search_text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tsv tsvector NOT NULL DEFAULT ''::tsvector
);

-- Maintain the tsvector column via trigger to satisfy Postgres immutability requirements
CREATE OR REPLACE FUNCTION update_message_search_index_tsv() RETURNS trigger AS $$
BEGIN
    NEW.tsv := to_tsvector('simple', coalesce(NEW.search_text, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS message_search_index_tsv_trigger ON message_search_index;

CREATE TRIGGER message_search_index_tsv_trigger
BEFORE INSERT OR UPDATE ON message_search_index
FOR EACH ROW EXECUTE FUNCTION update_message_search_index_tsv();

UPDATE message_search_index
SET tsv = to_tsvector('simple', coalesce(search_text, ''))
WHERE TRUE;

CREATE INDEX IF NOT EXISTS idx_msg_search_conversation_created
    ON message_search_index(conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_msg_search_tsv ON message_search_index USING GIN (tsv);

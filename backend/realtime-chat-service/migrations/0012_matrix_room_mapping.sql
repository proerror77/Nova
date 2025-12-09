-- Migration: Add Matrix room mapping table
-- Maps Nova conversation_id to Matrix room_id

CREATE TABLE IF NOT EXISTS matrix_room_mapping (
    conversation_id UUID NOT NULL PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
    matrix_room_id TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index for reverse lookup (Matrix room_id -> conversation_id)
CREATE INDEX idx_matrix_room_mapping_room_id ON matrix_room_mapping(matrix_room_id);

-- Add matrix_event_id to messages table (optional, for dual-write tracking)
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS matrix_event_id TEXT;

-- Index for matrix_event_id lookups
CREATE INDEX IF NOT EXISTS idx_messages_matrix_event_id ON messages(matrix_event_id)
WHERE matrix_event_id IS NOT NULL;

COMMENT ON TABLE matrix_room_mapping IS 'Maps Nova conversations to Matrix rooms for E2EE messaging';
COMMENT ON COLUMN messages.matrix_event_id IS 'Matrix event ID if message was sent through Matrix';

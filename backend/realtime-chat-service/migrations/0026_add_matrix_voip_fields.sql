-- Add Matrix VoIP integration fields to call_sessions
-- Migration: 0026_add_matrix_voip_fields
-- Date: 2025-12-09
-- Purpose: Support Matrix E2EE VoIP signaling via m.call.* events

-- Add Matrix event tracking to call_sessions
ALTER TABLE call_sessions
    ADD COLUMN matrix_invite_event_id TEXT,
    ADD COLUMN matrix_party_id VARCHAR(100);

COMMENT ON COLUMN call_sessions.matrix_invite_event_id
IS 'Matrix event ID for m.call.invite event (e.g., $abc123...)';

COMMENT ON COLUMN call_sessions.matrix_party_id
IS 'Matrix party ID for this call session (e.g., nova-{uuid})';

-- Add Matrix event tracking to call_participants
ALTER TABLE call_participants
    ADD COLUMN matrix_answer_event_id TEXT,
    ADD COLUMN matrix_party_id VARCHAR(100);

COMMENT ON COLUMN call_participants.matrix_answer_event_id
IS 'Matrix event ID for m.call.answer event sent by this participant';

COMMENT ON COLUMN call_participants.matrix_party_id
IS 'Matrix party ID for this participant (e.g., nova-{uuid})';

-- Create indexes for Matrix event lookups
-- Query pattern: Find call by Matrix invite event ID
CREATE INDEX IF NOT EXISTS idx_call_sessions_matrix_invite_event
ON call_sessions(matrix_invite_event_id)
WHERE matrix_invite_event_id IS NOT NULL;

-- Query pattern: Find call by Matrix party ID
CREATE INDEX IF NOT EXISTS idx_call_sessions_matrix_party
ON call_sessions(matrix_party_id)
WHERE matrix_party_id IS NOT NULL;

-- Query pattern: Find participant by Matrix answer event ID
CREATE INDEX IF NOT EXISTS idx_call_participants_matrix_answer_event
ON call_participants(matrix_answer_event_id)
WHERE matrix_answer_event_id IS NOT NULL;

-- Query pattern: Find participant by Matrix party ID
CREATE INDEX IF NOT EXISTS idx_call_participants_matrix_party
ON call_participants(call_id, matrix_party_id)
WHERE matrix_party_id IS NOT NULL;

-- Add constraint to ensure Matrix fields are consistent
-- If matrix_invite_event_id is set, matrix_party_id must also be set
ALTER TABLE call_sessions ADD CONSTRAINT matrix_fields_consistency_sessions
CHECK (
    (matrix_invite_event_id IS NULL AND matrix_party_id IS NULL)
    OR
    (matrix_invite_event_id IS NOT NULL AND matrix_party_id IS NOT NULL)
);

-- If matrix_answer_event_id is set, matrix_party_id must also be set
ALTER TABLE call_participants ADD CONSTRAINT matrix_fields_consistency_participants
CHECK (
    (matrix_answer_event_id IS NULL AND matrix_party_id IS NULL)
    OR
    (matrix_answer_event_id IS NOT NULL AND matrix_party_id IS NOT NULL)
);

COMMENT ON CONSTRAINT matrix_fields_consistency_sessions ON call_sessions
IS 'Ensures Matrix event ID and party ID are set together or both NULL';

COMMENT ON CONSTRAINT matrix_fields_consistency_participants ON call_participants
IS 'Ensures Matrix event ID and party ID are set together or both NULL';

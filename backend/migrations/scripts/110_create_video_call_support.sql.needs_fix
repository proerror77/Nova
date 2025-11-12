-- Create video call support infrastructure
-- Migration: 0016_create_video_call_support

-- Call sessions table (one call per session)
CREATE TABLE IF NOT EXISTS call_sessions (
    id UUID PRIMARY KEY,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    initiator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'ringing' NOT NULL,
    COMMENT ON COLUMN call_sessions.status IS 'ringing, connected, ended, failed',

    -- Timing information
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    COMMENT ON COLUMN call_sessions.started_at IS 'When first participant connected',

    ended_at TIMESTAMP WITH TIME ZONE,
    COMMENT ON COLUMN call_sessions.ended_at IS 'When call ended',

    duration_ms INTEGER,
    COMMENT ON COLUMN call_sessions.duration_ms IS 'Call duration in milliseconds',

    -- Call configuration
    max_participants INTEGER DEFAULT 2 NOT NULL,
    COMMENT ON COLUMN call_sessions.max_participants IS 'Maximum allowed participants (2 for 1:1, >2 for group)',

    -- Technical metadata
    initiator_sdp TEXT,
    COMMENT ON COLUMN call_sessions.initiator_sdp IS 'SDP offer from call initiator',

    call_type VARCHAR(20) DEFAULT 'direct' NOT NULL,
    COMMENT ON COLUMN call_sessions.call_type IS 'direct (1:1), group',

    -- Soft delete for archival
    deleted_at TIMESTAMP WITH TIME ZONE
);

COMMENT ON TABLE call_sessions IS 'Video call sessions - each row represents one complete call';

-- Call participants table (tracks who participated)
CREATE TABLE IF NOT EXISTS call_participants (
    id UUID PRIMARY KEY,
    call_id UUID NOT NULL REFERENCES call_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Participation timing
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    left_at TIMESTAMP WITH TIME ZONE,
    COMMENT ON COLUMN call_participants.left_at IS 'When participant left the call',

    -- Media status
    has_audio BOOLEAN DEFAULT true,
    has_video BOOLEAN DEFAULT true,
    COMMENT ON COLUMN call_participants.has_audio IS 'Whether audio was enabled',
    COMMENT ON COLUMN call_participants.has_video IS 'Whether video was enabled',

    -- Connection info for debugging
    last_ice_candidate_timestamp TIMESTAMP WITH TIME ZONE,
    COMMENT ON COLUMN call_participants.last_ice_candidate_timestamp IS 'Last ICE candidate exchange time',

    -- SDP data for WebRTC negotiation
    answer_sdp TEXT,
    COMMENT ON COLUMN call_participants.answer_sdp IS 'SDP answer from peer',

    -- Participant status
    connection_state VARCHAR(30) DEFAULT 'new',
    COMMENT ON COLUMN call_participants.connection_state IS 'new, connecting, connected, disconnected, failed, closed'
);

COMMENT ON TABLE call_participants IS 'Participants in a video call session';

-- Create indexes for efficient queries
-- Query pattern: Get all calls in a conversation
CREATE INDEX IF NOT EXISTS idx_call_sessions_conversation
ON call_sessions(conversation_id, created_at DESC)
WHERE deleted_at IS NULL;

-- Query pattern: Get active calls for a user
CREATE INDEX IF NOT EXISTS idx_call_sessions_initiator
ON call_sessions(initiator_id, created_at DESC)
WHERE status IN ('ringing', 'connected') AND deleted_at IS NULL;

-- Query pattern: Get participants in a call
CREATE INDEX IF NOT EXISTS idx_call_participants_call
ON call_participants(call_id, joined_at ASC);

-- Query pattern: Get user's active calls
CREATE INDEX IF NOT EXISTS idx_call_participants_user
ON call_participants(user_id, call_id)
WHERE left_at IS NULL;

-- Query pattern: Find calls by user for history
CREATE INDEX IF NOT EXISTS idx_call_participants_user_history
ON call_participants(user_id, joined_at DESC);

-- Constraints to ensure data integrity
-- Ensure initiator is always a participant
ALTER TABLE call_sessions ADD CONSTRAINT initiator_is_participant
CHECK (initiator_id IN (
    SELECT user_id FROM call_participants
    WHERE call_id = call_sessions.id
));

-- Ensure at least 1 participant (besides the constraint above)
ALTER TABLE call_sessions ADD CONSTRAINT min_participants_check
CHECK (max_participants >= 1);

-- Ensure valid status transitions
ALTER TABLE call_sessions ADD CONSTRAINT valid_status
CHECK (status IN ('ringing', 'connected', 'ended', 'failed'));

-- Ensure valid connection states
ALTER TABLE call_participants ADD CONSTRAINT valid_connection_state
CHECK (connection_state IN ('new', 'connecting', 'connected', 'disconnected', 'failed', 'closed'));

-- Ensure a call has reasonable duration
ALTER TABLE call_sessions ADD CONSTRAINT valid_duration
CHECK (duration_ms IS NULL OR (duration_ms > 0 AND duration_ms <= 86400000));
-- 86400000 ms = 24 hours max call duration

COMMENT ON CONSTRAINT min_participants_check ON call_sessions
IS 'Ensures max_participants is at least 1';

COMMENT ON CONSTRAINT valid_status ON call_sessions
IS 'Ensures status is one of: ringing, connected, ended, failed';

COMMENT ON CONSTRAINT valid_connection_state ON call_participants
IS 'Ensures connection_state follows valid WebRTC states';

COMMENT ON CONSTRAINT valid_duration ON call_sessions
IS 'Ensures duration is positive and less than 24 hours';

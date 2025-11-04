-- Cleanup legacy message sequence infrastructure after adopting conversation_counters

-- Drop trigger/function on messages
DROP TRIGGER IF EXISTS set_message_sequence ON messages;
DROP FUNCTION IF EXISTS assign_message_sequence();

-- Drop legacy column on conversations
ALTER TABLE conversations
    DROP COLUMN IF EXISTS last_sequence_number;

-- Ensure messages.sequence_number has no default sequence
ALTER TABLE messages
    ALTER COLUMN sequence_number DROP DEFAULT;

-- Drop auto sequence created by old BIGSERIAL definition if still present
DROP SEQUENCE IF EXISTS messages_sequence_number_seq;

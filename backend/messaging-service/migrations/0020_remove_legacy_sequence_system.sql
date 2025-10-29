-- Remove legacy sequence auto-increment logic; rely on conversation_counters instead

-- Drop trigger/function that updated conversations.last_sequence_number
DROP TRIGGER IF EXISTS set_message_sequence ON messages;
DROP FUNCTION IF EXISTS assign_message_sequence();

-- Drop legacy sequence tracking column
ALTER TABLE conversations
    DROP COLUMN IF EXISTS last_sequence_number;

-- Ensure messages.sequence_number no longer uses implicit sequence/default
ALTER TABLE messages
    ALTER COLUMN sequence_number DROP DEFAULT;

-- Drop auto-generated sequence created by legacy BIGSERIAL definition if present
DROP SEQUENCE IF EXISTS messages_sequence_number_seq;

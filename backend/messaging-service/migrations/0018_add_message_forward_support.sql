-- Add message forward support
-- This migration adds tables and triggers for message forwarding functionality

-- Create message_forwards table to track forwarded messages
CREATE TABLE IF NOT EXISTS message_forwards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    original_message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    forwarded_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    forwarded_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    custom_note TEXT, -- Optional additional message when forwarding
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_message_forwards_original
    ON message_forwards(original_message_id);
CREATE INDEX IF NOT EXISTS idx_message_forwards_user
    ON message_forwards(forwarded_by_user_id);
CREATE INDEX IF NOT EXISTS idx_message_forwards_target_conversation
    ON message_forwards(target_conversation_id);
CREATE INDEX IF NOT EXISTS idx_message_forwards_created_at
    ON message_forwards(created_at DESC);

-- Create forward_count column in messages table if it doesn't exist
ALTER TABLE messages ADD COLUMN IF NOT EXISTS forward_count INT DEFAULT 0;

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_message_forwards_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_message_forwards_updated_at ON message_forwards;

CREATE TRIGGER trg_update_message_forwards_updated_at
BEFORE UPDATE ON message_forwards
FOR EACH ROW
EXECUTE FUNCTION update_message_forwards_updated_at();

-- Create trigger to increment forward_count when a message is forwarded
CREATE OR REPLACE FUNCTION increment_message_forward_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE messages SET forward_count = forward_count + 1 WHERE id = NEW.original_message_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_increment_message_forward_count ON message_forwards;

CREATE TRIGGER trg_increment_message_forward_count
AFTER INSERT ON message_forwards
FOR EACH ROW
EXECUTE FUNCTION increment_message_forward_count();

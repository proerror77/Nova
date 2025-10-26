-- Add audio message support with proper type discrimination
-- Migration: 0015_add_audio_message_support

-- Add message type field to messages table
ALTER TABLE messages ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text';
COMMENT ON COLUMN messages.message_type IS 'Type of message: text, audio, image, video, file';

-- Add audio-specific metadata fields
ALTER TABLE messages ADD COLUMN IF NOT EXISTS duration_ms INTEGER;
COMMENT ON COLUMN messages.duration_ms IS 'Duration of audio message in milliseconds';

ALTER TABLE messages ADD COLUMN IF NOT EXISTS audio_codec VARCHAR(20);
COMMENT ON COLUMN messages.audio_codec IS 'Audio codec: opus, aac, mp3, wav';

ALTER TABLE messages ADD COLUMN IF NOT EXISTS transcription TEXT;
COMMENT ON COLUMN messages.transcription IS 'Optional transcription of audio message';

ALTER TABLE messages ADD COLUMN IF NOT EXISTS transcription_language VARCHAR(10) DEFAULT 'en';
COMMENT ON COLUMN messages.transcription_language IS 'Language of transcription (ISO 639-1 code)';

-- Create index for message type queries (useful for filtering)
CREATE INDEX IF NOT EXISTS idx_messages_type ON messages(message_type)
WHERE message_type IN ('audio', 'image', 'video');
COMMENT ON INDEX idx_messages_type IS 'Index for efficient media message filtering';

-- Create index for conversation+type queries (common pattern)
CREATE INDEX IF NOT EXISTS idx_messages_conversation_type ON messages(conversation_id, message_type)
WHERE message_type != 'text';
COMMENT ON INDEX idx_messages_conversation_type IS 'Index for media messages in conversation';

-- Add constraint to ensure audio messages have required metadata
-- (using check constraint to enforce data integrity)
ALTER TABLE messages ADD CONSTRAINT audio_message_metadata_check
CHECK (
  message_type != 'audio' OR
  (duration_ms > 0 AND duration_ms <= 600000 AND audio_codec IS NOT NULL)
);
COMMENT ON CONSTRAINT audio_message_metadata_check ON messages
IS 'Audio messages must have positive duration (<= 10 minutes) and codec specified';

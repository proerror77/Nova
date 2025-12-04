-- Migration: Create message_reactions table for emoji reactions
-- Supports multiple users reacting to the same message with different emojis
-- Primary key ensures one reaction type per user per message

-- Up
-- Note: user_id FK removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS message_reactions (
  user_id UUID NOT NULL,
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  reaction TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, message_id, reaction)
);

-- Index for fast lookup of all reactions on a message
CREATE INDEX IF NOT EXISTS idx_reactions_message_id
  ON message_reactions(message_id);

-- Index for finding all reactions by a specific user
CREATE INDEX IF NOT EXISTS idx_reactions_user_id
  ON message_reactions(user_id);

-- Check constraint to prevent empty reaction strings
ALTER TABLE message_reactions
  ADD CONSTRAINT chk_reaction_not_empty
  CHECK (length(trim(reaction)) > 0);

-- Down
DROP TABLE IF EXISTS message_reactions;

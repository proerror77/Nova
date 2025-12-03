-- Migration: Create message_recalls table for audit trail
-- Tracks when messages are recalled and by whom for compliance and debugging

-- Up
-- Note: recalled_by FK removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS message_recalls (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  recalled_by UUID NOT NULL,
  recall_reason TEXT,
  recalled_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for finding all recalls for a specific message
CREATE INDEX IF NOT EXISTS idx_recalls_message_id
  ON message_recalls(message_id);

-- Index for finding all recalls performed by a user
CREATE INDEX IF NOT EXISTS idx_recalls_recalled_by
  ON message_recalls(recalled_by);

-- Index for time-based queries (recent recalls, audit reports)
CREATE INDEX IF NOT EXISTS idx_recalls_recalled_at
  ON message_recalls(recalled_at DESC);

-- Composite index for message recall history with timestamp ordering
CREATE INDEX IF NOT EXISTS idx_recalls_message_time
  ON message_recalls(message_id, recalled_at DESC);

-- Down
DROP TABLE IF EXISTS message_recalls;

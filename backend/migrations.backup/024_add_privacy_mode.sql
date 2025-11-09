-- Add privacy_mode to conversations to control indexing/search behavior
-- Values: 'strict_e2e' (do not index or allow search), 'search_enabled' (allow client-provided plaintext indexing)

ALTER TABLE conversations
ADD COLUMN IF NOT EXISTS privacy_mode VARCHAR(20) NOT NULL DEFAULT 'search_enabled' 
    CHECK (privacy_mode IN ('strict_e2e', 'search_enabled'));

-- Optional: index for filtering by privacy_mode if needed later
CREATE INDEX IF NOT EXISTS idx_conversations_privacy_mode ON conversations(privacy_mode);


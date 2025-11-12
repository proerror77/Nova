CREATE TYPE conversation_type AS ENUM ('direct', 'group');
CREATE TYPE privacy_mode AS ENUM ('strict_e2e', 'search_enabled');

CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY,
  kind conversation_type NOT NULL,
  name TEXT,
  description TEXT,
  member_count INT NOT NULL DEFAULT 0,
  last_message_id UUID,
  privacy_mode privacy_mode NOT NULL DEFAULT 'strict_e2e',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


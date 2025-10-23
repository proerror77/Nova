-- Initial users table for messaging-service
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  public_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


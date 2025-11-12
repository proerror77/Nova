-- Migration to fix messaging-service writing to users table
-- This is a CRITICAL P0 fix for data ownership violations

-- Step 1: Remove messaging-service's ability to write to users table
-- (This should be done at the application level and permissions)

-- Step 2: Create proper message sender cache table owned by messaging-service
CREATE TABLE IF NOT EXISTS message_sender_cache (
    user_id UUID PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    avatar_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- This is a cache/read model, not source of truth
    -- Data is populated from UserCreated/UserUpdated events
    CONSTRAINT cache_ttl CHECK (last_updated > NOW() - INTERVAL '7 days')
);

-- Create indexes
CREATE INDEX idx_message_sender_cache_updated ON message_sender_cache(last_updated);

-- Step 3: Migrate existing message references
-- Update messages table to use cached sender info instead of direct user join
ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS sender_username VARCHAR(255),
    ADD COLUMN IF NOT EXISTS sender_display_name VARCHAR(255),
    ADD COLUMN IF NOT EXISTS sender_avatar_url TEXT;

-- Populate the new columns from existing data
UPDATE messages m
SET
    sender_username = u.username,
    sender_display_name = u.display_name,
    sender_avatar_url = u.avatar_url
FROM users u
WHERE m.sender_id = u.id
    AND m.sender_username IS NULL;

-- Step 4: Create event handler table for messaging-service
CREATE TABLE IF NOT EXISTS messaging_event_inbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id VARCHAR(255) NOT NULL UNIQUE,
    event_type VARCHAR(100) NOT NULL,
    aggregate_id VARCHAR(255) NOT NULL,
    event_data JSONB NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,

    -- Ensure idempotency
    CONSTRAINT unique_event_id UNIQUE (event_id)
);

-- Create indexes
CREATE INDEX idx_messaging_inbox_unprocessed ON messaging_event_inbox(received_at)
    WHERE processed_at IS NULL;
CREATE INDEX idx_messaging_inbox_aggregate ON messaging_event_inbox(aggregate_id);

-- Step 5: Remove foreign key constraint from messages to users
-- This breaks the direct dependency
ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_sender_id_fkey,
    DROP CONSTRAINT IF EXISTS messages_recipient_id_fkey;

-- Add comment explaining the change
COMMENT ON TABLE message_sender_cache IS 'Read-only cache of user data for messaging service. Updated via events from identity-service.';
COMMENT ON TABLE messaging_event_inbox IS 'Inbox for consuming domain events from other services.';

-- Step 6: Create stored procedure for event-driven cache updates
CREATE OR REPLACE FUNCTION update_message_sender_cache()
RETURNS TRIGGER AS $$
BEGIN
    -- This would be called by event handler, not trigger
    -- Shown here for documentation purposes
    INSERT INTO message_sender_cache (user_id, username, display_name, avatar_url, is_active, last_updated)
    VALUES (NEW.user_id, NEW.username, NEW.display_name, NEW.avatar_url, NEW.is_active, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET
        username = EXCLUDED.username,
        display_name = EXCLUDED.display_name,
        avatar_url = EXCLUDED.avatar_url,
        is_active = EXCLUDED.is_active,
        last_updated = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 7: Add monitoring for cache staleness
CREATE OR REPLACE VIEW stale_message_sender_cache AS
SELECT
    user_id,
    username,
    last_updated,
    NOW() - last_updated AS age
FROM message_sender_cache
WHERE last_updated < NOW() - INTERVAL '1 day'
ORDER BY last_updated ASC;

-- Step 8: Revoke direct access permissions
-- REVOKE INSERT, UPDATE, DELETE ON users FROM messaging_service_role;
-- GRANT SELECT (id, is_active) ON users TO messaging_service_role;  -- Read-only for validation

-- Step 9: Create migration status tracking
CREATE TABLE IF NOT EXISTS migration_status (
    migration_name VARCHAR(255) PRIMARY KEY,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    status VARCHAR(50) NOT NULL DEFAULT 'in_progress',
    details JSONB
);

INSERT INTO migration_status (migration_name, status, details)
VALUES ('fix_messaging_service_boundaries', 'in_progress',
    '{"step": "schema_changes", "next": "update_application_code"}'::jsonb);

-- Note: After this migration:
-- 1. messaging-service must be updated to use message_sender_cache instead of users table
-- 2. messaging-service must subscribe to UserCreated/UserUpdated events
-- 3. messaging-service must stop writing to users table
-- 4. GraphQL gateway must be updated to not expect messaging to have user data
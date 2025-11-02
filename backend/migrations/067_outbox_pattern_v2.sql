-- ============================================
-- Migration: 067_outbox_pattern_v2
--
-- Changes from v1:
-- - Introduce Outbox table (guarantees atomicity)
-- - Do NOT use CASCADE (violates microservices philosophy)
-- - Event-driven cascade delete via Kafka
--
-- Linus Principle: "Simple is better than complex"
-- Outbox pattern ensures:
-- 1. Atomic database transaction
-- 2. Event guaranteed to publish (can retry)
-- 3. Distributed systems safety
--
-- Do NOT use CASCADE constraints for microservices.
-- Use event-driven deletion instead.
--
-- Author: Nova Team + Backend Architect Review
-- Date: 2025-11-02
-- ============================================

-- Step 1: Create Outbox table
-- This table captures all events that need to be published to Kafka
CREATE TABLE IF NOT EXISTS outbox_events (
    id BIGSERIAL PRIMARY KEY,
    aggregate_type VARCHAR(50) NOT NULL,     -- 'User', 'Message', 'Post'
    aggregate_id UUID NOT NULL,              -- user_id, message_id, post_id
    event_type VARCHAR(50) NOT NULL,         -- 'UserDeleted', 'MessageCreated'
    payload JSONB NOT NULL,                  -- Event data (user_id, timestamp, etc.)
    created_at TIMESTAMP DEFAULT NOW(),
    published_at TIMESTAMP NULL,             -- When Kafka confirmed receipt
    retry_count INT DEFAULT 0
);

-- Step 2: Create index for unpublished events (Kafka consumer polls this)
CREATE INDEX IF NOT EXISTS idx_outbox_unpublished
    ON outbox_events(created_at ASC)
    WHERE published_at IS NULL
    AND retry_count < 3;

-- Step 3: Create index for event retry and monitoring
CREATE INDEX IF NOT EXISTS idx_outbox_by_aggregate
    ON outbox_events(aggregate_type, aggregate_id, created_at DESC);

-- Step 4: Create trigger function for UserDeleted event
-- When a user is soft-deleted, emit an event
CREATE OR REPLACE FUNCTION emit_user_deletion_event()
RETURNS TRIGGER AS $$
BEGIN
    -- Only emit when user transitions from active to deleted
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
        VALUES (
            'User',
            NEW.id,
            'UserDeleted',
            jsonb_build_object(
                'user_id', NEW.id,
                'deleted_at', NEW.deleted_at,
                'deleted_by', NEW.deleted_by,
                'timestamp', NOW()
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Create trigger on users table
-- This ensures EVERY user deletion creates an Outbox event (atomically)
CREATE TRIGGER IF NOT EXISTS trg_user_deletion
AFTER UPDATE OF deleted_at ON users
FOR EACH ROW
EXECUTE FUNCTION emit_user_deletion_event();

-- Step 6: Soft-delete trigger for messages (when user is deleted)
-- Messaging service will listen to Outbox events and soft-delete user's messages
CREATE OR REPLACE FUNCTION cascade_delete_user_messages()
RETURNS TRIGGER AS $$
BEGIN
    -- If user is soft-deleted, also soft-delete their messages
    -- (for audit trail while cascade delete is in progress)
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        UPDATE messages
        SET deleted_at = NEW.deleted_at,
            deleted_by = NEW.deleted_by
        WHERE sender_id = NEW.id
            AND deleted_at IS NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 7: Create trigger for soft-delete cascade
-- This provides immediate cascade for backward compatibility
-- But the authoritative cascade happens via Kafka (from messaging-service consumer)
CREATE TRIGGER IF NOT EXISTS trg_cascade_delete_user_messages
AFTER UPDATE OF deleted_at ON users
FOR EACH ROW
EXECUTE FUNCTION cascade_delete_user_messages();

-- Step 8: Create helper function to get user messages (for manual cascading if needed)
CREATE OR REPLACE FUNCTION get_user_messages_for_deletion(p_user_id UUID)
RETURNS TABLE (
    message_id UUID,
    conversation_id UUID,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.id, m.conversation_id, m.created_at
    FROM messages m
    WHERE m.sender_id = p_user_id
        AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Step 9: Add comment explaining Outbox pattern
COMMENT ON TABLE outbox_events IS
    'Outbox pattern for guaranteed event delivery. Events are inserted atomically with business logic changes. Kafka consumer polls this table and publishes to Kafka topics.';

COMMENT ON COLUMN outbox_events.published_at IS
    'Timestamp when event was successfully published to Kafka. NULL = not yet published. Used to detect stale/stuck events.';

COMMENT ON COLUMN outbox_events.retry_count IS
    'How many times publishing was retried. Helps detect poison pill events that consistently fail.';

-- Step 10: Add NOT CASCADE constraint to messages.sender_id
-- We do NOT add CASCADE because we use event-driven deletion
-- If sender_id foreign key doesn't exist yet, create without CASCADE
ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;

-- Recreate FK without CASCADE
ALTER TABLE messages
    ADD CONSTRAINT fk_messages_sender_id
    FOREIGN KEY (sender_id) REFERENCES users(id)
    ON DELETE RESTRICT;  -- RESTRICT: don't allow hard delete if messages exist
    -- This forces proper soft-delete workflow

COMMENT ON CONSTRAINT fk_messages_sender_id ON messages IS
    'FK to users.id with RESTRICT (no hard deletes). Soft deletes are handled via Outbox pattern + Kafka event listeners. Do not use CASCADE.';

-- Step 11: Add similar pattern for other cascade scenarios
-- Example: when message is deleted, update conversation.message_count
CREATE OR REPLACE FUNCTION emit_message_deletion_event()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
        VALUES (
            'Message',
            NEW.id,
            'MessageDeleted',
            jsonb_build_object(
                'message_id', NEW.id,
                'conversation_id', NEW.conversation_id,
                'deleted_at', NEW.deleted_at,
                'deleted_by', NEW.deleted_by
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER IF NOT EXISTS trg_message_deletion
AFTER UPDATE OF deleted_at ON messages
FOR EACH ROW
EXECUTE FUNCTION emit_message_deletion_event();

-- Step 12: Log migration
INSERT INTO schema_migrations_log (migration_number, table_name, change_description)
VALUES (
    '067',
    'outbox_events,messages,users',
    'Added Outbox pattern for event-driven cascade deletes. Emit UserDeleted event when user is soft-deleted. Kafka consumers handle cascade deletions. DO NOT use CASCADE constraints for microservices.'
)
ON CONFLICT DO NOTHING;

-- Step 13: Add monitoring view for Outbox backlog
CREATE OR REPLACE VIEW outbox_status AS
SELECT
    COUNT(*) as total_events,
    COUNT(CASE WHEN published_at IS NULL THEN 1 END) as unpublished_events,
    COUNT(CASE WHEN published_at IS NULL AND retry_count > 0 THEN 1 END) as failed_events,
    MIN(created_at) as oldest_unpublished,
    MAX(created_at) as newest_event,
    ROUND(EXTRACT(EPOCH FROM (NOW() - MIN(created_at)))) as oldest_age_seconds
FROM outbox_events;

COMMENT ON VIEW outbox_status IS
    'Monitor Outbox table health. Used to detect if Kafka consumer is behind or failing.';

-- Step 14: Add alert function for stale events
CREATE OR REPLACE FUNCTION check_outbox_health()
RETURNS TABLE (
    health_status VARCHAR(20),
    message TEXT,
    unpublished_count BIGINT,
    oldest_age_seconds BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        CASE
            WHEN COUNT(CASE WHEN published_at IS NULL THEN 1 END) > 1000
                THEN 'CRITICAL'::VARCHAR(20)
            WHEN COUNT(CASE WHEN published_at IS NULL THEN 1 END) > 100
                THEN 'WARNING'::VARCHAR(20)
            ELSE 'OK'::VARCHAR(20)
        END as health_status,
        CASE
            WHEN COUNT(CASE WHEN published_at IS NULL THEN 1 END) > 1000
                THEN 'Kafka consumer is severely behind. Check messaging-service logs.'
            WHEN COUNT(CASE WHEN published_at IS NULL THEN 1 END) > 100
                THEN 'Kafka consumer is behind. Monitor progress.'
            ELSE 'All events publishing normally'
        END as message,
        COUNT(CASE WHEN published_at IS NULL THEN 1 END) as unpublished_count,
        ROUND(EXTRACT(EPOCH FROM (NOW() - MIN(created_at)))) as oldest_age_seconds
    FROM outbox_events
    WHERE published_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Step 15: Analyze new tables
ANALYZE outbox_events;
ANALYZE messages;
ANALYZE users;

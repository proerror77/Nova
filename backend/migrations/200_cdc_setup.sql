-- CDC Setup Migration: PostgreSQL logical replication for Debezium
-- This migration creates the prerequisites for Change Data Capture

-- 1. Create heartbeat table for Debezium to detect replication lag
CREATE TABLE IF NOT EXISTS cdc_heartbeat (
    id INTEGER PRIMARY KEY DEFAULT 1,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT cdc_heartbeat_single_row CHECK (id = 1)
);

-- Initialize heartbeat row
INSERT INTO cdc_heartbeat (id, ts) VALUES (1, NOW())
ON CONFLICT (id) DO UPDATE SET ts = NOW();

-- 2. Create CDC publication for Debezium
-- This publication includes all tables that should be captured
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'nova_cdc_publication'
    ) THEN
        CREATE PUBLICATION nova_cdc_publication FOR TABLE
            posts,
            follows,
            comments,
            likes;
    END IF;
END $$;

-- 3. Ensure replica identity is set correctly for CDC tables
-- FULL replica identity ensures DELETE operations include all column values
ALTER TABLE posts REPLICA IDENTITY FULL;
ALTER TABLE follows REPLICA IDENTITY FULL;
ALTER TABLE comments REPLICA IDENTITY FULL;
ALTER TABLE likes REPLICA IDENTITY FULL;

-- 4. Create CDC tracking metadata table
CREATE TABLE IF NOT EXISTS cdc_sync_status (
    id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL UNIQUE,
    last_synced_at TIMESTAMPTZ,
    last_lsn TEXT,
    records_synced BIGINT DEFAULT 0,
    sync_status TEXT DEFAULT 'pending',
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert tracking records for each CDC table
INSERT INTO cdc_sync_status (table_name, sync_status) VALUES
    ('posts', 'pending'),
    ('follows', 'pending'),
    ('comments', 'pending'),
    ('likes', 'pending')
ON CONFLICT (table_name) DO NOTHING;

-- 5. Grant replication permissions (if not already granted)
-- Note: The debezium/postgres image already has replication enabled
DO $$
BEGIN
    -- Ensure wal_level is logical (should be set in debezium/postgres image)
    -- This is informational only - actual setting is in postgresql.conf
    RAISE NOTICE 'CDC Setup: Ensure wal_level=logical in postgresql.conf';
END $$;

COMMENT ON TABLE cdc_heartbeat IS 'Debezium heartbeat table for replication lag detection';
COMMENT ON TABLE cdc_sync_status IS 'CDC synchronization status tracking';
COMMENT ON PUBLICATION nova_cdc_publication IS 'PostgreSQL publication for Debezium CDC';

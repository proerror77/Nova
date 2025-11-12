-- ============================================================
-- Data Ownership Enforcement Migration
-- Author: System Architect (Following Linus Principles)
-- Date: 2025-11-11
-- Purpose: Enforce single data ownership per service
-- ============================================================

-- This migration adds service ownership constraints to all tables
-- ensuring each data entity can only be written by one service

BEGIN;

-- ============================================================
-- Step 1: Add service_owner column to all tables
-- ============================================================

-- Helper function to add service_owner column if not exists
CREATE OR REPLACE FUNCTION add_service_owner_column(
    table_name TEXT,
    service_name TEXT
) RETURNS VOID AS $$
BEGIN
    -- Check if column exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = $1
        AND column_name = 'service_owner'
    ) THEN
        EXECUTE format('ALTER TABLE %I ADD COLUMN service_owner VARCHAR(50) DEFAULT %L NOT NULL',
                       table_name, service_name);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Step 2: Apply ownership to Identity Service tables
-- ============================================================

-- Sessions table
SELECT add_service_owner_column('sessions', 'identity-service');
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS owned_by_identity_sessions;
ALTER TABLE sessions ADD CONSTRAINT owned_by_identity_sessions
    CHECK (service_owner = 'identity-service');

-- Refresh tokens table
SELECT add_service_owner_column('refresh_tokens', 'identity-service');
ALTER TABLE refresh_tokens DROP CONSTRAINT IF EXISTS owned_by_identity_tokens;
ALTER TABLE refresh_tokens ADD CONSTRAINT owned_by_identity_tokens
    CHECK (service_owner = 'identity-service');

-- Revoked tokens table
SELECT add_service_owner_column('revoked_tokens', 'identity-service');
ALTER TABLE revoked_tokens DROP CONSTRAINT IF EXISTS owned_by_identity_revoked;
ALTER TABLE revoked_tokens ADD CONSTRAINT owned_by_identity_revoked
    CHECK (service_owner = 'identity-service');

-- ============================================================
-- Step 3: Apply ownership to User Service tables
-- ============================================================

-- Users table
SELECT add_service_owner_column('users', 'user-service');
ALTER TABLE users DROP CONSTRAINT IF EXISTS owned_by_user_users;
ALTER TABLE users ADD CONSTRAINT owned_by_user_users
    CHECK (service_owner = 'user-service');

-- Roles table
SELECT add_service_owner_column('roles', 'user-service');
ALTER TABLE roles DROP CONSTRAINT IF EXISTS owned_by_user_roles;
ALTER TABLE roles ADD CONSTRAINT owned_by_user_roles
    CHECK (service_owner = 'user-service');

-- Permissions table
SELECT add_service_owner_column('permissions', 'user-service');
ALTER TABLE permissions DROP CONSTRAINT IF EXISTS owned_by_user_perms;
ALTER TABLE permissions ADD CONSTRAINT owned_by_user_perms
    CHECK (service_owner = 'user-service');

-- User roles mapping
SELECT add_service_owner_column('user_roles', 'user-service');
ALTER TABLE user_roles DROP CONSTRAINT IF EXISTS owned_by_user_ur;
ALTER TABLE user_roles ADD CONSTRAINT owned_by_user_ur
    CHECK (service_owner = 'user-service');

-- Role permissions mapping
SELECT add_service_owner_column('role_permissions', 'user-service');
ALTER TABLE role_permissions DROP CONSTRAINT IF EXISTS owned_by_user_rp;
ALTER TABLE role_permissions ADD CONSTRAINT owned_by_user_rp
    CHECK (service_owner = 'user-service');

-- ============================================================
-- Step 4: Apply ownership to Content Service tables
-- ============================================================

-- Posts table
SELECT add_service_owner_column('posts', 'content-service');
ALTER TABLE posts DROP CONSTRAINT IF EXISTS owned_by_content_posts;
ALTER TABLE posts ADD CONSTRAINT owned_by_content_posts
    CHECK (service_owner = 'content-service');

-- Articles table
SELECT add_service_owner_column('articles', 'content-service');
ALTER TABLE articles DROP CONSTRAINT IF EXISTS owned_by_content_articles;
ALTER TABLE articles ADD CONSTRAINT owned_by_content_articles
    CHECK (service_owner = 'content-service');

-- Comments table
SELECT add_service_owner_column('comments', 'content-service');
ALTER TABLE comments DROP CONSTRAINT IF EXISTS owned_by_content_comments;
ALTER TABLE comments ADD CONSTRAINT owned_by_content_comments
    CHECK (service_owner = 'content-service');

-- Content versions table
SELECT add_service_owner_column('content_versions', 'content-service');
ALTER TABLE content_versions DROP CONSTRAINT IF EXISTS owned_by_content_versions;
ALTER TABLE content_versions ADD CONSTRAINT owned_by_content_versions
    CHECK (service_owner = 'content-service');

-- ============================================================
-- Step 5: Apply ownership to Social Service (Feed) tables
-- ============================================================

-- Relationships table (follows)
SELECT add_service_owner_column('relationships', 'social-service');
ALTER TABLE relationships DROP CONSTRAINT IF EXISTS owned_by_social_rel;
ALTER TABLE relationships ADD CONSTRAINT owned_by_social_rel
    CHECK (service_owner = 'social-service');

-- Feeds table
SELECT add_service_owner_column('feeds', 'social-service');
ALTER TABLE feeds DROP CONSTRAINT IF EXISTS owned_by_social_feeds;
ALTER TABLE feeds ADD CONSTRAINT owned_by_social_feeds
    CHECK (service_owner = 'social-service');

-- Likes table
SELECT add_service_owner_column('likes', 'social-service');
ALTER TABLE likes DROP CONSTRAINT IF EXISTS owned_by_social_likes;
ALTER TABLE likes ADD CONSTRAINT owned_by_social_likes
    CHECK (service_owner = 'social-service');

-- Shares table
SELECT add_service_owner_column('shares', 'social-service');
ALTER TABLE shares DROP CONSTRAINT IF EXISTS owned_by_social_shares;
ALTER TABLE shares ADD CONSTRAINT owned_by_social_shares
    CHECK (service_owner = 'social-service');

-- ============================================================
-- Step 6: Apply ownership to Messaging Service tables
-- ============================================================

-- Conversations table
SELECT add_service_owner_column('conversations', 'messaging-service');
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS owned_by_messaging_conv;
ALTER TABLE conversations ADD CONSTRAINT owned_by_messaging_conv
    CHECK (service_owner = 'messaging-service');

-- Messages table
SELECT add_service_owner_column('messages', 'messaging-service');
ALTER TABLE messages DROP CONSTRAINT IF EXISTS owned_by_messaging_msg;
ALTER TABLE messages ADD CONSTRAINT owned_by_messaging_msg
    CHECK (service_owner = 'messaging-service');

-- Message status table
SELECT add_service_owner_column('message_status', 'messaging-service');
ALTER TABLE message_status DROP CONSTRAINT IF EXISTS owned_by_messaging_status;
ALTER TABLE message_status ADD CONSTRAINT owned_by_messaging_status
    CHECK (service_owner = 'messaging-service');

-- ============================================================
-- Step 7: Apply ownership to Notification Service tables
-- ============================================================

-- Notifications table
SELECT add_service_owner_column('notifications', 'notification-service');
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS owned_by_notif_notif;
ALTER TABLE notifications ADD CONSTRAINT owned_by_notif_notif
    CHECK (service_owner = 'notification-service');

-- Email queue table
SELECT add_service_owner_column('email_queue', 'notification-service');
ALTER TABLE email_queue DROP CONSTRAINT IF EXISTS owned_by_notif_email;
ALTER TABLE email_queue ADD CONSTRAINT owned_by_notif_email
    CHECK (service_owner = 'notification-service');

-- SMS queue table
SELECT add_service_owner_column('sms_queue', 'notification-service');
ALTER TABLE sms_queue DROP CONSTRAINT IF EXISTS owned_by_notif_sms;
ALTER TABLE sms_queue ADD CONSTRAINT owned_by_notif_sms
    CHECK (service_owner = 'notification-service');

-- Push tokens table
SELECT add_service_owner_column('push_tokens', 'notification-service');
ALTER TABLE push_tokens DROP CONSTRAINT IF EXISTS owned_by_notif_push;
ALTER TABLE push_tokens ADD CONSTRAINT owned_by_notif_push
    CHECK (service_owner = 'notification-service');

-- ============================================================
-- Step 8: Apply ownership to Media Service tables
-- ============================================================

-- Media files table
SELECT add_service_owner_column('media_files', 'media-service');
ALTER TABLE media_files DROP CONSTRAINT IF EXISTS owned_by_media_files;
ALTER TABLE media_files ADD CONSTRAINT owned_by_media_files
    CHECK (service_owner = 'media-service');

-- Media metadata table
SELECT add_service_owner_column('media_metadata', 'media-service');
ALTER TABLE media_metadata DROP CONSTRAINT IF EXISTS owned_by_media_meta;
ALTER TABLE media_metadata ADD CONSTRAINT owned_by_media_meta
    CHECK (service_owner = 'media-service');

-- Thumbnails table
SELECT add_service_owner_column('thumbnails', 'media-service');
ALTER TABLE thumbnails DROP CONSTRAINT IF EXISTS owned_by_media_thumb;
ALTER TABLE thumbnails ADD CONSTRAINT owned_by_media_thumb
    CHECK (service_owner = 'media-service');

-- Transcode jobs table
SELECT add_service_owner_column('transcode_jobs', 'media-service');
ALTER TABLE transcode_jobs DROP CONSTRAINT IF EXISTS owned_by_media_transcode;
ALTER TABLE transcode_jobs ADD CONSTRAINT owned_by_media_transcode
    CHECK (service_owner = 'media-service');

-- ============================================================
-- Step 9: Apply ownership to Events Service tables
-- ============================================================

-- Domain events table
SELECT add_service_owner_column('domain_events', 'events-service');
ALTER TABLE domain_events DROP CONSTRAINT IF EXISTS owned_by_events_events;
ALTER TABLE domain_events ADD CONSTRAINT owned_by_events_events
    CHECK (service_owner = 'events-service');

-- Event handlers table
SELECT add_service_owner_column('event_handlers', 'events-service');
ALTER TABLE event_handlers DROP CONSTRAINT IF EXISTS owned_by_events_handlers;
ALTER TABLE event_handlers ADD CONSTRAINT owned_by_events_handlers
    CHECK (service_owner = 'events-service');

-- Event subscriptions table
SELECT add_service_owner_column('event_subscriptions', 'events-service');
ALTER TABLE event_subscriptions DROP CONSTRAINT IF EXISTS owned_by_events_subs;
ALTER TABLE event_subscriptions ADD CONSTRAINT owned_by_events_subs
    CHECK (service_owner = 'events-service');

-- ============================================================
-- Step 10: Create audit trigger for cross-service violations
-- ============================================================

-- Create audit log table
CREATE TABLE IF NOT EXISTS service_boundary_violations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    violation_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_name VARCHAR(50) NOT NULL,
    table_name VARCHAR(50) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    attempted_by VARCHAR(100),
    query_text TEXT,
    error_message TEXT
);

-- Create function to log violations
CREATE OR REPLACE FUNCTION log_boundary_violation()
RETURNS TRIGGER AS $$
DECLARE
    current_service VARCHAR(50);
    table_owner VARCHAR(50);
BEGIN
    -- Get current service from application name or session variable
    current_service := current_setting('application_name', true);

    -- Get table owner
    IF TG_OP = 'INSERT' THEN
        table_owner := NEW.service_owner;
    ELSIF TG_OP = 'UPDATE' THEN
        table_owner := OLD.service_owner;
    ELSIF TG_OP = 'DELETE' THEN
        table_owner := OLD.service_owner;
    END IF;

    -- Check if service matches owner
    IF current_service IS NOT NULL AND current_service != table_owner THEN
        -- Log violation
        INSERT INTO service_boundary_violations (
            service_name, table_name, operation,
            attempted_by, query_text, error_message
        ) VALUES (
            current_service, TG_TABLE_NAME, TG_OP,
            current_user, current_query(),
            format('Service %s attempted to %s on table owned by %s',
                   current_service, TG_OP, table_owner)
        );

        -- Raise exception to prevent operation
        RAISE EXCEPTION 'Service boundary violation: % cannot % table % owned by %',
            current_service, TG_OP, TG_TABLE_NAME, table_owner
            USING ERRCODE = 'check_violation';
    END IF;

    -- Allow operation if check passes
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Step 11: Create helper view for service ownership overview
-- ============================================================

CREATE OR REPLACE VIEW service_table_ownership AS
SELECT
    schemaname,
    tablename,
    COALESCE(
        (SELECT service_owner
         FROM information_schema.columns
         WHERE table_schema = t.schemaname
         AND table_name = t.tablename
         AND column_name = 'service_owner'
         LIMIT 1),
        'unassigned'
    ) as owning_service,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as table_size,
    (SELECT COUNT(*)
     FROM information_schema.columns
     WHERE table_schema = t.schemaname
     AND table_name = t.tablename) as column_count
FROM pg_tables t
WHERE schemaname = 'public'
ORDER BY owning_service, tablename;

-- ============================================================
-- Step 12: Create validation function
-- ============================================================

CREATE OR REPLACE FUNCTION validate_service_boundaries()
RETURNS TABLE(
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check 1: All tables have service_owner
    RETURN QUERY
    SELECT
        'All tables have service owner'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'::TEXT
            ELSE 'FAIL'::TEXT
        END,
        CASE
            WHEN COUNT(*) = 0 THEN 'All tables have service_owner column'::TEXT
            ELSE format('%s tables missing service_owner', COUNT(*))::TEXT
        END
    FROM pg_tables t
    WHERE schemaname = 'public'
    AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns c
        WHERE c.table_schema = t.schemaname
        AND c.table_name = t.tablename
        AND c.column_name = 'service_owner'
    );

    -- Check 2: No cross-service foreign keys
    RETURN QUERY
    WITH cross_service_fks AS (
        SELECT
            tc.table_name as from_table,
            kcu.column_name as from_column,
            ccu.table_name as to_table,
            ccu.column_name as to_column
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu
            ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
    )
    SELECT
        'No cross-service foreign keys'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'::TEXT
            ELSE 'WARNING'::TEXT
        END,
        CASE
            WHEN COUNT(*) = 0 THEN 'No cross-service foreign keys detected'::TEXT
            ELSE format('%s potential cross-service FKs found', COUNT(*))::TEXT
        END
    FROM cross_service_fks;

    -- Check 3: Recent boundary violations
    RETURN QUERY
    SELECT
        'No recent boundary violations'::TEXT,
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'::TEXT
            ELSE 'FAIL'::TEXT
        END,
        CASE
            WHEN COUNT(*) = 0 THEN 'No violations in last 24 hours'::TEXT
            ELSE format('%s violations in last 24 hours', COUNT(*))::TEXT
        END
    FROM service_boundary_violations
    WHERE violation_time > NOW() - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Step 13: Run validation
-- ============================================================

SELECT * FROM validate_service_boundaries();

-- ============================================================
-- Step 14: Create index for performance
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_service_owner ON users(service_owner);
CREATE INDEX IF NOT EXISTS idx_violations_time ON service_boundary_violations(violation_time DESC);

-- ============================================================
-- Step 15: Grant appropriate permissions
-- ============================================================

-- Each service should only have write access to its own tables
-- This is an example for the user-service

-- Revoke all default permissions
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

-- Create service-specific roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'identity_service') THEN
        CREATE ROLE identity_service WITH LOGIN PASSWORD 'ChangeMeInProduction';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'user_service') THEN
        CREATE ROLE user_service WITH LOGIN PASSWORD 'ChangeMeInProduction';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'content_service') THEN
        CREATE ROLE content_service WITH LOGIN PASSWORD 'ChangeMeInProduction';
    END IF;

    -- Add more service roles as needed
END $$;

-- Grant permissions based on ownership
-- Example for user-service
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO user_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON roles TO user_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON permissions TO user_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_roles TO user_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON role_permissions TO user_service;

-- Grant read-only access to other services' tables for queries
GRANT SELECT ON users TO identity_service;
GRANT SELECT ON users TO content_service;

-- Clean up helper function
DROP FUNCTION IF EXISTS add_service_owner_column(TEXT, TEXT);

COMMIT;

-- ============================================================
-- Rollback Script (save separately)
-- ============================================================
/*
-- To rollback this migration, run:

BEGIN;

-- Remove constraints
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS owned_by_identity_sessions;
ALTER TABLE refresh_tokens DROP CONSTRAINT IF EXISTS owned_by_identity_tokens;
-- ... (repeat for all tables)

-- Remove columns
ALTER TABLE sessions DROP COLUMN IF EXISTS service_owner;
ALTER TABLE refresh_tokens DROP COLUMN IF EXISTS service_owner;
-- ... (repeat for all tables)

-- Drop audit table and functions
DROP TABLE IF EXISTS service_boundary_violations;
DROP FUNCTION IF EXISTS log_boundary_violation();
DROP FUNCTION IF EXISTS validate_service_boundaries();
DROP VIEW IF EXISTS service_table_ownership;

-- Restore default permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO PUBLIC;

COMMIT;
*/
-- ============================================================================
-- Migration: Deprecate Old Messaging Schema (Phase E) - SAFE VERSION
-- Purpose: Mark old messaging tables as deprecated before realtime-chat-service migration
-- Context: messaging-service split into realtime-chat-service + notification-service
-- Safety: Uses expand-contract pattern to avoid data loss
-- ============================================================================

-- ⚠️ EXPAND PHASE: Mark tables as deprecated without dropping
-- Tables will be dropped in a future migration after data migration is confirmed

-- Add deprecation notices via comments
COMMENT ON TABLE messages IS '⚠️ DEPRECATED: Use realtime-chat-service schema. Will be dropped after data migration.';
COMMENT ON TABLE conversation_members IS '⚠️ DEPRECATED: Use realtime-chat-service schema. Will be dropped after data migration.';
COMMENT ON TABLE conversations IS '⚠️ DEPRECATED: Use realtime-chat-service schema. Will be dropped after data migration.';

-- Disable triggers to prevent accidental writes
ALTER TABLE messages DISABLE TRIGGER ALL;
ALTER TABLE conversation_members DISABLE TRIGGER ALL;
ALTER TABLE conversations DISABLE TRIGGER ALL;

-- ============================================================================
-- Next steps:
-- 1. Verify realtime-chat-service has migrated all data
-- 2. Confirm no services are using these deprecated tables
-- 3. Apply migration 998_down.sql to actually drop tables
--
-- Apply realtime-chat migrations:
--   cd backend/realtime-chat-service
--   sqlx migrate run --database-url postgres://postgres:postgres@localhost:5432/nova_chat
-- ============================================================================

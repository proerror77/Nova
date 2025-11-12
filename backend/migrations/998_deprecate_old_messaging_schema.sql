-- ============================================================================
-- Migration: Deprecate Old Messaging Schema (Phase E)
-- Purpose: Remove old messaging tables before realtime-chat-service migration
-- Context: messaging-service split into realtime-chat-service + notification-service
-- ============================================================================

-- WARNING: This will DROP messaging tables. Backup first if data exists.

-- ============ Drop old messaging tables ============
-- These will be replaced by realtime-chat-service's improved schema
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS conversation_members CASCADE;
DROP TABLE IF EXISTS conversations CASCADE;

-- ============ Drop related triggers ============
DROP TRIGGER IF EXISTS trigger_update_conversation_timestamp ON messages;

-- ============ Drop related functions ============
DROP FUNCTION IF EXISTS update_conversation_timestamp() CASCADE;
DROP FUNCTION IF EXISTS get_unread_count(UUID, UUID) CASCADE;

-- ============================================================================
-- Next steps:
-- realtime-chat-service will create new tables with:
-- - ENUM types for conversation_type and privacy_mode
-- - Improved schema with privacy_mode support
-- - Additional tables: message_attachments, message_reactions, location_sharing, etc.
--
-- Apply realtime-chat migrations:
--   cd backend/realtime-chat-service
--   sqlx migrate run --database-url postgres://postgres:postgres@localhost:5432/nova_chat
-- ============================================================================

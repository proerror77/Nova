-- ============================================================================
-- Migration: FINAL DROP of Old Messaging Schema (Phase E-Final)
-- Purpose: Actually drop deprecated messaging tables after data migration
-- Context: Run ONLY after confirming data migration to realtime-chat-service
-- Safety: This is the CONTRACT phase - data will be permanently deleted
-- ============================================================================

-- ⚠️⚠️⚠️ WARNING ⚠️⚠️⚠️
-- This migration PERMANENTLY DELETES DATA
-- DO NOT RUN unless:
-- 1. Data has been migrated to realtime-chat-service
-- 2. All services have been updated to use new schema
-- 3. Production backup has been verified
-- ============================================================================

-- ============ Drop old messaging tables ============
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS conversation_members CASCADE;
DROP TABLE IF EXISTS conversations CASCADE;

-- ============ Drop related triggers ============
DROP TRIGGER IF EXISTS trigger_update_conversation_timestamp ON messages;

-- ============ Drop related functions ============
DROP FUNCTION IF EXISTS update_conversation_timestamp() CASCADE;
DROP FUNCTION IF EXISTS get_unread_count(UUID, UUID) CASCADE;

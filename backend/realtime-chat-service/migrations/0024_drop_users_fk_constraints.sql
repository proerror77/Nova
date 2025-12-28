-- Migration: Drop FK constraints to users table
-- Reason: Single-writer principle - realtime-chat-service should not have FK dependencies on users table owned by identity-service
-- Pattern: Microservices should not have cross-service FK constraints; data consistency is handled at application level

-- Drop FK constraints from conversation_members
ALTER TABLE conversation_members DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;

-- Drop FK constraints from messages
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;

-- Drop FK constraints from message_reactions
ALTER TABLE message_reactions DROP CONSTRAINT IF EXISTS message_reactions_user_id_fkey;

-- Drop FK constraints from message_attachments
ALTER TABLE message_attachments DROP CONSTRAINT IF EXISTS message_attachments_uploaded_by_fkey;

-- Drop FK constraints from message_recalls
ALTER TABLE message_recalls DROP CONSTRAINT IF EXISTS message_recalls_recalled_by_fkey;

-- Drop FK constraints from call_sessions (table name from 0016)
ALTER TABLE call_sessions DROP CONSTRAINT IF EXISTS call_sessions_initiator_id_fkey;

-- Drop FK constraints from call_participants (table name from 0016)
ALTER TABLE call_participants DROP CONSTRAINT IF EXISTS call_participants_user_id_fkey;

-- Drop FK constraints from location tables (table names from 0021)
ALTER TABLE user_locations DROP CONSTRAINT IF EXISTS user_locations_user_id_fkey;
ALTER TABLE location_share_events DROP CONSTRAINT IF EXISTS location_share_events_user_id_fkey;
ALTER TABLE location_permissions DROP CONSTRAINT IF EXISTS location_permissions_user_id_fkey;

-- Drop FK constraints from blocks and dm_permissions (table names from 0023)
ALTER TABLE blocks DROP CONSTRAINT IF EXISTS blocks_blocker_id_fkey;
ALTER TABLE blocks DROP CONSTRAINT IF EXISTS blocks_blocked_id_fkey;
ALTER TABLE message_requests DROP CONSTRAINT IF EXISTS message_requests_requester_id_fkey;
ALTER TABLE message_requests DROP CONSTRAINT IF EXISTS message_requests_recipient_id_fkey;

-- Drop FK constraints from E2EE tables (table names from 0010)
ALTER TABLE user_devices DROP CONSTRAINT IF EXISTS user_devices_user_id_fkey;
ALTER TABLE olm_sessions DROP CONSTRAINT IF EXISTS olm_sessions_user_id_fkey;
ALTER TABLE megolm_inbound_sessions DROP CONSTRAINT IF EXISTS megolm_inbound_sessions_user_id_fkey;

-- Add indexes for columns that lost FK constraints (for query performance)
-- These replace the implicit indexes that FK constraints provided
CREATE INDEX IF NOT EXISTS idx_conversation_members_user_id ON conversation_members(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id ON message_reactions(user_id);
CREATE INDEX IF NOT EXISTS idx_message_attachments_uploaded_by ON message_attachments(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_call_sessions_initiator_id ON call_sessions(initiator_id);

-- Note: Application layer is now responsible for validating user existence
-- This follows the microservices pattern where each service owns its data

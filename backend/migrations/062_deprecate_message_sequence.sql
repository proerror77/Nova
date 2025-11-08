-- Phase 1: Mark legacy message sequence infrastructure as deprecated
-- This allows gradual migration without breaking existing code
-- See expand-contract pattern: expand-contract-deprecate-remove

-- Mark legacy trigger and function as deprecated (but keep them functional)
ALTER TRIGGER IF EXISTS set_message_sequence ON messages RENAME TO set_message_sequence_deprecated;
ALTER FUNCTION IF EXISTS assign_message_sequence() RENAME TO assign_message_sequence_deprecated();

-- Add deprecation comment to last_sequence_number column
COMMENT ON COLUMN conversations.last_sequence_number IS 
'DEPRECATED: Use conversation_counters table instead. This column will be removed in a future version after all code is updated.';

-- Add deprecation comment to messages.sequence_number
COMMENT ON COLUMN messages.sequence_number IS 
'DEPRECATED: This column is deprecated but still maintained for backward compatibility. No new code should rely on this.';

-- Track migration status for monitoring
-- This helps teams understand when legacy columns can be safely removed
INSERT INTO migration_status (migration_name, status, notes)
VALUES (
  '062_deprecate_message_sequence',
  'deprecated',
  'Message sequence system deprecated. Application code must migrate to conversation_counters. Keep this column until all services are updated.'
)
ON CONFLICT (migration_name) 
DO UPDATE SET status = 'deprecated', last_updated = NOW();

-- Phase 2 (FUTURE): Remove message sequence infrastructure
-- 
-- DO NOT EXECUTE YET!
-- Only execute this migration after:
-- 1. All application code has been updated to use conversation_counters
-- 2. At least 1-2 release cycles have passed
-- 3. You've confirmed all dependent services are updated
-- 
-- This migration is provided as a template for future cleanup.
-- Current version keeps deprecated columns for backward compatibility.

-- TODO: Uncomment and execute only after expand-contract complete

-- Step 1: Drop deprecated trigger and function
-- DROP TRIGGER IF EXISTS set_message_sequence_deprecated ON messages;
-- DROP FUNCTION IF EXISTS assign_message_sequence_deprecated();

-- Step 2: Drop auto sequence
-- DROP SEQUENCE IF EXISTS messages_sequence_number_seq;

-- Step 3: Drop legacy column (AFTER all code updated)
-- ALTER TABLE conversations DROP COLUMN IF EXISTS last_sequence_number;

-- Step 4: Optional - drop sequence_number from messages if not needed
-- (Keep this if you want to maintain sequence_number for audit purposes)
-- ALTER TABLE messages DROP COLUMN IF EXISTS sequence_number;

-- Step 5: Verify removal
-- \d conversations
-- \d messages

-- SUCCESS: Legacy message sequence system has been completely removed

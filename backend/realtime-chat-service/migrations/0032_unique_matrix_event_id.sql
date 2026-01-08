-- Migration: 0032_unique_matrix_event_id
-- Purpose: Ensure Matrix ingress deduplication is enforced at the database layer.
-- Notes:
--   - Required by MessageService::store_matrix_message_metadata_db ON CONFLICT clause.
--   - Safe/idempotent via IF NOT EXISTS.

CREATE UNIQUE INDEX IF NOT EXISTS ux_messages_matrix_event_id
ON messages(matrix_event_id)
WHERE matrix_event_id IS NOT NULL;

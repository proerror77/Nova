-- Migration: Create message_attachments table for file attachments
-- Supports multiple files per message with metadata tracking

-- Up
-- Note: uploaded_by FK removed - users table is in separate database (identity-service)
CREATE TABLE IF NOT EXISTS message_attachments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  file_url TEXT NOT NULL,
  file_type VARCHAR(255) NOT NULL,
  file_size BIGINT NOT NULL,
  uploaded_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for retrieving all attachments for a message
CREATE INDEX IF NOT EXISTS idx_attachments_message_id
  ON message_attachments(message_id);

-- Index for finding attachments uploaded by a user
CREATE INDEX IF NOT EXISTS idx_attachments_uploaded_by
  ON message_attachments(uploaded_by);

-- Index for filtering by file type
CREATE INDEX IF NOT EXISTS idx_attachments_file_type
  ON message_attachments(file_type);

-- Check constraints for data validation
ALTER TABLE message_attachments
  ADD CONSTRAINT chk_file_url_not_empty
  CHECK (length(trim(file_url)) > 0);

ALTER TABLE message_attachments
  ADD CONSTRAINT chk_file_size_positive
  CHECK (file_size > 0);

ALTER TABLE message_attachments
  ADD CONSTRAINT chk_file_type_not_empty
  CHECK (length(trim(file_type)) > 0);

-- Down
DROP TABLE IF EXISTS message_attachments;

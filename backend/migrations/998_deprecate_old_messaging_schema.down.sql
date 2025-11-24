-- ============================================================================
-- Rollback: Re-enable deprecated messaging schema
-- ============================================================================

-- Re-enable triggers
ALTER TABLE messages ENABLE TRIGGER ALL;
ALTER TABLE conversation_members ENABLE TRIGGER ALL;
ALTER TABLE conversations ENABLE TRIGGER ALL;

-- Remove deprecation warnings
COMMENT ON TABLE messages IS 'Chat messages';
COMMENT ON TABLE conversation_members IS 'Conversation membership';
COMMENT ON TABLE conversations IS 'Chat conversations';

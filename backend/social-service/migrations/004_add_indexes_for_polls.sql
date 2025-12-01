-- ============================================================================
-- Migration: Add indexes for poll voting queries
-- Service: social-service
-- Purpose:
--   - Improve performance for queries that aggregate votes per candidate
--   - Keep schema compatible with existing application code
-- Safety:
--   - Purely additive index, no table or data modifications
--   - Idempotent via IF NOT EXISTS
-- ============================================================================

-- When displaying poll results or candidate rankings, queries often need to
-- aggregate votes per candidate. This index avoids full-table scans on
-- poll_votes for those use cases.
CREATE INDEX IF NOT EXISTS idx_poll_votes_candidate_id
    ON poll_votes (candidate_id);


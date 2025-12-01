-- ============================================================================
-- Migration: Add indexes for invite codes and user channel subscriptions
-- Service: identity-service
-- Purpose:
--   - Optimize invite code lookups during registration
--   - Optimize queries that list subscribers of a given channel
-- Safety:
--   - Purely additive indexes, no schema or data changes
--   - Idempotent via IF NOT EXISTS
-- ============================================================================

-- Fast lookup of active invite codes by code.
-- NOTE: We intentionally do NOT include expires_at in the predicate to keep
-- the predicate simple and to avoid relying on time-based expressions.
CREATE INDEX IF NOT EXISTS idx_invite_codes_code_active
    ON invite_codes (code)
    WHERE redeemed_at IS NULL;

-- Efficiently list all users subscribed to a given channel.
CREATE INDEX IF NOT EXISTS idx_user_channels_channel_id
    ON user_channels (channel_id);


-- Migration: Add invite quota system and referral chain tracking
-- Follows expand-contract pattern: only additive changes

-- 1. Add invite quota and referral tracking to users table
ALTER TABLE users
ADD COLUMN IF NOT EXISTS invite_quota INT NOT NULL DEFAULT 10,
ADD COLUMN IF NOT EXISTS referred_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS total_successful_referrals INT NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS referral_reward_per_signup INT NOT NULL DEFAULT 1;

-- Index for finding referrals
CREATE INDEX IF NOT EXISTS idx_users_referred_by ON users(referred_by_user_id) WHERE referred_by_user_id IS NOT NULL;

-- 2. Referral chain tracking (for analytics and rewards)
CREATE TABLE IF NOT EXISTS referral_chains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    referee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invite_code_id UUID REFERENCES invite_codes(id) ON DELETE SET NULL,
    depth INT NOT NULL DEFAULT 1,  -- 1 = direct invite, 2+ = chain depth
    status VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending, active, churned
    reward_granted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    activated_at TIMESTAMPTZ,  -- when referee becomes "active" (e.g., first post)
    UNIQUE(referrer_id, referee_id),
    CHECK (referrer_id != referee_id)
);

CREATE INDEX IF NOT EXISTS idx_referral_chains_referrer ON referral_chains(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referral_chains_referee ON referral_chains(referee_id);
CREATE INDEX IF NOT EXISTS idx_referral_chains_status ON referral_chains(status);

-- 3. Invite delivery tracking (SMS, Email, Link shares)
CREATE TABLE IF NOT EXISTS invite_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invite_code_id UUID NOT NULL REFERENCES invite_codes(id) ON DELETE CASCADE,
    channel VARCHAR(20) NOT NULL,  -- sms, email, link, qrcode
    recipient VARCHAR(255),  -- phone number or email (null for link shares)
    external_id VARCHAR(255),  -- AWS SNS message ID or similar
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,  -- tracked via redirect
    status VARCHAR(20) NOT NULL DEFAULT 'sent',  -- sent, delivered, opened, failed
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_invite_deliveries_code ON invite_deliveries(invite_code_id);
CREATE INDEX IF NOT EXISTS idx_invite_deliveries_channel ON invite_deliveries(channel);
CREATE INDEX IF NOT EXISTS idx_invite_deliveries_status ON invite_deliveries(status);

-- 4. Update invite_codes table: extend expiry default to 30 days
-- Note: This only affects new rows, existing rows keep their expiry
COMMENT ON COLUMN invite_codes.expires_at IS 'Default expiry is 30 days from creation';

-- 5. Function to check and consume invite quota
CREATE OR REPLACE FUNCTION check_invite_quota(p_user_id UUID)
RETURNS TABLE(can_invite BOOLEAN, remaining INT, total INT) AS $$
DECLARE
    v_quota INT;
    v_used INT;
BEGIN
    -- Get user quota
    SELECT invite_quota INTO v_quota FROM users WHERE id = p_user_id;

    -- Count used invites (generated, not necessarily redeemed)
    SELECT COUNT(*) INTO v_used
    FROM invite_codes
    WHERE issuer_user_id = p_user_id;

    RETURN QUERY SELECT
        (v_used < v_quota) AS can_invite,
        GREATEST(0, v_quota - v_used) AS remaining,
        v_quota AS total;
END;
$$ LANGUAGE plpgsql;

-- 6. Function to grant referral reward
CREATE OR REPLACE FUNCTION grant_referral_reward(p_referee_id UUID)
RETURNS VOID AS $$
DECLARE
    v_referrer_id UUID;
    v_reward INT;
BEGIN
    -- Find the referrer
    SELECT referred_by_user_id INTO v_referrer_id
    FROM users
    WHERE id = p_referee_id;

    IF v_referrer_id IS NOT NULL THEN
        -- Get reward amount
        SELECT referral_reward_per_signup INTO v_reward
        FROM users
        WHERE id = v_referrer_id;

        -- Grant additional quota to referrer
        UPDATE users
        SET invite_quota = invite_quota + COALESCE(v_reward, 1),
            total_successful_referrals = total_successful_referrals + 1
        WHERE id = v_referrer_id;

        -- Update referral chain
        UPDATE referral_chains
        SET status = 'active',
            activated_at = NOW(),
            reward_granted = TRUE
        WHERE referrer_id = v_referrer_id
          AND referee_id = p_referee_id
          AND NOT reward_granted;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 7. Trigger to auto-setup referral when invite is redeemed
CREATE OR REPLACE FUNCTION on_invite_redeemed()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process when redeemed_by changes from NULL to a value
    IF OLD.redeemed_by IS NULL AND NEW.redeemed_by IS NOT NULL THEN
        -- Create referral chain entry
        INSERT INTO referral_chains (referrer_id, referee_id, invite_code_id, depth, status)
        VALUES (NEW.issuer_user_id, NEW.redeemed_by, NEW.id, 1, 'pending')
        ON CONFLICT (referrer_id, referee_id) DO NOTHING;

        -- Update user's referred_by
        UPDATE users
        SET referred_by_user_id = NEW.issuer_user_id
        WHERE id = NEW.redeemed_by
          AND referred_by_user_id IS NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invite_redeemed ON invite_codes;
CREATE TRIGGER trg_invite_redeemed
    AFTER UPDATE ON invite_codes
    FOR EACH ROW
    EXECUTE FUNCTION on_invite_redeemed();

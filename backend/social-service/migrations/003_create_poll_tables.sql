-- ============================================================================
-- Poll Tables (投票榜单功能)
-- 集成到 social-service，与 likes/comments 同属社交互动领域
-- ============================================================================

-- POLLS TABLE (投票/榜单主表)
CREATE TABLE IF NOT EXISTS polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    cover_image_url TEXT,
    creator_id UUID NOT NULL,
    poll_type VARCHAR(30) NOT NULL DEFAULT 'ranking',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    total_votes BIGINT NOT NULL DEFAULT 0,
    candidate_count INT NOT NULL DEFAULT 0,
    post_id UUID,  -- 关联内容（可选）
    tags TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at TIMESTAMPTZ,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT chk_poll_type CHECK (poll_type IN ('single_choice', 'multiple_choice', 'ranking')),
    CONSTRAINT chk_poll_status CHECK (status IN ('draft', 'active', 'closed', 'archived'))
);

CREATE INDEX idx_polls_creator_id ON polls(creator_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_polls_status ON polls(status) WHERE is_deleted = FALSE;
CREATE INDEX idx_polls_total_votes ON polls(total_votes DESC) WHERE status = 'active' AND is_deleted = FALSE;

-- CANDIDATES TABLE (候选人表)
CREATE TABLE IF NOT EXISTS poll_candidates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    avatar_url TEXT,
    description TEXT,
    user_id UUID,  -- 如果候选人是系统用户
    vote_count BIGINT NOT NULL DEFAULT 0,
    position INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX idx_poll_candidates_poll_id ON poll_candidates(poll_id) WHERE is_deleted = FALSE;
CREATE INDEX idx_poll_candidates_vote_count ON poll_candidates(poll_id, vote_count DESC) WHERE is_deleted = FALSE;

-- VOTES TABLE (投票记录表)
CREATE TABLE IF NOT EXISTS poll_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    poll_id UUID NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES poll_candidates(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_vote_per_user_per_poll UNIQUE (poll_id, user_id)
);

CREATE INDEX idx_poll_votes_poll_id ON poll_votes(poll_id);
CREATE INDEX idx_poll_votes_user_id ON poll_votes(user_id);

-- TRIGGERS: 自动更新投票计数
CREATE OR REPLACE FUNCTION update_poll_vote_counts() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE poll_candidates SET vote_count = vote_count + 1 WHERE id = NEW.candidate_id;
        UPDATE polls SET total_votes = total_votes + 1, updated_at = NOW() WHERE id = NEW.poll_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE poll_candidates SET vote_count = GREATEST(vote_count - 1, 0) WHERE id = OLD.candidate_id;
        UPDATE polls SET total_votes = GREATEST(total_votes - 1, 0), updated_at = NOW() WHERE id = OLD.poll_id;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_poll_vote_counts
AFTER INSERT OR DELETE ON poll_votes
FOR EACH ROW EXECUTE FUNCTION update_poll_vote_counts();

-- 示例数据：Hottest Banker
INSERT INTO polls (id, title, description, creator_id, poll_type, status, tags)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Hottest Banker',
    'Vote for the hottest banker!',
    '00000000-0000-0000-0000-000000000000',
    'ranking', 'active',
    ARRAY['finance', 'trending']
) ON CONFLICT DO NOTHING;

INSERT INTO poll_candidates (poll_id, name, avatar_url, position) VALUES
    ('00000000-0000-0000-0000-000000000001', 'Alex Chen', 'https://randomuser.me/api/portraits/men/1.jpg', 1),
    ('00000000-0000-0000-0000-000000000001', 'Sarah Johnson', 'https://randomuser.me/api/portraits/women/2.jpg', 2),
    ('00000000-0000-0000-0000-000000000001', 'Michael Wang', 'https://randomuser.me/api/portraits/men/3.jpg', 3)
ON CONFLICT DO NOTHING;

UPDATE polls SET candidate_count = 3 WHERE id = '00000000-0000-0000-0000-000000000001';

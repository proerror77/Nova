-- CDN Service Database Schema
-- Phase 1B Week 4 - Asset Management

-- ============================================================================
-- Table: assets
-- Stores metadata for all uploaded CDN assets
-- ============================================================================
CREATE TABLE IF NOT EXISTS assets (
    asset_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    original_filename VARCHAR(256) NOT NULL,
    file_size BIGINT NOT NULL CHECK (file_size > 0),
    content_type VARCHAR(100) NOT NULL,
    storage_key VARCHAR(512) NOT NULL UNIQUE, -- S3 object key
    cdn_url VARCHAR(1024),
    upload_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    access_count BIGINT NOT NULL DEFAULT 0,
    last_accessed TIMESTAMP WITH TIME ZONE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,

    -- Indexes for performance
    CONSTRAINT assets_storage_key_unique UNIQUE (storage_key)
);

CREATE INDEX idx_assets_user_upload ON assets(user_id, upload_timestamp DESC) WHERE is_deleted = FALSE;
CREATE INDEX idx_assets_storage_key ON assets(storage_key) WHERE is_deleted = FALSE;
CREATE INDEX idx_assets_deleted ON assets(is_deleted, upload_timestamp) WHERE is_deleted = TRUE;

-- ============================================================================
-- Table: cache_invalidations
-- Tracks cache invalidation requests and status
-- ============================================================================
CREATE TABLE IF NOT EXISTS cache_invalidations (
    invalidation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID REFERENCES assets(asset_id) ON DELETE CASCADE,
    invalidation_reason VARCHAR(256) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- pending, in_progress, completed, failed
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMP WITH TIME ZONE,

    -- Constraints
    CONSTRAINT check_invalidation_status CHECK (status IN ('pending', 'in_progress', 'completed', 'failed'))
);

CREATE INDEX idx_cache_inv_asset ON cache_invalidations(asset_id, created_at DESC);
CREATE INDEX idx_cache_inv_status ON cache_invalidations(status, created_at) WHERE status != 'completed';

-- ============================================================================
-- Table: cdn_quota
-- Tracks storage quota per user
-- ============================================================================
CREATE TABLE IF NOT EXISTS cdn_quota (
    user_id UUID PRIMARY KEY,
    total_quota_bytes BIGINT NOT NULL DEFAULT 10737418240, -- 10GB default
    used_bytes BIGINT NOT NULL DEFAULT 0,
    last_updated TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT check_quota_positive CHECK (total_quota_bytes > 0),
    CONSTRAINT check_used_non_negative CHECK (used_bytes >= 0),
    CONSTRAINT check_used_within_quota CHECK (used_bytes <= total_quota_bytes)
);

-- ============================================================================
-- Function: Update quota on asset changes
-- ============================================================================
CREATE OR REPLACE FUNCTION update_cdn_quota()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Increment used bytes
        INSERT INTO cdn_quota (user_id, used_bytes)
        VALUES (NEW.user_id, NEW.file_size)
        ON CONFLICT (user_id) DO UPDATE
        SET used_bytes = cdn_quota.used_bytes + NEW.file_size,
            last_updated = NOW();

    ELSIF TG_OP = 'UPDATE' AND NEW.is_deleted = TRUE AND OLD.is_deleted = FALSE THEN
        -- Decrement used bytes on soft delete
        UPDATE cdn_quota
        SET used_bytes = GREATEST(0, used_bytes - OLD.file_size),
            last_updated = NOW()
        WHERE user_id = OLD.user_id;

    ELSIF TG_OP = 'DELETE' THEN
        -- Decrement used bytes on hard delete
        UPDATE cdn_quota
        SET used_bytes = GREATEST(0, used_bytes - OLD.file_size),
            last_updated = NOW()
        WHERE user_id = OLD.user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Auto-update quota
CREATE TRIGGER trigger_update_cdn_quota
AFTER INSERT OR UPDATE OR DELETE ON assets
FOR EACH ROW
EXECUTE FUNCTION update_cdn_quota();

-- ============================================================================
-- Function: Update access count
-- ============================================================================
CREATE OR REPLACE FUNCTION update_asset_access()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE assets
    SET access_count = access_count + 1,
        last_accessed = NOW()
    WHERE asset_id = NEW.asset_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Initial Data: Default quotas (optional)
-- ============================================================================
COMMENT ON TABLE assets IS 'CDN asset metadata with S3 storage keys';
COMMENT ON TABLE cache_invalidations IS 'Cache invalidation tracking for CDN assets';
COMMENT ON TABLE cdn_quota IS 'Storage quota management per user';
COMMENT ON COLUMN assets.storage_key IS 'Unique S3 object key, format: {user_id}/{asset_id}/{filename}';
COMMENT ON COLUMN assets.cdn_url IS 'Full CDN URL with domain, generated on upload';

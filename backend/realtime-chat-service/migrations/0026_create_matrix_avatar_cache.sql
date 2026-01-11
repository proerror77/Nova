-- Create matrix_avatar_cache table to avoid re-uploading same avatars to Matrix
CREATE TABLE IF NOT EXISTS matrix_avatar_cache (
    user_id UUID NOT NULL,
    avatar_url_hash VARCHAR(64) NOT NULL,
    mxc_url TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, avatar_url_hash)
);

-- Index for faster lookups by user_id
CREATE INDEX idx_matrix_avatar_cache_user_id ON matrix_avatar_cache(user_id);

-- Index for faster lookups by hash (for deduplication across users)
CREATE INDEX idx_matrix_avatar_cache_hash ON matrix_avatar_cache(avatar_url_hash);

-- Trigger to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_matrix_avatar_cache_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_matrix_avatar_cache_updated_at
    BEFORE UPDATE ON matrix_avatar_cache
    FOR EACH ROW
    EXECUTE FUNCTION update_matrix_avatar_cache_updated_at();

-- Add comment for documentation
COMMENT ON TABLE matrix_avatar_cache IS 'Caches mapping between Nova avatar URLs and Matrix mxc:// URLs to avoid re-uploading';
COMMENT ON COLUMN matrix_avatar_cache.avatar_url_hash IS 'SHA256 hash of the original avatar URL from Nova';
COMMENT ON COLUMN matrix_avatar_cache.mxc_url IS 'Matrix mxc:// URL returned from media upload';

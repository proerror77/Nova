-- Add post sharing and bookmarking functionality
-- Created for implementing share and bookmark features for posts

-- Create post_shares table
CREATE TABLE IF NOT EXISTS post_shares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shared_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    share_via VARCHAR(50), -- 'direct_message', 'story', 'feed', 'external'
    shared_with_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE(post_id, user_id, shared_at)
);

CREATE INDEX IF NOT EXISTS idx_post_shares_post ON post_shares(post_id);
CREATE INDEX IF NOT EXISTS idx_post_shares_user ON post_shares(user_id);
CREATE INDEX IF NOT EXISTS idx_post_shares_created_at ON post_shares(shared_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_shares_shared_with ON post_shares(shared_with_user_id);

-- Create bookmarks table
CREATE TABLE IF NOT EXISTS bookmarks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    bookmarked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    collection_id UUID REFERENCES bookmark_collections(id) ON DELETE SET NULL,
    UNIQUE(user_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_user ON bookmarks(user_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_post ON bookmarks(post_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_created_at ON bookmarks(bookmarked_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmarks_collection ON bookmarks(collection_id);

-- Create bookmark_collections table (for organizing bookmarks into folders)
CREATE TABLE IF NOT EXISTS bookmark_collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_private BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bookmark_collections_user ON bookmark_collections(user_id);
CREATE INDEX IF NOT EXISTS idx_bookmark_collections_created_at ON bookmark_collections(created_at DESC);

-- Add share_count column to posts if it doesn't exist
ALTER TABLE posts ADD COLUMN IF NOT EXISTS share_count INT DEFAULT 0;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS bookmark_count INT DEFAULT 0;

-- Add share_count to social_metadata if it doesn't exist
ALTER TABLE social_metadata ADD COLUMN IF NOT EXISTS share_count INT DEFAULT 0;

-- Create trigger to update share_count when a share is created
CREATE OR REPLACE FUNCTION update_post_share_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET share_count = share_count + 1 WHERE id = NEW.post_id;
        UPDATE social_metadata SET share_count = share_count + 1 WHERE post_id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE posts SET share_count = GREATEST(0, share_count - 1) WHERE id = OLD.post_id;
        UPDATE social_metadata SET share_count = GREATEST(0, share_count - 1) WHERE post_id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_post_share_count ON post_shares;

CREATE TRIGGER trg_update_post_share_count
AFTER INSERT OR DELETE ON post_shares
FOR EACH ROW
EXECUTE FUNCTION update_post_share_count();

-- Create trigger to update bookmark_count when a bookmark is created
CREATE OR REPLACE FUNCTION update_post_bookmark_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET bookmark_count = bookmark_count + 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE posts SET bookmark_count = GREATEST(0, bookmark_count - 1) WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_post_bookmark_count ON bookmarks;

CREATE TRIGGER trg_update_post_bookmark_count
AFTER INSERT OR DELETE ON bookmarks
FOR EACH ROW
EXECUTE FUNCTION update_post_bookmark_count();

-- Create trigger to update updated_at for collections
CREATE OR REPLACE FUNCTION update_bookmark_collections_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_bookmark_collections_updated_at ON bookmark_collections;

CREATE TRIGGER trg_update_bookmark_collections_updated_at
BEFORE UPDATE ON bookmark_collections
FOR EACH ROW
EXECUTE FUNCTION update_bookmark_collections_updated_at();

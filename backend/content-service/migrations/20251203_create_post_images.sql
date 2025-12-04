-- Create post_images table for thumbnail backfill
-- Required by thumb-migrate job

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS post_images (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    s3_key VARCHAR(512) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    size_variant VARCHAR(50) NOT NULL,
    file_size INT,
    width INT,
    height INT,
    url VARCHAR(1024),
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT size_variant_valid CHECK (size_variant IN ('original', 'medium', 'thumbnail')),
    CONSTRAINT status_valid CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    CONSTRAINT s3_key_not_empty CHECK (LENGTH(s3_key) > 0)
);

CREATE INDEX IF NOT EXISTS idx_post_images_post_id ON post_images(post_id);
CREATE INDEX IF NOT EXISTS idx_post_images_status ON post_images(status);
CREATE INDEX IF NOT EXISTS idx_post_images_size_variant ON post_images(size_variant);
CREATE INDEX IF NOT EXISTS idx_post_images_post_status ON post_images(post_id, status);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_post_images_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_post_images_updated_at ON post_images;
CREATE TRIGGER update_post_images_updated_at
    BEFORE UPDATE ON post_images
    FOR EACH ROW
    EXECUTE FUNCTION update_post_images_updated_at();

-- Migration: Add author_account_type to posts table
-- Issue: #259 - Avatar borders indicating account type (Red = Real Name, Gray = Alias)
-- Description: Store the account type used when creating a post for historical accuracy

-- Add author_account_type column
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS author_account_type VARCHAR(20) DEFAULT 'primary';

-- Add constraint for valid values
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_posts_author_account_type'
    ) THEN
        ALTER TABLE posts
            ADD CONSTRAINT chk_posts_author_account_type
            CHECK (author_account_type IN ('primary', 'alias'));
    END IF;
END $$;

-- Create index for potential filtering by account type
CREATE INDEX IF NOT EXISTS idx_posts_author_account_type
    ON posts(author_account_type);

-- Backfill: All existing posts default to 'primary' (historically accurate -
-- alias feature didn't exist when these posts were created)
UPDATE posts SET author_account_type = 'primary' WHERE author_account_type IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN posts.author_account_type IS
    'Account type used when post was created: "primary" (real name) or "alias" (pseudonym)';

-- Add TOTP (Two-Factor Authentication) support and username to users table

-- Add username column
ALTER TABLE users
ADD COLUMN IF NOT EXISTS username VARCHAR(50) UNIQUE,
ADD COLUMN IF NOT EXISTS display_name VARCHAR(100);

-- Add TOTP columns
ALTER TABLE users
ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS totp_verified BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS totp_secret VARCHAR(255);

-- Create index for username lookups
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE username IS NOT NULL;

-- Add comment
COMMENT ON COLUMN users.totp_enabled IS 'Whether TOTP two-factor authentication is enabled';
COMMENT ON COLUMN users.totp_verified IS 'Whether TOTP has been verified at least once';
COMMENT ON COLUMN users.totp_secret IS 'Encrypted TOTP secret key';
COMMENT ON COLUMN users.username IS 'Unique username for the user';
COMMENT ON COLUMN users.display_name IS 'Display name shown in the UI';

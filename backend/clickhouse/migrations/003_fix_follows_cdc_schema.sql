-- Migration: Fix follows_cdc schema mismatch
-- Issue: analytics-service inserts with `followee_id`, but table has `followed_id`
--
-- This migration adds the followee_id column if it doesn't exist,
-- to support both old and new column names during transition.

-- Option 1: If table was created with old schema (followed_id as UUID)
-- Add followee_id as materialized column that copies from followed_id
ALTER TABLE follows_cdc ADD COLUMN IF NOT EXISTS followee_id String MATERIALIZED toString(followed_id);

-- Option 2: If we need to recreate the table with correct schema
-- Uncomment below if Option 1 fails

-- BACKUP: Create backup before migration
-- CREATE TABLE IF NOT EXISTS follows_cdc_backup_v3 AS follows_cdc;

-- DROP TABLE IF EXISTS follows_cdc;

-- CREATE TABLE IF NOT EXISTS follows_cdc (
--   follower_id String,
--   followee_id String,
--   created_at DateTime DEFAULT now(),
--   cdc_timestamp UInt64,
--   is_deleted UInt8 DEFAULT 0
-- ) ENGINE = ReplacingMergeTree(cdc_timestamp)
-- PARTITION BY toYYYYMM(created_at)
-- ORDER BY (follower_id, followee_id, created_at)
-- SETTINGS index_granularity = 8192;

-- Restore from backup if data existed
-- INSERT INTO follows_cdc (follower_id, followee_id, created_at, cdc_timestamp, is_deleted)
-- SELECT
--     toString(follower_id),
--     toString(followed_id),  -- Map old column to new
--     toDateTime(created_at),
--     toUnixTimestamp64Milli(cdc_timestamp),
--     0
-- FROM follows_cdc_backup_v3;

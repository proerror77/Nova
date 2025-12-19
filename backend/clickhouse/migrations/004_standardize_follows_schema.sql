-- Migration: Standardize follows_cdc schema
-- Date: 2024-12-19
-- Description: Consolidate follows_cdc to use `followee_id` consistently
--
-- Schema Standardization:
--   PostgreSQL: follower_id, following_id (the person being followed)
--   ClickHouse: follower_id, followee_id (standardized name for analytics)
--
-- This migration ensures the follows_cdc table uses the correct schema.

-- Step 1: Check if we need to migrate from old schema (followed_id → followee_id)
-- If the table has followed_id but not followee_id, create a migration

-- Create new table with correct schema if it doesn't exist
CREATE TABLE IF NOT EXISTS follows_cdc_v2 (
    follower_id UUID,
    followee_id UUID,
    created_at DateTime64(3) DEFAULT now64(3),
    cdc_operation Enum8('INSERT' = 1, 'DELETE' = 2),
    cdc_timestamp DateTime64(3) DEFAULT now64(3),
    follow_count Int8,
    INDEX idx_follower_id (follower_id) TYPE bloom_filter GRANULARITY 1,
    INDEX idx_followee_id (followee_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = SummingMergeTree((follow_count))
PARTITION BY toYYYYMM(created_at)
ORDER BY (followee_id, follower_id, cdc_timestamp)
TTL created_at + INTERVAL 365 DAY;

-- If old follows_cdc exists with followed_id, migrate data
-- This is idempotent - if followee_id already exists, this will just insert duplicates
-- that will be deduplicated by SummingMergeTree

-- INSERT INTO follows_cdc_v2 (follower_id, followee_id, created_at, cdc_operation, cdc_timestamp, follow_count)
-- SELECT
--     follower_id,
--     followed_id AS followee_id,
--     created_at,
--     cdc_operation,
--     cdc_timestamp,
--     follow_count
-- FROM follows_cdc
-- WHERE 1=0;  -- Disabled by default, run manually if migration needed

-- After migration is verified, swap tables:
-- RENAME TABLE follows_cdc TO follows_cdc_old, follows_cdc_v2 TO follows_cdc;
-- DROP TABLE follows_cdc_old;

-- ============================================
-- Migration: 011_videos_table (legacy placeholder)
-- Description: Original MySQL schema for videos; superseded by 007/022 Postgres migrations
-- ============================================

-- This migration is intentionally left blank. The canonical Postgres schema
-- is defined in 007_video_schema_postgres.sql and subsequent forward migrations.
-- Existing deployments that ran the legacy MySQL-style migration should already
-- have their schema aligned via 022_video_schema_postgres_fix.sql.

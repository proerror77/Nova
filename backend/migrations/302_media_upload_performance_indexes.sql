-- ============================================
-- Migration: 302_media_upload_performance_indexes
--
-- Description: Add performance indexes for media upload flow
-- These indexes optimize common query patterns in the media upload pipeline.
--
-- Tables Affected:
-- 1. uploads - Add user_id, status, and created_at indexes
-- 2. post_images - Add composite indexes for status queries
--
-- Performance Impact:
-- - User uploads listing: O(n) → O(log n)
-- - Status-based filtering: O(n) → O(log n)
-- - Recent uploads cleanup: O(n) → O(log n)
--
-- Author: Claude Code
-- Date: 2025-12-29
--
-- NOTE: This migration uses CREATE INDEX CONCURRENTLY which cannot run
-- inside a transaction. Each statement runs independently, so if one fails
-- after others have succeeded, you may need to manually drop the created
-- indexes before re-running.
-- ============================================

-- NOTE: No BEGIN/COMMIT - CONCURRENTLY cannot run in a transaction

-- ============================================
-- Part 1: uploads table indexes
-- ============================================

-- Pattern: List user's uploads
-- SELECT * FROM uploads WHERE user_id = $1 ORDER BY created_at DESC
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_uploads_user_id
    ON uploads(user_id, created_at DESC);

-- Pattern: Filter by status (pending, completed, failed)
-- SELECT * FROM uploads WHERE status = 'pending'
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_uploads_status
    ON uploads(status);

-- Pattern: Find incomplete uploads (for cleanup/retry)
-- SELECT * FROM uploads WHERE status = 'pending' AND created_at < NOW() - INTERVAL '1 hour'
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_uploads_pending_cleanup
    ON uploads(created_at ASC)
    WHERE status = 'pending';

-- Pattern: Recently completed uploads (for processing pipeline)
-- SELECT * FROM uploads WHERE status = 'completed' ORDER BY created_at DESC LIMIT 100
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_uploads_completed_recent
    ON uploads(created_at DESC)
    WHERE status = 'completed';

-- ============================================
-- Part 2: post_images table optimizations
-- ============================================

-- Pattern: Get all images for a post that are ready to display
-- SELECT * FROM post_images WHERE post_id = $1 AND status = 'ready' ORDER BY display_order
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_post_images_ready
    ON post_images(post_id, display_order)
    WHERE status = 'ready';

-- Pattern: Find images pending processing
-- SELECT * FROM post_images WHERE status = 'processing' ORDER BY created_at ASC
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_post_images_processing
    ON post_images(created_at ASC)
    WHERE status = 'processing';

-- ============================================
-- Part 3: upload_sessions optimizations
-- ============================================

-- Pattern: Find active upload sessions for a user
-- SELECT * FROM upload_sessions WHERE user_id = $1 AND is_completed = FALSE
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_upload_sessions_user_active
    ON upload_sessions(user_id)
    WHERE is_completed = FALSE;

-- ============================================
-- Part 4: Analyze tables for query planner
-- ============================================

ANALYZE uploads;
ANALYZE post_images;
ANALYZE upload_sessions;

-- NOTE: No COMMIT - CONCURRENTLY cannot run in a transaction

-- ============================================
-- Verification Queries (run after migration)
-- ============================================

/*
-- Verify indexes are used for user uploads query
EXPLAIN ANALYZE
SELECT * FROM uploads
WHERE user_id = 'your-test-uuid'::UUID
ORDER BY created_at DESC
LIMIT 20;

-- Expected: Index Scan using idx_uploads_user_id

-- Verify pending uploads cleanup query
EXPLAIN ANALYZE
SELECT * FROM uploads
WHERE status = 'pending'
AND created_at < NOW() - INTERVAL '1 hour';

-- Expected: Index Scan using idx_uploads_pending_cleanup

-- Check index sizes
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE tablename IN ('uploads', 'post_images', 'upload_sessions')
ORDER BY pg_relation_size(indexrelid) DESC;
*/

-- ============================================
-- Rollback Script
-- ============================================

/*
DROP INDEX CONCURRENTLY IF EXISTS idx_uploads_user_id;
DROP INDEX CONCURRENTLY IF EXISTS idx_uploads_status;
DROP INDEX CONCURRENTLY IF EXISTS idx_uploads_pending_cleanup;
DROP INDEX CONCURRENTLY IF EXISTS idx_uploads_completed_recent;
DROP INDEX CONCURRENTLY IF EXISTS idx_post_images_ready;
DROP INDEX CONCURRENTLY IF EXISTS idx_post_images_processing;
DROP INDEX CONCURRENTLY IF EXISTS idx_upload_sessions_user_active;
*/

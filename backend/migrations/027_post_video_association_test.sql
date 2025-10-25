-- ============================================
-- Test Suite for Migration 027: Post-Video Association
-- ============================================
-- This file contains comprehensive tests to validate the migration.
-- Run with: psql -U postgres -d nova_auth -f 027_post_video_association_test.sql

BEGIN;

-- ============================================
-- Setup: Create test fixtures
-- ============================================

-- Ensure test user exists
INSERT INTO users (id, username, email, password_hash, email_verified)
VALUES ('10000000-0000-0000-0000-000000000001'::uuid, 'test_user_027', 'test027@nova.com', 'test_hash', true)
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, email = EXCLUDED.email;

-- Create test videos
INSERT INTO videos (id, creator_id, title, duration_seconds, status)
VALUES
    ('20000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'Test Video 1', 30, 'published'),
    ('20000000-0000-0000-0000-000000000002'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'Test Video 2', 45, 'published')
ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title;

-- Clean up previous test runs
DELETE FROM posts WHERE user_id = '10000000-0000-0000-0000-000000000001'::uuid;

-- ============================================
-- Test 1: Backward Compatibility
-- ============================================

\echo '=== Test 1: Legacy image posts should default to content_type=image ==='
INSERT INTO posts (id, user_id, caption, image_key, status)
VALUES ('30000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'Legacy image post', 'legacy.jpg', 'published');

SELECT
    id,
    content_type,
    CASE
        WHEN content_type = 'image' THEN '✓ PASS: Default content_type is image'
        ELSE '✗ FAIL: Expected content_type=image, got ' || content_type
    END as result
FROM posts
WHERE id = '30000000-0000-0000-0000-000000000001'::uuid;

-- ============================================
-- Test 2: Video-Only Post
-- ============================================

\echo ''
\echo '=== Test 2: Video-only post should maintain content_type=video ==='
INSERT INTO posts (id, user_id, caption, image_key, status, content_type)
VALUES ('30000000-0000-0000-0000-000000000002'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'Video post', 'placeholder.jpg', 'published', 'video');

INSERT INTO post_videos (post_id, video_id, position)
VALUES ('30000000-0000-0000-0000-000000000002'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, 0);

SELECT
    id,
    content_type,
    CASE
        WHEN content_type = 'video' THEN '✓ PASS: Content type is video'
        ELSE '✗ FAIL: Expected content_type=video, got ' || content_type
    END as result
FROM posts
WHERE id = '30000000-0000-0000-0000-000000000002'::uuid;

-- ============================================
-- Test 3: Multiple Videos with Positioning
-- ============================================

\echo ''
\echo '=== Test 3: Multiple videos should respect position ordering ==='
INSERT INTO posts (id, user_id, caption, image_key, status, content_type)
VALUES ('30000000-0000-0000-0000-000000000003'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'Multi-video post', 'multi.jpg', 'published', 'video');

INSERT INTO post_videos (post_id, video_id, position)
VALUES
    ('30000000-0000-0000-0000-000000000003'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, 1),
    ('30000000-0000-0000-0000-000000000003'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, 0);

SELECT
    pv.position,
    v.title,
    CASE
        WHEN pv.position = 0 AND v.title = 'Test Video 2' THEN '✓ PASS: Position 0 has Video 2'
        WHEN pv.position = 1 AND v.title = 'Test Video 1' THEN '✓ PASS: Position 1 has Video 1'
        ELSE '✗ FAIL: Position ordering incorrect'
    END as result
FROM post_videos pv
JOIN videos v ON pv.video_id = v.id
WHERE pv.post_id = '30000000-0000-0000-0000-000000000003'::uuid
ORDER BY pv.position;

-- ============================================
-- Test 4: get_post_with_media Function
-- ============================================

\echo ''
\echo '=== Test 4: get_post_with_media should return complete media data ==='
SELECT
    id,
    content_type,
    jsonb_array_length(videos) as video_count,
    jsonb_array_length(images) as image_count,
    CASE
        WHEN jsonb_array_length(videos) = 2 THEN '✓ PASS: Correct video count (2)'
        ELSE '✗ FAIL: Expected 2 videos, got ' || jsonb_array_length(videos)::text
    END as result
FROM get_post_with_media('30000000-0000-0000-0000-000000000003'::uuid);

-- ============================================
-- Test 5: Position Uniqueness Constraint
-- ============================================

\echo ''
\echo '=== Test 5: Duplicate position should be prevented ==='
DO $$
BEGIN
    INSERT INTO post_videos (post_id, video_id, position)
    VALUES ('30000000-0000-0000-0000-000000000003'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, 0);

    RAISE EXCEPTION '✗ FAIL: Duplicate position was allowed (should have been blocked)';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '✓ PASS: Unique constraint on position correctly prevented duplicate';
END $$;

-- ============================================
-- Test 6: Post-Video Uniqueness Constraint
-- ============================================

\echo ''
\echo '=== Test 6: Same video cannot be added twice to same post ==='
DO $$
BEGIN
    INSERT INTO post_videos (post_id, video_id, position)
    VALUES ('30000000-0000-0000-0000-000000000003'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, 5);

    RAISE EXCEPTION '✗ FAIL: Duplicate post-video association was allowed';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '✓ PASS: Unique constraint on post_id+video_id prevented duplicate';
END $$;

-- ============================================
-- Test 7: Cascade Delete on Post
-- ============================================

\echo ''
\echo '=== Test 7: Deleting post should cascade delete post_videos ==='
DELETE FROM posts WHERE id = '30000000-0000-0000-0000-000000000003'::uuid;

SELECT
    COUNT(*) as remaining_associations,
    CASE
        WHEN COUNT(*) = 0 THEN '✓ PASS: Cascade delete worked correctly'
        ELSE '✗ FAIL: post_videos entries still exist after post deletion'
    END as result
FROM post_videos
WHERE post_id = '30000000-0000-0000-0000-000000000003'::uuid;

-- ============================================
-- Test 8: Indexes Exist
-- ============================================

\echo ''
\echo '=== Test 8: All required indexes should exist ==='
SELECT
    idx.indexname,
    CASE
        WHEN idx.indexname IN (
            'idx_posts_content_type',
            'idx_posts_user_content_type',
            'idx_post_videos_post_id',
            'idx_post_videos_video_id',
            'idx_post_videos_post_position'
        ) THEN '✓ PASS: Index exists'
        ELSE '? INFO: Additional index'
    END as result
FROM pg_indexes idx
WHERE idx.schemaname = 'public'
  AND (idx.tablename = 'posts' OR idx.tablename = 'post_videos')
  AND idx.indexname LIKE '%content_type%' OR idx.indexname LIKE '%post_videos%'
ORDER BY idx.tablename, idx.indexname;

-- ============================================
-- Test Summary
-- ============================================

\echo ''
\echo '========================================='
\echo 'Test Suite Complete'
\echo '========================================='
\echo 'If all tests show ✓ PASS, migration is working correctly.'
\echo ''

ROLLBACK;

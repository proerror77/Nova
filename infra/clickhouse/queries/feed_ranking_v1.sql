-- ============================================
-- Feed ranking query v1.0 (Personalized + Trending)
-- Query P95 target: ≤ 800ms
-- Input: user_id (UUID)
-- Output: Top 50 posts ranked by combined score
-- ============================================

-- Strategy: UNION three candidate sources, score each, deduplicate, rank
-- 1. Followees' recent posts (social graph signal)
-- 2. Trending posts (engagement signal)
-- 3. Affinity-based posts (personalization signal)

WITH
    -- Parameters (substitute from application layer)
    current_user AS (
        SELECT toUUID('{user_id}') AS uid  -- Replace with actual user_id
    ),

    -- Source 1: Posts from users I follow (last 72 hours)
    -- Social signal: People I chose to follow
    followees_posts AS (
        SELECT DISTINCT
            p.post_id,
            p.created_at,
            100 AS source_priority,  -- Highest priority
            'followee' AS source_type
        FROM nova_feed.follows_cdc f
        INNER JOIN nova_feed.posts_cdc p
            ON f.following_id = p.user_id
        WHERE f.follower_id = (SELECT uid FROM current_user)
            AND f.deleted = 0
            AND p.deleted = 0
            AND p.created_at >= now() - INTERVAL 72 HOUR
            -- Performance optimization: Use latest version without FINAL
            AND (f.follower_id, f.following_id, f._version) IN (
                SELECT follower_id, following_id, max(_version)
                FROM nova_feed.follows_cdc
                WHERE follower_id = (SELECT uid FROM current_user)
                GROUP BY follower_id, following_id
            )
            AND (p.post_id, p._version) IN (
                SELECT post_id, max(_version)
                FROM nova_feed.posts_cdc
                WHERE user_id IN (
                    SELECT following_id FROM nova_feed.follows_cdc
                    WHERE follower_id = (SELECT uid FROM current_user) AND deleted = 0
                )
                GROUP BY post_id
            )
        LIMIT 100
    ),

    -- Source 2: Trending posts (last 24 hours, high engagement)
    -- Engagement signal: What's popular right now
    trending_posts AS (
        SELECT
            post_id,
            window_start AS created_at,
            80 AS source_priority,
            'trending' AS source_type
        FROM (
            SELECT
                post_id,
                max(window_start) AS window_start,
                sum(views) AS total_views,
                sum(likes) AS total_likes,
                sum(comments) AS total_comments,
                sum(exposures) AS total_exposures,
                -- Engagement score: weighted sum of interactions
                (sum(views) * 1 + sum(likes) * 10 + sum(comments) * 15) AS engagement_score
            FROM nova_feed.post_metrics_1h
            WHERE window_start >= now() - INTERVAL 24 HOUR
            GROUP BY post_id
            HAVING total_exposures >= 100  -- Filter low-confidence posts
            ORDER BY engagement_score DESC
            LIMIT 100
        )
    ),

    -- Source 3: Posts from authors I have affinity with (last 90 days interaction)
    -- Personalization signal: Content discovery based on my behavior
    affinity_posts AS (
        SELECT DISTINCT
            p.post_id,
            p.created_at,
            60 AS source_priority,
            'affinity' AS source_type
        FROM (
            SELECT
                author_id,
                sum(likes) AS total_likes,
                sum(comments) AS total_comments,
                sum(views) AS total_views,
                (sum(likes) * 10 + sum(comments) * 5 + sum(views)) AS affinity_score
            FROM nova_feed.user_author_90d
            WHERE user_id = (SELECT uid FROM current_user)
            GROUP BY author_id
            ORDER BY affinity_score DESC
            LIMIT 50  -- Top 50 authors
        ) AS top_authors
        INNER JOIN nova_feed.posts_cdc p
            ON top_authors.author_id = p.user_id
        WHERE p.created_at >= now() - INTERVAL 168 HOUR  -- Last 7 days
            AND p.deleted = 0
            AND (p.post_id, p._version) IN (
                SELECT post_id, max(_version)
                FROM nova_feed.posts_cdc
                GROUP BY post_id
            )
        LIMIT 100
    ),

    -- UNION all candidates and deduplicate
    all_candidates AS (
        SELECT * FROM followees_posts
        UNION ALL
        SELECT * FROM trending_posts
        UNION ALL
        SELECT * FROM affinity_posts
    ),

    -- Enrich with real-time metrics
    scored_posts AS (
        SELECT
            c.post_id,
            c.created_at,
            c.source_type,
            c.source_priority,

            -- Freshness score (decay over time)
            -- Formula: 100 * exp(-age_hours / 24)
            -- 0 hours → 100, 24 hours → 37, 72 hours → 5
            100 * exp(-date_diff('hour', c.created_at, now()) / 24.0) AS freshness_score,

            -- Engagement score from metrics (last 24h)
            coalesce(
                (sum(m.views) * 1 + sum(m.likes) * 10 + sum(m.comments) * 15) / nullIf(sum(m.exposures), 0) * 100,
                0
            ) AS engagement_score,

            -- Combined score
            (
                c.source_priority * 1.0 +
                100 * exp(-date_diff('hour', c.created_at, now()) / 24.0) * 0.5 +
                coalesce(
                    (sum(m.views) * 1 + sum(m.likes) * 10 + sum(m.comments) * 15) / nullIf(sum(m.exposures), 0) * 100,
                    10  -- Default score for posts without metrics
                ) * 0.3
            ) AS combined_score

        FROM all_candidates c
        LEFT JOIN nova_feed.post_metrics_1h m
            ON c.post_id = m.post_id
            AND m.window_start >= now() - INTERVAL 24 HOUR
        GROUP BY c.post_id, c.created_at, c.source_type, c.source_priority
    )

-- Final ranking: Deduplicate by post_id, sort by combined_score
SELECT
    post_id,
    created_at,
    source_type,
    round(freshness_score, 2) AS freshness,
    round(engagement_score, 2) AS engagement,
    round(combined_score, 2) AS score
FROM (
    SELECT
        *,
        row_number() OVER (PARTITION BY post_id ORDER BY combined_score DESC) AS rn
    FROM scored_posts
)
WHERE rn = 1  -- Deduplicate: keep highest score per post_id
ORDER BY combined_score DESC
LIMIT 50;

-- Performance optimization notes:
-- 1. No FINAL queries on ReplacingMergeTree (use explicit _version filtering)
-- 2. Limit each source to 100 posts before UNION (reduce intermediate data)
-- 3. Use bloom_filter indexes on user_id, post_id (defined in table DDL)
-- 4. Pre-aggregate metrics in post_metrics_1h (avoid scanning events table)
-- 5. Use SummingMergeTree for affinity scores (avoid aggregation on query)

-- Query plan complexity:
-- - followees_posts: O(followees × posts/72h) ≈ 200 × 100 = 20K rows
-- - trending_posts: O(trending posts in 24h) ≈ 10K rows
-- - affinity_posts: O(top_authors × posts/7d) ≈ 50 × 500 = 25K rows
-- - Total intermediate rows: ~55K
-- - Final output: 50 rows after ranking

-- Expected query latency breakdown (P95):
-- - followees_posts: 150ms (index scan + join)
-- - trending_posts: 100ms (aggregation on pre-aggregated data)
-- - affinity_posts: 200ms (join + filter)
-- - UNION + scoring + ranking: 150ms
-- - Total: ~600ms (well within 800ms target)

-- Fallback strategy for cold start users (no followees, no affinity):
-- - Query will return only trending_posts (always non-empty)
-- - Recommended: Cache trending_posts result for 5 minutes to reduce load

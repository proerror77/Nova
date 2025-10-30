use std::sync::Arc;
use std::time::Duration;

use tokio::task::JoinHandle;
use tokio::time::{interval_at, Instant};
use tracing::{debug, error, info};

use crate::db::ch_client::ClickHouseClient;
use crate::error::Result;

/// Refresh interval for feed candidate tables.
const DEFAULT_REFRESH_INTERVAL: Duration = Duration::from_secs(300);

/// Background job that refreshes ClickHouse feed candidate tables on a cadence.
///
/// The feed ranking service reads from `feed_candidates_*` tables. Without this
/// refresher the tables would stay empty and the request path would fall back to
/// PostgreSQL. We recompute the tables every five minutes to balance freshness
/// with batch cost.
#[derive(Clone)]
pub struct FeedCandidateRefreshJob {
    ch_client: Arc<ClickHouseClient>,
    interval: Duration,
}

impl FeedCandidateRefreshJob {
    pub fn new(ch_client: Arc<ClickHouseClient>) -> Self {
        Self {
            ch_client,
            interval: DEFAULT_REFRESH_INTERVAL,
        }
    }

    #[cfg(test)]
    pub fn with_interval(mut self, interval: Duration) -> Self {
        self.interval = interval;
        self
    }

    /// Run the refresh loop. Intended to be spawned on the Tokio runtime.
    pub async fn run(self) {
        let mut ticker = interval_at(Instant::now() + Duration::from_secs(5), self.interval);
        info!(
            "Feed candidate refresh job started (interval: {:?})",
            self.interval
        );

        loop {
            ticker.tick().await;

            if let Err(err) = self.refresh_all().await {
                error!("Feed candidate refresh failed: {}", err);
            } else {
                debug!("Feed candidate tables refreshed successfully");
            }
        }
    }

    /// Spawn the refresh loop as a Tokio task.
    pub fn spawn(self) -> JoinHandle<()> {
        tokio::spawn(self.run())
    }

    async fn refresh_all(&self) -> Result<()> {
        self.refresh_followees().await?;
        self.refresh_trending().await?;
        self.refresh_affinity().await?;
        Ok(())
    }

    async fn refresh_followees(&self) -> Result<()> {
        info!("Refreshing feed_candidates_followees");
        self.rebuild_table(
            "feed_candidates_followees",
            INSERT_FEED_CANDIDATES_FOLLOWEES,
        )
        .await
    }

    async fn refresh_trending(&self) -> Result<()> {
        info!("Refreshing feed_candidates_trending");
        self.rebuild_table("feed_candidates_trending", INSERT_FEED_CANDIDATES_TRENDING)
            .await
    }

    async fn refresh_affinity(&self) -> Result<()> {
        info!("Refreshing feed_candidates_affinity");
        self.rebuild_table("feed_candidates_affinity", INSERT_FEED_CANDIDATES_AFFINITY)
            .await
    }

    async fn rebuild_table(&self, table: &str, insert_tpl: &str) -> Result<()> {
        let staging = format!("{}_staging", table);

        self.ch_client
            .execute(&format!("DROP TABLE IF EXISTS {}", staging))
            .await?;
        self.ch_client
            .execute(&format!("CREATE TABLE {} AS {}", staging, table))
            .await?;

        let insert_sql = insert_tpl.replace("{table}", &staging);
        self.ch_client.execute(&insert_sql).await?;

        self.ch_client
            .execute(&format!("EXCHANGE TABLES {} AND {}", table, staging))
            .await?;

        self.ch_client
            .execute(&format!("DROP TABLE IF EXISTS {}", staging))
            .await
    }
}

const INSERT_FEED_CANDIDATES_FOLLOWEES: &str = r#"
INSERT INTO {table}
SELECT
    f.follower_id AS user_id,
    p.id AS post_id,
    p.user_id AS author_id,
    ifNull(likes.likes_count, 0) AS likes,
    ifNull(comments.comments_count, 0) AS comments,
    toUInt32(0) AS shares,
    greatest(
        toUInt32(ifNull(likes.likes_count, 0)) * 5 +
        toUInt32(ifNull(comments.comments_count, 0)) * 10 + 10,
        toUInt32(1)
    ) AS impressions,
    exp(-0.0025 * dateDiff('minute', p.created_at, now())) AS freshness_score,
    log1p(ifNull(likes.likes_count, 0) + 2 * ifNull(comments.comments_count, 0)) AS engagement_score,
    ifNull(affinity.affinity_score, 0.0) AS affinity_score,
    0.35 * freshness_score + 0.40 * engagement_score + 0.25 * ifNull(affinity.affinity_score, 0.0) AS combined_score,
    p.created_at,
    now()
FROM posts_cdc AS p
INNER JOIN follows_cdc AS f
    ON f.followee_id = p.user_id
    AND f.is_deleted = 0
LEFT JOIN (
    SELECT post_id, count() AS likes_count
    FROM likes_cdc
    WHERE is_deleted = 0
      AND created_at >= now() - INTERVAL 30 DAY
    GROUP BY post_id
) AS likes ON likes.post_id = p.id
LEFT JOIN (
    SELECT post_id, count() AS comments_count
    FROM comments_cdc
    WHERE is_deleted = 0
      AND created_at >= now() - INTERVAL 30 DAY
    GROUP BY post_id
) AS comments ON comments.post_id = p.id
LEFT JOIN (
    SELECT
        interactions.viewer_id AS user_id,
        interactions.author_id AS author_id,
        sum(interactions.weight) AS affinity_score
    FROM (
        SELECT
            l.user_id AS viewer_id,
            p.user_id AS author_id,
            1.0 AS weight
        FROM likes_cdc AS l
        INNER JOIN posts_cdc AS p
            ON p.id = l.post_id
        WHERE l.is_deleted = 0
          AND l.created_at >= now() - INTERVAL 90 DAY
        UNION ALL
        SELECT
            c.user_id AS viewer_id,
            p.user_id AS author_id,
            1.5 AS weight
        FROM comments_cdc AS c
        INNER JOIN posts_cdc AS p
            ON p.id = c.post_id
        WHERE c.is_deleted = 0
          AND c.created_at >= now() - INTERVAL 90 DAY
    ) AS interactions
    GROUP BY interactions.viewer_id, interactions.author_id
) AS affinity
    ON affinity.user_id = f.follower_id
    AND affinity.author_id = p.user_id
WHERE p.is_deleted = 0
  AND p.created_at >= now() - INTERVAL 30 DAY
ORDER BY user_id, combined_score DESC
LIMIT 500 BY user_id
"#;

const INSERT_FEED_CANDIDATES_TRENDING: &str = r#"
INSERT INTO {table}
SELECT
    p.id AS post_id,
    p.user_id AS author_id,
    ifNull(likes.likes_count, 0) AS likes,
    ifNull(comments.comments_count, 0) AS comments,
    toUInt32(0) AS shares,
    greatest(
        toUInt32(ifNull(likes.likes_count, 0)) * 5 +
        toUInt32(ifNull(comments.comments_count, 0)) * 10 + 10,
        toUInt32(1)
    ) AS impressions,
    exp(-0.0025 * dateDiff('minute', p.created_at, now())) AS freshness_score,
    log1p(ifNull(likes.likes_count, 0) + 2 * ifNull(comments.comments_count, 0)) AS engagement_score,
    toFloat64(0) AS affinity_score,
    0.50 * freshness_score + 0.50 * engagement_score AS combined_score,
    p.created_at,
    now()
FROM posts_cdc AS p
LEFT JOIN (
    SELECT post_id, count() AS likes_count
    FROM likes_cdc
    WHERE is_deleted = 0
      AND created_at >= now() - INTERVAL 14 DAY
    GROUP BY post_id
) AS likes ON likes.post_id = p.id
LEFT JOIN (
    SELECT post_id, count() AS comments_count
    FROM comments_cdc
    WHERE is_deleted = 0
      AND created_at >= now() - INTERVAL 14 DAY
    GROUP BY post_id
) AS comments ON comments.post_id = p.id
WHERE p.is_deleted = 0
  AND p.created_at >= now() - INTERVAL 14 DAY
ORDER BY combined_score DESC
LIMIT 1000
"#;

const INSERT_FEED_CANDIDATES_AFFINITY: &str = r#"
WITH affinity_edges AS (
    SELECT
        interactions.viewer_id AS user_id,
        interactions.author_id AS author_id,
        sum(interactions.weight) AS affinity_score
    FROM (
        SELECT
            l.user_id AS viewer_id,
            p.user_id AS author_id,
            1.0 AS weight
        FROM likes_cdc AS l
        INNER JOIN posts_cdc AS p
            ON p.id = l.post_id
        WHERE l.is_deleted = 0
          AND l.created_at >= now() - INTERVAL 90 DAY
        UNION ALL
        SELECT
            c.user_id AS viewer_id,
            p.user_id AS author_id,
            1.5 AS weight
        FROM comments_cdc AS c
        INNER JOIN posts_cdc AS p
            ON p.id = c.post_id
        WHERE c.is_deleted = 0
          AND c.created_at >= now() - INTERVAL 90 DAY
    ) AS interactions
    GROUP BY interactions.viewer_id, interactions.author_id
    HAVING affinity_score > 0
)
INSERT INTO {table}
SELECT
    affinity.user_id AS user_id,
    p.id AS post_id,
    p.user_id AS author_id,
    ifNull(likes.likes_count, 0) AS likes,
    ifNull(comments.comments_count, 0) AS comments,
    toUInt32(0) AS shares,
    greatest(
        toUInt32(ifNull(likes.likes_count, 0)) * 5 +
        toUInt32(ifNull(comments.comments_count, 0)) * 10 + 10,
        toUInt32(1)
    ) AS impressions,
    exp(-0.0025 * dateDiff('minute', p.created_at, now())) AS freshness_score,
    log1p(ifNull(likes.likes_count, 0) + 2 * ifNull(comments.comments_count, 0)) AS engagement_score,
    affinity.affinity_score AS affinity_score,
    0.20 * freshness_score + 0.40 * engagement_score + 0.40 * affinity.affinity_score AS combined_score,
    p.created_at,
    now()
FROM posts_cdc AS p
INNER JOIN affinity_edges AS affinity
    ON affinity.author_id = p.user_id
LEFT JOIN (
    SELECT post_id, count() AS likes_count
    FROM likes_cdc
    WHERE is_deleted = 0
      AND created_at >= now() - INTERVAL 30 DAY
    GROUP BY post_id
) AS likes ON likes.post_id = p.id
LEFT JOIN (
    SELECT post_id, count() AS comments_count
    FROM comments_cdc
    WHERE is_deleted = 0
      AND created_at >= now() - INTERVAL 30 DAY
    GROUP BY post_id
) AS comments ON comments.post_id = p.id
WHERE p.is_deleted = 0
  AND p.created_at >= now() - INTERVAL 30 DAY
ORDER BY user_id, combined_score DESC
LIMIT 300 BY user_id
"#;

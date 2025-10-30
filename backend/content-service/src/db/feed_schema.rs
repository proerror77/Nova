use tracing::info;

use crate::db::ch_client::ClickHouseClient;
use crate::error::Result;

/// Ensure ClickHouse feed candidate tables exist.
///
/// These tables power the personalized feed and must be present before
/// we attempt to materialize any candidates. We lazily create them at
/// service startup to unblock environments where migrations have not
/// been applied yet (e.g. fresh developer machines or CI spins).
pub async fn ensure_feed_tables(ch: &ClickHouseClient) -> Result<()> {
    info!("Ensuring ClickHouse feed candidate tables exist");

    ch.execute(FEED_CANDIDATES_FOLLOWEES_TABLE).await?;
    ch.execute(FEED_CANDIDATES_TRENDING_TABLE).await?;
    ch.execute(FEED_CANDIDATES_AFFINITY_TABLE).await?;

    Ok(())
}

const FEED_CANDIDATES_FOLLOWEES_TABLE: &str = r#"
CREATE TABLE IF NOT EXISTS feed_candidates_followees (
    user_id String,
    post_id String,
    author_id String,
    likes UInt32,
    comments UInt32,
    shares UInt32,
    impressions UInt32,
    freshness_score Float64,
    engagement_score Float64,
    affinity_score Float64,
    combined_score Float64,
    created_at DateTime,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, combined_score, post_id)
SETTINGS index_granularity = 8192
"#;

const FEED_CANDIDATES_TRENDING_TABLE: &str = r#"
CREATE TABLE IF NOT EXISTS feed_candidates_trending (
    post_id String,
    author_id String,
    likes UInt32,
    comments UInt32,
    shares UInt32,
    impressions UInt32,
    freshness_score Float64,
    engagement_score Float64,
    affinity_score Float64,
    combined_score Float64,
    created_at DateTime,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (combined_score, post_id)
SETTINGS index_granularity = 8192
"#;

const FEED_CANDIDATES_AFFINITY_TABLE: &str = r#"
CREATE TABLE IF NOT EXISTS feed_candidates_affinity (
    user_id String,
    post_id String,
    author_id String,
    likes UInt32,
    comments UInt32,
    shares UInt32,
    impressions UInt32,
    freshness_score Float64,
    engagement_score Float64,
    affinity_score Float64,
    combined_score Float64,
    created_at DateTime,
    updated_at DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(updated_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, combined_score, post_id)
SETTINGS index_granularity = 8192
"#;

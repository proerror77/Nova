//! 热榜生成器
//!
//! 定时从 ClickHouse 查询热门帖子,计算 engagement score 并缓存到 Redis
//!
//! # 算法
//! - 时间窗口: 1h, 24h, 7d (支持多窗口)
//! - 评分公式: `score = views * 0.1 + likes * 2 + comments * 3 + shares * 5`
//! - 时间衰减: 指数衰减系数,最近的帖子权重更高
//! - Top-K: 返回前 50 条

use super::{CacheRefreshJob, JobContext};
use anyhow::{Context, Result};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tracing::debug;
use uuid::Uuid;

/// 热门帖子(带评分)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostWithScore {
    pub post_id: Uuid,
    pub score: f64,
    pub cached_at: i64, // Unix timestamp
}

/// 热榜生成器配置
#[derive(Debug, Clone)]
pub struct TrendingConfig {
    /// 时间窗口(小时)
    pub window_hours: i64,
    /// 返回 Top-K 数量
    pub top_k: usize,
    /// 刷新间隔(秒)
    pub interval_sec: u64,
    /// Redis key
    pub redis_key: String,
    /// 时间衰减系数 (0.0-1.0, 越接近1衰减越慢)
    pub decay_factor: f64,
}

impl Default for TrendingConfig {
    fn default() -> Self {
        Self {
            window_hours: 1,
            top_k: 50,
            interval_sec: 60,
            redis_key: "nova:cache:trending:1h".to_string(),
            decay_factor: 0.95, // 适中的衰减速度
        }
    }
}

impl TrendingConfig {
    /// 预设: 1小时热榜(高刷新频率)
    pub fn hourly() -> Self {
        Self {
            window_hours: 1,
            top_k: 50,
            interval_sec: 60,
            redis_key: "nova:cache:trending:1h".to_string(),
            decay_factor: 0.9, // 较快衰减,突出最新内容
        }
    }

    /// 预设: 24小时热榜(中等刷新频率)
    pub fn daily() -> Self {
        Self {
            window_hours: 24,
            top_k: 50,
            interval_sec: 300, // 5 分钟刷新
            redis_key: "nova:cache:trending:24h".to_string(),
            decay_factor: 0.95, // 适中衰减
        }
    }

    /// 预设: 7天热榜(低刷新频率)
    pub fn weekly() -> Self {
        Self {
            window_hours: 24 * 7,
            top_k: 50,
            interval_sec: 3600, // 1 小时刷新
            redis_key: "nova:cache:trending:7d".to_string(),
            decay_factor: 0.98, // 缓慢衰减,关注长期热度
        }
    }
}

/// 热榜生成器 Job
pub struct TrendingGeneratorJob {
    config: TrendingConfig,
}

impl TrendingGeneratorJob {
    pub fn new(config: TrendingConfig) -> Self {
        Self { config }
    }

    /// 从 ClickHouse 查询热门帖子
    ///
    /// SQL 逻辑:
    /// 1. 筛选时间窗口内的事件
    /// 2. 聚合 engagement metrics (views/likes/comments/shares)
    /// 3. 计算基础 score + 时间衰减加权
    /// 4. 按加权 score 排序并取 Top-K
    async fn query_trending_posts(&self, ctx: &JobContext) -> Result<Vec<PostWithScore>> {
        let window_hours = self.config.window_hours;
        let top_k = self.config.top_k;
        let decay_factor = self.config.decay_factor;

        // ClickHouse SQL: 带时间衰减的热榜查询
        // 时间衰减公式: decay_factor ^ (hours_ago)
        let sql = format!(
            r#"
            WITH engagement AS (
                SELECT
                    post_id,
                    countIf(event_type = 'post_view') AS views,
                    countIf(event_type = 'post_like') AS likes,
                    countIf(event_type = 'post_comment') AS comments,
                    countIf(event_type = 'post_share') AS shares,
                    max(event_time) AS latest_event_time
                FROM post_events
                WHERE event_time >= now() - INTERVAL {window_hours} HOUR
                  AND event_type IN ('post_view', 'post_like', 'post_comment', 'post_share')
                GROUP BY post_id
            )
            SELECT
                post_id,
                views,
                likes,
                comments,
                shares,
                latest_event_time,
                (views * 0.1 + likes * 2 + comments * 3 + shares * 5) *
                pow({decay_factor}, date_diff('hour', latest_event_time, now())) AS score
            FROM engagement
            WHERE score > 0
            ORDER BY score DESC
            LIMIT {top_k}
            "#
        );

        debug!(
            correlation_id = %ctx.correlation_id,
            window_hours = window_hours,
            top_k = top_k,
            decay_factor = decay_factor,
            "Querying trending posts with time decay from ClickHouse"
        );

        #[derive(clickhouse::Row, serde::Deserialize)]
        struct TrendingRow {
            post_id: String,
            #[allow(dead_code)]
            views: u64,
            #[allow(dead_code)]
            likes: u64,
            #[allow(dead_code)]
            comments: u64,
            #[allow(dead_code)]
            shares: u64,
            #[allow(dead_code)]
            latest_event_time: String,
            score: f64,
        }

        let rows: Vec<TrendingRow> = ctx
            .ch_client
            .query(&sql)
            .fetch_all()
            .await
            .context("Failed to query ClickHouse for trending posts")?;

        let now = chrono::Utc::now().timestamp();
        let posts: Vec<PostWithScore> = rows
            .into_iter()
            .filter_map(|row| {
                Uuid::parse_str(&row.post_id)
                    .ok()
                    .map(|post_id| PostWithScore {
                        post_id,
                        score: row.score,
                        cached_at: now,
                    })
            })
            .collect();

        debug!(
            correlation_id = %ctx.correlation_id,
            count = posts.len(),
            "Fetched trending posts with time decay"
        );

        Ok(posts)
    }

    /// 计算 engagement score
    ///
    /// 权重设计:
    /// - views: 0.1 (基础流量)
    /// - likes: 2 (轻度互动)
    /// - comments: 3 (中度互动)
    /// - shares: 5 (重度互动,传播价值高)
    #[allow(dead_code)]
    pub fn compute_engagement_score(views: u64, likes: u64, comments: u64, shares: u64) -> f64 {
        (views as f64) * 0.1
            + (likes as f64) * 2.0
            + (comments as f64) * 3.0
            + (shares as f64) * 5.0
    }
}

#[async_trait]
impl CacheRefreshJob for TrendingGeneratorJob {
    async fn fetch_data(&self, ctx: &JobContext) -> Result<Vec<u8>> {
        let posts = self.query_trending_posts(ctx).await?;

        // 序列化为 JSON
        serde_json::to_vec(&posts).context("Failed to serialize trending posts")
    }

    fn redis_key(&self) -> &str {
        &self.config.redis_key
    }

    fn interval_sec(&self) -> u64 {
        self.config.interval_sec
    }

    fn ttl_sec(&self) -> u64 {
        // TTL 设为刷新间隔的 1.5 倍,允许短暂延迟
        (self.config.interval_sec as f64 * 1.5) as u64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engagement_score() {
        // 基础场景: 100 views, 10 likes
        assert_eq!(
            TrendingGeneratorJob::compute_engagement_score(100, 10, 0, 0),
            30.0 // 100*0.1 + 10*2
        );

        // 高互动场景: 1000 views, 50 likes, 20 comments, 10 shares
        assert_eq!(
            TrendingGeneratorJob::compute_engagement_score(1000, 50, 20, 10),
            310.0 // 1000*0.1 + 50*2 + 20*3 + 10*5 = 100 + 100 + 60 + 50
        );

        // 边界情况: 0 互动
        assert_eq!(
            TrendingGeneratorJob::compute_engagement_score(0, 0, 0, 0),
            0.0
        );
    }

    #[test]
    fn test_default_config() {
        let config = TrendingConfig::default();
        assert_eq!(config.window_hours, 1);
        assert_eq!(config.top_k, 50);
        assert_eq!(config.interval_sec, 60);
        assert_eq!(config.redis_key, "nova:cache:trending:1h");
    }

    #[test]
    fn test_ttl_calculation() {
        let job = TrendingGeneratorJob::new(TrendingConfig {
            interval_sec: 60,
            ..Default::default()
        });
        assert_eq!(job.ttl_sec(), 90); // 60 * 1.5
    }
}

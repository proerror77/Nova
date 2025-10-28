//! 缓存预热器
//!
//! 为活跃用户预先计算和缓存 feed 数据,减少首次访问的延迟
//!
//! # 策略
//! - 目标用户: 最近 7 天登录的用户(按 last_login 排序)
//! - 预热数量: Top 1000 活跃用户
//! - 预热内容: 透過 content-service gRPC 預先拉取 feed
//! - TTL: 120 秒(2分钟)
//! - 刷新间隔: 60 秒

use super::{CacheRefreshJob, JobContext};
use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info};
use uuid::Uuid;

use crate::grpc::{ContentServiceClient, nova::content::GetFeedRequest};

/// 预热用户信息
#[derive(Debug, Clone, Serialize, Deserialize)]
struct WarmupUser {
    user_id: Uuid,
    last_login: String, // ISO8601 timestamp
}

/// 缓存预热器配置
#[derive(Debug, Clone)]
pub struct CacheWarmerConfig {
    /// 预热用户数量
    pub target_users: usize,
    /// 刷新间隔(秒)
    pub interval_sec: u64,
    /// Redis key 前缀
    pub redis_key_prefix: String,
    /// Feed TTL(秒)
    pub feed_ttl_sec: u64,
    /// 活跃度窗口(天)
    pub active_days: i64,
}

impl Default for CacheWarmerConfig {
    fn default() -> Self {
        Self {
            target_users: 1000,
            interval_sec: 60,
            redis_key_prefix: "nova:cache:feed".to_string(),
            feed_ttl_sec: 120,
            active_days: 7,
        }
    }
}

/// 缓存预热器 Job
pub struct CacheWarmerJob {
    config: CacheWarmerConfig,
    content_client: Arc<ContentServiceClient>,
}

impl CacheWarmerJob {
    pub fn new(config: CacheWarmerConfig, content_client: Arc<ContentServiceClient>) -> Self {
        Self {
            config,
            content_client,
        }
    }

    /// 从 PostgreSQL 获取最近活跃的用户
    ///
    /// 查询逻辑:
    /// - WHERE last_login > now() - 7 days
    /// - ORDER BY last_login DESC
    /// - LIMIT 1000
    async fn get_active_users(&self, ctx: &JobContext) -> Result<Vec<WarmupUser>> {
        let target_users = self.config.target_users;
        let active_days = self.config.active_days;

        // 注意: 这里需要 PostgreSQL 连接,但 JobContext 只有 Redis + ClickHouse
        // 实际实现中需要扩展 JobContext 或者从 ClickHouse 查询活跃用户
        //
        // 临时方案: 从 ClickHouse 的 post_events 表查询活跃用户
        let sql = format!(
            r#"
            SELECT DISTINCT user_id
            FROM post_events
            WHERE event_time >= now() - INTERVAL {active_days} DAY
              AND event_type IN ('post_view', 'feed_refresh', 'post_like')
            ORDER BY max(event_time) DESC
            LIMIT {target_users}
            "#
        );

        debug!(
            correlation_id = %ctx.correlation_id,
            target_users = target_users,
            active_days = active_days,
            "Querying active users for cache warmup"
        );

        #[derive(clickhouse::Row, serde::Deserialize)]
        struct ActiveUserRow {
            user_id: String,
        }

        let rows: Vec<ActiveUserRow> = ctx
            .ch_client
            .query(&sql)
            .fetch_all()
            .await
            .context("Failed to query active users from ClickHouse")?;

        let users: Vec<WarmupUser> = rows
            .into_iter()
            .filter_map(|row| {
                Uuid::parse_str(&row.user_id)
                    .ok()
                    .map(|user_id| WarmupUser {
                        user_id,
                        last_login: chrono::Utc::now().to_rfc3339(),
                    })
            })
            .collect();

        debug!(
            correlation_id = %ctx.correlation_id,
            count = users.len(),
            "Fetched active users for warmup"
        );

        Ok(users)
    }

    /// 为单个用户预热 feed 缓存
    ///
    /// 注意: 这里只是 mock 实现,实际需要调用 feed_ranking 服务
    async fn warmup_user_feed(&self, _ctx: &JobContext, user_id: Uuid) -> Result<usize> {
        let request = GetFeedRequest {
            user_id: user_id.to_string(),
            algo: "ch".to_string(),
            limit: 20,
            cursor: String::new(),
        };

        let response = self
            .content_client
            .get_feed(request)
            .await
            .map_err(|status| anyhow!("content-service get_feed failed: {}", status))?;

        debug!(
            "Warmup feed via content-service (user={} posts={})",
            user_id,
            response.post_ids.len()
        );

        Ok(response.post_ids.len())
    }

    /// 批量预热用户 feed
    async fn warmup_batch(
        &self,
        ctx: &JobContext,
        users: Vec<WarmupUser>,
    ) -> Result<(usize, usize, usize)> {
        use futures::stream::{self, StreamExt};

        const CONCURRENT_BATCH_SIZE: usize = 20;

        let total_users = users.len();
        let mut warmed_count = 0;
        let mut failed_count = 0;

        let results: Vec<Result<usize>> = stream::iter(users)
            .map(|user| async move { self.warmup_user_feed(ctx, user.user_id).await })
            .buffer_unordered(CONCURRENT_BATCH_SIZE)
            .collect()
            .await;

        for result in results {
            match result {
                Ok(_) => warmed_count += 1,
                Err(e) => {
                    debug!(error = %e, "Failed to warmup user feed");
                    failed_count += 1;
                }
            }
        }

        let skipped_count = total_users.saturating_sub(warmed_count + failed_count);

        Ok((warmed_count, skipped_count, failed_count))
    }
}

#[async_trait]
impl CacheRefreshJob for CacheWarmerJob {
    async fn fetch_data(&self, ctx: &JobContext) -> Result<Vec<u8>> {
        use tokio::time::Instant;

        let start = Instant::now();

        // 1. 获取活跃用户列表
        let active_users = self.get_active_users(ctx).await?;

        if active_users.is_empty() {
            debug!(
                correlation_id = %ctx.correlation_id,
                "No active users found, skipping cache warmup"
            );
            return Ok(vec![]);
        }

        // 2. 批量预热
        let (warmed, skipped, failed) = self.warmup_batch(ctx, active_users).await?;

        let elapsed = start.elapsed();
        info!(
            correlation_id = %ctx.correlation_id,
            warmed_count = warmed,
            skipped_count = skipped,
            failed_count = failed,
            elapsed_ms = elapsed.as_millis(),
            "Cache warmup completed"
        );

        // 返回统计数据
        let stats = serde_json::json!({
            "warmed": warmed,
            "skipped": skipped,
            "failed": failed,
            "elapsed_ms": elapsed.as_millis(),
        });

        serde_json::to_vec(&stats).context("Failed to serialize warmup stats")
    }

    fn redis_key(&self) -> &str {
        &self.config.redis_key_prefix
    }

    fn interval_sec(&self) -> u64 {
        self.config.interval_sec
    }

    fn ttl_sec(&self) -> u64 {
        self.config.feed_ttl_sec
    }

    /// 重写 refresh 方法,因为我们不需要写入单个 key
    async fn refresh(&self, ctx: &JobContext) -> Result<()> {
        use tokio::time::Instant;
        use tracing::error;

        let start = Instant::now();

        info!(
            correlation_id = %ctx.correlation_id,
            "Starting cache warmup"
        );

        // fetch_data 内部已经完成了查询和写入
        self.fetch_data(ctx).await.map_err(|e| {
            error!(
                correlation_id = %ctx.correlation_id,
                error = %e,
                "Failed to warmup cache"
            );
            e
        })?;

        let elapsed = start.elapsed();
        info!(
            correlation_id = %ctx.correlation_id,
            elapsed_ms = elapsed.as_millis(),
            "Cache warmup completed"
        );

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = CacheWarmerConfig::default();
        assert_eq!(config.target_users, 1000);
        assert_eq!(config.interval_sec, 60);
        assert_eq!(config.feed_ttl_sec, 120);
        assert_eq!(config.active_days, 7);
    }

    #[test]
    fn test_ttl_calculation() {
        let job = CacheWarmerJob::new(CacheWarmerConfig {
            feed_ttl_sec: 120,
            ..Default::default()
        });
        assert_eq!(job.ttl_sec(), 120);
    }
}

//! 后台任务模块
//!
//! 提供定时刷新 Redis 缓存的后台任务框架,包括:
//! - 热榜生成 (trending posts)
//! - 建议用户生成 (suggested users)
//!
//! # 设计原则
//! - **简洁**: 每个 job 只需实现 2 个方法 (fetch_data + redis_key)
//! - **幂等性**: 所有操作可安全重试
//! - **可观测性**: 内置指标导出和结构化日志
//! - **优雅关闭**: 支持 SIGTERM 处理

use anyhow::Result;
use async_trait::async_trait;
use redis::AsyncCommands;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tokio::time::{interval, Instant};
use tracing::{error, info};
use uuid::Uuid;

pub mod cache_warmer;
pub mod dlq_handler;
pub mod metrics_export;
pub mod suggested_users_generator;
// pub mod trending_generator; // REMOVED - moved to feed-service (port 8089) [DELETED]

/// Job 执行上下文,持有共享的数据库连接
#[derive(Clone)]
pub struct JobContext {
    pub redis_pool: redis::aio::ConnectionManager,
    pub ch_client: clickhouse::Client,
    pub correlation_id: String,
}

impl JobContext {
    pub fn new(redis_pool: redis::aio::ConnectionManager, ch_client: clickhouse::Client) -> Self {
        Self {
            redis_pool,
            ch_client,
            correlation_id: Uuid::new_v4().to_string(),
        }
    }

    /// 生成新的 correlation_id 用于日志追踪
    pub fn with_new_correlation_id(&self) -> Self {
        Self {
            redis_pool: self.redis_pool.clone(),
            ch_client: self.ch_client.clone(),
            correlation_id: Uuid::new_v4().to_string(),
        }
    }
}

/// 缓存刷新任务的统一接口
///
/// # 实现示例
/// ```ignore
/// struct TrendingJob;
///
/// #[async_trait]
/// impl CacheRefreshJob for TrendingJob {
///     async fn fetch_data(&self, ctx: &JobContext) -> Result<Vec<u8>> {
///         // 从 ClickHouse 查询热门帖子
///         let posts = query_trending_posts(&ctx.ch_client).await?;
///         Ok(serde_json::to_vec(&posts)?)
///     }
///
///     fn redis_key(&self) -> &str {
///         "nova:cache:trending:1h"
///     }
///
///     fn interval_sec(&self) -> u64 {
///         60  // 每 60 秒刷新
///     }
/// }
/// ```
#[async_trait]
pub trait CacheRefreshJob: Send + Sync {
    /// 从数据源获取数据并序列化
    async fn fetch_data(&self, ctx: &JobContext) -> Result<Vec<u8>>;

    /// Redis 缓存的 key
    fn redis_key(&self) -> &str;

    /// 刷新间隔(秒)
    fn interval_sec(&self) -> u64;

    /// Redis TTL(秒),默认为刷新间隔的 2 倍
    fn ttl_sec(&self) -> u64 {
        self.interval_sec() * 2
    }

    /// 完整的刷新流程: 查询数据 → 写入 Redis
    ///
    /// 默认实现提供:
    /// - 自动序列化和 TTL 设置
    /// - 错误处理和日志记录
    /// - 指标收集
    async fn refresh(&self, ctx: &JobContext) -> Result<()> {
        let start = Instant::now();
        let key = self.redis_key();

        info!(
            correlation_id = %ctx.correlation_id,
            redis_key = %key,
            "Starting cache refresh"
        );

        // 获取数据
        let data = self.fetch_data(ctx).await.map_err(|e| {
            error!(
                correlation_id = %ctx.correlation_id,
                error = %e,
                "Failed to fetch data"
            );
            e
        })?;

        // 写入 Redis (带 TTL)
        let ttl = self.ttl_sec();
        let mut conn = ctx.redis_pool.clone();

        conn.set_ex::<_, _, ()>(key, data, ttl).await.map_err(|e| {
            error!(
                correlation_id = %ctx.correlation_id,
                redis_key = %key,
                error = %e,
                "Failed to write to Redis"
            );
            anyhow::anyhow!("Redis write failed: {}", e)
        })?;

        let elapsed = start.elapsed();
        info!(
            correlation_id = %ctx.correlation_id,
            redis_key = %key,
            ttl_sec = ttl,
            elapsed_ms = elapsed.as_millis(),
            "Cache refresh completed"
        );

        Ok(())
    }

    /// 任务名称(用于日志)
    fn name(&self) -> &str {
        std::any::type_name::<Self>()
    }
}

/// 运行单个 job 的定时循环
///
/// # 特性
/// - 使用 tokio::time::interval 保证固定间隔
/// - 错误不中断循环(记录日志后继续)
/// - 指数退避重试(连续失败时增加延迟)
/// - 支持优雅关闭
pub async fn run_job_loop(
    job: Arc<dyn CacheRefreshJob>,
    ctx: JobContext,
    shutdown_signal: tokio::sync::broadcast::Receiver<()>,
) {
    let mut interval_timer = interval(Duration::from_secs(job.interval_sec()));
    let mut shutdown = shutdown_signal;
    let mut consecutive_failures = 0u32;

    info!(
        job_name = %job.name(),
        interval_sec = job.interval_sec(),
        "Starting job loop"
    );

    loop {
        tokio::select! {
            _ = interval_timer.tick() => {
                let ctx = ctx.with_new_correlation_id();

                match job.refresh(&ctx).await {
                    Ok(()) => {
                        if consecutive_failures > 0 {
                            info!(
                                job_name = %job.name(),
                                recovered_after = consecutive_failures,
                                "Job recovered after failures"
                            );
                            consecutive_failures = 0;
                        }
                    }
                    Err(e) => {
                        consecutive_failures += 1;
                        error!(
                            job_name = %job.name(),
                            error = %e,
                            consecutive_failures = consecutive_failures,
                            "Job execution failed, will retry on next interval"
                        );

                        // 指数退避: 连续失败时增加延迟(最多 5 次)
                        if consecutive_failures >= 3 {
                            let backoff_secs = 2u64.pow(consecutive_failures.min(5));
                            info!(
                                job_name = %job.name(),
                                backoff_secs = backoff_secs,
                                "Applying exponential backoff due to consecutive failures"
                            );
                            tokio::time::sleep(Duration::from_secs(backoff_secs)).await;
                        }
                    }
                }
            }
            _ = shutdown.recv() => {
                info!(
                    job_name = %job.name(),
                    "Received shutdown signal, stopping job loop"
                );
                break;
            }
        }
    }

    info!(job_name = %job.name(), "Job loop stopped");
}

/// 批量运行多个 job
///
/// # 并发控制
/// 使用 Semaphore 限制同时执行的 job 数量,避免资源耗尽
pub async fn run_jobs(
    jobs: Vec<(Arc<dyn CacheRefreshJob>, JobContext)>,
    max_concurrent: usize,
    shutdown_signal: tokio::sync::broadcast::Sender<()>,
) {
    let semaphore = Arc::new(Semaphore::new(max_concurrent));
    let mut handles = vec![];

    for (job, ctx) in jobs {
        let permit = semaphore.clone().acquire_owned().await.unwrap();
        let shutdown_rx = shutdown_signal.subscribe();

        let handle = tokio::spawn(async move {
            run_job_loop(job, ctx, shutdown_rx).await;
            drop(permit); // 释放信号量
        });

        handles.push(handle);
    }

    // 等待所有 job 完成
    for handle in handles {
        if let Err(e) = handle.await {
            error!(error = %e, "Job task panicked");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct MockJob {
        pub redis_key: String,
        pub interval: u64,
    }

    #[async_trait]
    impl CacheRefreshJob for MockJob {
        async fn fetch_data(&self, _ctx: &JobContext) -> Result<Vec<u8>> {
            Ok(b"test_data".to_vec())
        }

        fn redis_key(&self) -> &str {
            &self.redis_key
        }

        fn interval_sec(&self) -> u64 {
            self.interval
        }
    }

    #[test]
    fn test_ttl_default() {
        let job = MockJob {
            redis_key: "test:key".to_string(),
            interval: 60,
        };
        assert_eq!(job.ttl_sec(), 120); // 默认为 interval * 2
    }
}

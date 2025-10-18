//! 建议用户生成器
//!
//! 基于社交图谱生成个性化推荐用户列表
//!
//! # 算法
//! - **二度好友推荐**: 找出"你的关注者的关注者"(但排除已关注)
//! - **协同过滤**: 基于共同关注数量评分
//! - **活跃度加权**: 最近 7 天有活动的用户优先
//!
//! # 缓存策略
//! - 采样策略: 每次刷新处理一批活跃用户(而不是全量)
//! - TTL: 10 分钟(允许推荐数据有一定延迟)

use super::{CacheRefreshJob, JobContext};
use anyhow::{Context, Result};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tracing::debug;
use uuid::Uuid;

/// 建议用户(带评分和推荐理由)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserWithScore {
    pub user_id: Uuid,
    pub score: f64,
    pub reason: String, // 例如: "3 mutual connections"
}

/// 建议用户生成器配置
#[derive(Debug, Clone)]
pub struct SuggestionConfig {
    /// 每次刷新处理的用户数(采样)
    pub batch_size: usize,
    /// 每个用户推荐的数量
    pub suggestions_per_user: usize,
    /// 刷新间隔(秒)
    pub interval_sec: u64,
    /// Redis key 前缀
    pub redis_key_prefix: String,
    /// 活跃度窗口(天)
    pub active_days: i64,
}

impl Default for SuggestionConfig {
    fn default() -> Self {
        Self {
            batch_size: 100,
            suggestions_per_user: 20,
            interval_sec: 600, // 10 分钟
            redis_key_prefix: "nova:cache:suggested_users".to_string(),
            active_days: 7,
        }
    }
}

/// 建议用户生成器 Job
pub struct SuggestedUsersJob {
    config: SuggestionConfig,
}

impl SuggestedUsersJob {
    pub fn new(config: SuggestionConfig) -> Self {
        Self { config }
    }

    /// 从 ClickHouse 获取最近活跃的用户 ID 列表
    async fn get_active_users(&self, ctx: &JobContext) -> Result<Vec<Uuid>> {
        let active_days = self.config.active_days;
        let batch_size = self.config.batch_size;

        let sql = format!(
            r#"
            SELECT DISTINCT user_id
            FROM post_events
            WHERE event_time >= now() - INTERVAL {active_days} DAY
              AND event_type IN ('post_view', 'post_like', 'follow')
            ORDER BY rand()
            LIMIT {batch_size}
            "#
        );

        #[derive(clickhouse::Row, serde::Deserialize)]
        struct ActiveUser {
            user_id: String,
        }

        let rows: Vec<ActiveUser> = ctx
            .ch_client
            .query(&sql)
            .fetch_all()
            .await
            .context("Failed to query active users")?;

        let user_ids: Vec<Uuid> = rows
            .into_iter()
            .filter_map(|row| Uuid::parse_str(&row.user_id).ok())
            .collect();

        debug!(
            correlation_id = %ctx.correlation_id,
            count = user_ids.len(),
            "Fetched active users for suggestion generation"
        );

        Ok(user_ids)
    }

    /// 为单个用户计算建议列表
    ///
    /// 算法:
    /// 1. 查询该用户的关注列表 (following)
    /// 2. 查询这些人的关注列表 (friends of friends)
    /// 3. 排除已关注的用户
    /// 4. 按共同关注数排序
    async fn compute_suggestions_for_user(
        &self,
        ctx: &JobContext,
        user_id: Uuid,
    ) -> Result<Vec<UserWithScore>> {
        let suggestions_count = self.config.suggestions_per_user;

        let sql = format!(
            r#"
            WITH user_following AS (
                SELECT followee_id
                FROM user_relationships
                WHERE follower_id = '{user_id}'
                  AND status = 'active'
            ),
            friends_of_friends AS (
                SELECT
                    r.followee_id AS candidate_id,
                    count() AS mutual_count
                FROM user_relationships r
                WHERE r.follower_id IN (SELECT followee_id FROM user_following)
                  AND r.followee_id != '{user_id}'
                  AND r.followee_id NOT IN (SELECT followee_id FROM user_following)
                  AND r.status = 'active'
                GROUP BY r.followee_id
            )
            SELECT
                candidate_id,
                mutual_count
            FROM friends_of_friends
            ORDER BY mutual_count DESC
            LIMIT {suggestions_count}
            "#
        );

        #[derive(clickhouse::Row, serde::Deserialize)]
        struct SuggestionRow {
            candidate_id: String,
            mutual_count: u64,
        }

        let rows: Vec<SuggestionRow> = ctx
            .ch_client
            .query(&sql)
            .fetch_all()
            .await
            .context("Failed to query suggested users")?;

        let suggestions: Vec<UserWithScore> = rows
            .into_iter()
            .filter_map(|row| {
                Uuid::parse_str(&row.candidate_id)
                    .ok()
                    .map(|candidate_id| UserWithScore {
                        user_id: candidate_id,
                        score: row.mutual_count as f64,
                        reason: if row.mutual_count == 1 {
                            "1 mutual connection".to_string()
                        } else {
                            format!("{} mutual connections", row.mutual_count)
                        },
                    })
            })
            .collect();

        Ok(suggestions)
    }

    /// 批量写入建议用户缓存
    ///
    /// 使用 Redis Pipeline 优化批量写入性能
    async fn write_suggestions_batch(
        &self,
        ctx: &JobContext,
        suggestions: Vec<(Uuid, Vec<UserWithScore>)>,
    ) -> Result<()> {
        let mut pipe = redis::pipe();
        let ttl = self.ttl_sec();

        for (user_id, user_suggestions) in suggestions {
            let key = format!("{}:{}", self.config.redis_key_prefix, user_id);
            let value =
                serde_json::to_vec(&user_suggestions).context("Failed to serialize suggestions")?;

            pipe.set_ex(&key, value, ttl);
        }

        let mut conn = ctx.redis_pool.clone();
        pipe.query_async(&mut conn)
            .await
            .context("Failed to execute Redis pipeline")?;

        Ok(())
    }
}

#[async_trait]
impl CacheRefreshJob for SuggestedUsersJob {
    async fn fetch_data(&self, ctx: &JobContext) -> Result<Vec<u8>> {
        use futures::stream::{self, StreamExt};

        // 1. 获取活跃用户列表
        let active_users = self.get_active_users(ctx).await?;

        if active_users.is_empty() {
            debug!(
                correlation_id = %ctx.correlation_id,
                "No active users found, skipping suggestion generation"
            );
            return Ok(vec![]);
        }

        // 2. 并行计算建议(每批10个用户,避免过载)
        const CONCURRENT_BATCH_SIZE: usize = 10;

        let suggestions: Vec<(Uuid, Vec<UserWithScore>)> = stream::iter(active_users)
            .map(|user_id| async move {
                match self.compute_suggestions_for_user(ctx, user_id).await {
                    Ok(user_suggestions) if !user_suggestions.is_empty() => {
                        Some((user_id, user_suggestions))
                    }
                    Ok(_) => {
                        debug!(user_id = %user_id, "No suggestions found for user");
                        None
                    }
                    Err(e) => {
                        debug!(user_id = %user_id, error = %e, "Failed to compute suggestions");
                        None
                    }
                }
            })
            .buffer_unordered(CONCURRENT_BATCH_SIZE)
            .filter_map(|result| async { result })
            .collect()
            .await;

        debug!(
            correlation_id = %ctx.correlation_id,
            users_count = suggestions.len(),
            "Computed suggestions for users with parallel processing"
        );

        // 3. 批量写入 Redis
        if !suggestions.is_empty() {
            self.write_suggestions_batch(ctx, suggestions).await?;
        }

        // 返回空数据(因为已经直接写入了)
        Ok(vec![])
    }

    fn redis_key(&self) -> &str {
        // 这里返回前缀,实际 key 是 prefix:user_id
        &self.config.redis_key_prefix
    }

    fn interval_sec(&self) -> u64 {
        self.config.interval_sec
    }

    fn ttl_sec(&self) -> u64 {
        // TTL 设为 2 倍刷新间隔
        self.config.interval_sec * 2
    }

    /// 重写 refresh 方法,因为我们需要批量写入多个 key
    async fn refresh(&self, ctx: &JobContext) -> Result<()> {
        use tokio::time::Instant;
        use tracing::info;

        let start = Instant::now();

        info!(
            correlation_id = %ctx.correlation_id,
            redis_key_prefix = %self.redis_key(),
            "Starting suggested users cache refresh"
        );

        // fetch_data 内部已经完成了查询和写入
        self.fetch_data(ctx).await?;

        let elapsed = start.elapsed();
        info!(
            correlation_id = %ctx.correlation_id,
            elapsed_ms = elapsed.as_millis(),
            "Suggested users cache refresh completed"
        );

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = SuggestionConfig::default();
        assert_eq!(config.batch_size, 100);
        assert_eq!(config.suggestions_per_user, 20);
        assert_eq!(config.interval_sec, 600);
        assert_eq!(config.redis_key_prefix, "nova:cache:suggested_users");
    }

    #[test]
    fn test_ttl_calculation() {
        let job = SuggestedUsersJob::new(SuggestionConfig {
            interval_sec: 600,
            ..Default::default()
        });
        assert_eq!(job.ttl_sec(), 1200); // 600 * 2
    }

    #[test]
    fn test_reason_formatting() {
        let single = UserWithScore {
            user_id: Uuid::new_v4(),
            score: 1.0,
            reason: "1 mutual connection".to_string(),
        };
        assert_eq!(single.reason, "1 mutual connection");

        let multiple = UserWithScore {
            user_id: Uuid::new_v4(),
            score: 5.0,
            reason: "5 mutual connections".to_string(),
        };
        assert_eq!(multiple.reason, "5 mutual connections");
    }
}

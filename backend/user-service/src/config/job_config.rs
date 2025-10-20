//! Job 配置模块
//!
//! 从环境变量读取 job 相关配置

use serde::Deserialize;
use std::env;

/// Job Worker 配置
#[derive(Debug, Clone, Deserialize)]
pub struct JobWorkerConfig {
    /// Redis 连接 URL
    #[serde(default = "default_redis_url")]
    pub redis_url: String,

    /// ClickHouse 连接 URL
    #[serde(default = "default_clickhouse_url")]
    pub clickhouse_url: String,

    /// 热榜刷新间隔(秒)
    #[serde(default = "default_trending_interval")]
    pub trending_interval_sec: u64,

    /// 热榜时间窗口(小时)
    #[serde(default = "default_trending_window")]
    pub trending_window_hours: i64,

    /// 热榜 Top-K 数量
    #[serde(default = "default_trending_topk")]
    pub trending_topk: usize,

    /// 建议用户刷新间隔(秒)
    #[serde(default = "default_suggestion_interval")]
    pub suggestion_interval_sec: u64,

    /// 建议用户批量大小
    #[serde(default = "default_suggestion_batch_size")]
    pub suggestion_batch_size: usize,

    /// 每个用户的建议数量
    #[serde(default = "default_suggestions_per_user")]
    pub suggestions_per_user: usize,

    /// ClickHouse 查询超时(毫秒)
    #[serde(default = "default_ch_timeout")]
    pub ch_timeout_ms: u64,

    /// Redis 连接池大小
    #[serde(default = "default_redis_pool_size")]
    pub redis_pool_size: u32,

    /// 最大并发 job 数量
    #[serde(default = "default_max_concurrent_jobs")]
    pub max_concurrent_jobs: usize,
}

// 默认值函数
fn default_redis_url() -> String {
    env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string())
}

fn default_clickhouse_url() -> String {
    env::var("CLICKHOUSE_URL").unwrap_or_else(|_| "http://localhost:8123".to_string())
}

fn default_trending_interval() -> u64 {
    env::var("JOB_TRENDING_INTERVAL_SEC")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(60)
}

fn default_trending_window() -> i64 {
    env::var("JOB_TRENDING_WINDOW_HOURS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(1)
}

fn default_trending_topk() -> usize {
    env::var("JOB_TRENDING_TOPK")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(50)
}

fn default_suggestion_interval() -> u64 {
    env::var("JOB_SUGGESTION_INTERVAL_SEC")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(600)
}

fn default_suggestion_batch_size() -> usize {
    env::var("JOB_SUGGESTION_BATCH_SIZE")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100)
}

fn default_suggestions_per_user() -> usize {
    env::var("JOB_SUGGESTIONS_PER_USER")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(20)
}

fn default_ch_timeout() -> u64 {
    env::var("JOB_CH_TIMEOUT_MS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(30000) // 30 秒
}

fn default_redis_pool_size() -> u32 {
    env::var("JOB_REDIS_POOL_SIZE")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(10)
}

fn default_max_concurrent_jobs() -> usize {
    env::var("JOB_MAX_CONCURRENT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(4)
}

impl Default for JobWorkerConfig {
    fn default() -> Self {
        Self {
            redis_url: default_redis_url(),
            clickhouse_url: default_clickhouse_url(),
            trending_interval_sec: default_trending_interval(),
            trending_window_hours: default_trending_window(),
            trending_topk: default_trending_topk(),
            suggestion_interval_sec: default_suggestion_interval(),
            suggestion_batch_size: default_suggestion_batch_size(),
            suggestions_per_user: default_suggestions_per_user(),
            ch_timeout_ms: default_ch_timeout(),
            redis_pool_size: default_redis_pool_size(),
            max_concurrent_jobs: default_max_concurrent_jobs(),
        }
    }
}

impl JobWorkerConfig {
    /// 从环境变量加载配置
    pub fn from_env() -> Result<Self, envy::Error> {
        // 使用 envy 自动从环境变量解析,如果没有则使用默认值
        Ok(Self::default())
    }

    /// 验证配置的合法性
    pub fn validate(&self) -> Result<(), String> {
        if self.trending_interval_sec == 0 {
            return Err("trending_interval_sec must be greater than 0".to_string());
        }

        if self.suggestion_interval_sec == 0 {
            return Err("suggestion_interval_sec must be greater than 0".to_string());
        }

        if self.trending_topk == 0 {
            return Err("trending_topk must be greater than 0".to_string());
        }

        if self.suggestion_batch_size == 0 {
            return Err("suggestion_batch_size must be greater than 0".to_string());
        }

        if self.ch_timeout_ms == 0 {
            return Err("ch_timeout_ms must be greater than 0".to_string());
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = JobWorkerConfig::default();
        assert_eq!(config.trending_interval_sec, 60);
        assert_eq!(config.suggestion_interval_sec, 600);
        assert_eq!(config.trending_topk, 50);
        assert_eq!(config.max_concurrent_jobs, 4);
    }

    #[test]
    fn test_validation() {
        let mut config = JobWorkerConfig::default();
        assert!(config.validate().is_ok());

        config.trending_interval_sec = 0;
        assert!(config.validate().is_err());
    }
}

//! Job 集成测试
//!
//! 测试 job 的核心逻辑,使用 mock 的 ClickHouse 和 Redis

use anyhow::Result;
use redis::AsyncCommands;
use serde_json::Value;
use user_service::jobs::{
    trending_generator::{PostWithScore, TrendingConfig, TrendingGeneratorJob},
    CacheRefreshJob, JobContext,
};

/// Mock 测试辅助函数: 创建 Redis 连接
async fn create_test_redis() -> Result<redis::aio::ConnectionManager> {
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let client = redis::Client::open(redis_url)?;
    Ok(redis::aio::ConnectionManager::new(client).await?)
}

/// 测试: 热榜 job 的序列化逻辑
#[tokio::test]
async fn test_trending_job_serialization() {
    // 创建 mock 数据
    let posts = vec![
        PostWithScore {
            post_id: uuid::Uuid::new_v4(),
            score: 100.5,
            cached_at: 1234567890,
        },
        PostWithScore {
            post_id: uuid::Uuid::new_v4(),
            score: 50.2,
            cached_at: 1234567890,
        },
    ];

    // 测试序列化
    let json = serde_json::to_vec(&posts).unwrap();
    assert!(!json.is_empty());

    // 测试反序列化
    let deserialized: Vec<PostWithScore> = serde_json::from_slice(&json).unwrap();
    assert_eq!(deserialized.len(), 2);
    assert_eq!(deserialized[0].score, 100.5);
}

/// 测试: 验证 Redis 写入和读取
#[tokio::test]
#[ignore] // 需要 Redis 实例,CI 环境跳过
async fn test_redis_cache_write_read() -> Result<()> {
    let mut redis = create_test_redis().await?;

    // 写入测试数据
    let test_key = "nova:cache:test:trending";
    let test_data = vec![PostWithScore {
        post_id: uuid::Uuid::new_v4(),
        score: 123.45,
        cached_at: chrono::Utc::now().timestamp(),
    }];

    let json = serde_json::to_vec(&test_data)?;
    redis.set_ex(test_key, &json, 60).await?;

    // 读取并验证
    let cached: Vec<u8> = redis.get(test_key).await?;
    let restored: Vec<PostWithScore> = serde_json::from_slice(&cached)?;

    assert_eq!(restored.len(), 1);
    assert_eq!(restored[0].score, 123.45);

    // 清理
    let _: () = redis.del(test_key).await?;

    Ok(())
}

/// 测试: TrendingConfig 默认值
#[test]
fn test_trending_config_defaults() {
    let config = TrendingConfig::default();
    assert_eq!(config.window_hours, 1);
    assert_eq!(config.top_k, 50);
    assert_eq!(config.interval_sec, 60);
    assert_eq!(config.redis_key, "nova:cache:trending:1h");
}

/// 测试: Job TTL 计算
#[test]
fn test_job_ttl() {
    let job = TrendingGeneratorJob::new(TrendingConfig {
        interval_sec: 60,
        ..Default::default()
    });

    // TTL 应该是 interval * 1.5
    assert_eq!(job.ttl_sec(), 90);
}

/// 测试: engagement score 计算
#[test]
fn test_engagement_score_calculation() {
    use user_service::jobs::trending_generator::TrendingGeneratorJob;

    // 场景 1: 高浏览量,低互动
    let score1 = TrendingGeneratorJob::compute_engagement_score(1000, 10, 0, 0);
    assert_eq!(score1, 120.0); // 1000*0.1 + 10*2

    // 场景 2: 中浏览量,高互动
    let score2 = TrendingGeneratorJob::compute_engagement_score(100, 50, 20, 10);
    assert_eq!(score2, 220.0); // 100*0.1 + 50*2 + 20*3 + 10*5

    // 场景 3: 零互动
    let score3 = TrendingGeneratorJob::compute_engagement_score(0, 0, 0, 0);
    assert_eq!(score3, 0.0);
}

/// 测试: Redis key 格式正确性
#[test]
fn test_redis_key_format() {
    let job = TrendingGeneratorJob::new(TrendingConfig::default());
    assert!(job.redis_key().starts_with("nova:cache:"));
    assert!(job.redis_key().contains("trending"));
}

/// 测试: 排序逻辑 (模拟 ClickHouse 返回数据)
#[test]
fn test_post_sorting() {
    let mut posts = vec![
        PostWithScore {
            post_id: uuid::Uuid::new_v4(),
            score: 50.0,
            cached_at: 1000,
        },
        PostWithScore {
            post_id: uuid::Uuid::new_v4(),
            score: 150.0,
            cached_at: 1000,
        },
        PostWithScore {
            post_id: uuid::Uuid::new_v4(),
            score: 100.0,
            cached_at: 1000,
        },
    ];

    // 按 score 降序排序
    posts.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());

    assert_eq!(posts[0].score, 150.0);
    assert_eq!(posts[1].score, 100.0);
    assert_eq!(posts[2].score, 50.0);
}

/// 测试: 空结果处理
#[test]
fn test_empty_results_serialization() {
    let empty: Vec<PostWithScore> = vec![];
    let json = serde_json::to_vec(&empty).unwrap();

    // 空数组应该序列化为 "[]"
    let value: Value = serde_json::from_slice(&json).unwrap();
    assert!(value.is_array());
    assert_eq!(value.as_array().unwrap().len(), 0);
}

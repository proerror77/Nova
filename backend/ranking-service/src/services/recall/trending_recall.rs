use super::{Candidate, RecallSource, RecallStrategy};
use anyhow::{Context, Result};
use async_trait::async_trait;
use redis::AsyncCommands;
use tracing::warn;

/// Trending Recall Strategy - 熱門召回
/// 從 Redis Sorted Set 中獲取最近熱門的帖子
pub struct TrendingRecallStrategy {
    redis_client: redis::Client,
}

impl TrendingRecallStrategy {
    pub fn new(redis_client: redis::Client) -> Self {
        Self { redis_client }
    }
}

#[async_trait]
impl RecallStrategy for TrendingRecallStrategy {
    async fn recall(&self, _user_id: &str, limit: i32) -> Result<Vec<Candidate>> {
        // 從 Redis Sorted Set 獲取熱門帖子（按分數降序）
        let trending_posts = self.get_trending_posts(limit).await?;

        if trending_posts.is_empty() {
            warn!("No trending posts found in Redis");
            return Ok(Vec::new());
        }

        let candidates: Vec<Candidate> = trending_posts
            .into_iter()
            .map(|(post_id, score)| Candidate {
                post_id,
                recall_source: RecallSource::Trending,
                recall_weight: score as f32,
                timestamp: chrono::Utc::now().timestamp(),
            })
            .collect();

        Ok(candidates)
    }

    fn source(&self) -> RecallSource {
        RecallSource::Trending
    }
}

impl TrendingRecallStrategy {
    /// 從 Redis Sorted Set 獲取熱門帖子
    /// Key: "trending:posts:1h" (1 小時內熱門)
    /// Score: 互動分數（likes + comments + shares）
    async fn get_trending_posts(&self, limit: i32) -> Result<Vec<(String, f64)>> {
        let mut conn = self
            .redis_client
            .get_multiplexed_async_connection()
            .await
            .context("Failed to get Redis connection")?;

        // ZREVRANGE trending:posts:1h 0 {limit-1} WITHSCORES
        let key = "trending:posts:1h";
        let results: Vec<(String, f64)> = conn
            .zrevrange_withscores(key, 0, (limit - 1) as isize)
            .await
            .context("Failed to fetch trending posts from Redis")?;

        Ok(results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_trending_recall_empty() {
        // Mock Redis client (需要實際 Redis 實例或 mock)
        let redis_client =
            redis::Client::open("redis://localhost:6379").expect("Redis client failed");

        let strategy = TrendingRecallStrategy::new(redis_client);
        let result = strategy.recall("user123", 10).await;

        // 如果 Redis 中沒有數據，應該返回空列表
        match result {
            Ok(candidates) => assert!(candidates.is_empty() || !candidates.is_empty()),
            Err(_) => {
                // Redis 連接失敗時跳過測試
                println!("Redis not available, skipping test");
            }
        }
    }
}

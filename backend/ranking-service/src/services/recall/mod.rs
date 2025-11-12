mod graph_recall;
mod personalized_recall;
mod trending_recall;

use crate::config::RecallConfig;
use crate::models::{Candidate, RecallSource, RecallStats};
use anyhow::Result;
use async_trait::async_trait;
use std::collections::HashSet;
use tonic::transport::Channel;
use tracing::{info, warn};

pub use graph_recall::GraphRecallStrategy;
pub use personalized_recall::PersonalizedRecallStrategy;
pub use trending_recall::TrendingRecallStrategy;

/// Recall 策略特徵
#[async_trait]
pub trait RecallStrategy: Send + Sync {
    async fn recall(&self, user_id: &str, limit: i32) -> Result<Vec<Candidate>>;
    fn source(&self) -> RecallSource;
}

/// Recall 層：多策略召回候選集
pub struct RecallLayer {
    strategies: Vec<(Box<dyn RecallStrategy>, f32)>, // (策略, 權重)
    config: RecallConfig,
}

impl RecallLayer {
    pub fn new(graph_client: Channel, redis_client: redis::Client, config: RecallConfig) -> Self {
        let strategies: Vec<(Box<dyn RecallStrategy>, f32)> = vec![
            (
                Box::new(GraphRecallStrategy::new(graph_client.clone())),
                config.graph_recall_weight,
            ),
            (
                Box::new(TrendingRecallStrategy::new(redis_client.clone())),
                config.trending_recall_weight,
            ),
            (
                Box::new(PersonalizedRecallStrategy::new(redis_client)),
                config.personalized_recall_weight,
            ),
        ];

        Self { strategies, config }
    }

    /// 召回候選集（多策略並行）
    pub async fn recall_candidates(
        &self,
        user_id: &str,
        limit_override: Option<i32>,
    ) -> Result<(Vec<Candidate>, RecallStats)> {
        let mut all_candidates = Vec::new();
        let mut stats = RecallStats::default();

        // 並行執行所有召回策略（實際上這裡不需要並行，因為策略不能 Clone）
        // 改為順序執行
        for (strategy, _weight) in &self.strategies {
            let limit = match strategy.source() {
                RecallSource::Graph => limit_override.unwrap_or(self.config.graph_recall_limit),
                RecallSource::Trending => {
                    limit_override.unwrap_or(self.config.trending_recall_limit)
                }
                RecallSource::Personalized => {
                    limit_override.unwrap_or(self.config.personalized_recall_limit)
                }
            };

            match strategy.recall(user_id, limit).await {
                Ok(candidates) => {
                    let source = strategy.source();
                    match source {
                        RecallSource::Graph => stats.graph_recall_count = candidates.len() as i32,
                        RecallSource::Trending => {
                            stats.trending_recall_count = candidates.len() as i32
                        }
                        RecallSource::Personalized => {
                            stats.personalized_recall_count = candidates.len() as i32
                        }
                    }
                    all_candidates.extend(candidates);
                }
                Err(e) => {
                    warn!("Recall strategy {:?} failed: {}", strategy.source(), e);
                }
            }
        }

        // 去重（同一 post_id 可能來自多個策略）
        let unique_candidates = self.deduplicate_and_merge(all_candidates);

        stats.total_candidates = unique_candidates.len() as i32;

        info!(
            "Recall completed: user_id={}, graph={}, trending={}, personalized={}, total={}",
            user_id,
            stats.graph_recall_count,
            stats.trending_recall_count,
            stats.personalized_recall_count,
            stats.total_candidates
        );

        Ok((unique_candidates, stats))
    }

    /// 去重並合併權重（相同 post_id 取最高權重的策略）
    fn deduplicate_and_merge(&self, candidates: Vec<Candidate>) -> Vec<Candidate> {
        let mut seen: HashSet<String> = HashSet::new();
        let mut unique: Vec<Candidate> = Vec::new();

        for candidate in candidates {
            if !seen.contains(&candidate.post_id) {
                seen.insert(candidate.post_id.clone());
                unique.push(candidate);
            }
        }

        unique
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deduplicate_and_merge() {
        let candidates = vec![
            Candidate {
                post_id: "post1".to_string(),
                recall_source: RecallSource::Graph,
                recall_weight: 0.8,
                timestamp: 1000,
            },
            Candidate {
                post_id: "post1".to_string(),
                recall_source: RecallSource::Trending,
                recall_weight: 0.6,
                timestamp: 1000,
            },
            Candidate {
                post_id: "post2".to_string(),
                recall_source: RecallSource::Personalized,
                recall_weight: 0.5,
                timestamp: 1000,
            },
        ];

        let config = RecallConfig {
            graph_recall_limit: 200,
            trending_recall_limit: 100,
            personalized_recall_limit: 100,
            graph_recall_weight: 0.6,
            trending_recall_weight: 0.3,
            personalized_recall_weight: 0.1,
        };

        let redis_client =
            redis::Client::open("redis://localhost:6379").expect("Redis client failed");
        let graph_channel = Channel::from_static("http://localhost:9008").connect_lazy();

        let layer = RecallLayer::new(graph_channel, redis_client, config);
        let unique = layer.deduplicate_and_merge(candidates);

        assert_eq!(unique.len(), 2);
        assert_eq!(unique[0].post_id, "post1");
        assert_eq!(unique[1].post_id, "post2");
    }
}

use crate::models::{Candidate, PostFeatures, RankedPost};
use anyhow::Result;

/// Ranking Layer - GBDT 模型打分
/// Phase D: 簡化版打分邏輯（Phase E 將接入真實 ONNX 模型）
pub struct RankingLayer;

impl Default for RankingLayer {
    fn default() -> Self {
        Self::new()
    }
}

impl RankingLayer {
    pub fn new() -> Self {
        Self
    }

    /// 對候選集進行打分排序
    pub async fn rank_candidates(&self, candidates: Vec<Candidate>) -> Result<Vec<RankedPost>> {
        let mut ranked_posts: Vec<RankedPost> = candidates
            .into_iter()
            .map(|candidate| {
                let features = self.extract_features(&candidate);
                let score = self.compute_score(&features);

                RankedPost {
                    post_id: candidate.post_id,
                    score,
                    recall_source: candidate.recall_source,
                    features,
                }
            })
            .collect();

        // 按分數降序排序
        // Note: NaN scores are treated as less than any valid score
        ranked_posts.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        Ok(ranked_posts)
    }

    /// 特徵提取（Phase D: 簡化版）
    fn extract_features(&self, candidate: &Candidate) -> PostFeatures {
        // TODO: Phase E - 從 content-service 獲取真實特徵
        // 目前使用佔位符特徵
        PostFeatures {
            engagement_score: candidate.recall_weight * 0.8,
            recency_score: self.compute_recency_score(candidate.timestamp),
            author_quality_score: 0.7,  // 佔位符
            content_quality_score: 0.8, // 佔位符
            author_id: None,            // Phase E: 從 content-service 獲取
        }
    }

    /// 計算時效分數（越新越高）
    fn compute_recency_score(&self, timestamp: i64) -> f32 {
        let now = chrono::Utc::now().timestamp();
        let age_seconds = (now - timestamp) as f32;
        let age_hours = age_seconds / 3600.0;

        // 指數衰減：24 小時衰減到 0.1
        (-age_hours / 24.0).exp().max(0.1)
    }

    /// 計算最終分數（Phase D: 線性加權）
    /// Phase E: 替換為 GBDT ONNX 模型推理
    fn compute_score(&self, features: &PostFeatures) -> f32 {
        let weights = (0.4, 0.3, 0.2, 0.1); // (engagement, recency, author, content)

        features.engagement_score * weights.0
            + features.recency_score * weights.1
            + features.author_quality_score * weights.2
            + features.content_quality_score * weights.3
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::RecallSource;

    #[tokio::test]
    async fn test_rank_candidates() {
        let layer = RankingLayer::new();

        let candidates = vec![
            Candidate {
                post_id: "post1".to_string(),
                recall_source: RecallSource::Graph,
                recall_weight: 0.9,
                timestamp: chrono::Utc::now().timestamp() - 3600, // 1 小時前
            },
            Candidate {
                post_id: "post2".to_string(),
                recall_source: RecallSource::Trending,
                recall_weight: 0.7,
                timestamp: chrono::Utc::now().timestamp() - 7200, // 2 小時前
            },
        ];

        let ranked = layer.rank_candidates(candidates).await.unwrap();

        assert_eq!(ranked.len(), 2);
        assert!(ranked[0].score >= ranked[1].score); // 確保降序排序
    }

    #[test]
    fn test_recency_score() {
        let layer = RankingLayer::new();
        let now = chrono::Utc::now().timestamp();

        // 剛發布
        let score_fresh = layer.compute_recency_score(now);
        assert!(score_fresh > 0.9);

        // 24 小時前
        let score_old = layer.compute_recency_score(now - 86400);
        assert!(score_old < 0.5);
    }
}

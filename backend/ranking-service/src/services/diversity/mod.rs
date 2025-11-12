use crate::models::RankedPost;
use std::collections::HashSet;
use uuid::Uuid;

/// Diversity Layer - 多樣性重排
/// 使用 MMR (Maximal Marginal Relevance) 算法
pub struct DiversityLayer {
    lambda: f32, // 平衡 relevance 和 diversity 的參數（0~1）
    max_consecutive_from_author: usize, // 同一作者最多連續出現次數
}

impl DiversityLayer {
    pub fn new(lambda: f32) -> Self {
        Self {
            lambda,
            max_consecutive_from_author: 2,
        }
    }

    /// Create with custom consecutive author limit
    pub fn with_author_limit(lambda: f32, max_consecutive: usize) -> Self {
        Self {
            lambda,
            max_consecutive_from_author: max_consecutive,
        }
    }

    /// 重排候選集以提高多樣性
    /// lambda = 1.0: 只看相關性
    /// lambda = 0.0: 只看多樣性
    /// lambda = 0.7: 平衡（推薦值）
    pub fn rerank(&self, posts: Vec<RankedPost>, top_k: usize) -> Vec<RankedPost> {
        if posts.is_empty() {
            return Vec::new();
        }

        let mut selected: Vec<RankedPost> = Vec::new();
        let mut remaining = posts;
        let mut seen_sources: HashSet<String> = HashSet::new();

        // MMR 貪心選擇
        while selected.len() < top_k && !remaining.is_empty() {
            let mut best_idx = 0;
            let mut best_mmr_score = f32::MIN;

            // Get recent authors for diversity check
            let recent_authors = self.get_recent_authors(&selected);

            for (i, post) in remaining.iter().enumerate() {
                // Hard constraint: Skip if violates author diversity
                if self.violates_author_diversity(&recent_authors, post) {
                    continue;
                }

                let relevance = post.score;
                let diversity = self.compute_diversity(post, &selected, &seen_sources);
                let mmr_score = self.lambda * relevance + (1.0 - self.lambda) * diversity;

                if mmr_score > best_mmr_score {
                    best_mmr_score = mmr_score;
                    best_idx = i;
                }
            }

            let selected_post = remaining.remove(best_idx);
            seen_sources.insert(selected_post.recall_source.as_str().to_string());
            selected.push(selected_post);
        }

        selected
    }

    /// Get recent N author IDs from selected posts
    fn get_recent_authors(&self, selected: &[RankedPost]) -> Vec<Option<Uuid>> {
        selected
            .iter()
            .rev()
            .take(self.max_consecutive_from_author)
            .map(|p| p.features.author_id)
            .collect()
    }

    /// Check if adding this post violates author diversity constraint
    fn violates_author_diversity(&self, recent_authors: &[Option<Uuid>], post: &RankedPost) -> bool {
        if recent_authors.len() < self.max_consecutive_from_author {
            return false;
        }

        // Violation: All recent posts are from the same author
        if let Some(post_author) = post.features.author_id {
            recent_authors.iter().all(|&a| a == Some(post_author))
        } else {
            false
        }
    }

    /// 計算多樣性分數（與已選擇的帖子相比）
    fn compute_diversity(
        &self,
        post: &RankedPost,
        selected: &[RankedPost],
        seen_sources: &HashSet<String>,
    ) -> f32 {
        if selected.is_empty() {
            return 1.0;
        }

        // 簡化版多樣性：如果召回源已經出現過，降低分數
        let source_diversity = if seen_sources.contains(post.recall_source.as_str()) {
            0.5
        } else {
            1.0
        };

        // Author diversity: Penalize if author already appears in recent posts
        let author_diversity = if let Some(post_author) = post.features.author_id {
            let author_count = selected
                .iter()
                .filter(|p| p.features.author_id == Some(post_author))
                .count();

            if author_count == 0 {
                1.0
            } else {
                0.3 // Heavy penalty for repeated author
            }
        } else {
            1.0
        };

        // Combined diversity score
        (source_diversity + author_diversity) / 2.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{PostFeatures, RecallSource};

    #[test]
    fn test_diversity_rerank() {
        let layer = DiversityLayer::new(0.7);

        let posts = vec![
            RankedPost {
                post_id: "post1".to_string(),
                score: 0.9,
                recall_source: RecallSource::Graph,
                features: PostFeatures::default(),
            },
            RankedPost {
                post_id: "post2".to_string(),
                score: 0.85,
                recall_source: RecallSource::Graph,
                features: PostFeatures::default(),
            },
            RankedPost {
                post_id: "post3".to_string(),
                score: 0.8,
                recall_source: RecallSource::Trending,
                features: PostFeatures::default(),
            },
            RankedPost {
                post_id: "post4".to_string(),
                score: 0.75,
                recall_source: RecallSource::Personalized,
                features: PostFeatures::default(),
            },
        ];

        let reranked = layer.rerank(posts, 3);

        assert_eq!(reranked.len(), 3);
        // 應該選擇不同 recall_source 的帖子以提高多樣性
        let sources: Vec<_> = reranked
            .iter()
            .map(|p| p.recall_source.as_str())
            .collect();
        let unique_sources: HashSet<_> = sources.iter().collect();
        assert!(unique_sources.len() >= 2); // 至少有 2 個不同來源
    }

    #[test]
    fn test_author_diversity_enforcement() {
        let layer = DiversityLayer::new(0.7);

        let author1 = Uuid::new_v4();
        let author2 = Uuid::new_v4();

        let posts = vec![
            RankedPost {
                post_id: "post1".to_string(),
                score: 0.9,
                recall_source: RecallSource::Graph,
                features: PostFeatures {
                    author_id: Some(author1),
                    ..Default::default()
                },
            },
            RankedPost {
                post_id: "post2".to_string(),
                score: 0.88,
                recall_source: RecallSource::Graph,
                features: PostFeatures {
                    author_id: Some(author1),
                    ..Default::default()
                },
            },
            RankedPost {
                post_id: "post3".to_string(),
                score: 0.86,
                recall_source: RecallSource::Graph,
                features: PostFeatures {
                    author_id: Some(author1),
                    ..Default::default()
                },
            },
            RankedPost {
                post_id: "post4".to_string(),
                score: 0.7,
                recall_source: RecallSource::Trending,
                features: PostFeatures {
                    author_id: Some(author2),
                    ..Default::default()
                },
            },
        ];

        let reranked = layer.rerank(posts, 4);

        assert_eq!(reranked.len(), 4);

        // Should not have 3 consecutive posts from same author
        for i in 0..reranked.len().saturating_sub(2) {
            let window = &reranked[i..i + 3];
            let all_same = window
                .iter()
                .all(|p| p.features.author_id == window[0].features.author_id);
            assert!(
                !all_same,
                "Found 3 consecutive posts from same author at position {}",
                i
            );
        }
    }

    #[test]
    fn test_with_author_limit() {
        let layer = DiversityLayer::with_author_limit(0.7, 1);

        let author1 = Uuid::new_v4();

        let posts = vec![
            RankedPost {
                post_id: "post1".to_string(),
                score: 0.9,
                recall_source: RecallSource::Graph,
                features: PostFeatures {
                    author_id: Some(author1),
                    ..Default::default()
                },
            },
            RankedPost {
                post_id: "post2".to_string(),
                score: 0.88,
                recall_source: RecallSource::Graph,
                features: PostFeatures {
                    author_id: Some(author1),
                    ..Default::default()
                },
            },
        ];

        let reranked = layer.rerank(posts, 2);

        // With limit=1, no two consecutive posts from same author
        if reranked.len() >= 2 {
            assert_ne!(
                reranked[0].features.author_id,
                reranked[1].features.author_id
            );
        }
    }
}

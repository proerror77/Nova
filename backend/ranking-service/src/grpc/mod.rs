use crate::models::{RankedPost, RecallStats};
use crate::services::{DiversityLayer, RankingLayer, RecallLayer};
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::info;

// Proto 生成的代碼
pub mod ranking_proto {
    tonic::include_proto!("ranking.v1");
}

use ranking_proto::{
    ranking_service_server::RankingService, Candidate, PostFeatures, RankFeedRequest,
    RankFeedResponse, RankedPost as ProtoRankedPost, RecallRequest, RecallResponse,
    RecallStats as ProtoRecallStats,
};

pub struct RankingServiceImpl {
    recall_layer: Arc<RecallLayer>,
    ranking_layer: Arc<RankingLayer>,
    diversity_layer: Arc<DiversityLayer>,
}

impl RankingServiceImpl {
    pub fn new(
        recall_layer: RecallLayer,
        ranking_layer: RankingLayer,
        diversity_layer: DiversityLayer,
    ) -> Self {
        Self {
            recall_layer: Arc::new(recall_layer),
            ranking_layer: Arc::new(ranking_layer),
            diversity_layer: Arc::new(diversity_layer),
        }
    }
}

#[tonic::async_trait]
impl RankingService for RankingServiceImpl {
    async fn rank_feed(
        &self,
        request: Request<RankFeedRequest>,
    ) -> Result<Response<RankFeedResponse>, Status> {
        let req = request.into_inner();
        let user_id = req.user_id;
        let limit = req.limit.max(1).min(100);

        info!("RankFeed request: user_id={}, limit={}", user_id, limit);

        // 1. Recall 召回候選集
        let (candidates, recall_stats) = self
            .recall_layer
            .recall_candidates(&user_id, None)
            .await
            .map_err(|e| Status::internal(format!("Recall failed: {}", e)))?;

        if candidates.is_empty() {
            return Ok(Response::new(RankFeedResponse {
                posts: vec![],
                recall_stats: Some(to_proto_recall_stats(recall_stats)),
            }));
        }

        // 2. Ranking 排序
        let ranked_posts = self
            .ranking_layer
            .rank_candidates(candidates)
            .await
            .map_err(|e| Status::internal(format!("Ranking failed: {}", e)))?;

        // 3. Diversity 重排
        let final_posts = self.diversity_layer.rerank(ranked_posts, limit as usize);

        let proto_posts: Vec<ProtoRankedPost> =
            final_posts.into_iter().map(to_proto_ranked_post).collect();

        Ok(Response::new(RankFeedResponse {
            posts: proto_posts,
            recall_stats: Some(to_proto_recall_stats(recall_stats)),
        }))
    }

    async fn recall_candidates(
        &self,
        request: Request<RecallRequest>,
    ) -> Result<Response<RecallResponse>, Status> {
        let req = request.into_inner();
        let user_id = req.user_id;

        info!("RecallCandidates request: user_id={}", user_id);

        let (candidates, stats) = self
            .recall_layer
            .recall_candidates(&user_id, None)
            .await
            .map_err(|e| Status::internal(format!("Recall failed: {}", e)))?;

        let proto_candidates: Vec<Candidate> = candidates
            .into_iter()
            .map(|c| Candidate {
                post_id: c.post_id,
                recall_source: c.recall_source.as_str().to_string(),
                recall_weight: c.recall_weight,
            })
            .collect();

        Ok(Response::new(RecallResponse {
            candidates: proto_candidates,
            stats: Some(to_proto_recall_stats(stats)),
        }))
    }
}

// Helper: 轉換為 Proto 格式
fn to_proto_ranked_post(post: RankedPost) -> ProtoRankedPost {
    ProtoRankedPost {
        post_id: post.post_id,
        score: post.score,
        recall_source: post.recall_source.as_str().to_string(),
        features: Some(PostFeatures {
            engagement_score: post.features.engagement_score,
            recency_score: post.features.recency_score,
            author_quality_score: post.features.author_quality_score,
            content_quality_score: post.features.content_quality_score,
        }),
    }
}

fn to_proto_recall_stats(stats: RecallStats) -> ProtoRecallStats {
    ProtoRecallStats {
        graph_recall_count: stats.graph_recall_count,
        trending_recall_count: stats.trending_recall_count,
        personalized_recall_count: stats.personalized_recall_count,
        total_candidates: stats.total_candidates,
        final_count: stats.final_count,
    }
}

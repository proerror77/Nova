use super::{Candidate, RecallSource, RecallStrategy};
use anyhow::{Context, Result};
use async_trait::async_trait;
use tonic::transport::Channel;
use tracing::{info, warn};

/// Graph Recall Strategy - 基於關注的召回
///
/// Phase E: 完整實現 - 集成 graph-service 和 content-service
/// 1. 從 graph-service 獲取用戶關注列表
/// 2. 從 content-service 獲取關注用戶的最新帖子
pub struct GraphRecallStrategy {
    graph_client: Channel,
    content_client: Channel,
}

impl GraphRecallStrategy {
    pub fn new(graph_client: Channel, content_client: Channel) -> Self {
        Self {
            graph_client,
            content_client,
        }
    }
}

#[async_trait]
impl RecallStrategy for GraphRecallStrategy {
    async fn recall(&self, user_id: &str, limit: i32) -> Result<Vec<Candidate>> {
        // 1. 獲取用戶關注列表（gRPC 調用 graph-service）
        let following_ids = self.get_following_users(user_id, limit).await?;

        if following_ids.is_empty() {
            warn!(
                "User {} has no following, graph recall returns empty",
                user_id
            );
            return Ok(Vec::new());
        }

        info!(
            "Graph recall for user {}: found {} following users",
            user_id,
            following_ids.len()
        );

        // 2. 獲取關注用戶的最新帖子（gRPC 調用 content-service）
        let posts_per_user = (limit / following_ids.len() as i32).max(3);
        let candidates = self
            .get_posts_from_users(&following_ids, posts_per_user)
            .await?;

        info!(
            "Graph recall for user {}: retrieved {} posts from {} authors",
            user_id,
            candidates.len(),
            following_ids.len()
        );

        Ok(candidates)
    }

    fn source(&self) -> RecallSource {
        RecallSource::Graph
    }
}

impl GraphRecallStrategy {
    async fn get_following_users(&self, user_id: &str, limit: i32) -> Result<Vec<String>> {
        use tonic::Request;

        // 生成 gRPC client stub
        let mut client = graph_service_client(&self.graph_client);

        let request = Request::new(graph_proto::GetFollowingRequest {
            user_id: user_id.to_string(),
            limit,
            offset: 0,
        });

        let response = client
            .get_following(request)
            .await
            .context("Failed to call graph-service GetFollowing")?;

        let following_response = response.into_inner();
        Ok(following_response.user_ids)
    }

    /// 從 content-service 批量獲取用戶的最新帖子
    async fn get_posts_from_users(
        &self,
        user_ids: &[String],
        posts_per_user: i32,
    ) -> Result<Vec<Candidate>> {
        use tonic::Request;

        let mut all_candidates = Vec::new();

        // 對每個關注用戶獲取其最新帖子
        // TODO: 優化為批量請求（需要 content-service 支援 batch API）
        for (idx, following_user_id) in user_ids.iter().enumerate() {
            let mut client = content_service_client(&self.content_client);

            let request = Request::new(content_proto::GetUserPostsRequest {
                user_id: following_user_id.clone(),
                limit: posts_per_user,
                offset: 0,
                status: content_proto::ContentStatus::Published as i32,
            });

            match client.get_user_posts(request).await {
                Ok(response) => {
                    let posts_response = response.into_inner();

                    for post in posts_response.posts {
                        // 計算召回權重：關注順序靠前的用戶帖子權重更高
                        let base_weight = 1.0 - (idx as f32 * 0.02);
                        let recency_boost = self.compute_recency_boost(post.created_at);

                        all_candidates.push(Candidate {
                            post_id: post.id,
                            recall_source: RecallSource::Graph,
                            recall_weight: (base_weight * recency_boost).clamp(0.1, 1.0),
                            timestamp: post.created_at,
                        });
                    }
                }
                Err(e) => {
                    warn!(
                        "Failed to get posts for user {}: {}",
                        following_user_id, e
                    );
                    // 繼續處理其他用戶，不中斷整個流程
                }
            }
        }

        // 按時間戳降序排序（最新的優先）
        all_candidates.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));

        Ok(all_candidates)
    }

    /// 計算時效性加成（24小時內發布的帖子獲得更高權重）
    fn compute_recency_boost(&self, created_at: i64) -> f32 {
        let now = chrono::Utc::now().timestamp();
        let age_hours = ((now - created_at) as f32 / 3600.0).max(0.0);

        // 指數衰減：6小時內為 1.0，24小時衰減到 0.5
        (1.0 - (age_hours / 48.0)).clamp(0.5, 1.0)
    }
}

// Helper: 生成 GraphService client
fn graph_service_client(
    channel: &Channel,
) -> graph_proto::graph_service_client::GraphServiceClient<Channel> {
    graph_proto::graph_service_client::GraphServiceClient::new(channel.clone())
}

// Helper: 生成 ContentService client
fn content_service_client(
    channel: &Channel,
) -> content_proto::content_service_client::ContentServiceClient<Channel> {
    content_proto::content_service_client::ContentServiceClient::new(channel.clone())
}

// Proto 生成的代碼
mod graph_proto {
    tonic::include_proto!("graph.v1");
}

mod content_proto {
    tonic::include_proto!("nova.content_service.v2");
}

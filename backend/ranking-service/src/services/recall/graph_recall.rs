use super::{Candidate, RecallSource, RecallStrategy};
use anyhow::{Context, Result};
use async_trait::async_trait;
use tonic::transport::Channel;
use tracing::warn;

/// Graph Recall Strategy - 基於關注的召回
pub struct GraphRecallStrategy {
    graph_client: Channel,
}

impl GraphRecallStrategy {
    pub fn new(graph_client: Channel) -> Self {
        Self { graph_client }
    }
}

#[async_trait]
impl RecallStrategy for GraphRecallStrategy {
    async fn recall(&self, user_id: &str, limit: i32) -> Result<Vec<Candidate>> {
        // 1. 獲取用戶關注列表（gRPC 調用 graph-service）
        let following_ids = self.get_following_users(user_id, limit).await?;

        if following_ids.is_empty() {
            warn!("User {} has no following, graph recall returns empty", user_id);
            return Ok(Vec::new());
        }

        // 2. 召回這些用戶最近的帖子（這裡暫時返回佔位符）
        // TODO: Phase E - 調用 content-service 獲取實際帖子
        let candidates: Vec<Candidate> = following_ids
            .into_iter()
            .enumerate()
            .map(|(i, user_id)| Candidate {
                post_id: format!("post_from_{}", user_id), // 佔位符
                recall_source: RecallSource::Graph,
                recall_weight: 1.0 - (i as f32 * 0.01), // 遞減權重
                timestamp: chrono::Utc::now().timestamp(),
            })
            .collect();

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
}

// Helper: 生成 GraphService client
fn graph_service_client(
    channel: &Channel,
) -> graph_proto::graph_service_client::GraphServiceClient<Channel> {
    graph_proto::graph_service_client::GraphServiceClient::new(channel.clone())
}

// Proto 生成的代碼
mod graph_proto {
    tonic::include_proto!("graph.v1");
}

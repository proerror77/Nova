use chrono::{DateTime, Utc};
use grpc_clients::nova::graph_service::v2::{
    graph_service_client::GraphServiceClient, GetFollowersRequest, GetFollowingRequest,
    IsFollowingRequest,
};
use tonic::transport::Channel;
use uuid::Uuid;

#[derive(Clone)]
pub struct FollowService {
    pub graph_client: GraphServiceClient<Channel>,
}

impl FollowService {
    pub fn new(graph_client: GraphServiceClient<Channel>) -> Self {
        Self { graph_client }
    }

    /// Create follow is now handled by publishing events (see grpc/server_v2.rs)
    /// This method is kept for backward compatibility but should not write to DB
    pub async fn create_follow(
        &self,
        _follower_id: Uuid,
        _followee_id: Uuid,
    ) -> anyhow::Result<bool> {
        // No-op: actual follow creation happens via Kafka events consumed by graph-service
        // Return true to indicate the operation was accepted
        Ok(true)
    }

    /// Delete follow is now handled by publishing events (see grpc/server_v2.rs)
    /// This method is kept for backward compatibility but should not write to DB
    pub async fn delete_follow(
        &self,
        _follower_id: Uuid,
        _followee_id: Uuid,
    ) -> anyhow::Result<bool> {
        // No-op: actual follow deletion happens via Kafka events consumed by graph-service
        // Return true to indicate the operation was accepted
        Ok(true)
    }

    /// Get followers (user_ids) with pagination via graph-service gRPC
    pub async fn get_followers(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<(Vec<Uuid>, i64)> {
        let mut client = self.graph_client.clone();
        let request = tonic::Request::new(GetFollowersRequest {
            user_id: user_id.to_string(),
            limit: limit as i32,
            offset: offset as i32,
        });

        let response = client.get_followers(request).await?;
        let inner = response.into_inner();

        let follower_ids: Vec<Uuid> = inner
            .user_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        Ok((follower_ids, inner.total_count as i64))
    }

    /// Get following (user_ids) with pagination via graph-service gRPC
    pub async fn get_following(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> anyhow::Result<(Vec<Uuid>, i64)> {
        let mut client = self.graph_client.clone();
        let request = tonic::Request::new(GetFollowingRequest {
            user_id: user_id.to_string(),
            limit: limit as i32,
            offset: offset as i32,
        });

        let response = client.get_following(request).await?;
        let inner = response.into_inner();

        let following_ids: Vec<Uuid> = inner
            .user_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        Ok((following_ids, inner.total_count as i64))
    }

    /// Get follow relationship metadata via graph-service gRPC
    /// Returns Some((id, created_at)) if relationship exists, None otherwise
    pub async fn get_relationship(
        &self,
        follower_id: Uuid,
        followee_id: Uuid,
    ) -> anyhow::Result<Option<(Uuid, DateTime<Utc>)>> {
        let mut client = self.graph_client.clone();
        let request = tonic::Request::new(IsFollowingRequest {
            follower_id: follower_id.to_string(),
            followee_id: followee_id.to_string(),
        });

        match client.is_following(request).await {
            Ok(response) => {
                let inner = response.into_inner();
                if inner.is_following {
                    // Since graph-service doesn't return edge ID or timestamp,
                    // we'll generate a new UUID and use current time
                    // This is acceptable since the method is only used to check existence
                    Ok(Some((Uuid::new_v4(), Utc::now())))
                } else {
                    Ok(None)
                }
            }
            Err(status) => {
                if status.code() == tonic::Code::NotFound {
                    Ok(None)
                } else {
                    Err(anyhow::anyhow!("gRPC error: {}", status))
                }
            }
        }
    }
}

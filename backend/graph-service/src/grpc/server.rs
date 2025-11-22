use crate::repository::GraphRepository;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::{error, info};
use uuid::Uuid;

// Include generated protobuf code
pub mod graph {
    tonic::include_proto!("nova.graph_service.v2");
}

use graph::graph_service_server::GraphService;
use graph::*;

pub struct GraphServiceImpl {
    repo: Arc<GraphRepository>,
    /// Optional write token; if None => writes are disabled (read-only mode).
    write_token: Option<String>,
}

impl GraphServiceImpl {
    pub fn new(repo: GraphRepository, write_token: Option<String>) -> Self {
        Self {
            repo: Arc::new(repo),
            write_token,
        }
    }

    fn authorize_write<T>(&self, req: &Request<T>) -> Result<(), Status> {
        match &self.write_token {
            Some(expected) => {
                let token = req
                    .metadata()
                    .get("x-internal-token")
                    .and_then(|v| v.to_str().ok());
                if token == Some(expected.as_str()) {
                    Ok(())
                } else {
                    Err(Status::permission_denied(
                        "write operations require valid internal token",
                    ))
                }
            }
            None => Err(Status::permission_denied(
                "graph-service write APIs disabled (no INTERNAL_GRAPH_WRITE_TOKEN)",
            )),
        }
    }
}

#[tonic::async_trait]
impl GraphService for GraphServiceImpl {
    async fn create_follow(
        &self,
        request: Request<CreateFollowRequest>,
    ) -> Result<Response<CreateFollowResponse>, Status> {
        self.authorize_write(&request)?;
        let req = request.into_inner();

        let follower_id = Uuid::parse_str(&req.follower_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid follower_id: {}", e)))?;

        let followee_id = Uuid::parse_str(&req.followee_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid followee_id: {}", e)))?;

        match self.repo.create_follow(follower_id, followee_id).await {
            Ok(_) => {
                info!("Created follow: {} -> {}", follower_id, followee_id);
                Ok(Response::new(CreateFollowResponse {
                    success: true,
                    message: "Follow created successfully".to_string(),
                }))
            }
            Err(e) => {
                error!("Failed to create follow: {}", e);
                Err(Status::internal(format!("Failed to create follow: {}", e)))
            }
        }
    }

    async fn delete_follow(
        &self,
        request: Request<DeleteFollowRequest>,
    ) -> Result<Response<DeleteFollowResponse>, Status> {
        self.authorize_write(&request)?;
        let req = request.into_inner();

        let follower_id = Uuid::parse_str(&req.follower_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid follower_id: {}", e)))?;

        let followee_id = Uuid::parse_str(&req.followee_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid followee_id: {}", e)))?;

        match self.repo.delete_follow(follower_id, followee_id).await {
            Ok(_) => {
                info!("Deleted follow: {} -> {}", follower_id, followee_id);
                Ok(Response::new(DeleteFollowResponse {
                    success: true,
                    message: "Follow deleted successfully".to_string(),
                }))
            }
            Err(e) => {
                error!("Failed to delete follow: {}", e);
                Err(Status::internal(format!("Failed to delete follow: {}", e)))
            }
        }
    }

    async fn create_mute(
        &self,
        request: Request<CreateMuteRequest>,
    ) -> Result<Response<CreateMuteResponse>, Status> {
        self.authorize_write(&request)?;
        let req = request.into_inner();

        let muter_id = Uuid::parse_str(&req.muter_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid muter_id: {}", e)))?;

        let mutee_id = Uuid::parse_str(&req.mutee_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid mutee_id: {}", e)))?;

        match self.repo.create_mute(muter_id, mutee_id).await {
            Ok(_) => {
                info!("Created mute: {} -> {}", muter_id, mutee_id);
                Ok(Response::new(CreateMuteResponse {
                    success: true,
                    message: "Mute created successfully".to_string(),
                }))
            }
            Err(e) => {
                error!("Failed to create mute: {}", e);
                Err(Status::internal(format!("Failed to create mute: {}", e)))
            }
        }
    }

    async fn delete_mute(
        &self,
        request: Request<DeleteMuteRequest>,
    ) -> Result<Response<DeleteMuteResponse>, Status> {
        self.authorize_write(&request)?;
        let req = request.into_inner();

        let muter_id = Uuid::parse_str(&req.muter_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid muter_id: {}", e)))?;

        let mutee_id = Uuid::parse_str(&req.mutee_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid mutee_id: {}", e)))?;

        match self.repo.delete_mute(muter_id, mutee_id).await {
            Ok(_) => {
                info!("Deleted mute: {} -> {}", muter_id, mutee_id);
                Ok(Response::new(DeleteMuteResponse {
                    success: true,
                    message: "Mute deleted successfully".to_string(),
                }))
            }
            Err(e) => {
                error!("Failed to delete mute: {}", e);
                Err(Status::internal(format!("Failed to delete mute: {}", e)))
            }
        }
    }

    async fn create_block(
        &self,
        request: Request<CreateBlockRequest>,
    ) -> Result<Response<CreateBlockResponse>, Status> {
        self.authorize_write(&request)?;
        let req = request.into_inner();

        let blocker_id = Uuid::parse_str(&req.blocker_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid blocker_id: {}", e)))?;

        let blocked_id = Uuid::parse_str(&req.blocked_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid blocked_id: {}", e)))?;

        match self.repo.create_block(blocker_id, blocked_id).await {
            Ok(_) => {
                info!("Created block: {} -> {}", blocker_id, blocked_id);
                Ok(Response::new(CreateBlockResponse {
                    success: true,
                    message: "Block created successfully".to_string(),
                }))
            }
            Err(e) => {
                error!("Failed to create block: {}", e);
                Err(Status::internal(format!("Failed to create block: {}", e)))
            }
        }
    }

    async fn delete_block(
        &self,
        request: Request<DeleteBlockRequest>,
    ) -> Result<Response<DeleteBlockResponse>, Status> {
        self.authorize_write(&request)?;
        let req = request.into_inner();

        let blocker_id = Uuid::parse_str(&req.blocker_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid blocker_id: {}", e)))?;

        let blocked_id = Uuid::parse_str(&req.blocked_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid blocked_id: {}", e)))?;

        match self.repo.delete_block(blocker_id, blocked_id).await {
            Ok(_) => {
                info!("Deleted block: {} -> {}", blocker_id, blocked_id);
                Ok(Response::new(DeleteBlockResponse {
                    success: true,
                    message: "Block deleted successfully".to_string(),
                }))
            }
            Err(e) => {
                error!("Failed to delete block: {}", e);
                Err(Status::internal(format!("Failed to delete block: {}", e)))
            }
        }
    }

    async fn get_followers(
        &self,
        request: Request<GetFollowersRequest>,
    ) -> Result<Response<GetFollowersResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let limit = if req.limit > 0 {
            req.limit
        } else {
            1000 // Default limit
        };
        let offset = req.offset;

        match self.repo.get_followers(user_id, limit, offset).await {
            Ok((followers, total_count, has_more)) => {
                let user_ids: Vec<String> = followers.iter().map(|id| id.to_string()).collect();

                info!(
                    "Get followers for {}: {} results (offset: {}, has_more: {})",
                    user_id,
                    user_ids.len(),
                    offset,
                    has_more
                );

                Ok(Response::new(GetFollowersResponse {
                    user_ids,
                    total_count,
                    has_more,
                }))
            }
            Err(e) => {
                error!("Failed to get followers: {}", e);
                Err(Status::internal(format!("Failed to get followers: {}", e)))
            }
        }
    }

    async fn get_following(
        &self,
        request: Request<GetFollowingRequest>,
    ) -> Result<Response<GetFollowingResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let limit = if req.limit > 0 { req.limit } else { 1000 };
        let offset = req.offset;

        match self.repo.get_following(user_id, limit, offset).await {
            Ok((following, total_count, has_more)) => {
                let user_ids: Vec<String> = following.iter().map(|id| id.to_string()).collect();

                info!(
                    "Get following for {}: {} results (offset: {}, has_more: {})",
                    user_id,
                    user_ids.len(),
                    offset,
                    has_more
                );

                Ok(Response::new(GetFollowingResponse {
                    user_ids,
                    total_count,
                    has_more,
                }))
            }
            Err(e) => {
                error!("Failed to get following: {}", e);
                Err(Status::internal(format!("Failed to get following: {}", e)))
            }
        }
    }

    async fn is_following(
        &self,
        request: Request<IsFollowingRequest>,
    ) -> Result<Response<IsFollowingResponse>, Status> {
        let req = request.into_inner();

        let follower_id = Uuid::parse_str(&req.follower_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid follower_id: {}", e)))?;

        let followee_id = Uuid::parse_str(&req.followee_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid followee_id: {}", e)))?;

        match self.repo.is_following(follower_id, followee_id).await {
            Ok(is_following) => Ok(Response::new(IsFollowingResponse { is_following })),
            Err(e) => {
                error!("Failed to check following: {}", e);
                Err(Status::internal(format!(
                    "Failed to check following: {}",
                    e
                )))
            }
        }
    }

    async fn is_muted(
        &self,
        request: Request<IsMutedRequest>,
    ) -> Result<Response<IsMutedResponse>, Status> {
        let req = request.into_inner();

        let muter_id = Uuid::parse_str(&req.muter_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid muter_id: {}", e)))?;

        let mutee_id = Uuid::parse_str(&req.mutee_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid mutee_id: {}", e)))?;

        match self.repo.is_muted(muter_id, mutee_id).await {
            Ok(is_muted) => Ok(Response::new(IsMutedResponse { is_muted })),
            Err(e) => {
                error!("Failed to check mute: {}", e);
                Err(Status::internal(format!("Failed to check mute: {}", e)))
            }
        }
    }

    async fn is_blocked(
        &self,
        request: Request<IsBlockedRequest>,
    ) -> Result<Response<IsBlockedResponse>, Status> {
        let req = request.into_inner();

        let blocker_id = Uuid::parse_str(&req.blocker_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid blocker_id: {}", e)))?;

        let blocked_id = Uuid::parse_str(&req.blocked_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid blocked_id: {}", e)))?;

        match self.repo.is_blocked(blocker_id, blocked_id).await {
            Ok(is_blocked) => Ok(Response::new(IsBlockedResponse { is_blocked })),
            Err(e) => {
                error!("Failed to check block: {}", e);
                Err(Status::internal(format!("Failed to check block: {}", e)))
            }
        }
    }

    async fn batch_check_following(
        &self,
        request: Request<BatchCheckFollowingRequest>,
    ) -> Result<Response<BatchCheckFollowingResponse>, Status> {
        let req = request.into_inner();

        let follower_id = Uuid::parse_str(&req.follower_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid follower_id: {}", e)))?;

        if req.followee_ids.len() > 100 {
            return Err(Status::invalid_argument(
                "Max 100 followee_ids allowed per batch",
            ));
        }

        let followee_ids: Result<Vec<Uuid>, _> = req
            .followee_ids
            .iter()
            .map(|id_str| {
                Uuid::parse_str(id_str)
                    .map_err(|e| Status::invalid_argument(format!("Invalid followee_id: {}", e)))
            })
            .collect();

        let followee_ids = followee_ids?;

        match self
            .repo
            .batch_check_following(follower_id, followee_ids)
            .await
        {
            Ok(results) => {
                info!(
                    "Batch checked {} followee_ids for follower {}",
                    results.len(),
                    follower_id
                );

                Ok(Response::new(BatchCheckFollowingResponse { results }))
            }
            Err(e) => {
                error!("Failed to batch check following: {}", e);
                Err(Status::internal(format!(
                    "Failed to batch check following: {}",
                    e
                )))
            }
        }
    }
}

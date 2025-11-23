use std::sync::Arc;

use chrono::{DateTime, Utc};
use pbjson_types::{Empty, Timestamp};
use sqlx::PgPool;
use tonic::{Request, Response, Status};
use transactional_outbox::{OutboxError, SqlxOutboxRepository};
use uuid::Uuid;

use crate::domain::models::{Comment as CommentModel, Like as LikeModel, Share as ShareModel};
use crate::repository::{CommentRepository, LikeRepository, ShareRepository};
use crate::services::{CounterService, FollowService};
use transactional_outbox::{OutboxEvent, OutboxRepository};

fn outbox_error_to_status(err: OutboxError) -> Status {
    Status::internal(format!("Outbox error: {}", err))
}

// Generated protobuf code (from backend/proto/services_v2/social_service.proto)
pub mod social {
    tonic::include_proto!("nova.social_service.v2");
}

use social::social_service_server::SocialService;
use social::*;

/// App state shared across gRPC handlers
#[derive(Clone)]
pub struct AppState {
    pub pg_pool: PgPool,
    pub counter_service: CounterService,
    pub outbox_repo: Arc<SqlxOutboxRepository>,
}

impl AppState {
    pub fn new(
        pg_pool: PgPool,
        counter_service: CounterService,
        outbox_repo: Arc<SqlxOutboxRepository>,
    ) -> Self {
        Self {
            pg_pool,
            counter_service,
            outbox_repo,
        }
    }
}

pub struct SocialServiceImpl {
    state: Arc<AppState>,
}

impl SocialServiceImpl {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }

    fn like_repo(&self) -> LikeRepository {
        LikeRepository::new(self.state.pg_pool.clone())
    }

    fn follow_service(&self) -> FollowService {
        FollowService::new(self.state.pg_pool.clone())
    }

    fn comment_repo(&self) -> CommentRepository {
        CommentRepository::new(self.state.pg_pool.clone())
    }

    fn share_repo(&self) -> ShareRepository {
        ShareRepository::new(self.state.pg_pool.clone())
    }
}

#[tonic::async_trait]
impl SocialService for SocialServiceImpl {
    // ========= Relationships (stubs) =========
    async fn follow_user(
        &self,
        request: Request<FollowUserRequest>,
    ) -> Result<Response<Empty>, Status> {
        let req = request.into_inner();
        let follower_id = parse_uuid(&req.follower_id, "follower_id")?;
        let followee_id = parse_uuid(&req.followee_id, "followee_id")?;

        let created = self
            .follow_service()
            .create_follow(follower_id, followee_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to create follow: {}", e)))?;

        if created {
            publish_outbox_follow(&self.state, follower_id, followee_id, true).await?;
        }

        Ok(Response::new(Empty {}))
    }

    async fn unfollow_user(
        &self,
        request: Request<UnfollowUserRequest>,
    ) -> Result<Response<Empty>, Status> {
        let req = request.into_inner();
        let follower_id = parse_uuid(&req.follower_id, "follower_id")?;
        let followee_id = parse_uuid(&req.followee_id, "followee_id")?;

        let deleted = self
            .follow_service()
            .delete_follow(follower_id, followee_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete follow: {}", e)))?;

        if deleted {
            publish_outbox_follow(&self.state, follower_id, followee_id, false).await?;
        }

        Ok(Response::new(Empty {}))
    }

    async fn block_user(
        &self,
        _request: Request<BlockUserRequest>,
    ) -> Result<Response<Empty>, Status> {
        Err(Status::unimplemented("block_user not implemented"))
    }

    async fn unblock_user(
        &self,
        _request: Request<UnblockUserRequest>,
    ) -> Result<Response<Empty>, Status> {
        Err(Status::unimplemented("unblock_user not implemented"))
    }

    async fn get_followers(
        &self,
        request: Request<GetFollowersRequest>,
    ) -> Result<Response<GetFollowersResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let limit = sanitize_limit(req.limit, 1, 200, 50) as i64;
        let offset = req.offset.max(0) as i64;

        let (followers, total) = self
            .follow_service()
            .get_followers(user_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get followers: {}", e)))?;

        Ok(Response::new(GetFollowersResponse {
            user_ids: followers.into_iter().map(|id| id.to_string()).collect(),
            total: total as i32,
        }))
    }

    async fn get_following(
        &self,
        request: Request<GetFollowingRequest>,
    ) -> Result<Response<GetFollowingResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let limit = sanitize_limit(req.limit, 1, 200, 50) as i64;
        let offset = req.offset.max(0) as i64;

        let (following, total) = self
            .follow_service()
            .get_following(user_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get following: {}", e)))?;

        Ok(Response::new(GetFollowingResponse {
            user_ids: following.into_iter().map(|id| id.to_string()).collect(),
            total: total as i32,
        }))
    }

    async fn get_relationship(
        &self,
        request: Request<GetRelationshipRequest>,
    ) -> Result<Response<GetRelationshipResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let other_user_id = parse_uuid(&req.other_user_id, "other_user_id")?;

        let rel = self
            .follow_service()
            .get_relationship(user_id, other_user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get relationship: {}", e)))?;

        let relationship = if let Some((id, created_at)) = rel {
            Relationship {
                id: id.to_string(),
                follower_id: user_id.to_string(),
                followee_id: other_user_id.to_string(),
                r#type: RelationshipType::Follow as i32,
                status: RelationshipStatus::Active as i32,
                created_at: to_ts(created_at),
                updated_at: to_ts(created_at),
            }
        } else {
            Relationship {
                id: String::new(),
                follower_id: user_id.to_string(),
                followee_id: other_user_id.to_string(),
                r#type: RelationshipType::Unspecified as i32,
                status: RelationshipStatus::Unspecified as i32,
                created_at: None,
                updated_at: None,
            }
        };

        Ok(Response::new(GetRelationshipResponse {
            relationship: Some(relationship),
        }))
    }

    // ========= Likes =========
    async fn create_like(
        &self,
        request: Request<CreateLikeRequest>,
    ) -> Result<Response<CreateLikeResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        let like_repo = self.like_repo();
        like_repo
            .create_like(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to create like: {}", e)))?;

        let like_count = match self
            .state
            .counter_service
            .increment_like_count(post_id)
            .await
        {
            Ok(v) => v,
            Err(_) => self
                .state
                .counter_service
                .get_like_count(post_id)
                .await
                .unwrap_or(0),
        };

        Ok(Response::new(CreateLikeResponse {
            success: true,
            like_count,
        }))
    }

    async fn delete_like(
        &self,
        request: Request<DeleteLikeRequest>,
    ) -> Result<Response<DeleteLikeResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        let like_repo = self.like_repo();
        like_repo
            .delete_like(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete like: {}", e)))?;

        let like_count = match self
            .state
            .counter_service
            .decrement_like_count(post_id)
            .await
        {
            Ok(v) => v,
            Err(_) => self
                .state
                .counter_service
                .get_like_count(post_id)
                .await
                .unwrap_or(0),
        };

        Ok(Response::new(DeleteLikeResponse {
            success: true,
            like_count,
        }))
    }

    async fn get_likes(
        &self,
        request: Request<GetLikesRequest>,
    ) -> Result<Response<GetLikesResponse>, Status> {
        let req = request.into_inner();
        let post_id = parse_uuid(&req.post_id, "post_id")?;
        let limit = sanitize_limit(req.limit, 1, 100, 50);
        let offset = req.offset.max(0);

        let like_repo = self.like_repo();
        let likes = like_repo
            .get_post_likes(post_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get likes: {}", e)))?;

        let total = match self.state.counter_service.get_like_count(post_id).await {
            Ok(count) => count as i32,
            Err(_) => like_repo.get_like_count(post_id).await.unwrap_or(0) as i32,
        };

        Ok(Response::new(GetLikesResponse {
            likes: likes.into_iter().map(to_proto_like).collect(),
            total,
        }))
    }

    async fn check_user_liked(
        &self,
        request: Request<CheckUserLikedRequest>,
    ) -> Result<Response<CheckUserLikedResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        let liked = self
            .like_repo()
            .check_user_liked(user_id, post_id)
            .await
            .unwrap_or(false);

        Ok(Response::new(CheckUserLikedResponse { liked }))
    }

    // ========= Comments =========
    async fn create_comment(
        &self,
        request: Request<CreateCommentRequest>,
    ) -> Result<Response<CreateCommentResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;
        let parent_comment_id = if req.parent_comment_id.is_empty() {
            None
        } else {
            Some(parse_uuid(&req.parent_comment_id, "parent_comment_id")?)
        };

        let comment = self
            .comment_repo()
            .create_comment(post_id, user_id, req.content, parent_comment_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to create comment: {}", e)))?;

        let _ = self
            .state
            .counter_service
            .increment_comment_count(post_id)
            .await;

        Ok(Response::new(CreateCommentResponse {
            comment: Some(to_proto_comment(comment)),
        }))
    }

    async fn delete_comment(
        &self,
        request: Request<DeleteCommentRequest>,
    ) -> Result<Response<DeleteCommentResponse>, Status> {
        let req = request.into_inner();
        let comment_id = parse_uuid(&req.comment_id, "comment_id")?;
        let user_id = parse_uuid(&req.user_id, "user_id")?;

        let repo = self.comment_repo();
        let deleted = repo
            .delete_comment(comment_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete comment: {}", e)))?;

        if deleted {
            if let Ok(Some(comment)) = repo.get_comment(comment_id).await {
                let _ = self
                    .state
                    .counter_service
                    .decrement_comment_count(comment.post_id)
                    .await;
            }
        }

        Ok(Response::new(DeleteCommentResponse { success: deleted }))
    }

    async fn get_comments(
        &self,
        request: Request<GetCommentsRequest>,
    ) -> Result<Response<GetCommentsResponse>, Status> {
        let req = request.into_inner();
        let post_id = parse_uuid(&req.post_id, "post_id")?;
        let limit = sanitize_limit(req.limit, 1, 100, 50);
        let offset = req.offset.max(0);

        let repo = self.comment_repo();
        let comments = repo
            .get_comments(post_id, limit, offset, "created_at", "desc")
            .await
            .map_err(|e| Status::internal(format!("Failed to get comments: {}", e)))?;

        let total = match self.state.counter_service.get_comment_count(post_id).await {
            Ok(count) => count as i32,
            Err(_) => repo.get_comment_count(post_id).await.unwrap_or(0) as i32,
        };

        Ok(Response::new(GetCommentsResponse {
            comments: comments.into_iter().map(to_proto_comment).collect(),
            total,
        }))
    }

    // ========= Shares =========
    async fn create_share(
        &self,
        request: Request<CreateShareRequest>,
    ) -> Result<Response<CreateShareResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        self.share_repo()
            .create_share(user_id, post_id, "repost".to_string())
            .await
            .map_err(|e| Status::internal(format!("Failed to create share: {}", e)))?;

        let _ = self
            .state
            .counter_service
            .increment_share_count(post_id)
            .await;

        Ok(Response::new(CreateShareResponse { success: true }))
    }

    async fn get_share_count(
        &self,
        request: Request<GetShareCountRequest>,
    ) -> Result<Response<GetShareCountResponse>, Status> {
        let req = request.into_inner();
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        let count = match self.state.counter_service.get_share_count(post_id).await {
            Ok(c) => c,
            Err(_) => self
                .share_repo()
                .get_share_count(post_id)
                .await
                .unwrap_or(0),
        };

        Ok(Response::new(GetShareCountResponse { count }))
    }

    // ========= Feed (stubs) =========
    async fn get_user_feed(
        &self,
        _request: Request<GetUserFeedRequest>,
    ) -> Result<Response<GetUserFeedResponse>, Status> {
        Err(Status::unimplemented("get_user_feed not implemented"))
    }

    async fn get_explore_feed(
        &self,
        _request: Request<GetExploreFeedRequest>,
    ) -> Result<Response<GetExploreFeedResponse>, Status> {
        Err(Status::unimplemented("get_explore_feed not implemented"))
    }
}

fn parse_uuid(value: &str, field: &str) -> Result<Uuid, Status> {
    Uuid::parse_str(value).map_err(|_| Status::invalid_argument(format!("Invalid {}", field)))
}

fn sanitize_limit(value: i32, min: i32, max: i32, default: i32) -> i32 {
    if value < min {
        default
    } else if value > max {
        max
    } else {
        value
    }
}

async fn publish_outbox_follow(
    state: &Arc<AppState>,
    follower_id: Uuid,
    followee_id: Uuid,
    created: bool,
) -> Result<(), Status> {
    let mut tx = state
        .pg_pool
        .begin()
        .await
        .map_err(|e| Status::internal(format!("Failed to open tx for outbox: {}", e)))?;

    let event = OutboxEvent {
        id: Uuid::new_v4(),
        aggregate_type: "follow".to_string(),
        aggregate_id: follower_id,
        event_type: if created {
            "social.follow.created"
        } else {
            "social.follow.deleted"
        }
        .to_string(),
        payload: serde_json::json!({
            "follower_id": follower_id.to_string(),
            "followee_id": followee_id.to_string()
        }),
        metadata: None,
        created_at: chrono::Utc::now(),
        published_at: None,
        retry_count: 0,
        last_error: None,
    };

    state
        .outbox_repo
        .insert(&mut tx, &event)
        .await
        .map_err(outbox_error_to_status)?;

    tx.commit()
        .await
        .map_err(|e| Status::internal(format!("Failed to commit follow outbox: {}", e)))?;
    Ok(())
}

fn to_ts(dt: DateTime<Utc>) -> Option<Timestamp> {
    Some(Timestamp {
        seconds: dt.timestamp(),
        nanos: dt.timestamp_subsec_nanos() as i32,
    })
}

fn to_proto_like(like: LikeModel) -> Like {
    Like {
        id: like.id.to_string(),
        user_id: like.user_id.to_string(),
        post_id: like.post_id.to_string(),
        created_at: to_ts(like.created_at),
    }
}

fn to_proto_comment(comment: CommentModel) -> Comment {
    Comment {
        id: comment.id.to_string(),
        user_id: comment.user_id.to_string(),
        post_id: comment.post_id.to_string(),
        content: comment.content,
        parent_comment_id: comment
            .parent_comment_id
            .map(|id| id.to_string())
            .unwrap_or_default(),
        created_at: to_ts(comment.created_at),
    }
}

#[allow(dead_code)]
fn _to_proto_share(_share: ShareModel) {}

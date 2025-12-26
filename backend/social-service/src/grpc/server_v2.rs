use std::sync::Arc;

use chrono::{DateTime, Utc};
use grpc_clients::nova::graph_service::v2::graph_service_client::GraphServiceClient;
use pbjson_types::{Empty, Timestamp};
use sqlx::PgPool;
use tonic::transport::Channel;
use tonic::{Request, Response, Status};
use transactional_outbox::{OutboxError, SqlxOutboxRepository};
use uuid::Uuid;

use crate::domain::models::{
    CandidatePreview as CandidatePreviewModel, CandidateWithRank, Comment as CommentModel,
    Like as LikeModel, Poll as PollModel, PollCandidate as PollCandidateModel, Share as ShareModel,
};
use crate::repository::{
    polls::CreateCandidateInput, BookmarkRepository, CommentRepository, LikeRepository,
    PollRepository, ShareRepository,
};
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
    pub graph_client: GraphServiceClient<Channel>,
}

impl AppState {
    pub fn new(
        pg_pool: PgPool,
        counter_service: CounterService,
        outbox_repo: Arc<SqlxOutboxRepository>,
        graph_client: GraphServiceClient<Channel>,
    ) -> Self {
        Self {
            pg_pool,
            counter_service,
            outbox_repo,
            graph_client,
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
        FollowService::new(self.state.graph_client.clone())
    }

    fn comment_repo(&self) -> CommentRepository {
        CommentRepository::new(self.state.pg_pool.clone())
    }

    fn share_repo(&self) -> ShareRepository {
        ShareRepository::new(self.state.pg_pool.clone())
    }

    fn poll_repo(&self) -> PollRepository {
        PollRepository::new(self.state.pg_pool.clone())
    }

    fn bookmark_repo(&self) -> BookmarkRepository {
        BookmarkRepository::new(self.state.pg_pool.clone())
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

    async fn get_user_liked_posts(
        &self,
        request: Request<GetUserLikedPostsRequest>,
    ) -> Result<Response<GetUserLikedPostsResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let limit = sanitize_limit(req.limit, 1, 100, 20);
        let offset = req.offset.max(0);

        let (post_ids, total) = self
            .like_repo()
            .get_user_liked_posts(user_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get user liked posts: {e}")))?;

        Ok(Response::new(GetUserLikedPostsResponse {
            post_ids: post_ids.iter().map(|id| id.to_string()).collect(),
            total,
        }))
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

        // Always use DB count for accuracy (counter cache can become stale after deletions)
        let total = repo.get_comment_count(post_id).await.unwrap_or(0) as i32;

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

    // ========= Polls (投票榜单) =========
    async fn get_trending_polls(
        &self,
        request: Request<GetTrendingPollsRequest>,
    ) -> Result<Response<GetTrendingPollsResponse>, Status> {
        let req = request.into_inner();
        let limit = sanitize_limit(req.limit, 1, 50, 10);
        let tags = if req.tags.is_empty() {
            None
        } else {
            Some(req.tags)
        };

        let repo = self.poll_repo();
        let polls = repo
            .get_trending_polls(limit, tags)
            .await
            .map_err(|e| Status::internal(format!("Failed to get trending polls: {}", e)))?;

        // Get top candidates for each poll
        let mut summaries = Vec::with_capacity(polls.len());
        for poll in polls {
            let top_candidates = repo
                .get_top_candidates(poll.id, 3)
                .await
                .unwrap_or_default();
            summaries.push(to_proto_poll_summary(poll, top_candidates));
        }

        Ok(Response::new(GetTrendingPollsResponse { polls: summaries }))
    }

    async fn get_poll(
        &self,
        request: Request<GetPollRequest>,
    ) -> Result<Response<GetPollResponse>, Status> {
        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;

        let repo = self.poll_repo();
        let poll = repo
            .get_poll(poll_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get poll: {}", e)))?
            .ok_or_else(|| Status::not_found("Poll not found"))?;

        let candidates = if req.include_candidates {
            let candidates = repo.get_poll_candidates(poll_id).await.unwrap_or_default();
            let total_votes = poll.total_votes;
            candidates
                .into_iter()
                .enumerate()
                .map(|(idx, c)| to_proto_candidate_with_rank(c, (idx + 1) as i32, total_votes))
                .collect()
        } else {
            vec![]
        };

        // TODO: Get user's voted candidate from request context
        let my_voted_candidate_id = String::new();

        Ok(Response::new(GetPollResponse {
            poll: Some(to_proto_poll(poll)),
            candidates,
            my_voted_candidate_id,
        }))
    }

    async fn get_poll_rankings(
        &self,
        request: Request<GetPollRankingsRequest>,
    ) -> Result<Response<GetPollRankingsResponse>, Status> {
        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;
        let limit = sanitize_limit(req.limit, 1, 100, 20);
        let offset = req.offset.max(0);

        let repo = self.poll_repo();
        let (rankings, total_candidates, total_votes) = repo
            .get_rankings(poll_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get rankings: {}", e)))?;

        Ok(Response::new(GetPollRankingsResponse {
            rankings: rankings
                .into_iter()
                .map(to_proto_candidate_ranked)
                .collect(),
            total_candidates,
            total_votes,
        }))
    }

    async fn vote_on_poll(
        &self,
        request: Request<VoteOnPollRequest>,
    ) -> Result<Response<VoteOnPollResponse>, Status> {
        // Get user_id from request metadata (set by auth interceptor)
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;
        let candidate_id = parse_uuid(&req.candidate_id, "candidate_id")?;

        let repo = self.poll_repo();

        // Vote (triggers update counts automatically)
        repo.vote(poll_id, candidate_id, user_id)
            .await
            .map_err(|e| {
                if e.to_string().contains("already voted") {
                    Status::already_exists("Already voted on this poll")
                } else {
                    Status::internal(format!("Failed to vote: {}", e))
                }
            })?;

        // Get updated candidate and poll stats
        let candidate = repo
            .get_candidate(candidate_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get candidate: {}", e)))?
            .ok_or_else(|| Status::not_found("Candidate not found"))?;

        let poll = repo
            .get_poll(poll_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get poll: {}", e)))?
            .ok_or_else(|| Status::not_found("Poll not found"))?;

        Ok(Response::new(VoteOnPollResponse {
            success: true,
            updated_candidate: Some(to_proto_candidate_with_rank(candidate, 0, poll.total_votes)),
            total_votes: poll.total_votes,
        }))
    }

    async fn check_poll_voted(
        &self,
        request: Request<CheckPollVotedRequest>,
    ) -> Result<Response<CheckPollVotedResponse>, Status> {
        // Get user_id from request metadata
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;

        let repo = self.poll_repo();
        let vote = repo
            .check_voted(poll_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to check vote: {}", e)))?;

        Ok(Response::new(CheckPollVotedResponse {
            has_voted: vote.is_some(),
            voted_candidate_id: vote
                .as_ref()
                .map(|v| v.candidate_id.to_string())
                .unwrap_or_default(),
            voted_at: vote.map(|v| to_ts(v.created_at)).flatten(),
        }))
    }

    async fn create_poll(
        &self,
        request: Request<CreatePollRequest>,
    ) -> Result<Response<CreatePollResponse>, Status> {
        // Get user_id from request metadata
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();

        if req.title.is_empty() {
            return Err(Status::invalid_argument("Title is required"));
        }

        let ends_at = req.ends_at.map(|ts| {
            chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                .unwrap_or_else(chrono::Utc::now)
        });

        let initial_candidates: Vec<CreateCandidateInput> = req
            .initial_candidates
            .into_iter()
            .map(|c| CreateCandidateInput {
                name: c.name,
                avatar_url: if c.avatar_url.is_empty() {
                    None
                } else {
                    Some(c.avatar_url)
                },
                description: if c.description.is_empty() {
                    None
                } else {
                    Some(c.description)
                },
                user_id: if c.user_id.is_empty() {
                    None
                } else {
                    Uuid::parse_str(&c.user_id).ok()
                },
            })
            .collect();

        let repo = self.poll_repo();
        let (poll, candidates) = repo
            .create_poll(
                user_id,
                req.title,
                if req.description.is_empty() {
                    None
                } else {
                    Some(req.description)
                },
                if req.cover_image_url.is_empty() {
                    None
                } else {
                    Some(req.cover_image_url)
                },
                if req.poll_type.is_empty() {
                    "ranking".to_string()
                } else {
                    req.poll_type
                },
                req.tags,
                ends_at,
                initial_candidates,
            )
            .await
            .map_err(|e| Status::internal(format!("Failed to create poll: {}", e)))?;

        Ok(Response::new(CreatePollResponse {
            poll: Some(to_proto_poll(poll)),
            candidates: candidates
                .into_iter()
                .enumerate()
                .map(|(idx, c)| to_proto_candidate_with_rank(c, (idx + 1) as i32, 0))
                .collect(),
        }))
    }

    async fn unvote_poll(
        &self,
        request: Request<UnvotePollRequest>,
    ) -> Result<Response<UnvotePollResponse>, Status> {
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;

        let repo = self.poll_repo();
        let success = repo
            .unvote(poll_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to unvote: {}", e)))?;

        let poll = repo.get_poll(poll_id).await.ok().flatten();
        let total_votes = poll.map(|p| p.total_votes).unwrap_or(0);

        Ok(Response::new(UnvotePollResponse {
            success,
            total_votes,
        }))
    }

    async fn add_poll_candidate(
        &self,
        request: Request<AddPollCandidateRequest>,
    ) -> Result<Response<AddPollCandidateResponse>, Status> {
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;

        if req.name.is_empty() {
            return Err(Status::invalid_argument("Candidate name is required"));
        }

        // Check if user is poll creator
        let repo = self.poll_repo();
        let poll = repo
            .get_poll(poll_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get poll: {}", e)))?
            .ok_or_else(|| Status::not_found("Poll not found"))?;

        if poll.creator_id != user_id {
            return Err(Status::permission_denied(
                "Only poll creator can add candidates",
            ));
        }

        let candidate_user_id = if req.user_id.is_empty() {
            None
        } else {
            Some(parse_uuid(&req.user_id, "user_id")?)
        };

        let candidate = repo
            .add_candidate(
                poll_id,
                req.name,
                if req.avatar_url.is_empty() {
                    None
                } else {
                    Some(req.avatar_url)
                },
                if req.description.is_empty() {
                    None
                } else {
                    Some(req.description)
                },
                candidate_user_id,
            )
            .await
            .map_err(|e| Status::internal(format!("Failed to add candidate: {}", e)))?;

        Ok(Response::new(AddPollCandidateResponse {
            candidate: Some(to_proto_candidate_with_rank(candidate, 0, poll.total_votes)),
        }))
    }

    async fn remove_poll_candidate(
        &self,
        request: Request<RemovePollCandidateRequest>,
    ) -> Result<Response<Empty>, Status> {
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;
        let candidate_id = parse_uuid(&req.candidate_id, "candidate_id")?;

        // Check if user is poll creator
        let repo = self.poll_repo();
        let poll = repo
            .get_poll(poll_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get poll: {}", e)))?
            .ok_or_else(|| Status::not_found("Poll not found"))?;

        if poll.creator_id != user_id {
            return Err(Status::permission_denied(
                "Only poll creator can remove candidates",
            ));
        }

        repo.remove_candidate(poll_id, candidate_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to remove candidate: {}", e)))?;

        Ok(Response::new(Empty {}))
    }

    async fn close_poll(
        &self,
        request: Request<ClosePollRequest>,
    ) -> Result<Response<Empty>, Status> {
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;

        let repo = self.poll_repo();
        let closed = repo
            .close_poll(poll_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to close poll: {}", e)))?;

        if !closed {
            return Err(Status::not_found(
                "Poll not found or you don't have permission to close it",
            ));
        }

        Ok(Response::new(Empty {}))
    }

    async fn delete_poll(
        &self,
        request: Request<DeletePollRequest>,
    ) -> Result<Response<Empty>, Status> {
        let user_id = request
            .metadata()
            .get("x-user-id")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or_else(|| Status::unauthenticated("User ID required"))?;

        let req = request.into_inner();
        let poll_id = parse_uuid(&req.poll_id, "poll_id")?;

        let repo = self.poll_repo();
        let deleted = repo
            .delete_poll(poll_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete poll: {}", e)))?;

        if !deleted {
            return Err(Status::not_found(
                "Poll not found or you don't have permission to delete it",
            ));
        }

        Ok(Response::new(Empty {}))
    }

    async fn get_active_polls(
        &self,
        request: Request<GetActivePollsRequest>,
    ) -> Result<Response<GetActivePollsResponse>, Status> {
        let req = request.into_inner();
        let limit = sanitize_limit(req.limit, 1, 50, 20);
        let offset = req.offset.max(0);
        let tags = if req.tags.is_empty() {
            None
        } else {
            Some(req.tags)
        };

        let repo = self.poll_repo();
        let (polls, total) = repo
            .get_active_polls(limit, offset, tags)
            .await
            .map_err(|e| Status::internal(format!("Failed to get active polls: {}", e)))?;

        // Get top candidates for each poll
        let mut summaries = Vec::with_capacity(polls.len());
        for poll in polls {
            let top_candidates = repo
                .get_top_candidates(poll.id, 3)
                .await
                .unwrap_or_default();
            summaries.push(to_proto_poll_summary(poll, top_candidates));
        }

        Ok(Response::new(GetActivePollsResponse {
            polls: summaries,
            total,
        }))
    }

    // ========= Batch Operations (Feed Rendering Optimization) =========

    async fn batch_get_counts(
        &self,
        request: Request<BatchGetCountsRequest>,
    ) -> Result<Response<BatchGetCountsResponse>, Status> {
        let req = request.into_inner();

        // Validate input
        if req.post_ids.is_empty() {
            return Ok(Response::new(BatchGetCountsResponse {
                counts: std::collections::HashMap::new(),
            }));
        }

        if req.post_ids.len() > 100 {
            return Err(Status::invalid_argument("Maximum 100 post_ids allowed"));
        }

        // Parse UUIDs
        let post_ids: Vec<Uuid> = req
            .post_ids
            .iter()
            .map(|id| parse_uuid(id, "post_id"))
            .collect::<Result<Vec<_>, _>>()?;

        // Fetch counts from CounterService
        let counts = self
            .state
            .counter_service
            .batch_get_counts(&post_ids)
            .await
            .map_err(|e| Status::internal(format!("Failed to fetch counts: {}", e)))?;

        // Convert to proto response
        let proto_counts: std::collections::HashMap<String, PostCounts> = counts
            .into_iter()
            .map(|(post_id, counts)| {
                (
                    post_id.to_string(),
                    PostCounts {
                        like_count: counts.like_count,
                        comment_count: counts.comment_count,
                        share_count: counts.share_count,
                        bookmark_count: counts.bookmark_count,
                    },
                )
            })
            .collect();

        Ok(Response::new(BatchGetCountsResponse {
            counts: proto_counts,
        }))
    }

    // ========= Bookmarks =========

    async fn create_bookmark(
        &self,
        request: Request<CreateBookmarkRequest>,
    ) -> Result<Response<CreateBookmarkResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        let bookmark = self
            .bookmark_repo()
            .create_bookmark(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to create bookmark: {}", e)))?;

        let proto_bookmark = Bookmark {
            id: bookmark.id.to_string(),
            user_id: bookmark.user_id.to_string(),
            post_id: bookmark.post_id.to_string(),
            collection_id: bookmark
                .collection_id
                .map(|id| id.to_string())
                .unwrap_or_default(),
            bookmarked_at: to_ts(bookmark.bookmarked_at),
        };

        Ok(Response::new(CreateBookmarkResponse {
            success: true,
            bookmark: Some(proto_bookmark),
        }))
    }

    async fn delete_bookmark(
        &self,
        request: Request<DeleteBookmarkRequest>,
    ) -> Result<Response<DeleteBookmarkResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        self.bookmark_repo()
            .delete_bookmark(user_id, post_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to delete bookmark: {}", e)))?;

        Ok(Response::new(DeleteBookmarkResponse { success: true }))
    }

    async fn get_bookmarks(
        &self,
        request: Request<GetBookmarksRequest>,
    ) -> Result<Response<GetBookmarksResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let limit = sanitize_limit(req.limit, 1, 100, 50);
        let offset = req.offset.max(0);

        let post_ids = self
            .bookmark_repo()
            .get_bookmarked_post_ids(user_id, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get bookmarks: {}", e)))?;

        let total_count = self
            .bookmark_repo()
            .get_user_bookmark_count(user_id)
            .await
            .unwrap_or(0) as i32;

        Ok(Response::new(GetBookmarksResponse {
            post_ids: post_ids.into_iter().map(|id| id.to_string()).collect(),
            total_count,
        }))
    }

    async fn check_user_bookmarked(
        &self,
        request: Request<CheckUserBookmarkedRequest>,
    ) -> Result<Response<CheckUserBookmarkedResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;
        let post_id = parse_uuid(&req.post_id, "post_id")?;

        let bookmarked = self
            .bookmark_repo()
            .check_user_bookmarked(user_id, post_id)
            .await
            .unwrap_or(false);

        Ok(Response::new(CheckUserBookmarkedResponse { bookmarked }))
    }

    async fn batch_check_bookmarked(
        &self,
        request: Request<BatchCheckBookmarkedRequest>,
    ) -> Result<Response<BatchCheckBookmarkedResponse>, Status> {
        let req = request.into_inner();
        let user_id = parse_uuid(&req.user_id, "user_id")?;

        if req.post_ids.len() > 100 {
            return Err(Status::invalid_argument(
                "Maximum 100 post IDs allowed in batch",
            ));
        }

        let post_ids: Vec<Uuid> = req
            .post_ids
            .iter()
            .map(|id| parse_uuid(id, "post_id"))
            .collect::<Result<Vec<_>, _>>()?;

        let bookmarked_ids = self
            .bookmark_repo()
            .batch_check_bookmarked(user_id, &post_ids)
            .await
            .map_err(|e| Status::internal(format!("Failed to batch check bookmarks: {}", e)))?;

        Ok(Response::new(BatchCheckBookmarkedResponse {
            bookmarked_post_ids: bookmarked_ids
                .into_iter()
                .map(|id| id.to_string())
                .collect(),
        }))
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

// ========= Poll Proto Conversions =========

fn to_proto_poll(poll: PollModel) -> Poll {
    Poll {
        id: poll.id.to_string(),
        title: poll.title,
        description: poll.description.unwrap_or_default(),
        cover_image_url: poll.cover_image_url.unwrap_or_default(),
        creator_id: poll.creator_id.to_string(),
        poll_type: poll.poll_type,
        status: poll.status,
        total_votes: poll.total_votes,
        candidate_count: poll.candidate_count,
        tags: poll.tags,
        created_at: to_ts(poll.created_at),
        ends_at: poll.ends_at.and_then(to_ts),
    }
}

fn to_proto_poll_summary(
    poll: PollModel,
    top_candidates: Vec<CandidatePreviewModel>,
) -> PollSummary {
    PollSummary {
        id: poll.id.to_string(),
        title: poll.title,
        cover_image_url: poll.cover_image_url.unwrap_or_default(),
        poll_type: poll.poll_type,
        status: poll.status,
        total_votes: poll.total_votes,
        candidate_count: poll.candidate_count,
        top_candidates: top_candidates
            .into_iter()
            .map(to_proto_candidate_preview)
            .collect(),
        tags: poll.tags,
        ends_at: poll.ends_at.and_then(to_ts),
    }
}

fn to_proto_candidate_preview(preview: CandidatePreviewModel) -> social::CandidatePreview {
    social::CandidatePreview {
        id: preview.id.to_string(),
        name: preview.name,
        avatar_url: preview.avatar_url.unwrap_or_default(),
        rank: preview.rank,
    }
}

fn to_proto_candidate_with_rank(
    candidate: PollCandidateModel,
    rank: i32,
    total_votes: i64,
) -> social::PollCandidate {
    let vote_percentage = if total_votes > 0 {
        (candidate.vote_count as f64 / total_votes as f64) * 100.0
    } else {
        0.0
    };

    social::PollCandidate {
        id: candidate.id.to_string(),
        name: candidate.name,
        avatar_url: candidate.avatar_url.unwrap_or_default(),
        description: candidate.description.unwrap_or_default(),
        user_id: candidate
            .user_id
            .map(|id| id.to_string())
            .unwrap_or_default(),
        vote_count: candidate.vote_count,
        rank,
        rank_change: 0,
        vote_percentage,
    }
}

fn to_proto_candidate_ranked(ranked: CandidateWithRank) -> social::PollCandidate {
    social::PollCandidate {
        id: ranked.id.to_string(),
        name: ranked.name,
        avatar_url: ranked.avatar_url.unwrap_or_default(),
        description: ranked.description.unwrap_or_default(),
        user_id: ranked.user_id.map(|id| id.to_string()).unwrap_or_default(),
        vote_count: ranked.vote_count,
        rank: ranked.rank,
        rank_change: ranked.rank_change,
        vote_percentage: ranked.vote_percentage,
    }
}

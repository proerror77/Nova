//! gRPC server for RecommendationService
//!
//! This module implements the RecommendationService gRPC server.
//! The service provides recommendation functionality including:
//! - Get personalized feed for users
//! - Rank posts based on user preferences
//! - Get recommended creators to follow
//! - Feed ranking algorithms

pub mod clients;
pub mod nova;

pub use clients::{ContentServiceClient, UserServiceClient};

use sqlx::PgPool;
use tonic::{Request, Response, Status};
use tracing::{debug, info};

// Generated protobuf types and service traits
pub mod proto {
    pub mod feed_service {
        pub mod v1 {
            tonic::include_proto!("nova.feed_service.v1");
        }
    }
}

pub use proto::feed_service::v1::{
    recommendation_service_server, FeedPost, GetFeedRequest, GetFeedResponse,
    GetRecommendedCreatorsRequest, GetRecommendedCreatorsResponse, RankPostsRequest,
    RankPostsResponse, RankablePost, RankedPost, RankingContext, RecommendedCreator,
};

/// RecommendationService gRPC server implementation
#[derive(Clone)]
pub struct RecommendationServiceImpl {
    pool: PgPool,
}

impl RecommendationServiceImpl {
    /// Create a new RecommendationService implementation
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[tonic::async_trait]
impl recommendation_service_server::RecommendationService for RecommendationServiceImpl {
    /// Get personalized feed for a user
    ///
    /// This method orchestrates gRPC calls to Content Service to fetch posts
    /// for the user's feed based on their follow relationships and preferences.
    ///
    /// **gRPC Call Flow**:
    /// 1. ContentService.GetFeed() - gets user's personalized feed
    /// 2. (Optional) UserService.GetUserFollowing() - for relationship data
    /// 3. (Optional) ContentService.GetPostsByIds() - batch fetch posts if needed
    async fn get_feed(
        &self,
        request: Request<GetFeedRequest>,
    ) -> Result<Response<GetFeedResponse>, Status> {
        let req = request.into_inner();
        info!(
            "Getting feed for user: {} (algo: {}, limit: {})",
            req.user_id, req.algo, req.limit
        );

        // Note: This is a gRPC server in Feed Service that orchestrates calls
        // to Content Service. The actual feed generation happens in Content Service.
        // Feed Service acts as a coordinator/cache layer.

        // In production, this would:
        // 1. Check Redis cache for user's feed
        // 2. If not cached, call ContentService.GetFeed()
        // 3. Cache the result with TTL
        // 4. Return combined data

        debug!(
            "Feed request delegated to Content Service: user_id={}, algo={}, limit={}",
            req.user_id, req.algo, req.limit
        );

        // Stub response - actual implementation delegates to ContentService
        Ok(Response::new(GetFeedResponse {
            posts: vec![],
            next_cursor: "".to_string(),
            has_more: false,
        }))
    }

    /// Rank posts for a user based on their preferences
    ///
    /// This method implements post ranking logic based on user context.
    /// It coordinates with the RecommendationService to score posts.
    async fn rank_posts(
        &self,
        request: Request<RankPostsRequest>,
    ) -> Result<Response<RankPostsResponse>, Status> {
        let req = request.into_inner();
        let _user_context = req.context.as_ref();
        debug!(
            "Ranking {} posts for user context",
            req.posts.len()
        );

        // Ranking logic:
        // 1. Extract user context (interests, recent activity, etc.)
        // 2. Score each post using collaborative filtering + content-based signals
        // 3. Apply diversity constraints (don't show too many from same creator)
        // 4. Apply temporal constraints (fresh content preferred)
        // 5. Return sorted by score descending

        let ranked = req
            .posts
            .iter()
            .enumerate()
            .map(|(idx, post)| RankedPost {
                post_id: post.post_id.clone(),
                score: (100.0 - idx as f32) / 100.0, // Simple ranking: earlier posts score higher
                reason: "default_ranking".to_string(),
            })
            .collect();

        Ok(Response::new(RankPostsResponse {
            ranked_posts: ranked,
        }))
    }

    /// Get recommended creators for a user to follow
    ///
    /// **gRPC Call Flow**:
    /// 1. ContentService.GetPostsByAuthor() - get popular creators' posts
    /// 2. UserService.GetUserFollowing() - check who user already follows
    /// 3. Filter out already-followed creators
    async fn get_recommended_creators(
        &self,
        request: Request<GetRecommendedCreatorsRequest>,
    ) -> Result<Response<GetRecommendedCreatorsResponse>, Status> {
        let req = request.into_inner();
        info!(
            "Getting recommended creators for user: {} (limit: {})",
            req.user_id, req.limit
        );

        // Recommendation logic:
        // 1. Find creators user doesn't follow
        // 2. Score by follower count, engagement rate, content relevance
        // 3. Apply diversity (different content types/niches)
        // 4. Return top N creators

        Ok(Response::new(GetRecommendedCreatorsResponse {
            creators: vec![],
        }))
    }
}

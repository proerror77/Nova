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
    async fn get_feed(
        &self,
        request: Request<GetFeedRequest>,
    ) -> Result<Response<GetFeedResponse>, Status> {
        let req = request.into_inner();
        info!("Getting feed for user: {}", req.user_id);

        // TODO: Implement actual feed generation logic
        Ok(Response::new(GetFeedResponse {
            posts: vec![],
            next_cursor: "".to_string(),
            has_more: false,
        }))
    }

    async fn rank_posts(
        &self,
        request: Request<RankPostsRequest>,
    ) -> Result<Response<RankPostsResponse>, Status> {
        let req = request.into_inner();
        let _user_context = req.context.as_ref();
        debug!("Ranking {} posts", req.posts.len());

        // TODO: Implement actual post ranking logic
        Ok(Response::new(RankPostsResponse {
            ranked_posts: vec![],
        }))
    }

    async fn get_recommended_creators(
        &self,
        request: Request<GetRecommendedCreatorsRequest>,
    ) -> Result<Response<GetRecommendedCreatorsResponse>, Status> {
        let req = request.into_inner();
        info!("Getting recommended creators for user: {}", req.user_id);

        // TODO: Implement actual creator recommendation logic
        Ok(Response::new(GetRecommendedCreatorsResponse {
            creators: vec![],
        }))
    }
}

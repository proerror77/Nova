use grpc_clients::nova::content_service::v2::{
    GetPostsByIdsRequest, GetPostsByIdsResponse, GetUserPostsRequest, GetUserPostsResponse,
    ListPostsByUsersRequest, ListPostsByUsersResponse, ListRecentPostsRequest,
    ListRecentPostsResponse,
};
/// gRPC clients for calling other services (centralized)
///
/// Feed Service orchestrates data from SocialService (profiles/relations), ContentService, and GraphService
/// to generate personalized feeds without direct database queries.
use grpc_clients::{config::GrpcConfig, GrpcClientPool};
use std::sync::Arc;
use tonic::Status;
use uuid::Uuid;

/// Content Service gRPC Client
/// Provides access to posts, comments, and likes
#[derive(Clone)]
pub struct ContentServiceClient {
    pool: Arc<GrpcClientPool>,
}

impl ContentServiceClient {
    /// Create new ContentServiceClient
    pub async fn new(_addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        let cfg = GrpcConfig::from_env()?;
        let pool = GrpcClientPool::new(&cfg).await?;
        Ok(Self {
            pool: Arc::new(pool),
        })
    }

    /// Create ContentServiceClient from existing pool
    pub fn from_pool(pool: Arc<GrpcClientPool>) -> Self {
        Self { pool }
    }

    /// Get posts by IDs (batch operation to prevent N+1)
    pub async fn get_posts_by_ids(
        &self,
        request: GetPostsByIdsRequest,
    ) -> Result<GetPostsByIdsResponse, Status> {
        let mut client = self.pool.content();
        client
            .get_posts_by_ids(request)
            .await
            .map(|resp| resp.into_inner())
    }

    /// Get posts for a specific user (pagination)
    pub async fn get_user_posts(
        &self,
        request: GetUserPostsRequest,
    ) -> Result<GetUserPostsResponse, Status> {
        let mut client = self.pool.content();
        client
            .get_user_posts(request)
            .await
            .map(|resp| resp.into_inner())
    }

    /// List recent posts globally (degraded fallback for feed/recommendation)
    pub async fn list_recent_posts(
        &self,
        request: ListRecentPostsRequest,
    ) -> Result<ListRecentPostsResponse, Status> {
        let mut client = self.pool.content();
        client
            .list_recent_posts(request)
            .await
            .map(|resp| resp.into_inner())
    }

    /// List posts by multiple users with timestamp-based pagination
    /// Used for efficient feed generation with proper chronological ordering
    pub async fn list_posts_by_users(
        &self,
        request: ListPostsByUsersRequest,
    ) -> Result<ListPostsByUsersResponse, Status> {
        let mut client = self.pool.content();
        client
            .list_posts_by_users(request)
            .await
            .map(|resp| resp.into_inner())
    }
}

/// Graph Service gRPC Client (new implementation)
/// Provides access to relationship graph operations (follow/mute/block)
#[derive(Clone)]
pub struct GraphServiceClient {
    pub pool: Arc<GrpcClientPool>,
    pub enabled: bool,
}

impl GraphServiceClient {
    /// Create new GraphServiceClient
    pub async fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let cfg = GrpcConfig::from_env()?;
        let pool = GrpcClientPool::new(&cfg).await?;
        let enabled = true;

        Ok(Self {
            pool: Arc::new(pool),
            enabled,
        })
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Get suggested friends using Friends-of-Friends (FoF) algorithm via gRPC
    ///
    /// Returns list of (user_id, mutual_count) tuples
    pub async fn suggested_friends(
        &self,
        user_id: Uuid,
        limit: usize,
    ) -> Result<Vec<(Uuid, u64)>, Status> {
        use grpc_clients::nova::graph_service::v2::GetFollowingRequest;

        if !self.enabled {
            return Ok(Vec::new());
        }

        // Step 1: Get all users that the current user follows
        let following = {
            let mut client = self.pool.graph();
            let response = client
                .get_following(GetFollowingRequest {
                    user_id: user_id.to_string(),
                    limit: 1000,
                    offset: 0,
                })
                .await?
                .into_inner();

            response.user_ids
        };

        if following.is_empty() {
            return Ok(Vec::new());
        }

        // Step 2: For each followed user, get their followings (friends of friends)
        let mut fof_map: std::collections::HashMap<String, u64> = std::collections::HashMap::new();

        for followed_id in &following {
            let mut client = self.pool.graph();
            match client
                .get_following(GetFollowingRequest {
                    user_id: followed_id.clone(),
                    limit: 1000,
                    offset: 0,
                })
                .await
            {
                Ok(resp) => {
                    let fof_list = resp.into_inner().user_ids;
                    for fof_id in fof_list {
                        if fof_id != user_id.to_string() {
                            *fof_map.entry(fof_id).or_insert(0) += 1;
                        }
                    }
                }
                Err(_) => continue, // Skip on error
            }
        }

        // Step 3: Filter out users that current user already follows
        let already_following_set: std::collections::HashSet<String> =
            following.iter().cloned().collect();

        let mut candidates: Vec<(String, u64)> = fof_map
            .into_iter()
            .filter(|(uid, _)| !already_following_set.contains(uid))
            .collect();

        // Step 4: Sort by mutual count (descending) and take top N
        candidates.sort_by(|a, b| b.1.cmp(&a.1));
        candidates.truncate(limit);

        // Step 5: Convert to (Uuid, u64)
        let result = candidates
            .into_iter()
            .filter_map(|(uid_str, count)| Uuid::parse_str(&uid_str).ok().map(|uid| (uid, count)))
            .collect();

        Ok(result)
    }
}

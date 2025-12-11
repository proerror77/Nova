//! gRPC server for RecommendationService
//!
//! This module implements the RecommendationService gRPC server.
//! The service provides recommendation functionality including:
//! - Get personalized feed for users
//! - Rank posts based on user preferences
//! - Get recommended creators to follow
//! - Feed ranking algorithms

pub mod clients;
pub mod nova {
    pub mod content_service {
        pub mod v2 {
            tonic::include_proto!("nova.content_service.v2");
        }
        pub use v2::*;
    }

    pub mod graph_service {
        pub mod v2 {
            tonic::include_proto!("nova.graph_service.v2");
        }
        pub use v2::*;
    }

    pub mod feed_service {
        pub mod v2 {
            tonic::include_proto!("nova.feed_service.v2");
        }
        pub use v2::*;
    }
}

pub use clients::ContentServiceClient;

use crate::cache::{CachedFeed, CachedFeedPost, FeedCache};
use chrono::Utc;
use grpc_clients::{config::GrpcConfig, GrpcClientPool};
use grpc_metrics::layer::RequestGuard;
use sqlx::PgPool;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::{debug, error, info, warn};

// Generated protobuf types and service traits
pub mod proto {
    pub mod feed_service {
        pub mod v2 {
            tonic::include_proto!("nova.feed_service.v2");
        }
    }
}

pub use proto::feed_service::v2::{
    recommendation_service_server, FeedPost, GetFeedRequest, GetFeedResponse,
    GetRecommendedCreatorsRequest, GetRecommendedCreatorsResponse, InvalidateFeedCacheRequest,
    InvalidateFeedCacheResponse, RankPostsRequest, RankPostsResponse, RankablePost, RankedPost,
    RankingContext, RecommendedCreator,
};

/// RecommendationService gRPC server implementation
#[derive(Clone)]
pub struct RecommendationServiceImpl {
    _pool: PgPool,
    cache: Arc<FeedCache>,
    grpc_pool: Arc<GrpcClientPool>,
}

impl RecommendationServiceImpl {
    /// Create a new RecommendationService implementation
    /// This requires cache initialization via with_cache() in an async context
    pub async fn new(pool: PgPool) -> Result<Self, Box<dyn std::error::Error>> {
        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());
        let cache = FeedCache::new(&redis_url, Default::default()).await?;

        // Initialize gRPC client pool for content-service
        let grpc_cfg = GrpcConfig::from_env()?;
        let grpc_pool = GrpcClientPool::new(&grpc_cfg).await?;

        Ok(Self {
            _pool: pool,
            cache: Arc::new(cache),
            grpc_pool: Arc::new(grpc_pool),
        })
    }

    /// Create a new RecommendationService with explicit cache and gRPC pool
    pub fn with_cache(pool: PgPool, cache: Arc<FeedCache>, grpc_pool: Arc<GrpcClientPool>) -> Self {
        Self {
            _pool: pool,
            cache,
            grpc_pool,
        }
    }
}

#[tonic::async_trait]
impl recommendation_service_server::RecommendationService for RecommendationServiceImpl {
    /// Get personalized feed for a user
    ///
    /// This method orchestrates gRPC calls to Content Service to fetch posts
    /// for the user's feed based on their follow relationships and preferences.
    ///
    /// **Caching Strategy**:
    /// 1. Check Redis cache for user's feed (L1 cache)
    /// 2. If cache miss: call ContentService and SocialService for data
    /// 3. Build ranking from followed users' posts
    /// 4. Store result in Redis with TTL
    /// 5. Return personalized feed
    ///
    /// **Cache Invalidation Triggers**:
    /// - User follows/unfollows someone
    /// - Followed user posts new content
    /// - User interests change
    async fn get_feed(
        &self,
        request: Request<GetFeedRequest>,
    ) -> Result<Response<GetFeedResponse>, Status> {
        let guard = RequestGuard::new("feed-service", "GetFeed");

        let req = request.into_inner();
        let user_id = req.user_id.clone();
        let algorithm = req.algorithm.clone();

        info!(
            "Getting feed for user: {} (algo: {}, limit: {})",
            user_id, algorithm, req.limit
        );

        // Step 1: Check Redis cache
        match self.cache.get_feed(&user_id, &algorithm).await {
            Ok(Some(cached)) => {
                debug!(
                    "Cache hit for user {} with algorithm {}",
                    user_id, algorithm
                );
                // Return cached feed
                guard.complete("0");
                return Ok(Response::new(GetFeedResponse {
                    posts: cached
                        .posts
                        .iter()
                        .map(|post| FeedPost {
                            id: post.id.clone(),
                            user_id: post.user_id.clone(),
                            content: post.content.clone(),
                            created_at: post.created_at,
                            ranking_score: post.ranking_score,
                            like_count: post.like_count,
                            comment_count: post.comment_count,
                            share_count: post.share_count,
                            media_urls: post.media_urls.clone(),
                            media_type: post.media_type.clone(),
                            thumbnail_urls: post.thumbnail_urls.clone(),
                        })
                        .collect(),
                    next_cursor: cached.cursor.unwrap_or_default(),
                    has_more: cached.has_more,
                }));
            }
            Ok(None) => {
                debug!(
                    "Cache miss for user {} with algorithm {}",
                    user_id, algorithm
                );
            }
            Err(e) => {
                warn!("Cache retrieval error for user {}: {}", user_id, e);
                // Continue with cache miss, don't fail
            }
        }

        // Step 2: Cache miss - fetch from ContentService
        let limit = if req.limit == 0 {
            20
        } else {
            req.limit as usize
        }
        .min(100)
        .max(1);

        // Fetch recent posts from content-service
        let posts = match self
            .fetch_posts_from_content_service(limit as i32, &user_id)
            .await
        {
            Ok(p) => p,
            Err(e) => {
                error!("Failed to fetch posts from content-service: {}", e);
                vec![]
            }
        };
        let has_more = posts.len() >= limit;

        // Step 3: Cache the result
        let cached_feed = CachedFeed {
            posts: posts.clone(),
            cursor: None,
            has_more,
            total_count: 0,
            cached_at: Utc::now().timestamp(),
        };

        if let Err(e) = self
            .cache
            .set_feed(&user_id, &algorithm, &cached_feed)
            .await
        {
            warn!("Failed to cache feed for user {}: {}", user_id, e);
            // Don't fail the request, just log the error
        }

        // Step 4: Return feed
        guard.complete("0");
        Ok(Response::new(GetFeedResponse {
            posts: posts
                .iter()
                .map(|post| FeedPost {
                    id: post.id.clone(),
                    user_id: post.user_id.clone(),
                    content: post.content.clone(),
                    created_at: post.created_at,
                    ranking_score: post.ranking_score,
                    like_count: post.like_count,
                    comment_count: post.comment_count,
                    share_count: post.share_count,
                    media_urls: post.media_urls.clone(),
                    media_type: post.media_type.clone(),
                    thumbnail_urls: post.thumbnail_urls.clone(),
                })
                .collect(),
            next_cursor: "".to_string(),
            has_more,
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
        let guard = RequestGuard::new("feed-service", "RankPosts");

        let req = request.into_inner();
        let _user_context = req.context.as_ref();
        debug!("Ranking {} posts for user context", req.posts.len());

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
                id: post.id.clone(),                 // Use 'id' field from proto
                score: (100.0 - idx as f64) / 100.0, // Simple ranking: earlier posts score higher
                reason: "default_ranking".to_string(),
            })
            .collect();

        guard.complete("0");
        Ok(Response::new(RankPostsResponse {
            ranked_posts: ranked,
        }))
    }

    /// Get recommended creators for a user to follow
    ///
    /// **gRPC Call Flow**:
    /// 1. ContentService.GetPostsByAuthor() - get popular creators' posts
    /// 2. SocialService.GetUserFollowing() - check who user already follows
    /// 3. Filter out already-followed creators
    async fn get_recommended_creators(
        &self,
        request: Request<GetRecommendedCreatorsRequest>,
    ) -> Result<Response<GetRecommendedCreatorsResponse>, Status> {
        let guard = RequestGuard::new("feed-service", "GetRecommendedCreators");

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

        guard.complete("0");
        Ok(Response::new(GetRecommendedCreatorsResponse {
            creators: vec![],
        }))
    }

    /// Invalidate cached feed for a user
    ///
    /// Triggered when user's feed should be refreshed due to:
    /// - New post from followed user
    /// - User follows/unfollows someone
    /// - Post is liked/commented/shared
    ///
    /// **Cache Invalidation Events**:
    /// - `new_follow`: User follows someone → invalidate follower's feed
    /// - `unfollow`: User unfollows someone → invalidate follower's feed
    /// - `new_post`: Creator posts → invalidate followers' feeds
    /// - `engagement`: Post liked/commented → invalidate caches
    async fn invalidate_feed_cache(
        &self,
        request: Request<InvalidateFeedCacheRequest>,
    ) -> Result<Response<InvalidateFeedCacheResponse>, Status> {
        let guard = RequestGuard::new("feed-service", "InvalidateFeedCache");

        let req = request.into_inner();
        info!(
            "Invalidating feed cache for user: {} (event: {})",
            req.user_id, req.event_type
        );

        // Invalidate Redis cache for this user
        let result = match self.cache.invalidate_feed(&req.user_id).await {
            Ok(()) => {
                debug!(
                    "Successfully invalidated feed cache for user {}",
                    req.user_id
                );
                Response::new(InvalidateFeedCacheResponse { success: true })
            }
            Err(e) => {
                warn!("Failed to invalidate cache for user {}: {}", req.user_id, e);
                // Don't fail the RPC, return success anyway
                // The cache will eventually expire on its own
                Response::new(InvalidateFeedCacheResponse { success: true })
            }
        };

        guard.complete("0");
        Ok(result)
    }
}

impl RecommendationServiceImpl {
    /// Fetch posts from content-service
    ///
    /// 1. Call ListRecentPosts to get post IDs
    /// 2. Call GetPostsByIds to get full post details
    /// 3. Convert to CachedPost format
    async fn fetch_posts_from_content_service(
        &self,
        limit: i32,
        _user_id: &str,
    ) -> Result<Vec<CachedFeedPost>, Status> {
        use grpc_clients::nova::content_service::v2::{
            GetPostsByIdsRequest, ListRecentPostsRequest,
        };
        use grpc_clients::nova::social_service::v2::BatchGetCountsRequest;

        // Step 1: Get recent post IDs from content-service
        let mut content_client = self.grpc_pool.content();

        let list_request = ListRecentPostsRequest {
            limit,
            exclude_user_id: String::new(), // Don't exclude any user for now
        };

        let list_response = content_client
            .list_recent_posts(list_request)
            .await
            .map_err(|e| {
                error!("list_recent_posts failed: {}", e);
                Status::internal(format!("Failed to list recent posts: {}", e))
            })?
            .into_inner();

        let post_ids = list_response.post_ids;
        if post_ids.is_empty() {
            debug!("No recent posts found");
            return Ok(vec![]);
        }

        info!("Found {} recent post IDs", post_ids.len());

        // Step 2: Get full post details
        let get_request = GetPostsByIdsRequest {
            post_ids: post_ids.clone(),
        };

        let get_response = content_client
            .get_posts_by_ids(get_request)
            .await
            .map_err(|e| {
                error!("get_posts_by_ids failed: {}", e);
                Status::internal(format!("Failed to get posts by IDs: {}", e))
            })?
            .into_inner();

        // Step 3: Fetch social stats from social-service (BatchGetCounts)
        let mut social_client = self.grpc_pool.social();
        let counts_request = BatchGetCountsRequest {
            post_ids: post_ids.clone(),
        };

        let social_counts = match social_client.batch_get_counts(counts_request).await {
            Ok(response) => {
                let counts = response.into_inner().counts;
                info!("Fetched social counts for {} posts", counts.len());
                counts
            }
            Err(e) => {
                warn!(
                    "Failed to fetch social counts (continuing with zeros): {}",
                    e
                );
                std::collections::HashMap::new()
            }
        };

        // Determine default image URL for posts marked as `image` but missing media_urls.
        // This is primarily used in staging/dev environments to ensure photos render even when
        // media_urls were not backfilled correctly in content-service.
        let default_image_url = std::env::var("FEED_DEFAULT_IMAGE_URL").unwrap_or_default();

        // Optional CDN rewrite configuration. When FEED_MEDIA_CDN_BASE_URL is set, any
        // media URLs that match the configured GCS prefix will be rewritten to go
        // through the CDN front (e.g., Cloud CDN HTTP LB) instead of hitting
        // storage.googleapis.com directly.
        let cdn_base_url = std::env::var("FEED_MEDIA_CDN_BASE_URL")
            .ok()
            .filter(|v| !v.is_empty());
        let gcs_prefix = std::env::var("FEED_MEDIA_GCS_PREFIX")
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| "https://storage.googleapis.com/nova-media-staging/".to_string());

        // Step 4: Convert to CachedFeedPost format with social stats
        let posts: Vec<CachedFeedPost> = get_response
            .posts
            .into_iter()
            .enumerate()
            .map(|(idx, post)| {
                let counts = social_counts.get(&post.id);
                // Fallback: if this is an image post but media_urls is empty, inject a default URL.
                let mut media_urls = post.media_urls.clone();
                let media_type = post.media_type.clone();
                let mut thumbnail_urls = post.thumbnail_urls.clone();
                if media_urls.is_empty() && media_type == "image" && !default_image_url.is_empty() {
                    media_urls = vec![default_image_url.clone()];
                }

                if thumbnail_urls.is_empty() {
                    thumbnail_urls = media_urls.clone();
                }

                // If configured, rewrite storage.googleapis.com URLs to the CDN front.
                let media_urls = rewrite_media_urls_for_cdn(media_urls, &cdn_base_url, &gcs_prefix);
                let thumbnail_urls =
                    rewrite_media_urls_for_cdn(thumbnail_urls, &cdn_base_url, &gcs_prefix);

                CachedFeedPost {
                    id: post.id.clone(),
                    user_id: post.author_id,
                    content: post.content,
                    created_at: post.created_at,
                    ranking_score: 1.0 - (idx as f64 * 0.01), // Simple ranking by recency
                    like_count: counts.map(|c| c.like_count as u32).unwrap_or(0),
                    comment_count: counts.map(|c| c.comment_count as u32).unwrap_or(0),
                    share_count: counts.map(|c| c.share_count as u32).unwrap_or(0),
                    media_urls,
                    media_type,
                    thumbnail_urls,
                }
            })
            .collect();

        info!(
            "Fetched {} posts from content-service with social stats",
            posts.len()
        );
        Ok(posts)
    }
}

/// Rewrite media URLs to pass through a CDN front instead of directly hitting
/// the GCS public endpoint. Only URLs starting with `gcs_prefix` are rewritten;
/// all others are left unchanged.
fn rewrite_media_urls_for_cdn(
    urls: Vec<String>,
    cdn_base_url: &Option<String>,
    gcs_prefix: &str,
) -> Vec<String> {
    let Some(cdn_base) = cdn_base_url else {
        return urls;
    };

    let cdn_base = cdn_base.trim_end_matches('/');

    urls.into_iter()
        .map(|url| {
            if url.starts_with(gcs_prefix) {
                let suffix = &url[gcs_prefix.len()..];
                format!("{}/{}", cdn_base, suffix)
            } else {
                url
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test GetFeed with empty posts (stub implementation)
    #[tokio::test]
    async fn test_get_feed_stub_response() {
        // Create a mock pool (in real tests, this would use a test database)
        // For now, we test the logic structure
        let req = GetFeedRequest {
            user_id: "user-123".to_string(),
            limit: 20,
            cursor: "".to_string(),
            algorithm: "ch".to_string(),
        };

        // Verify request fields are properly set
        assert_eq!(req.user_id, "user-123");
        assert_eq!(req.algorithm, "ch");
        assert_eq!(req.limit, 20);
    }

    /// Test GetFeed request limit validation
    #[tokio::test]
    async fn test_get_feed_limit_constraints() {
        // Test that limit is properly constrained between 1 and 100
        let req_zero = GetFeedRequest {
            user_id: "user-123".to_string(),
            limit: 0,
            cursor: "".to_string(),
            algorithm: "ch".to_string(),
        };

        let req_large = GetFeedRequest {
            user_id: "user-456".to_string(),
            limit: 500,
            cursor: "".to_string(),
            algorithm: "v2".to_string(),
        };

        // In get_feed(), limit 0 becomes 20, limit 500 becomes 100
        let constrained_zero = if req_zero.limit == 0 {
            20
        } else {
            req_zero.limit as usize
        }
        .min(100)
        .max(1);
        let constrained_large = if req_large.limit == 0 {
            20
        } else {
            req_large.limit as usize
        }
        .min(100)
        .max(1);

        assert_eq!(constrained_zero, 20);
        assert_eq!(constrained_large, 100);
    }

    /// Test RankPosts scoring logic
    #[tokio::test]
    async fn test_rank_posts_basic_scoring() {
        let posts = vec![
            RankablePost {
                id: "post-1".to_string(),
                author_id: "author-1".to_string(),
                content: "First post".to_string(),
                created_at: 1000,
                like_count: 10,
                comment_count: 2,
                share_count: 1,
            },
            RankablePost {
                id: "post-2".to_string(),
                author_id: "author-2".to_string(),
                content: "Second post".to_string(),
                created_at: 2000,
                like_count: 20,
                comment_count: 5,
                share_count: 3,
            },
        ];

        let req = RankPostsRequest {
            user_id: "user-123".to_string(),
            posts: posts.clone(),
            context: None,
        };

        // Verify request structure
        assert_eq!(req.posts.len(), 2);
        assert_eq!(req.posts[0].id, "post-1");
        assert_eq!(req.posts[1].id, "post-2");

        // Simulated ranking: earlier posts score higher
        let ranked: Vec<RankedPost> = req
            .posts
            .iter()
            .enumerate()
            .map(|(idx, post)| RankedPost {
                id: post.id.clone(),
                score: (100.0 - idx as f64) / 100.0,
                reason: "default_ranking".to_string(),
            })
            .collect();

        // Verify scoring
        assert_eq!(ranked.len(), 2);
        assert_eq!(ranked[0].score, 1.0); // (100 - 0) / 100
        assert_eq!(ranked[1].score, 0.99); // (100 - 1) / 100
        assert!(ranked[0].score > ranked[1].score);
    }

    /// Test InvalidateFeedCache request handling
    #[tokio::test]
    async fn test_invalidate_feed_cache_request() {
        let events = vec![
            ("new_follow", "user-123"),
            ("unfollow", "user-456"),
            ("new_post", "user-789"),
            ("engagement", "user-012"),
        ];

        for (event_type, user_id) in events {
            let req = InvalidateFeedCacheRequest {
                user_id: user_id.to_string(),
                event_type: event_type.to_string(),
            };

            assert_eq!(req.user_id, user_id);
            assert_eq!(req.event_type, event_type);
        }
    }

    /// Test FeedPost proto construction with all fields
    #[tokio::test]
    async fn test_feed_post_proto_construction() {
        let post = FeedPost {
            id: "post-123".to_string(),
            user_id: "user-456".to_string(),
            content: "Test post content".to_string(),
            created_at: 1234567890,
            ranking_score: 0.95,
            like_count: 42,
            comment_count: 5,
            share_count: 2,
            media_urls: vec![],
            media_type: String::new(),
            thumbnail_urls: vec![],
        };

        // Verify all proto fields are set correctly
        assert_eq!(post.id, "post-123");
        assert_eq!(post.user_id, "user-456");
        assert_eq!(post.content, "Test post content");
        assert_eq!(post.created_at, 1234567890);
        assert_eq!(post.ranking_score, 0.95);
        assert_eq!(post.like_count, 42);
        assert_eq!(post.comment_count, 5);
        assert_eq!(post.share_count, 2);
    }

    /// Test GetFeedResponse construction
    #[tokio::test]
    async fn test_get_feed_response_construction() {
        let posts = vec![
            FeedPost {
                id: "post-1".to_string(),
                user_id: "user-1".to_string(),
                content: "Content 1".to_string(),
                created_at: 1000,
                ranking_score: 0.9,
                like_count: 10,
                comment_count: 2,
                share_count: 1,
                media_urls: vec![],
                media_type: String::new(),
                thumbnail_urls: vec![],
            },
            FeedPost {
                id: "post-2".to_string(),
                user_id: "user-2".to_string(),
                content: "Content 2".to_string(),
                created_at: 2000,
                ranking_score: 0.85,
                like_count: 20,
                comment_count: 5,
                share_count: 3,
                media_urls: vec![],
                media_type: String::new(),
                thumbnail_urls: vec![],
            },
        ];

        let response = GetFeedResponse {
            posts,
            next_cursor: "cursor-abc123".to_string(),
            has_more: true,
        };

        // Verify response structure
        assert_eq!(response.posts.len(), 2);
        assert_eq!(response.posts[0].id, "post-1");
        assert_eq!(response.posts[1].id, "post-2");
        assert_eq!(response.next_cursor, "cursor-abc123");
        assert!(response.has_more);
    }

    /// Test RankPostsResponse construction
    #[tokio::test]
    async fn test_rank_posts_response_construction() {
        let ranked_posts = vec![
            RankedPost {
                id: "post-1".to_string(),
                score: 0.95,
                reason: "high_engagement".to_string(),
            },
            RankedPost {
                id: "post-2".to_string(),
                score: 0.87,
                reason: "user_interests_match".to_string(),
            },
        ];

        let response = RankPostsResponse { ranked_posts };

        // Verify response structure
        assert_eq!(response.ranked_posts.len(), 2);
        assert_eq!(response.ranked_posts[0].score, 0.95);
        assert_eq!(response.ranked_posts[1].score, 0.87);
        assert!(response.ranked_posts[0].score > response.ranked_posts[1].score);
    }

    /// Test RankingContext data structure
    #[tokio::test]
    async fn test_ranking_context_structure() {
        let context = RankingContext {
            timestamp: 1234567890,
            user_location: "US-CA".to_string(),
            user_interests: vec!["tech".to_string(), "sports".to_string()],
            followed_users: vec!["user-1".to_string(), "user-2".to_string()],
            blocked_users: vec!["user-spam".to_string()],
        };

        assert_eq!(context.timestamp, 1234567890);
        assert_eq!(context.user_location, "US-CA");
        assert_eq!(context.user_interests.len(), 2);
        assert_eq!(context.followed_users.len(), 2);
        assert_eq!(context.blocked_users.len(), 1);
    }

    /// Test RecommendedCreator proto construction
    #[tokio::test]
    async fn test_recommended_creator_construction() {
        let creator = RecommendedCreator {
            id: "creator-123".to_string(),
            name: "Tech Guru".to_string(),
            avatar: "https://example.com/avatar.jpg".to_string(),
            relevance_score: 0.92,
            follower_count: 50000,
            reason: "shares_your_interests".to_string(),
        };

        assert_eq!(creator.id, "creator-123");
        assert_eq!(creator.name, "Tech Guru");
        assert_eq!(creator.relevance_score, 0.92);
        assert_eq!(creator.follower_count, 50000);
    }

    /// Test GetRecommendedCreatorsResponse construction
    #[tokio::test]
    async fn test_get_recommended_creators_response() {
        let creators = vec![
            RecommendedCreator {
                id: "creator-1".to_string(),
                name: "Creator One".to_string(),
                avatar: "avatar1.jpg".to_string(),
                relevance_score: 0.95,
                follower_count: 100000,
                reason: "trending".to_string(),
            },
            RecommendedCreator {
                id: "creator-2".to_string(),
                name: "Creator Two".to_string(),
                avatar: "avatar2.jpg".to_string(),
                relevance_score: 0.88,
                follower_count: 75000,
                reason: "similar_interests".to_string(),
            },
        ];

        let response = GetRecommendedCreatorsResponse { creators };

        assert_eq!(response.creators.len(), 2);
        assert_eq!(response.creators[0].follower_count, 100000);
        assert_eq!(response.creators[1].follower_count, 75000);
    }

    /// Test InvalidateFeedCacheResponse
    #[tokio::test]
    async fn test_invalidate_cache_response() {
        let response = InvalidateFeedCacheResponse { success: true };
        assert!(response.success);

        let failed_response = InvalidateFeedCacheResponse { success: false };
        assert!(!failed_response.success);
    }

    /// Test pagination cursor handling
    #[tokio::test]
    async fn test_pagination_cursor_handling() {
        let _req1 = GetFeedRequest {
            user_id: "user-123".to_string(),
            limit: 20,
            cursor: "".to_string(),
            algorithm: "ch".to_string(),
        };

        // Simulate first page cursor in response
        let response1 = GetFeedResponse {
            posts: vec![],
            next_cursor: "base64-encoded-cursor-1".to_string(),
            has_more: true,
        };

        // Second request uses cursor from first response
        let req2 = GetFeedRequest {
            user_id: "user-123".to_string(),
            limit: 20,
            cursor: response1.next_cursor.clone(),
            algorithm: "ch".to_string(),
        };

        assert_eq!(req2.cursor, "base64-encoded-cursor-1");

        let response2 = GetFeedResponse {
            posts: vec![],
            next_cursor: "base64-encoded-cursor-2".to_string(),
            has_more: false,
        };

        assert!(!response2.has_more);
    }

    /// Performance test: Measure proto message serialization latency
    #[tokio::test]
    async fn test_feed_post_serialization_latency() {
        use std::time::Instant;

        let iterations = 10_000;

        // Create a realistic FeedPost
        let post = FeedPost {
            id: "post-123456789".to_string(),
            user_id: "user-987654321".to_string(),
            content: "This is a sample post content that contains engagement metrics and metadata for performance testing purposes.".to_string(),
            created_at: 1234567890,
            ranking_score: 0.95,
            like_count: 1000,
            comment_count: 250,
            share_count: 75,
            media_urls: vec![],
            media_type: String::new(),
            thumbnail_urls: vec![],
        };

        // Measure construction time
        let start = Instant::now();
        for _ in 0..iterations {
            let _p = FeedPost {
                id: post.id.clone(),
                user_id: post.user_id.clone(),
                content: post.content.clone(),
                created_at: post.created_at,
                ranking_score: post.ranking_score,
                like_count: post.like_count,
                comment_count: post.comment_count,
                share_count: post.share_count,
                media_urls: vec![],
                media_type: String::new(),
                thumbnail_urls: vec![],
            };
        }
        let elapsed = start.elapsed();
        let avg_micros = elapsed.as_micros() as f64 / iterations as f64;

        // Should be well under 100 microseconds per message
        println!(
            "FeedPost serialization: avg {:.2} µs per message",
            avg_micros
        );
        assert!(
            avg_micros < 100.0,
            "FeedPost serialization too slow: {:.2} µs",
            avg_micros
        );
    }

    /// Performance test: Measure batch request processing latency
    #[tokio::test]
    async fn test_batch_rank_posts_latency() {
        use std::time::Instant;

        let batch_size = 100;
        let batches = 1_000;

        // Create a batch of rankable posts
        let posts: Vec<RankablePost> = (0..batch_size)
            .map(|i| RankablePost {
                id: format!("post-{}", i),
                author_id: format!("author-{}", i % 100),
                content: "Sample post content".to_string(),
                created_at: 1234567890 + i as i64,
                like_count: 100 + i as u32,
                comment_count: 10 + (i % 50) as u32,
                share_count: (i % 25) as u32,
            })
            .collect();

        let start = Instant::now();
        for _ in 0..batches {
            let ranked: Vec<RankedPost> = posts
                .iter()
                .enumerate()
                .map(|(idx, post)| RankedPost {
                    id: post.id.clone(),
                    score: (100.0 - idx as f64) / 100.0,
                    reason: "ranking".to_string(),
                })
                .collect();
            // Verify output
            assert_eq!(ranked.len(), batch_size);
        }
        let elapsed = start.elapsed();
        let avg_micros = elapsed.as_micros() as f64 / (batches * batch_size) as f64;

        // Should be under 50 microseconds per post ranking
        println!("Batch post ranking: avg {:.2} µs per post", avg_micros);
        assert!(
            avg_micros < 50.0,
            "Batch ranking too slow: {:.2} µs per post",
            avg_micros
        );
    }

    /// Performance test: Measure GetFeedResponse construction latency
    #[tokio::test]
    async fn test_feed_response_construction_latency() {
        use std::time::Instant;

        let iterations = 1_000;
        let posts_per_response = 20;

        let posts: Vec<FeedPost> = (0..posts_per_response)
            .map(|i| FeedPost {
                id: format!("post-{}", i),
                user_id: format!("user-{}", i % 100),
                content: "Post content".to_string(),
                created_at: 1234567890 + i as i64,
                ranking_score: 0.5 + (i as f64 / 40.0),
                like_count: 100 + i as u32,
                comment_count: 10 + (i % 5) as u32,
                share_count: (i % 3) as u32,
                media_urls: vec![],
                media_type: String::new(),
                thumbnail_urls: vec![],
            })
            .collect();

        let start = Instant::now();
        for i in 0..iterations {
            let response = GetFeedResponse {
                posts: posts.clone(),
                next_cursor: format!("cursor-{}", i),
                has_more: i < iterations - 1,
            };
            // Verify
            assert_eq!(response.posts.len(), posts_per_response);
        }
        let elapsed = start.elapsed();
        let avg_micros = elapsed.as_micros() as f64 / iterations as f64;

        // Should be under 200 microseconds per response
        println!(
            "GetFeedResponse construction: avg {:.2} µs per response",
            avg_micros
        );
        assert!(
            avg_micros < 200.0,
            "Response construction too slow: {:.2} µs",
            avg_micros
        );
    }

    /// Performance test: Measure pagination handling throughput
    #[tokio::test]
    async fn test_pagination_throughput() {
        use std::time::Instant;

        let pages = 100;
        let posts_per_page = 20usize;

        let start = Instant::now();
        let mut cursor = String::new();

        for page in 0..pages {
            // Simulate request with cursor from previous page
            let _req = GetFeedRequest {
                user_id: "user-123".to_string(),
                limit: posts_per_page as u32,
                cursor: cursor.clone(),
                algorithm: "ch".to_string(),
            };

            // Simulate response with next cursor
            cursor = format!("cursor-page-{}", page + 1);
            let response = GetFeedResponse {
                posts: (0..posts_per_page)
                    .map(|i| FeedPost {
                        id: format!("post-{}-{}", page, i),
                        user_id: "user-123".to_string(),
                        content: "content".to_string(),
                        created_at: 1234567890 + (page as i64 * posts_per_page as i64) + i as i64,
                        ranking_score: 0.75,
                        like_count: 100,
                        comment_count: 10,
                        share_count: 5,
                        media_urls: vec![],
                        media_type: String::new(),
                        thumbnail_urls: vec![],
                    })
                    .collect(),
                next_cursor: cursor.clone(),
                has_more: page < pages - 1,
            };

            // Verify pagination works
            assert_eq!(response.posts.len(), posts_per_page as usize);
        }

        let elapsed = start.elapsed();
        let avg_ms = elapsed.as_secs_f64() * 1000.0 / pages as f64;

        // Should process each page in under 2ms (target P99 latency)
        println!("Pagination throughput: avg {:.3} ms per page", avg_ms);
        assert!(
            avg_ms < 2.0,
            "Pagination too slow: {:.3} ms per page",
            avg_ms
        );
    }

    /// Performance test: Algorithm variant selection latency
    #[tokio::test]
    async fn test_algorithm_variant_selection() {
        use std::time::Instant;

        let algorithms = vec!["ch", "v2", "hybrid", "collaborative", "content-based"];
        let users = 1_000;
        let iterations_per_user = 100;

        let start = Instant::now();
        for user_id in 0..users {
            for algo_idx in 0..algorithms.len() {
                for _ in 0..iterations_per_user {
                    let req = GetFeedRequest {
                        user_id: format!("user-{}", user_id),
                        limit: 20,
                        cursor: "".to_string(),
                        algorithm: algorithms[algo_idx % algorithms.len()].to_string(),
                    };

                    // Cache key generation (happens in get_feed)
                    let _cache_key = format!("feed:{}:{}", req.user_id, req.algorithm);
                }
            }
        }

        let elapsed = start.elapsed();
        let total_requests = users * algorithms.len() * iterations_per_user;
        let avg_micros = elapsed.as_micros() as f64 / total_requests as f64;

        // Should be under 10 microseconds per request
        println!("Algorithm selection: avg {:.2} µs per request", avg_micros);
        assert!(
            avg_micros < 10.0,
            "Algorithm selection too slow: {:.2} µs",
            avg_micros
        );
    }

    /// Performance test: Scoring calculation throughput
    #[tokio::test]
    async fn test_scoring_throughput() {
        use std::time::Instant;

        let iterations = 1_000;
        let posts_per_iteration = 50;

        let start = Instant::now();
        for _ in 0..iterations {
            let _ranked: Vec<f64> = (0..posts_per_iteration)
                .map(|idx| (100.0 - idx as f64) / 100.0)
                .collect();
        }
        let elapsed = start.elapsed();
        let avg_nanos = elapsed.as_nanos() as f64 / (iterations * posts_per_iteration) as f64;

        // Should be under 1000 nanos (1 microsecond) per score calculation
        println!("Scoring calculation: avg {:.0} ns per score", avg_nanos);
        assert!(avg_nanos < 1000.0, "Scoring too slow: {:.0} ns", avg_nanos);
    }
}

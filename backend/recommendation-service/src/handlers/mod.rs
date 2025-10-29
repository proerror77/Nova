pub mod discover;
pub mod feed;
pub mod recommendation;
pub mod trending;

// Re-export handlers for convenience
pub use discover::{get_suggested_users, DiscoverHandlerState, SuggestedUsersResponse, UserWithScore};
pub use feed::{get_feed, invalidate_feed_cache, FeedHandlerState, FeedQueryParams};
pub use recommendation::{
    get_recommendations, get_model_info, rank_candidates, RecommendationHandlerState,
    RecommendationQuery, RankingRequest, RecommendationResponse, ModelInfoResponse,
    RankingResponse, RankedPostResponse,
};
pub use trending::{
    get_trending, get_trending_categories, get_trending_posts, get_trending_streams,
    get_trending_videos, record_engagement, EngagementRequest, TrendingHandlerState, TrendingQuery,
};

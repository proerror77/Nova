pub mod discover;
pub mod feed;
pub mod recommendation;
pub mod trending;

// Re-export handlers for convenience
pub use discover::{
    get_suggested_users, DiscoverHandlerState, SuggestedUsersResponse, UserWithScore,
};
pub use feed::{get_feed, FeedHandlerState, FeedQueryParams};
pub use recommendation::{
    get_model_info, get_recommendations, rank_candidates, semantic_search, ModelInfoResponse,
    RankedPostResponse, RankingRequest, RankingResponse, RecommendationHandlerState,
    RecommendationQuery, RecommendationResponse, SemanticSearchRequest, SemanticSearchResponse,
    SemanticSearchResult,
};
pub use trending::{
    get_trending, get_trending_categories, get_trending_posts, get_trending_streams,
    get_trending_videos, record_engagement, EngagementRequest, TrendingHandlerState, TrendingQuery,
};

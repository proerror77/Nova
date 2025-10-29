pub mod discover;
pub mod feed;
pub mod trending;

// Re-export handlers for convenience
pub use discover::{get_suggested_users, DiscoverHandlerState, SuggestedUsersResponse, UserWithScore};
pub use feed::{get_feed, invalidate_feed_cache, FeedHandlerState, FeedQueryParams};
pub use trending::{
    get_trending, get_trending_categories, get_trending_posts, get_trending_streams,
    get_trending_videos, record_engagement, EngagementRequest, TrendingHandlerState, TrendingQuery,
};

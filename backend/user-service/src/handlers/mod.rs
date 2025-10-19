pub mod auth;
pub mod events;
pub mod feed;
pub mod health;
pub mod jwks;
pub mod oauth;
pub mod password_reset;
pub mod posts;
pub mod reels;
pub mod videos;

pub use auth::*;
pub use events::*;
pub use feed::*;
pub use health::*;
pub use jwks::*;
pub use oauth::*;
pub use password_reset::*;
pub use posts::*;
pub use videos::*;

// Reels module - selective export to avoid naming conflicts with feed module
pub use reels::{
    get_feed as reels_get_feed,
    get_video_stream,
    get_processing_status,
    like_video,
    watch_video,
    share_video,
    get_trending_sounds,
    get_trending_hashtags,
    search_videos,
    get_similar_videos,
    get_recommended_creators,
};

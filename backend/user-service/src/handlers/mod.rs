pub mod auth;
pub mod comments;
pub mod discover;
pub mod events;
pub mod experiments;
pub mod feed;
pub mod health;
pub mod jwks;
pub mod likes;
pub mod relationships;
// pub mod messaging; // REMOVED - moved to messaging-service (port 8085)
pub mod moderation;
pub mod oauth;
pub mod password_reset;
pub mod posts;
pub mod reels; // Phase 2: Reels functionality enabled
pub mod stories;
pub mod streams;
pub mod streams_ws;
pub mod transcoding_progress;
pub mod transcoding_queue;
pub mod trending;
pub mod uploads; // Resumable upload handlers
pub mod users; // Public user profile endpoints (minimal)
pub mod videos; // Enable basic Video handlers
pub mod videos_admin; // Admin utilities for video/Milvus

pub use auth::*;
pub use comments::*;
pub use discover::*;
pub use events::*;
pub use feed::*;
pub use health::*;
pub use jwks::*;
pub use likes::*;
pub use relationships::*;
// pub use messaging::*; // REMOVED - moved to messaging-service
pub use moderation::*;
pub use oauth::*;
pub use password_reset::*;
pub use posts::*;
// Reels: selective exports to avoid conflicts with feed/videos/trending modules
pub use reels::{
    get_feed as get_reels_feed, get_processing_status as get_reels_progress,
    get_recommended_creators, get_similar_videos as get_similar_reels, get_trending_hashtags,
    get_trending_sounds, get_video_stream as get_reels_stream, like_video as like_reel,
    search_videos as search_reels, share_video as share_reel, watch_video as record_reel_watch,
};
pub use stories::*;
pub use streams::*;
pub use streams_ws::*;
pub use transcoding_progress::*;
pub use transcoding_queue::*;
pub use trending::*;
pub use uploads::*; // Resumable upload handlers
pub use users::*;
pub use videos::*; // Enable basic Video handlers
pub use videos_admin::*;

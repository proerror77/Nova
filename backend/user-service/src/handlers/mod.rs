// pub mod auth; // REMOVED - moved to auth-service (port 8084) [DELETED]
// pub mod comments; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub mod discover; // REMOVED - moved to feed-service (port 8089) [DELETED]
pub mod events;
// pub mod experiments; // REMOVED - moved to feed-service (port 8089) [DELETED]
// pub mod feed; // REMOVED - moved to feed-service (port 8089) [DELETED]
pub mod health;
// pub mod likes; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub mod relationships; // REMOVED - moved to graph-service (port 9080) [DELETED]
// pub mod messaging; // REMOVED - moved to messaging-service (port 8085) [DELETED]
pub mod moderation;
// pub mod oauth; // REMOVED - moved to auth-service (port 8084) [DELETED]
// pub mod password_reset; // REMOVED - moved to auth-service (port 8084) [DELETED]
pub mod preferences;
// pub mod posts; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub mod reels; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod stories; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub mod streams; // REMOVED - moved to streaming-service (port 8088) [DELETED]
// pub mod streams_ws; // REMOVED - moved to streaming-service (port 8088) [DELETED]
// pub mod transcoding_progress; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod transcoding_queue; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub mod trending; // REMOVED - moved to feed-service (port 8089) [DELETED]
// pub mod uploads; // REMOVED - moved to media-service (port 8082) [DELETED]
pub mod users; // Public user profile endpoints (minimal)
               // pub mod videos; // REMOVED - moved to media-service (port 8082) [DELETED]
               // pub mod videos_admin; // REMOVED - moved to media-service (port 8082) [DELETED]

// pub use auth::*; // REMOVED - moved to auth-service (port 8084) [DELETED]
// pub use comments::*; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub use discover::*; // REMOVED - moved to feed-service (port 8089) [DELETED]
pub use events::*;
// pub use feed::*; // REMOVED - moved to feed-service (port 8089) [DELETED]
pub use health::*;
// pub use likes::*; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub use relationships::*; // REMOVED - moved to graph-service (port 9080) [DELETED]
// pub use messaging::*; // REMOVED - moved to messaging-service (port 8085) [DELETED]
pub use moderation::*;
// pub use oauth::*; // REMOVED - moved to auth-service (port 8084) [DELETED]
// pub use password_reset::*; // REMOVED - moved to auth-service (port 8084) [DELETED]
// Re-export from preferences (including block_user and unblock_user which should call graph-service)
pub use preferences::{block_user, get_feed_preferences, unblock_user, update_feed_preferences};
// pub use posts::*; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub use stories::*; // REMOVED - moved to content-service (port 8081) [DELETED]
// pub use streams::*; // REMOVED - moved to streaming-service (port 8088) [DELETED]
// pub use streams_ws::*; // REMOVED - moved to streaming-service (port 8088) [DELETED]
// pub use transcoding_progress::*; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub use transcoding_queue::*; // REMOVED - moved to media-service (port 8082) [DELETED]
// pub use trending::*; // REMOVED - moved to feed-service (port 8089) [DELETED]
pub use users::*;

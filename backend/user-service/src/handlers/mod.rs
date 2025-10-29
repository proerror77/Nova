pub mod auth;
// pub mod comments; // REMOVED - moved to content-service (port 8081)
pub mod discover;
pub mod events;
pub mod experiments;
pub mod feed;
pub mod health;
pub mod jwks;
// pub mod likes; // REMOVED - moved to content-service (port 8081)
pub mod relationships;
// pub mod messaging; // REMOVED - moved to messaging-service (port 8085)
pub mod moderation;
pub mod oauth;
pub mod password_reset;
pub mod preferences;
// pub mod posts; // REMOVED - moved to content-service (port 8081)
// pub mod reels; // REMOVED - moved to media-service (port 8082)
// pub mod stories; // REMOVED - moved to content-service (port 8081)
pub mod streams;
pub mod streams_ws;
pub mod transcoding_progress;
pub mod transcoding_queue;
pub mod trending;
// pub mod uploads; // REMOVED - moved to media-service (port 8082)
pub mod users; // Public user profile endpoints (minimal)
               // pub mod videos; // REMOVED - moved to media-service (port 8082)
               // pub mod videos_admin; // REMOVED - moved to media-service (port 8082)

pub use auth::*;
// pub use comments::*; // REMOVED - moved to content-service (port 8081)
pub use discover::*;
pub use events::*;
pub use feed::*;
pub use health::*;
pub use jwks::*;
// pub use likes::*; // REMOVED - moved to content-service (port 8081)
pub use relationships::*;
// pub use messaging::*; // REMOVED - moved to messaging-service
pub use moderation::*;
pub use oauth::*;
pub use password_reset::*;
pub use preferences::*;
// pub use posts::*; // REMOVED - moved to content-service (port 8081)
// Comments, likes, posts, stories, reels, uploads, videos, videos_admin REMOVED (see port assignments above)
// pub use stories::*; // REMOVED - moved to content-service (port 8081)
pub use streams::*;
pub use streams_ws::*;
pub use transcoding_progress::*;
pub use transcoding_queue::*;
pub use trending::*;
pub use users::*;

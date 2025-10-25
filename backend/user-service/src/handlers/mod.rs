pub mod auth;
pub mod comments;
pub mod discover;
pub mod experiments;
pub mod likes;
pub mod relationships;
pub mod events;
pub mod feed;
pub mod health;
pub mod jwks;
// pub mod messaging; // REMOVED - moved to messaging-service (port 8085)
pub mod oauth;
pub mod password_reset;
pub mod posts;
pub mod stories;
pub mod streams;
pub mod streams_ws;
pub mod transcoding_progress;
pub mod transcoding_queue;
pub mod trending;
pub mod uploads; // Resumable upload handlers
// pub mod reels;     // TODO: Phase 2 - needs VideoService implementation
pub mod users; // Public user profile endpoints (minimal)
pub mod videos; // Enable basic Video handlers
pub mod videos_admin; // Admin utilities for video/Milvus

pub use auth::*;
pub use comments::*;
pub use discover::*;
pub use likes::*;
pub use relationships::*;
pub use events::*;
pub use feed::*;
pub use health::*;
pub use jwks::*;
// pub use messaging::*; // REMOVED - moved to messaging-service
pub use oauth::*;
pub use password_reset::*;
pub use posts::*;
pub use stories::*;
pub use streams::*;
pub use streams_ws::*;
pub use transcoding_progress::*;
pub use transcoding_queue::*;
pub use trending::*;
pub use uploads::*; // Resumable upload handlers
// pub use reels::*;  // Disabled - Phase 2 pending
pub use users::*;
pub use videos::*; // Enable basic Video handlers
pub use videos_admin::*;

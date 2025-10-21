pub mod auth;
pub mod events;
pub mod feed;
pub mod health;
pub mod jwks;
pub mod messaging;
pub mod oauth;
pub mod password_reset;
pub mod posts;
pub mod social;
pub mod streaming_websocket;

pub use auth::*;
pub use events::*;
pub use feed::*;
pub use health::*;
pub use jwks::*;
pub use messaging::*;
pub use oauth::*;
pub use password_reset::*;
pub use posts::*;
pub use social::*;
pub use streaming_websocket::*;

// Phase 6+ Handlers (not yet implemented)
// - discover: Video discovery and recommendations (requires VideoService)
// - reels: Short-form video handler (requires VideoService)
// - videos: Full video management (requires VideoService)
//
// See GitHub Issue #T141 for Phase 6 Video System roadmap

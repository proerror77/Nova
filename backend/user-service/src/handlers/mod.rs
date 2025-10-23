pub mod auth;
// pub mod discover;  // TODO: Phase 2 - needs VideoService implementation
pub mod events;
pub mod feed;
pub mod health;
pub mod jwks;
pub mod oauth;
pub mod password_reset;
pub mod posts;
pub mod messaging;
pub mod stories;
// pub mod reels;     // TODO: Phase 2 - needs VideoService implementation
pub mod videos;    // Enable basic Video handlers
pub mod users;     // Public user profile endpoints (minimal)

pub use auth::*;
// pub use discover::*;  // Disabled - Phase 2 pending
pub use events::*;
pub use feed::*;
pub use health::*;
pub use jwks::*;
pub use oauth::*;
pub use password_reset::*;
pub use posts::*;
pub use messaging::*;
pub use stories::*;
// pub use reels::*;  // Disabled - Phase 2 pending
pub use videos::*; // Enable basic Video handlers
pub use users::*;

/// REST API v2 Module
///
/// Provides HTTP REST API endpoints for mobile clients (iOS/Android)
/// These endpoints translate HTTP requests to gRPC calls to backend microservices
///
/// Architecture:
/// ```
/// Mobile App (HTTP REST)
///     ↓
/// REST API Handler (this module)
///     ↓
/// gRPC Client → Microservice
/// ```
pub mod alice;
pub mod auth;
pub mod channels;
pub mod chat;
pub mod content;
pub mod feed;
pub mod graph;
pub mod identity;
pub mod media;
pub mod models;
pub mod notifications;
pub mod phone_auth;
pub mod poll;
pub mod search;
pub mod settings;
pub mod social;
pub mod social_likes;
pub mod user_profile;
// users module requires user-service gRPC - will be re-implemented when user-service v2 is available
// pub mod users;

pub use alice::*;
pub use auth::*;
pub use channels::*;
pub use chat::*;
pub use feed::*;
pub use media::*;
pub use social::*;
pub use user_profile::*;
// Modules with internal-only exports (actix handlers registered directly):
// content, graph, notifications, poll
// pub use users::*;

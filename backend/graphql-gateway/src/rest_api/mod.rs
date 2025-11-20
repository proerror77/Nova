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
pub mod auth;
pub mod feed;
// users module requires user-service gRPC - will be re-implemented when user-service v2 is available
// pub mod users;
pub mod models;

pub use auth::*;
pub use feed::*;
// pub use users::*;

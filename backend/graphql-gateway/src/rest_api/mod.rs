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
// users module temporarily disabled - user-service is deprecated
// pub mod users;
pub mod models;

pub use auth::*;
// pub use users::*; // Disabled - user-service is deprecated

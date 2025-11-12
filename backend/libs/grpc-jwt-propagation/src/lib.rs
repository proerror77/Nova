//! JWT Credential Propagation for gRPC Microservices
//!
//! This library provides transparent JWT token propagation between gRPC services,
//! enabling secure authentication and authorization across service boundaries.
//!
//! ## Core Components
//!
//! - **JwtClaims**: Structured representation of JWT claims with authorization helpers
//! - **JwtClientInterceptor**: Automatically injects JWT tokens into gRPC metadata
//! - **JwtServerInterceptor**: Extracts and validates JWT tokens from incoming requests
//! - **JwtClaimsExt**: Request extension trait for accessing claims and checking permissions
//!
//! ## Design Philosophy (Linus-style)
//!
//! - **Zero-copy where possible**: Token passed by reference, claims extracted once
//! - **No special cases**: Every endpoint gets same validation logic
//! - **Fail-fast**: Invalid tokens return `Status::unauthenticated` immediately
//! - **No magic**: Explicit interceptor attachment, clear error messages
//!
//! ## Usage Example
//!
//! ### Client Side (GraphQL Gateway)
//!
//! ```rust,no_run
//! use grpc_jwt_propagation::JwtClientInterceptor;
//! use tonic::Request;
//!
//! # async fn example() -> Result<(), Box<dyn std::error::Error>> {
//! // Extract JWT from GraphQL context
//! let jwt_token = "eyJhbGc..."; // From JwtMiddleware
//!
//! // Create interceptor
//! let interceptor = JwtClientInterceptor::new(jwt_token);
//!
//! // Attach to gRPC client
//! let channel = tonic::transport::Channel::from_static("http://[::1]:50051")
//!     .connect()
//!     .await?;
//!
//! // All requests will automatically include JWT
//! // let mut client = UserServiceClient::with_interceptor(channel, interceptor);
//! # Ok(())
//! # }
//! ```
//!
//! ### Server Side (Backend Service)
//!
//! ```rust,no_run
//! use grpc_jwt_propagation::{JwtServerInterceptor, JwtClaimsExt};
//! use tonic::{Request, Response, Status};
//!
//! // Service implementation
//! struct ContentService;
//!
//! // In endpoint handler
//! async fn delete_post(
//!     request: Request<()>,
//! ) -> Result<Response<()>, Status> {
//!     // Extract JWT claims (validated by interceptor)
//!     let claims = request.jwt_claims()?;
//!
//!     // Authorization check: only post author can delete
//!     let post_author_id = uuid::Uuid::new_v4(); // From database
//!     if !claims.is_owner(&post_author_id) {
//!         return Err(Status::permission_denied(
//!             "You can only delete your own posts"
//!         ));
//!     }
//!
//!     Ok(Response::new(()))
//! }
//! ```
//!
//! ## Security Guarantees
//!
//! - All tokens validated using RS256 (RSA with SHA-256)
//! - Expiration checked automatically
//! - No token = `Status::unauthenticated`
//! - Invalid token = `Status::unauthenticated`
//! - Missing permission = `Status::permission_denied`

mod claims;
mod client;
mod server;
mod extensions;

pub use claims::JwtClaims;
pub use client::JwtClientInterceptor;
pub use server::JwtServerInterceptor;
pub use extensions::JwtClaimsExt;

// Re-export tonic Status for convenience
pub use tonic::Status;

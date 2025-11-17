// gRPC server implementation for social-service
//
// `server.rs` contains the production-ready implementation aligned with the
// `nova.social_service.v2` proto schema.

pub mod server;

pub use server::SocialServiceImpl;

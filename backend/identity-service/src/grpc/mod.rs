/// gRPC server module for identity-service
///
/// Exports:
/// - IdentityServiceServer: Main gRPC server implementation
/// - nova: Generated protobuf types from auth_service.proto
pub mod server;

pub use server::nova;
pub use server::IdentityServiceServer;

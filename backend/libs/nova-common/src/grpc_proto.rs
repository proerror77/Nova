//! gRPC protocol definitions for inter-service communication
//!
//! This module contains gRPC service definitions that services can use
//! to communicate with each other. For now, this is a placeholder for future
//! gRPC integration. Services currently use HTTP/JSON.

// TODO: Add tonic::include_proto! macro after .proto files are generated

/// Placeholder for gRPC service definitions
/// In future phases, this will contain:
/// - StreamingService (Get stream info, list live streams, etc.)
/// - EventService (Publish/subscribe events)
/// - HealthService (Service health checks)
pub mod placeholder {
    pub const INFO: &str = "gRPC service definitions will be generated from .proto files";
}

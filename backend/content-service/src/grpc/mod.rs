//! gRPC implementations for inter-service communication
//!
//! This module contains:
//! - Server implementations (ContentService gRPC server)
//! - Client implementations (AuthClient from shared grpc-clients library)

pub mod server;

// Re-export from shared library
pub use grpc_clients::AuthClient;
pub use server::*;

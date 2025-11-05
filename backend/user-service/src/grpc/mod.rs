//! gRPC implementations for inter-service communication
//!
//! This module contains:
//! - Server implementations (Phase 0 gRPC API)
//! - Client implementations for calling other services
//! - Connection pooling and health checks

pub mod clients;
pub mod config;
pub mod health;
pub mod server;
pub mod servers;

pub use clients::{AuthServiceClient, ContentServiceClient, MediaServiceClient, UserProfileUpdate};
pub use config::GrpcClientConfig;
pub use health::HealthChecker;
pub use server::UserServiceImpl;

// Import generated proto code for gRPC service definitions
pub mod nova {
    pub mod user_service {
        tonic::include_proto!("nova.user_service");
    }
    pub mod content {
        tonic::include_proto!("nova.content");
    }
    pub mod media {
        tonic::include_proto!("nova.media");
    }
    pub mod auth {
        pub mod v1 {
            tonic::include_proto!("nova.auth.v1");
        }
    }
    pub mod video {
        pub mod v1 {
            tonic::include_proto!("nova.video.v1");
        }
    }
}

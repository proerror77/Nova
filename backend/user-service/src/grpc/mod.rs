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
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
    pub mod user_service {
        pub mod v1 {
            tonic::include_proto!("nova.user_service.v1");
        }
        pub use v1::*;
    }
    pub mod content_service {
        pub mod v1 {
            tonic::include_proto!("nova.content_service.v1");
        }
        pub use v1::*;
    }
    pub mod feed_service {
        pub mod v1 {
            tonic::include_proto!("nova.feed_service.v1");
        }
        pub use v1::*;
    }
    pub mod media_service {
        pub mod v1 {
            tonic::include_proto!("nova.media_service.v1");
        }
        pub use v1::*;
    }
    pub mod auth_service {
        pub mod v1 {
            tonic::include_proto!("nova.auth_service.v1");
        }
        pub use v1::*;
    }
    pub mod video_service {
        pub mod v1 {
            tonic::include_proto!("nova.video_service.v1");
        }
        pub use v1::*;
    }
}

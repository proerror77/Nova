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

pub use clients::{
    AuthServiceClient, ContentServiceClient, FeedServiceClient, MediaServiceClient,
    UserProfileUpdate,
};
pub use config::GrpcClientConfig;
pub use health::HealthChecker;
pub use server::UserServiceImpl;

// Import generated proto code for gRPC service definitions
pub mod nova {
    pub mod common {
        pub mod v2 {
            tonic::include_proto!("nova.common.v2");
        }
        pub use v2::*;
    }
    pub mod user_service {
        pub mod v2 {
            tonic::include_proto!("nova.user_service.v2");
        }
        pub use v2::*;
    }
    pub mod content_service {
        pub mod v2 {
            tonic::include_proto!("nova.content_service.v2");
        }
        pub use v2::*;
    }
    pub mod feed_service {
        pub mod v2 {
            tonic::include_proto!("nova.feed_service.v2");
        }
        pub use v2::*;
    }
    pub mod media_service {
        pub mod v2 {
            tonic::include_proto!("nova.media_service.v2");
        }
        pub use v2::*;
    }
    pub mod auth_service {
        pub mod v2 {
            tonic::include_proto!("nova.identity_service.v2");
        }
        pub use v2::*;
    }
    pub mod video_service {
        pub mod v2 {
            tonic::include_proto!("nova.video_service.v2");
        }
        pub use v2::*;
    }
}

//! gRPC client implementations for inter-service communication
//!
//! This module handles communication with other microservices (content-service, media-service)
//! via gRPC. It provides client implementations with connection pooling and health checks.

pub mod clients;
pub mod config;
pub mod health;
pub mod servers;

pub use clients::{AuthServiceClient, ContentServiceClient, MediaServiceClient, UserProfileUpdate};
pub use config::GrpcClientConfig;
pub use health::HealthChecker;

// Import generated proto code for gRPC service definitions
pub mod nova {
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
    pub mod recommendation {
        pub mod v1 {
            tonic::include_proto!("nova.recommendation.v1");
        }
    }
    pub mod video {
        pub mod v1 {
            tonic::include_proto!("nova.video.v1");
        }
    }
    pub mod streaming {
        pub mod v1 {
            tonic::include_proto!("nova.streaming.v1");
        }
    }
}

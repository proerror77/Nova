pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
pub mod jobs;
pub mod logging;
pub mod metrics;
pub mod middleware;
pub mod migrations;
pub mod models;
pub mod openapi;
pub mod redis_client;
pub mod routes;
pub mod security;
pub mod services;
pub mod state;
pub mod websocket;

// gRPC service modules - generated from protos
pub mod nova {
    pub mod messaging_service {
        pub mod v1 {
            tonic::include_proto!("nova.messaging_service.v1");
        }
        pub use v1::*;
    }
    pub mod auth_service {
        pub mod v1 {
            tonic::include_proto!("nova.auth_service.v1");
        }
        pub use v1::*;
    }
    // CRITICAL: common.proto defines ErrorStatus shared across all services
    // Must be included for super::super::common::v1::ErrorStatus references to resolve
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
}

pub use nova::auth_service::v1 as auth_service;
pub use nova::common::v1 as common;
pub use nova::messaging_service::v1 as messaging_service;

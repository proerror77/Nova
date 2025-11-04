pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
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

// gRPC service module - generated from protos (Phase 0 proto definitions)
pub mod nova {
    pub mod messaging_service {
        tonic::include_proto!("nova.messaging_service");
    }
}

pub use nova::messaging_service;

pub mod config;
pub mod db;
pub mod error;
pub mod logging;
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
pub mod grpc_service;

// gRPC service module - generated from protos
pub mod grpc {
    pub mod nova {
        pub mod messaging {
            include!(concat!(env!("OUT_DIR"), "/nova.messaging.rs"));
        }
    }
}

pub use grpc::nova::messaging;

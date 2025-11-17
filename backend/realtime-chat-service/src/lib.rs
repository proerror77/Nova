pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
pub mod logging;
pub mod middleware;
pub mod models;
pub mod redis_client;
pub mod routes;
pub mod security;
pub mod services;
pub mod state;
pub mod websocket;

// Re-export generated protobuf code
pub mod nova {
    pub mod realtime_chat {
        pub mod v2 {
            tonic::include_proto!("nova.realtime_chat.v2");
        }
    }
}

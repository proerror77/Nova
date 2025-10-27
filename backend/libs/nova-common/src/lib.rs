//! Nova Common Library
//!
//! Shared types, traits, and utilities for all Nova microservices.
//! Enables inter-service communication and consistent error handling.

pub mod error;
pub mod models;
pub mod grpc_proto;
pub mod http_client;

pub use error::{ServiceError, Result};

pub use models::{
    StreamEvent, EventType, StreamCommand, CommandRequest, CommandResponse,
};

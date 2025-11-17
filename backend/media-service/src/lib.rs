//! Media Service
//!
//! Microservice for managing videos, uploads, and reels.
//! Extracted from user-service as part of P1.2 service splitting.

pub mod cache;
pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
pub mod kafka;
pub mod handlers;
pub mod metrics;
pub mod middleware;
pub mod models;
pub mod openapi;
pub mod services;

// Public re-exports
pub use config::Config;
pub use error::{AppError, Result};

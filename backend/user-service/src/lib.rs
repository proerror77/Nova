pub mod app_state;
pub mod background;
pub mod cache;
pub mod cli;
pub mod config;
pub mod db;
pub mod error;
pub mod handlers;
pub mod jobs;
pub mod metrics;
pub mod middleware;
pub mod models;
pub mod openapi;
pub mod routes;
pub mod security;
pub mod services;
pub mod utils;
pub mod validators;

pub use config::Config;
pub use error::{AppError, Result};

// Re-export for integration tests
pub use services::{image_processing, job_queue};

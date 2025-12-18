//! Thumbnail generation service
//!
//! This module provides thumbnail generation capabilities:
//! - GCS client for downloading/uploading images
//! - Image processor for resizing and encoding
//! - Service for coordinating thumbnail generation
//! - Kafka consumer for real-time processing

pub mod consumer;
pub mod gcs_client;
pub mod processor;
pub mod service;

pub use consumer::{ThumbnailConsumer, ThumbnailConsumerConfig};
pub use gcs_client::GcsClient;
pub use processor::{ThumbnailConfig, ThumbnailProcessor, ThumbnailResult};
pub use service::{ThumbnailService, ThumbnailServiceConfig, ThumbnailStats};

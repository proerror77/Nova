//! Kafka Event Producer (Stub Implementation)
//!
//! This is a simplified stub implementation for streaming service.
//! Full implementation should be migrated from user-service when needed.

use anyhow::Result;
use serde::Serialize;
use std::sync::Arc;
use tracing::warn;

/// Event producer for Kafka
#[derive(Clone)]
pub struct EventProducer {
    // Placeholder for Kafka producer
}

impl EventProducer {
    /// Create a new event producer
    pub fn new(_kafka_brokers: String, _topic: String) -> Result<Self> {
        warn!("Using stub EventProducer - events will not be sent to Kafka");
        Ok(Self {})
    }

    /// Send an event (stub implementation)
    pub async fn send_event<T: Serialize>(&self, _event: T) -> Result<()> {
        // Stub: Just log that event would be sent
        // In production, this should serialize and send to Kafka
        Ok(())
    }

    /// Send JSON event with key (stub implementation)
    pub async fn send_json(&self, _key: &str, _payload: &str) -> Result<()> {
        // Stub: Just log that event would be sent
        // In production, this should send to Kafka with the key
        Ok(())
    }
}

/// Shared event producer for use across services
pub type SharedEventProducer = Arc<EventProducer>;

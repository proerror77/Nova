//! VLM Kafka Producer
//!
//! Publishes VLM analysis results to Kafka topics.

use crate::kafka::events::{topics, ChannelsAutoAssigned, VLMDeadLetterEvent, VLMPostAnalyzed};
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info, warn};
use uuid::Uuid;

/// VLM Kafka producer with retry and DLQ support
pub struct VLMProducer {
    producer: FutureProducer,
    delivery_timeout: Duration,
}

impl VLMProducer {
    /// Create a new VLM producer
    pub fn new(brokers: &str) -> Result<Self, rdkafka::error::KafkaError> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("enable.idempotence", "true")
            .set("acks", "all")
            .set("max.in.flight.requests.per.connection", "5")
            .set("retries", "3")
            .set("compression.type", "lz4")
            .set("linger.ms", "10")
            .set("batch.size", "16384")
            .set("message.timeout.ms", "30000")
            .create()?;

        info!("VLM Kafka producer initialized with brokers: {}", brokers);

        Ok(Self {
            producer,
            delivery_timeout: Duration::from_secs(30),
        })
    }

    /// Publish VLM analysis result
    pub async fn publish_analyzed(&self, event: VLMPostAnalyzed) -> Result<(), VLMProducerError> {
        let payload = serde_json::to_string(&event)
            .map_err(|e| VLMProducerError::Serialization(e.to_string()))?;

        let key = event.post_id.to_string();

        let record = FutureRecord::to(topics::VLM_POST_ANALYZED)
            .key(&key)
            .payload(&payload);

        match self.producer.send(record, self.delivery_timeout).await {
            Ok((partition, offset)) => {
                info!(
                    post_id = %event.post_id,
                    partition = partition,
                    offset = offset,
                    "Published VLM analysis result"
                );
                Ok(())
            }
            Err((err, _)) => {
                error!(
                    post_id = %event.post_id,
                    error = %err,
                    "Failed to publish VLM analysis result"
                );
                Err(VLMProducerError::Kafka(err.to_string()))
            }
        }
    }

    /// Publish channels auto-assigned event
    pub async fn publish_channels_assigned(
        &self,
        event: ChannelsAutoAssigned,
    ) -> Result<(), VLMProducerError> {
        let payload = serde_json::to_string(&event)
            .map_err(|e| VLMProducerError::Serialization(e.to_string()))?;

        let key = event.post_id.to_string();

        let record = FutureRecord::to(topics::CHANNELS_AUTO_ASSIGNED)
            .key(&key)
            .payload(&payload);

        match self.producer.send(record, self.delivery_timeout).await {
            Ok((partition, offset)) => {
                info!(
                    post_id = %event.post_id,
                    channels = ?event.channel_ids,
                    partition = partition,
                    offset = offset,
                    "Published channels auto-assigned event"
                );
                Ok(())
            }
            Err((err, _)) => {
                error!(
                    post_id = %event.post_id,
                    error = %err,
                    "Failed to publish channels auto-assigned event"
                );
                Err(VLMProducerError::Kafka(err.to_string()))
            }
        }
    }

    /// Send failed event to dead letter queue
    pub async fn send_to_dlq(
        &self,
        original_topic: &str,
        original_event: serde_json::Value,
        error: &str,
        retry_count: u32,
    ) -> Result<(), VLMProducerError> {
        let dlq_event = VLMDeadLetterEvent {
            original_event,
            original_topic: original_topic.to_string(),
            error: error.to_string(),
            retry_count,
            failed_at: chrono::Utc::now().timestamp_millis(),
        };

        let payload = serde_json::to_string(&dlq_event)
            .map_err(|e| VLMProducerError::Serialization(e.to_string()))?;

        let key = Uuid::new_v4().to_string();

        let record = FutureRecord::to(topics::VLM_DLQ)
            .key(&key)
            .payload(&payload);

        match self.producer.send(record, self.delivery_timeout).await {
            Ok(_) => {
                warn!(
                    original_topic = original_topic,
                    retry_count = retry_count,
                    "Sent event to DLQ"
                );
                Ok(())
            }
            Err((err, _)) => {
                error!(
                    original_topic = original_topic,
                    error = %err,
                    "Failed to send event to DLQ"
                );
                Err(VLMProducerError::Kafka(err.to_string()))
            }
        }
    }
}

/// Producer error types
#[derive(Debug, thiserror::Error)]
pub enum VLMProducerError {
    #[error("Kafka error: {0}")]
    Kafka(String),

    #[error("Serialization error: {0}")]
    Serialization(String),
}

/// Shared producer instance
pub type SharedVLMProducer = Arc<VLMProducer>;

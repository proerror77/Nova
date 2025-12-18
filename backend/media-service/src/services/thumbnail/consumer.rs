//! Kafka consumer for thumbnail generation
//!
//! Listens for media upload completion events and triggers thumbnail generation.

use super::service::ThumbnailService;
use crate::error::Result;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use rdkafka::ClientConfig;
use std::sync::Arc;
use tokio::sync::watch;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Kafka consumer configuration
#[derive(Clone, Debug)]
pub struct ThumbnailConsumerConfig {
    pub brokers: String,
    pub topic: String,
    pub group_id: String,
}

impl Default for ThumbnailConsumerConfig {
    fn default() -> Self {
        Self {
            brokers: "localhost:9092".to_string(),
            topic: "media_events".to_string(),
            group_id: "thumbnail-worker".to_string(),
        }
    }
}

/// Media uploaded event from Kafka
#[derive(Debug, serde::Deserialize)]
struct MediaUploadedEvent {
    media_id: String,
    user_id: String,
    #[allow(dead_code)]
    size_bytes: Option<i64>,
    #[allow(dead_code)]
    file_name: Option<String>,
}

/// Kafka consumer for thumbnail generation
pub struct ThumbnailConsumer {
    consumer: StreamConsumer,
    thumbnail_service: Arc<ThumbnailService>,
    shutdown_rx: watch::Receiver<bool>,
}

impl ThumbnailConsumer {
    /// Create a new thumbnail consumer
    pub fn new(
        config: &ThumbnailConsumerConfig,
        thumbnail_service: Arc<ThumbnailService>,
        shutdown_rx: watch::Receiver<bool>,
    ) -> Result<Self> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", &config.brokers)
            .set("group.id", &config.group_id)
            .set("enable.auto.commit", "true")
            .set("auto.commit.interval.ms", "5000")
            .set("auto.offset.reset", "earliest")
            .set("session.timeout.ms", "45000")
            .set("max.poll.interval.ms", "300000")
            .create()
            .map_err(|e| {
                crate::error::AppError::Internal(format!("Failed to create Kafka consumer: {e}"))
            })?;

        consumer.subscribe(&[&config.topic]).map_err(|e| {
            crate::error::AppError::Internal(format!("Failed to subscribe to topic: {e}"))
        })?;

        info!(
            brokers = %config.brokers,
            topic = %config.topic,
            group_id = %config.group_id,
            "Thumbnail consumer initialized"
        );

        Ok(Self {
            consumer,
            thumbnail_service,
            shutdown_rx,
        })
    }

    /// Run the consumer loop
    pub async fn run(&mut self) -> Result<()> {
        use futures::StreamExt;

        info!("Starting thumbnail consumer loop");

        let mut message_stream = self.consumer.stream();

        loop {
            tokio::select! {
                // Check for shutdown signal
                _ = self.shutdown_rx.changed() => {
                    if *self.shutdown_rx.borrow() {
                        info!("Shutdown signal received, stopping consumer");
                        break;
                    }
                }

                // Process messages
                message = message_stream.next() => {
                    match message {
                        Some(Ok(msg)) => {
                            if let Err(e) = self.process_message(&msg).await {
                                error!(error = %e, "Failed to process message");
                            }
                        }
                        Some(Err(e)) => {
                            error!(error = %e, "Kafka consumer error");
                            // Continue consuming despite errors
                        }
                        None => {
                            warn!("Message stream ended unexpectedly");
                            break;
                        }
                    }
                }
            }
        }

        info!("Thumbnail consumer stopped");
        Ok(())
    }

    /// Process a single Kafka message
    async fn process_message<M: Message>(&self, msg: &M) -> Result<()> {
        let payload = match msg.payload() {
            Some(p) => p,
            None => {
                debug!("Empty message payload, skipping");
                return Ok(());
            }
        };

        let event: MediaUploadedEvent = match serde_json::from_slice(payload) {
            Ok(e) => e,
            Err(e) => {
                warn!(error = %e, "Failed to parse message payload, skipping");
                return Ok(());
            }
        };

        debug!(
            media_id = %event.media_id,
            user_id = %event.user_id,
            "Received media uploaded event"
        );

        // Parse media_id as UUID
        let media_id = match Uuid::parse_str(&event.media_id) {
            Ok(id) => id,
            Err(e) => {
                warn!(
                    media_id = %event.media_id,
                    error = %e,
                    "Invalid media_id format, skipping"
                );
                return Ok(());
            }
        };

        // Process the image (generate thumbnail)
        match self.thumbnail_service.process_image(media_id).await {
            Ok(()) => {
                info!(media_id = %media_id, "Thumbnail generated for uploaded media");
            }
            Err(e) => {
                // Log but don't fail - the batch processor will catch up
                warn!(
                    media_id = %media_id,
                    error = %e,
                    "Failed to generate thumbnail, will retry in batch"
                );
            }
        }

        Ok(())
    }
}

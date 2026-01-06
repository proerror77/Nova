//! Kafka consumer for thumbnail generation
//!
//! Listens for media upload completion events and triggers thumbnail generation.

use super::service::ThumbnailService;
use crate::error::Result;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::{Headers, Message};
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
        let topic_prefix =
            std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova".to_string());
        let topic = std::env::var("KAFKA_MEDIA_EVENTS_TOPIC")
            .or_else(|_| std::env::var("KAFKA_EVENTS_TOPIC"))
            .unwrap_or_else(|_| format!("{}.media.events", topic_prefix));
        Self {
            brokers: "localhost:9092".to_string(),
            topic,
            group_id: "thumbnail-worker".to_string(),
        }
    }
}

/// Media uploaded event from Kafka
#[derive(Debug, serde::Deserialize)]
struct MediaUploadedEvent {
    upload_id: Option<String>,
    media_id: Option<String>,
    user_id: Option<String>,
    #[allow(dead_code)]
    size_bytes: Option<i64>,
    #[allow(dead_code)]
    file_name: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
struct EventEnvelope<T> {
    data: T,
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

        if let Some(event_type) = header_value(msg, "event_type") {
            if !matches!(
                event_type,
                "media.upload.completed" | "media.uploaded" | "MediaUploadedEvent"
            ) {
                debug!(event_type = %event_type, "Ignoring non-media upload event");
                return Ok(());
            }
        }

        let event: MediaUploadedEvent = match parse_enveloped_or_direct(payload) {
            Ok(e) => e,
            Err(e) => {
                warn!(error = %e, "Failed to parse message payload, skipping");
                return Ok(());
            }
        };

        let upload_id = match event.upload_id.as_deref().or(event.media_id.as_deref()) {
            Some(id) => id.to_string(),
            None => {
                warn!("Media upload event missing upload_id/media_id, skipping");
                return Ok(());
            }
        };

        debug!(
            upload_id = %upload_id,
            user_id = %event.user_id.clone().unwrap_or_else(|| "unknown".to_string()),
            "Received media uploaded event"
        );

        // Parse upload_id as UUID
        let upload_id = match Uuid::parse_str(&upload_id) {
            Ok(id) => id,
            Err(e) => {
                warn!(
                    upload_id = %upload_id,
                    error = %e,
                    "Invalid upload_id format, skipping"
                );
                return Ok(());
            }
        };

        // Process the image (generate thumbnail)
        match self.thumbnail_service.process_image(upload_id).await {
            Ok(()) => {
                info!(upload_id = %upload_id, "Thumbnail generated for uploaded media");
            }
            Err(e) => {
                // Log but don't fail - the batch processor will catch up
                warn!(
                    upload_id = %upload_id,
                    error = %e,
                    "Failed to generate thumbnail, will retry in batch"
                );
            }
        }

        Ok(())
    }
}

fn parse_enveloped_or_direct(payload: &[u8]) -> Result<MediaUploadedEvent> {
    if let Ok(envelope) = serde_json::from_slice::<EventEnvelope<MediaUploadedEvent>>(payload) {
        return Ok(envelope.data);
    }

    Ok(serde_json::from_slice::<MediaUploadedEvent>(payload)?)
}

fn header_value<'a, M: Message>(message: &'a M, key: &str) -> Option<&'a str> {
    message
        .headers()
        .and_then(|headers| {
            headers
                .iter()
                .find(|header| header.key == key)
                .and_then(|header| header.value)
        })
        .and_then(|value| std::str::from_utf8(value).ok())
}

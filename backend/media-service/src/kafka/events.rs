use crate::models::Upload;
use anyhow::{Context, Result};
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;

/// Kafka producer wrapper for media-service events.
#[derive(Clone)]
pub struct MediaEventsProducer {
    inner: Arc<FutureProducer>,
    topic: String,
}

impl MediaEventsProducer {
    pub fn new(brokers: &str, topic: &str) -> Result<Self> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("enable.idempotence", "true")
            .set("acks", "all")
            .set("message.timeout.ms", "5000")
            .create()
            .with_context(|| format!("Failed to create Kafka producer for '{}'", topic))?;

        Ok(Self {
            inner: Arc::new(producer),
            topic: topic.to_string(),
        })
    }

    /// Publish a MediaUploaded-style event when an upload is marked as completed.
    ///
    /// This follows the `MediaUploadedEvent` intent from the event architecture,
    /// using the Upload model fields that are currently available.
    pub async fn publish_media_uploaded(&self, upload: &Upload) -> Result<()> {
        // Only emit events for completed uploads
        if upload.status != "completed" {
            return Ok(());
        }

        let payload = json!({
            "media_id": upload.id.to_string(),
            "user_id": upload.user_id.to_string(),
            "size_bytes": upload.file_size,
            "file_name": upload.file_name,
            "uploaded_at": upload.updated_at,
        });

        let payload_str =
            serde_json::to_string(&payload).context("Failed to serialize MediaUploaded payload")?;

        let key = upload.user_id.to_string();

        let record = FutureRecord::to(&self.topic)
            .key(&key)
            .payload(&payload_str);

        // Fire-and-forget with a reasonable timeout; errors are surfaced to caller.
        self.inner
            .send(record, Duration::from_secs(10))
            .await
            .map_err(|(err, _)| {
                anyhow::anyhow!("Failed to publish MediaUploaded event: {}", err)
            })?;

        Ok(())
    }
}

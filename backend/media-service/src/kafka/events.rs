use crate::models::Upload;
use anyhow::{Context, Result};
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use resilience::{CircuitBreaker, CircuitBreakerError, CircuitState};
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn};

/// Kafka producer wrapper for media-service events with circuit breaker and retry.
#[derive(Clone)]
pub struct MediaEventsProducer {
    inner: Arc<FutureProducer>,
    topic: String,
    circuit_breaker: Arc<CircuitBreaker>,
}

impl MediaEventsProducer {
    /// Create a new Kafka producer with circuit breaker protection
    pub fn new(brokers: &str, topic: &str) -> Result<Self> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("enable.idempotence", "true")
            .set("acks", "all")
            .set("message.timeout.ms", "10000")
            .set("retries", "3") // Producer-level retries
            .set("retry.backoff.ms", "100")
            .create()
            .with_context(|| format!("Failed to create Kafka producer for '{}'", topic))?;

        // Use Kafka-optimized circuit breaker config
        let cb_config = resilience::presets::kafka_config().circuit_breaker;
        let circuit_breaker = Arc::new(CircuitBreaker::new(cb_config));

        info!(
            brokers = %brokers,
            topic = %topic,
            "Media service Kafka producer initialized with circuit breaker"
        );

        Ok(Self {
            inner: Arc::new(producer),
            topic: topic.to_string(),
            circuit_breaker,
        })
    }

    /// Get the current circuit breaker state
    pub fn circuit_state(&self) -> CircuitState {
        self.circuit_breaker.state()
    }

    /// Check if circuit breaker is open
    pub fn is_circuit_open(&self) -> bool {
        matches!(self.circuit_state(), CircuitState::Open)
    }

    /// Get current error rate
    pub fn error_rate(&self) -> f64 {
        self.circuit_breaker.error_rate()
    }

    /// Publish a MediaUploaded-style event when an upload is marked as completed.
    ///
    /// This follows the `MediaUploadedEvent` intent from the event architecture,
    /// using the Upload model fields that are currently available.
    ///
    /// Includes circuit breaker protection and automatic retry.
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
        let topic = self.topic.clone();
        let producer = self.inner.clone();
        let upload_id = upload.id;

        let result = self
            .circuit_breaker
            .call(|| async {
                let record = FutureRecord::to(&topic).key(&key).payload(&payload_str);

                producer
                    .send(record, Duration::from_secs(10))
                    .await
                    .map(|_| ())
                    .map_err(|(err, _)| format!("{}", err))
            })
            .await;

        match result {
            Ok(()) => Ok(()),
            Err(CircuitBreakerError::Open) => {
                warn!(
                    upload_id = %upload_id,
                    circuit_state = ?self.circuit_state(),
                    "Circuit breaker open - rejecting MediaUploaded publish"
                );
                Err(anyhow::anyhow!(
                    "Kafka circuit breaker open - MediaUploaded publish rejected"
                ))
            }
            Err(CircuitBreakerError::CallFailed(msg)) => {
                warn!(
                    upload_id = %upload_id,
                    error = %msg,
                    circuit_state = ?self.circuit_state(),
                    error_rate = self.error_rate(),
                    "MediaUploaded publish failed"
                );
                Err(anyhow::anyhow!(
                    "Failed to publish MediaUploaded event: {}",
                    msg
                ))
            }
        }
    }
}

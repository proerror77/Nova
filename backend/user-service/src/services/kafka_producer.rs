use rdkafka::producer::{FutureProducer, FutureRecord, Producer};
use rdkafka::ClientConfig;
use std::time::Duration;
use tokio::time::{sleep, timeout};
use tracing::{debug, warn};

use crate::config::KafkaConfig;
use crate::error::{AppError, Result};

/// Kafka producer wrapper for behavioural events
#[derive(Clone)]
pub struct EventProducer {
    producer: FutureProducer,
    topic: String,
    timeout: Duration,
    retry_attempts: u32,
    retry_backoff: Duration,
}

impl EventProducer {
    pub fn new(config: &KafkaConfig) -> Result<Self> {
        let timeout_ms = config.request_timeout_ms.max(1000);
        let backoff_ms = config.retry_backoff_ms.max(100);

        let producer = ClientConfig::new()
            .set("bootstrap.servers", &config.brokers)
            .set("message.timeout.ms", timeout_ms.to_string())
            .set("request.timeout.ms", timeout_ms.to_string())
            .set("socket.timeout.ms", timeout_ms.to_string())
            .set("retries", config.retry_attempts.to_string())
            .set("retry.backoff.ms", backoff_ms.to_string())
            .set("queue.buffering.max.messages", "100000")
            .set("acks", "all")
            .set("enable.idempotence", "true")
            .set("compression.type", "lz4")
            .create()
            .map_err(AppError::Kafka)?;

        Ok(Self {
            producer,
            topic: config.events_topic.clone(),
            timeout: Duration::from_millis(timeout_ms),
            retry_attempts: config.retry_attempts.max(1),
            retry_backoff: Duration::from_millis(backoff_ms),
        })
    }

    pub async fn send_json(&self, key: &str, payload: &str) -> Result<()> {
        let mut last_err: Option<AppError> = None;

        for attempt in 0..self.retry_attempts {
            let record = FutureRecord::to(&self.topic).payload(payload).key(key);
            debug!("Publishing event to topic {} (key={})", self.topic, key);

            match timeout(self.timeout, self.producer.send(record, self.timeout)).await {
                Ok(Ok(_)) => return Ok(()),
                Ok(Err((e, _))) => {
                    warn!(attempt = attempt + 1, "Kafka send error: {}", e);
                    last_err = Some(AppError::Kafka(e));
                }
                Err(_) => {
                    warn!(
                        attempt = attempt + 1,
                        "Kafka send timed out after {:?}", self.timeout
                    );
                    last_err = Some(AppError::Internal("Kafka publish timeout".into()));
                }
            }

            if attempt + 1 < self.retry_attempts {
                sleep(self.retry_backoff * (attempt + 1)).await;
            }
        }

        Err(last_err.unwrap_or_else(|| AppError::Internal("Kafka publish failed".into())))
    }

    /// Lightweight health check by fetching cluster metadata
    pub async fn health_check(&self) -> Result<()> {
        // librdkafka performs metadata fetch synchronously; scope is limited to readiness probes.
        self.producer
            .client()
            .fetch_metadata(Some(&self.topic), self.timeout)
            .map(|_| ())
            .map_err(AppError::Kafka)
    }
}

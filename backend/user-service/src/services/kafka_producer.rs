use rdkafka::producer::{FutureProducer, FutureRecord, Producer};
use rdkafka::ClientConfig;
use std::time::Duration;
use tokio::time::timeout;
use tracing::{debug, warn};

use crate::error::{AppError, Result};

/// Kafka producer wrapper for behavioural events
#[derive(Clone)]
pub struct EventProducer {
    producer: FutureProducer,
    topic: String,
    timeout: Duration,
}

impl EventProducer {
    pub fn new(brokers: &str, topic: String) -> Result<Self> {
        let producer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("message.timeout.ms", "5000")
            .set("queue.buffering.max.messages", "100000")
            .set("acks", "all")
            .set("compression.type", "lz4")
            .create()
            .map_err(AppError::Kafka)?;

        Ok(Self {
            producer,
            topic,
            timeout: Duration::from_secs(5),
        })
    }

    pub async fn send_json(&self, key: &str, payload: &str) -> Result<()> {
        let record = FutureRecord::to(&self.topic).payload(payload).key(key);

        debug!("Publishing event to topic {} (key={})", self.topic, key);

        match timeout(self.timeout, self.producer.send(record, self.timeout)).await {
            Ok(Ok(_)) => Ok(()),
            Ok(Err((e, _))) => Err(AppError::Kafka(e)),
            Err(_) => {
                warn!("Kafka send timed out after {:?}", self.timeout);
                Err(AppError::Internal("Kafka publish timeout".into()))
            }
        }
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

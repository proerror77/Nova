use rdkafka::producer::{FutureProducer, FutureRecord};
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
            timeout: Duration::from_millis(100),  // ← 从 5s 改为 100ms，快速失败
        })
    }

    /// Send JSON with explicit timeout override (for advanced use cases)
    pub async fn send_json_with_timeout(
        &self,
        key: &str,
        payload: &str,
        timeout_ms: u64,
    ) -> Result<()> {
        let custom_timeout = Duration::from_millis(timeout_ms);
        let record = FutureRecord::to(&self.topic).payload(payload).key(key);

        debug!(
            "Publishing event to topic {} (key={}) with timeout {}ms",
            self.topic, key, timeout_ms
        );

        match timeout(custom_timeout, self.producer.send(record, custom_timeout)).await {
            Ok(Ok(_)) => Ok(()),
            Ok(Err((e, _))) => Err(AppError::Kafka(e)),
            Err(_) => {
                warn!("Kafka send timed out after {}ms", timeout_ms);
                Err(AppError::Internal("Kafka publish timeout".into()))
            }
        }
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
}

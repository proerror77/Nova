/// Social graph synchronization service
///
/// Consumes follow/unfollow events from Kafka and syncs to Neo4j.
/// Implements retry logic and dead-letter queue for failed events.

use anyhow::{anyhow, Result};
use rdkafka::consumer::{CommitMode, Consumer, StreamConsumer};
use rdkafka::message::Message;
use rdkafka::ClientConfig;
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::Duration;
use tokio::task::JoinHandle;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::config::KafkaConfig;
use crate::services::graph::GraphService;
use crate::services::kafka_producer::EventProducer;

const SOCIAL_EVENTS_TOPIC: &str = "social.events";
const SOCIAL_EVENTS_DLQ_TOPIC: &str = "social.events.dlq";

/// Event type enum for social graph events
#[derive(Debug, Clone)]
enum SocialEventType {
    Follow,
    Unfollow,
}

impl SocialEventType {
    fn from_str(s: &str) -> Option<Self> {
        match s {
            "new_follow" | "follow" => Some(SocialEventType::Follow),
            "unfollow" => Some(SocialEventType::Unfollow),
            _ => None,
        }
    }
}

/// Social event from Kafka
#[derive(Debug, Clone)]
struct SocialEvent {
    event_id: String,
    event_type: SocialEventType,
    timestamp: i64,
    follower_id: Uuid,
    followee_id: Uuid,
}

impl SocialEvent {
    fn from_payload(payload: &str) -> Result<Self> {
        let json: Value = serde_json::from_str(payload)
            .map_err(|e| anyhow!("Failed to parse JSON: {}", e))?;

        let event_type_str = json
            .get("event_type")
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow!("Missing event_type"))?;

        let event_type = SocialEventType::from_str(event_type_str)
            .ok_or_else(|| anyhow!("Unknown event_type: {}", event_type_str))?;

        let event_id = json
            .get("event_id")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        let timestamp = json
            .get("timestamp")
            .and_then(|v| v.as_i64())
            .unwrap_or_else(|| chrono::Utc::now().timestamp_millis());

        // Handle both direct fields and nested properties
        let (follower_id, followee_id) = if let Some(props) = json.get("properties").and_then(|v| v.as_object()) {
            let follower = props
                .get("follower_id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("Missing follower_id in properties"))?;
            let followee = props
                .get("followee_id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("Missing followee_id in properties"))?;
            (
                Uuid::parse_str(follower)?,
                Uuid::parse_str(followee)?,
            )
        } else {
            // Fallback to direct fields
            let follower = json
                .get("follower_id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("Missing follower_id"))?;
            let followee = json
                .get("followee_id")
                .and_then(|v| v.as_str())
                .ok_or_else(|| anyhow!("Missing followee_id"))?;
            (
                Uuid::parse_str(follower)?,
                Uuid::parse_str(followee)?,
            )
        };

        Ok(SocialEvent {
            event_id,
            event_type,
            timestamp,
            follower_id,
            followee_id,
        })
    }
}

/// Social graph sync consumer
pub struct SocialGraphSyncConsumer {
    consumer: StreamConsumer,
    graph_service: Arc<GraphService>,
    event_producer: Arc<EventProducer>,
    max_retries: u32,
}

impl SocialGraphSyncConsumer {
    /// Create a new social graph sync consumer
    pub async fn new(
        kafka_config: &KafkaConfig,
        graph_service: Arc<GraphService>,
        event_producer: Arc<EventProducer>,
    ) -> Result<Self> {
        if !graph_service.is_enabled() {
            warn!("Neo4j is disabled; social graph sync will be no-op");
        }

        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", &kafka_config.brokers)
            .set("group.id", "social-graph-sync")
            .set("auto.offset.reset", "earliest")
            .set("enable.auto.commit", "false") // Manual commit for reliability
            .set("session.timeout.ms", "6000")
            .set("heartbeat.interval.ms", "2000")
            .set("isolation.level", "read_committed")
            .create()
            .map_err(|e| anyhow!("Failed to create Kafka consumer: {}", e))?;

        consumer
            .subscribe(&[SOCIAL_EVENTS_TOPIC])
            .map_err(|e| anyhow!("Failed to subscribe to topic: {}", e))?;

        Ok(Self {
            consumer,
            graph_service,
            event_producer,
            max_retries: 3,
        })
    }

    /// Start consuming events (returns a background task handle)
    pub fn start(self: Arc<Self>) -> JoinHandle<()> {
        tokio::spawn(async move {
            if let Err(e) = self.run().await {
                error!("Social graph sync consumer error: {}", e);
            }
        })
    }

    /// Run the consumer loop
    async fn run(&self) -> Result<()> {
        info!("Starting social graph sync consumer");

        loop {
            match tokio::time::timeout(
                Duration::from_secs(30),
                self.consumer.recv(),
            )
            .await
            {
                Ok(Ok(msg)) => {
                    let payload = match msg.payload_view::<str>() {
                        Some(Ok(p)) => p,
                        _ => {
                            warn!("Invalid message payload");
                            continue;
                        }
                    };

                    match self.process_event(payload).await {
                        Ok(_) => {
                            // Commit offset after successful processing
                            if let Err(e) = self.consumer.commit_message(&msg, CommitMode::Async) {
                                warn!("Failed to commit offset: {}", e);
                            }
                        }
                        Err(e) => {
                            error!("Failed to process event: {}", e);
                            // Send to DLQ on failure
                            if let Err(dlq_err) = self.send_to_dlq(payload).await {
                                error!("Failed to send to DLQ: {}", dlq_err);
                            }
                        }
                    }
                }
                Ok(Err(e)) => {
                    error!("Consumer error: {}", e);
                }
                Err(_) => {
                    // Timeout, continue
                }
            }
        }
    }

    /// Process a single event with retry logic
    async fn process_event(&self, payload: &str) -> Result<()> {
        let event = SocialEvent::from_payload(payload)?;

        for attempt in 0..=self.max_retries {
            match self.apply_event(&event).await {
                Ok(_) => {
                    info!(
                        event_id = %event.event_id,
                        event_type = ?event.event_type,
                        follower = %event.follower_id,
                        followee = %event.followee_id,
                        "Event processed successfully"
                    );
                    return Ok(());
                }
                Err(e) => {
                    if attempt < self.max_retries {
                        let backoff = Duration::from_millis(100 * 2_u64.pow(attempt));
                        warn!(
                            event_id = %event.event_id,
                            attempt = attempt + 1,
                            backoff_ms = backoff.as_millis(),
                            error = %e,
                            "Retrying event processing"
                        );
                        tokio::time::sleep(backoff).await;
                    } else {
                        return Err(anyhow!(
                            "Event processing failed after {} retries: {}",
                            self.max_retries,
                            e
                        ));
                    }
                }
            }
        }

        Err(anyhow!("Event processing exhausted all retries"))
    }

    /// Apply the event to Neo4j
    async fn apply_event(&self, event: &SocialEvent) -> Result<()> {
        if !self.graph_service.is_enabled() {
            return Ok(());
        }

        match event.event_type {
            SocialEventType::Follow => {
                self.graph_service
                    .follow(event.follower_id, event.followee_id)
                    .await?;
            }
            SocialEventType::Unfollow => {
                self.graph_service
                    .unfollow(event.follower_id, event.followee_id)
                    .await?;
            }
        }

        Ok(())
    }

    /// Send failed event to DLQ
    async fn send_to_dlq(&self, original_payload: &str) -> Result<()> {
        let dlq_event = json!({
            "original_payload": original_payload,
            "failed_at": chrono::Utc::now().to_rfc3339(),
            "dlq_version": "1.0"
        });

        let key = format!("dlq-{}", Uuid::new_v4());
        self.event_producer
            .send_json_to_topic(&key, &dlq_event.to_string(), SOCIAL_EVENTS_DLQ_TOPIC)
            .await?;

        info!("Event sent to DLQ: {}", key);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_social_event_parsing() {
        let payload = r#"{
            "event_id": "test-123",
            "event_type": "new_follow",
            "timestamp": 1234567890,
            "properties": {
                "follower_id": "00000000-0000-0000-0000-000000000001",
                "followee_id": "00000000-0000-0000-0000-000000000002"
            }
        }"#;

        let event = SocialEvent::from_payload(payload).expect("Failed to parse");
        assert_eq!(event.event_id, "test-123");
        match event.event_type {
            SocialEventType::Follow => (),
            _ => panic!("Expected Follow event"),
        }
    }
}

use anyhow::Result;
use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::repository::GraphRepositoryTrait;

/// Event payload for follow created/deleted events from social-service
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FollowEventPayload {
    pub follower_id: String,
    pub followee_id: String,
}

/// Kafka event structure from transactional outbox
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEvent {
    pub id: String,
    pub aggregate_type: String,
    pub aggregate_id: String,
    pub event_type: String,
    pub payload: serde_json::Value,
    pub created_at: String,
}

/// Consumer for social-service events (follow/unfollow)
pub struct SocialEventsConsumer {
    consumer: StreamConsumer,
    repository: Arc<dyn GraphRepositoryTrait + Send + Sync>,
    topic: String,
}

impl SocialEventsConsumer {
    /// Create a new SocialEventsConsumer
    pub fn new(
        brokers: &str,
        group_id: &str,
        topic: &str,
        repository: Arc<dyn GraphRepositoryTrait + Send + Sync>,
    ) -> Result<Self> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("group.id", group_id)
            .set("enable.auto.commit", "true")
            .set("auto.offset.reset", "earliest")
            .set("session.timeout.ms", "30000")
            .set("enable.partition.eof", "false")
            .create()?;

        consumer.subscribe(&[topic])?;
        info!(
            "Created Kafka consumer for topic '{}' with group '{}'",
            topic, group_id
        );

        Ok(Self {
            consumer,
            repository,
            topic: topic.to_string(),
        })
    }

    /// Start consuming events
    pub async fn start(self) -> Result<()> {
        info!("Starting social events consumer for topic '{}'", self.topic);

        loop {
            match self.consumer.recv().await {
                Ok(message) => {
                    if let Some(payload) = message.payload() {
                        match serde_json::from_slice::<OutboxEvent>(payload) {
                            Ok(event) => {
                                if let Err(e) = self.process_event(&event).await {
                                    error!(
                                        "Failed to process event {} (type: {}): {}",
                                        event.id, event.event_type, e
                                    );
                                }
                            }
                            Err(e) => {
                                warn!("Failed to deserialize Kafka message: {}", e);
                            }
                        }
                    }
                }
                Err(e) => {
                    error!("Kafka consumer error: {}", e);
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    /// Process a single event
    async fn process_event(&self, event: &OutboxEvent) -> Result<()> {
        match event.event_type.as_str() {
            "social.follow.created" => {
                let payload: FollowEventPayload = serde_json::from_value(event.payload.clone())?;
                let follower_id = Uuid::parse_str(&payload.follower_id)?;
                let followee_id = Uuid::parse_str(&payload.followee_id)?;

                info!(
                    "Processing follow created: {} -> {}",
                    follower_id, followee_id
                );

                self.repository
                    .create_follow(follower_id, followee_id)
                    .await?;

                info!("Successfully created follow edge in graph");
            }
            "social.follow.deleted" => {
                let payload: FollowEventPayload = serde_json::from_value(event.payload.clone())?;
                let follower_id = Uuid::parse_str(&payload.follower_id)?;
                let followee_id = Uuid::parse_str(&payload.followee_id)?;

                info!(
                    "Processing follow deleted: {} -> {}",
                    follower_id, followee_id
                );

                self.repository
                    .delete_follow(follower_id, followee_id)
                    .await?;

                info!("Successfully deleted follow edge from graph");
            }
            _ => {
                // Ignore unrelated events
                warn!("Ignoring event type: {}", event.event_type);
            }
        }

        Ok(())
    }
}

use std::time::Duration;

use rdkafka::config::ClientConfig;
use rdkafka::consumer::{CommitMode, Consumer, StreamConsumer};
use rdkafka::error::KafkaError;
use rdkafka::message::Message;
use tokio::task::JoinHandle;
use tracing::{debug, error, info, warn};

use super::consumers::{on_message_deleted, on_message_persisted, EventContext, EventError};

#[derive(Debug, Clone)]
pub struct KafkaConsumerConfig {
    pub brokers: String,
    pub group_id: String,
    pub message_persisted_topic: String,
    pub message_deleted_topic: String,
}

impl KafkaConsumerConfig {
    /// Load Kafka configuration from environment variables.
    /// Returns `None` if brokers are not configured.
    pub fn from_env() -> Option<Self> {
        let brokers = std::env::var("KAFKA_BROKERS").ok()?;

        if brokers.trim().is_empty() {
            return None;
        }

        Some(Self {
            brokers,
            group_id: std::env::var("KAFKA_SEARCH_GROUP_ID")
                .unwrap_or_else(|_| "nova-search-service".to_string()),
            message_persisted_topic: std::env::var("KAFKA_MESSAGE_PERSISTED_TOPIC")
                .unwrap_or_else(|_| "message_persisted".to_string()),
            message_deleted_topic: std::env::var("KAFKA_MESSAGE_DELETED_TOPIC")
                .unwrap_or_else(|_| "message_deleted".to_string()),
        })
    }
}

/// Spawn a Tokio task running the Kafka consumer loop.
pub fn spawn_message_consumer(ctx: EventContext, config: KafkaConsumerConfig) -> JoinHandle<()> {
    tokio::spawn(async move {
        if let Err(err) = run_consumer(ctx, config).await {
            error!("Kafka consumer terminated with error: {err}");
        }
    })
}

async fn run_consumer(ctx: EventContext, config: KafkaConsumerConfig) -> Result<(), KafkaError> {
    info!(
        "Starting Kafka consumer for search indexing (topics: {}, {})",
        config.message_persisted_topic, config.message_deleted_topic
    );

    let consumer: StreamConsumer = ClientConfig::new()
        .set("bootstrap.servers", &config.brokers)
        .set("group.id", &config.group_id)
        .set("enable.auto.commit", "true")
        .set("enable.partition.eof", "false")
        .set("session.timeout.ms", "45000")
        .set("max.poll.interval.ms", "300000")
        .create()?;

    consumer.subscribe(&[
        config.message_persisted_topic.as_str(),
        config.message_deleted_topic.as_str(),
    ])?;

    loop {
        match consumer.recv().await {
            Ok(record) => {
                let topic = record.topic();
                let payload = record.payload();

                if payload.is_none() {
                    debug!(
                        "Received Kafka message with empty payload (topic: {})",
                        topic
                    );
                    continue;
                }

                let data = payload.expect("Payload checked to be Some above");

                let result = if topic == config.message_persisted_topic {
                    on_message_persisted(&ctx, data).await
                } else if topic == config.message_deleted_topic {
                    on_message_deleted(&ctx, data).await
                } else {
                    warn!("Received message for unexpected topic: {}", topic);
                    Ok(())
                };

                if let Err(err) = result {
                    match err {
                        EventError::Decode(e) => {
                            warn!("Failed to decode Kafka payload: {}", e);
                        }
                        EventError::Search(e) => {
                            error!("Search backend error while processing Kafka event: {}", e);
                        }
                    }
                }

                if let Err(commit_err) = consumer.commit_message(&record, CommitMode::Async) {
                    warn!("Failed to commit Kafka offset: {}", commit_err);
                }
            }
            Err(err) => {
                error!("Kafka error: {}", err);
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        }
    }
}

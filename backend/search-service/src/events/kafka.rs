use std::time::Duration;

use rdkafka::config::ClientConfig;
use rdkafka::consumer::{CommitMode, Consumer, StreamConsumer};
use rdkafka::error::KafkaError;
use rdkafka::message::Message;
use tokio::task::JoinHandle;
use tracing::{debug, error, info, warn};

use super::consumers::{
    on_identity_event, on_message_deleted, on_message_persisted, EventContext, EventError,
};

#[derive(Debug, Clone)]
pub struct KafkaConsumerConfig {
    pub brokers: String,
    pub group_id: String,
    pub message_persisted_topic: String,
    pub message_deleted_topic: String,
    pub message_events_topic: Option<String>,
    pub identity_events_topic: String,
}

impl KafkaConsumerConfig {
    /// Load Kafka configuration from environment variables.
    /// Returns `None` if brokers are not configured.
    pub fn from_env() -> Option<Self> {
        let brokers = std::env::var("KAFKA_BROKERS").ok()?;

        if brokers.trim().is_empty() {
            return None;
        }

        let topic_prefix = std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova".to_string());

        Some(Self {
            brokers,
            group_id: std::env::var("KAFKA_SEARCH_GROUP_ID")
                .unwrap_or_else(|_| "nova-search-service".to_string()),
            message_persisted_topic: std::env::var("KAFKA_MESSAGE_PERSISTED_TOPIC")
                .unwrap_or_else(|_| "message_persisted".to_string()),
            message_deleted_topic: std::env::var("KAFKA_MESSAGE_DELETED_TOPIC")
                .unwrap_or_else(|_| "message_deleted".to_string()),
            message_events_topic: std::env::var("KAFKA_MESSAGE_EVENTS_TOPIC")
                .ok()
                .filter(|topic| !topic.trim().is_empty()),
            identity_events_topic: std::env::var("KAFKA_IDENTITY_EVENTS_TOPIC")
                .unwrap_or_else(|_| format!("{}.identity.events", topic_prefix)),
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
        "Starting Kafka consumer for search indexing (topics: {}, {}, {}, {})",
        config.message_persisted_topic,
        config.message_deleted_topic,
        config.identity_events_topic,
        config
            .message_events_topic
            .as_deref()
            .unwrap_or("<disabled>")
    );

    let consumer: StreamConsumer = ClientConfig::new()
        .set("bootstrap.servers", &config.brokers)
        .set("group.id", &config.group_id)
        .set("enable.auto.commit", "true")
        .set("enable.partition.eof", "false")
        .set("session.timeout.ms", "45000")
        .set("max.poll.interval.ms", "300000")
        .create()?;

    let mut topics = vec![
        config.message_persisted_topic.as_str(),
        config.message_deleted_topic.as_str(),
        config.identity_events_topic.as_str(),
    ];

    if let Some(ref topic) = config.message_events_topic {
        topics.push(topic.as_str());
    }

    consumer.subscribe(&topics)?;

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
                let event_type = header_value(&record, "event_type");

                let result = if topic == config.message_persisted_topic {
                    on_message_persisted(&ctx, data).await
                } else if topic == config.message_deleted_topic {
                    on_message_deleted(&ctx, data).await
                } else if topic == config.identity_events_topic {
                    on_identity_event(&ctx, event_type, data).await
                } else if config.message_events_topic.as_deref() == Some(topic) {
                    match event_type {
                        Some("message.persisted") | Some("message_persisted") => {
                            on_message_persisted(&ctx, data).await
                        }
                        Some("message.deleted") | Some("message_deleted") => {
                            on_message_deleted(&ctx, data).await
                        }
                        Some(other) => {
                            warn!("Unknown message event type on unified topic: {}", other);
                            Ok(())
                        }
                        None => {
                            warn!(
                                "Unified message events topic missing event_type header; skipping"
                            );
                            Ok(())
                        }
                    }
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

fn header_value<'a>(message: &'a rdkafka::message::BorrowedMessage<'a>, key: &str) -> Option<&'a str> {
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

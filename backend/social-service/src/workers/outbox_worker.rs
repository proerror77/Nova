use std::sync::Arc;
use std::time::Duration;
use tonic::async_trait;
use tracing::{info, warn};
#[allow(unused_imports)]
use transactional_outbox::{
    metrics::OutboxMetrics, KafkaOutboxPublisher, OutboxProcessor, OutboxPublisher,
    OutboxRepository, OutboxResult, SqlxOutboxRepository,
};

fn build_publisher() -> CombinedPublisher {
    let brokers = std::env::var("KAFKA_BROKERS").unwrap_or_default();
    let topic_prefix = std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova".into());
    let allow_kafka = std::env::var("SOCIAL_OUTBOX_USE_KAFKA")
        .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
        .unwrap_or(true);

    if allow_kafka && !brokers.is_empty() {
        match rdkafka::ClientConfig::new()
            .set("bootstrap.servers", brokers.clone())
            .set("enable.idempotence", "true")
            .set("acks", "all")
            .set("max.in.flight.requests.per.connection", "5")
            .set("retries", "10")
            .create()
        {
            Ok(producer) => {
                info!("Using KafkaOutboxPublisher for social-service outbox");
                let publisher = KafkaOutboxPublisher::new(producer, topic_prefix);
                return CombinedPublisher {
                    inner: PublisherKind::Kafka(publisher),
                };
            }
            Err(e) => {
                warn!(
                    "Failed to create Kafka producer for outbox ({}), falling back to noop: {}",
                    brokers, e
                );
            }
        }
    } else {
        if !allow_kafka {
            info!("SOCIAL_OUTBOX_USE_KAFKA disabled, using noop publisher");
        } else {
            warn!("KAFKA_BROKERS not set; using noop outbox publisher");
        }
    }

    info!("Using NoopPublisher for social-service outbox");
    CombinedPublisher {
        inner: PublisherKind::Noop(NoopPublisher),
    }
}

/// No-op publisher used to drain the outbox until Kafka/event bus wiring is ready.
/// This marks events as "published" via OutboxProcessor so pending rows不会无限堆积。
struct NoopPublisher;

enum PublisherKind {
    Noop(NoopPublisher),
    Kafka(KafkaOutboxPublisher),
}

struct CombinedPublisher {
    inner: PublisherKind,
}

#[async_trait]
impl OutboxPublisher for CombinedPublisher {
    async fn publish(&self, event: &transactional_outbox::OutboxEvent) -> OutboxResult<()> {
        match &self.inner {
            PublisherKind::Noop(p) => p.publish(event).await,
            PublisherKind::Kafka(p) => p.publish(event).await,
        }
    }
}

impl NoopPublisher {
    async fn publish(&self, _event: &transactional_outbox::OutboxEvent) -> OutboxResult<()> {
        Ok(())
    }
}

/// Start a background outbox processor that drains pending events.
pub async fn run(
    db: sqlx::Pool<sqlx::Postgres>,
    repo: Arc<SqlxOutboxRepository>,
) -> anyhow::Result<()> {
    info!("Starting social-service outbox worker (noop publisher)");

    let publisher = Arc::new(build_publisher());
    let metrics = OutboxMetrics::new("social_service");
    let processor = OutboxProcessor::new_with_metrics(
        repo,
        publisher,
        metrics,
        100,                    // batch_size
        Duration::from_secs(5), // poll_interval
        5,                      // max_retries
    );

    // Run forever; log and continue on error.
    tokio::spawn(async move {
        if let Err(e) = processor.start().await {
            warn!("Outbox processor exited with error: {}", e);
        }
    });

    // Keep worker alive alongside service lifetime.
    let _ = db; // db kept for lifetime alignment
    Ok(())
}

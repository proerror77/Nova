use prometheus::{IntCounter, IntGauge};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tonic::async_trait;
use tracing::{error, info, warn};
#[allow(unused_imports)]
use transactional_outbox::{
    metrics::OutboxMetrics, CircuitBreakerKafkaPublisher, KafkaOutboxPublisher, OutboxProcessor,
    OutboxPublisher, OutboxRepository, OutboxResult, SqlxOutboxRepository,
};

/// Metrics for tracking outbox publisher health
#[derive(Clone)]
pub struct OutboxPublisherMetrics {
    /// Total events dropped by NoOp publisher
    pub events_dropped_total: IntCounter,
    /// Whether the publisher is in degraded mode (NoOp)
    pub degraded_mode: IntGauge,
    /// Publisher type: 0=unknown, 1=kafka, 2=noop
    pub publisher_type: IntGauge,
}

impl OutboxPublisherMetrics {
    pub fn new() -> Self {
        let registry = prometheus::default_registry();

        let events_dropped_total = IntCounter::new(
            "outbox_events_dropped_total",
            "Total number of outbox events dropped by NoOp publisher (data loss)",
        )
        .expect("valid metric for outbox_events_dropped_total");

        let degraded_mode = IntGauge::new(
            "outbox_publisher_degraded",
            "Whether the outbox publisher is in degraded mode (1 = NoOp/degraded, 0 = healthy)",
        )
        .expect("valid metric for outbox_publisher_degraded");

        let publisher_type = IntGauge::new(
            "outbox_publisher_type",
            "Current publisher type (0=unknown, 1=kafka, 2=noop)",
        )
        .expect("valid metric for outbox_publisher_type");

        for metric in [
            Box::new(events_dropped_total.clone()) as Box<dyn prometheus::core::Collector>,
            Box::new(degraded_mode.clone()),
            Box::new(publisher_type.clone()),
        ] {
            let _ = registry.register(metric);
        }

        Self {
            events_dropped_total,
            degraded_mode,
            publisher_type,
        }
    }
}

impl Default for OutboxPublisherMetrics {
    fn default() -> Self {
        Self::new()
    }
}

/// Configuration for outbox publisher behavior
#[derive(Debug, Clone)]
pub struct OutboxPublisherConfig {
    /// Kafka broker addresses
    pub brokers: String,
    /// Kafka topic prefix
    pub topic_prefix: String,
    /// Whether Kafka publishing is enabled
    pub kafka_enabled: bool,
    /// If true, fail startup when Kafka is unavailable instead of falling back to NoOp
    pub fail_on_kafka_unavailable: bool,
    /// Interval for warning logs when in NoOp mode
    pub noop_warning_interval_secs: u64,
}

impl OutboxPublisherConfig {
    pub fn from_env() -> Self {
        let brokers = std::env::var("KAFKA_BROKERS").unwrap_or_default();
        let topic_prefix = std::env::var("KAFKA_TOPIC_PREFIX").unwrap_or_else(|_| "nova".into());
        let kafka_enabled = std::env::var("SOCIAL_OUTBOX_USE_KAFKA")
            .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
            .unwrap_or(true);
        let fail_on_kafka_unavailable = std::env::var("SOCIAL_OUTBOX_FAIL_ON_KAFKA_UNAVAILABLE")
            .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
            .unwrap_or(false); // Default: graceful degradation
        let noop_warning_interval_secs = std::env::var("SOCIAL_OUTBOX_NOOP_WARNING_INTERVAL")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(60); // Default: warn every 60 seconds

        Self {
            brokers,
            topic_prefix,
            kafka_enabled,
            fail_on_kafka_unavailable,
            noop_warning_interval_secs,
        }
    }
}

/// Result of building a publisher
pub enum BuildPublisherResult {
    /// Successfully built a Kafka publisher
    Kafka(CombinedPublisher),
    /// Fell back to NoOp publisher (with reason)
    Noop(CombinedPublisher, String),
    /// Failed to build publisher (when fail_on_kafka_unavailable is true)
    Failed(String),
}

fn build_publisher(config: &OutboxPublisherConfig, metrics: OutboxPublisherMetrics) -> BuildPublisherResult {
    if !config.kafka_enabled {
        info!("SOCIAL_OUTBOX_USE_KAFKA disabled, using NoOp publisher");
        metrics.degraded_mode.set(1);
        metrics.publisher_type.set(2); // NoOp
        return BuildPublisherResult::Noop(
            CombinedPublisher {
                inner: PublisherKind::Noop(NoopPublisher::new(metrics, config.noop_warning_interval_secs)),
            },
            "Kafka disabled by configuration".to_string(),
        );
    }

    if config.brokers.is_empty() {
        let reason = "KAFKA_BROKERS not set".to_string();
        if config.fail_on_kafka_unavailable {
            return BuildPublisherResult::Failed(reason);
        }
        warn!("{}; using NoOp outbox publisher - EVENTS WILL BE DROPPED", reason);
        metrics.degraded_mode.set(1);
        metrics.publisher_type.set(2);
        return BuildPublisherResult::Noop(
            CombinedPublisher {
                inner: PublisherKind::Noop(NoopPublisher::new(metrics, config.noop_warning_interval_secs)),
            },
            reason,
        );
    }

    match rdkafka::ClientConfig::new()
        .set("bootstrap.servers", config.brokers.clone())
        .set("enable.idempotence", "true")
        .set("acks", "all")
        .set("max.in.flight.requests.per.connection", "5")
        .set("retries", "10")
        .create()
    {
        Ok(producer) => {
            info!("Using CircuitBreakerKafkaPublisher for social-service outbox");
            metrics.degraded_mode.set(0);
            metrics.publisher_type.set(1); // Kafka with circuit breaker
            let publisher = CircuitBreakerKafkaPublisher::with_config(
                producer,
                config.topic_prefix.clone(),
                resilience::presets::kafka_config().circuit_breaker,
                "social_service",
            );
            BuildPublisherResult::Kafka(CombinedPublisher {
                inner: PublisherKind::Kafka(publisher, metrics),
            })
        }
        Err(e) => {
            let reason = format!("Failed to create Kafka producer: {}", e);
            if config.fail_on_kafka_unavailable {
                return BuildPublisherResult::Failed(reason);
            }
            error!(
                brokers = %config.brokers,
                error = %e,
                "Kafka producer creation failed - falling back to NoOp publisher. EVENTS WILL BE DROPPED!"
            );
            metrics.degraded_mode.set(1);
            metrics.publisher_type.set(2);
            BuildPublisherResult::Noop(
                CombinedPublisher {
                    inner: PublisherKind::Noop(NoopPublisher::new(metrics, config.noop_warning_interval_secs)),
                },
                reason,
            )
        }
    }
}

/// NoOp publisher that tracks dropped events and emits periodic warnings.
///
/// WARNING: This publisher drops all events! Use only when:
/// 1. Kafka is explicitly disabled for development/testing
/// 2. As a temporary fallback when Kafka is unavailable
///
/// Events "published" via this publisher are marked as processed but are NOT
/// actually delivered anywhere - they are permanently lost.
struct NoopPublisher {
    metrics: OutboxPublisherMetrics,
    dropped_count: AtomicU64,
    last_warning_time: AtomicU64,
    warning_interval_secs: u64,
    warned_this_session: AtomicBool,
}

impl NoopPublisher {
    fn new(metrics: OutboxPublisherMetrics, warning_interval_secs: u64) -> Self {
        Self {
            metrics,
            dropped_count: AtomicU64::new(0),
            last_warning_time: AtomicU64::new(0),
            warning_interval_secs,
            warned_this_session: AtomicBool::new(false),
        }
    }

    async fn publish(&self, event: &transactional_outbox::OutboxEvent) -> OutboxResult<()> {
        // Track dropped event
        let count = self.dropped_count.fetch_add(1, Ordering::Relaxed) + 1;
        self.metrics.events_dropped_total.inc();

        // Emit initial warning on first drop
        if !self.warned_this_session.swap(true, Ordering::Relaxed) {
            error!(
                event_id = %event.id,
                event_type = %event.event_type,
                aggregate_type = %event.aggregate_type,
                "NoOp publisher active - FIRST EVENT DROPPED! Events are being lost. \
                 Set KAFKA_BROKERS or set SOCIAL_OUTBOX_FAIL_ON_KAFKA_UNAVAILABLE=true to fail fast."
            );
        }

        // Periodic warning (throttled)
        let now_secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let last_warning = self.last_warning_time.load(Ordering::Relaxed);

        if now_secs >= last_warning + self.warning_interval_secs {
            if self.last_warning_time.compare_exchange(
                last_warning,
                now_secs,
                Ordering::SeqCst,
                Ordering::Relaxed,
            ).is_ok() {
                warn!(
                    total_dropped = count,
                    event_type = %event.event_type,
                    "NoOp publisher: {} events dropped this session. Events are NOT being delivered!",
                    count
                );
            }
        }

        Ok(())
    }
}

enum PublisherKind {
    Noop(NoopPublisher),
    Kafka(CircuitBreakerKafkaPublisher, OutboxPublisherMetrics),
}

/// Combined publisher that can be either Kafka or NoOp
pub struct CombinedPublisher {
    inner: PublisherKind,
}

impl CombinedPublisher {
    /// Check if the publisher is in degraded (NoOp) mode
    pub fn is_degraded(&self) -> bool {
        matches!(self.inner, PublisherKind::Noop(_))
    }

    /// Get the publisher type as a string
    pub fn publisher_type(&self) -> &'static str {
        match &self.inner {
            PublisherKind::Noop(_) => "noop",
            PublisherKind::Kafka(_, _) => "kafka",
        }
    }

    /// Get circuit breaker state (if using Kafka publisher)
    pub fn circuit_state(&self) -> Option<&'static str> {
        match &self.inner {
            PublisherKind::Kafka(p, _) => {
                Some(match p.circuit_state() {
                    resilience::CircuitState::Closed => "closed",
                    resilience::CircuitState::Open => "open",
                    resilience::CircuitState::HalfOpen => "half_open",
                })
            }
            PublisherKind::Noop(_) => None,
        }
    }

    /// Check if circuit breaker is open (failing fast)
    pub fn is_circuit_open(&self) -> bool {
        match &self.inner {
            PublisherKind::Kafka(p, _) => p.is_circuit_open(),
            PublisherKind::Noop(_) => false,
        }
    }

    /// Get current error rate from circuit breaker
    pub fn error_rate(&self) -> Option<f64> {
        match &self.inner {
            PublisherKind::Kafka(p, _) => Some(p.error_rate()),
            PublisherKind::Noop(_) => None,
        }
    }
}

#[async_trait]
impl OutboxPublisher for CombinedPublisher {
    async fn publish(&self, event: &transactional_outbox::OutboxEvent) -> OutboxResult<()> {
        match &self.inner {
            PublisherKind::Noop(p) => p.publish(event).await,
            PublisherKind::Kafka(p, _metrics) => p.publish(event).await,
        }
    }
}

/// Health status for the outbox worker
#[derive(Debug, Clone)]
pub struct OutboxWorkerHealth {
    /// Whether the worker is using a real publisher (Kafka)
    pub healthy: bool,
    /// Current publisher type
    pub publisher_type: &'static str,
    /// Reason if degraded
    pub degraded_reason: Option<String>,
    /// Circuit breaker state (if using Kafka)
    pub circuit_state: Option<&'static str>,
    /// Current error rate from circuit breaker
    pub error_rate: Option<f64>,
}

/// Global health state for the outbox worker (for health checks)
static WORKER_HEALTH: std::sync::OnceLock<std::sync::RwLock<OutboxWorkerHealth>> = std::sync::OnceLock::new();

/// Get the current outbox worker health status
pub fn get_health() -> OutboxWorkerHealth {
    WORKER_HEALTH
        .get()
        .and_then(|lock| lock.read().ok())
        .map(|h| h.clone())
        .unwrap_or(OutboxWorkerHealth {
            healthy: false,
            publisher_type: "unknown",
            degraded_reason: Some("Worker not initialized".to_string()),
            circuit_state: None,
            error_rate: None,
        })
}

fn set_health(health: OutboxWorkerHealth) {
    let lock = WORKER_HEALTH.get_or_init(|| std::sync::RwLock::new(health.clone()));
    if let Ok(mut h) = lock.write() {
        *h = health;
    }
}

/// Start a background outbox processor that drains pending events.
///
/// # Errors
///
/// Returns an error if:
/// - `SOCIAL_OUTBOX_FAIL_ON_KAFKA_UNAVAILABLE=true` and Kafka is unavailable
///
/// # Environment Variables
///
/// - `KAFKA_BROKERS`: Comma-separated list of Kafka brokers
/// - `KAFKA_TOPIC_PREFIX`: Prefix for Kafka topics (default: "nova")
/// - `SOCIAL_OUTBOX_USE_KAFKA`: Set to "false" or "0" to disable Kafka (default: true)
/// - `SOCIAL_OUTBOX_FAIL_ON_KAFKA_UNAVAILABLE`: Set to "true" or "1" to fail if Kafka unavailable (default: false)
/// - `SOCIAL_OUTBOX_NOOP_WARNING_INTERVAL`: Seconds between NoOp warnings (default: 60)
pub async fn run(
    db: sqlx::Pool<sqlx::Postgres>,
    repo: Arc<SqlxOutboxRepository>,
) -> anyhow::Result<()> {
    let config = OutboxPublisherConfig::from_env();
    let publisher_metrics = OutboxPublisherMetrics::new();

    info!(
        kafka_enabled = config.kafka_enabled,
        fail_on_unavailable = config.fail_on_kafka_unavailable,
        brokers = %config.brokers,
        "Starting social-service outbox worker"
    );

    let publisher = match build_publisher(&config, publisher_metrics) {
        BuildPublisherResult::Kafka(p) => {
            set_health(OutboxWorkerHealth {
                healthy: true,
                publisher_type: "kafka",
                degraded_reason: None,
                circuit_state: p.circuit_state(),
                error_rate: p.error_rate(),
            });
            info!(
                circuit_state = ?p.circuit_state(),
                "Outbox worker using Kafka publisher with circuit breaker - events will be delivered"
            );
            Arc::new(p)
        }
        BuildPublisherResult::Noop(p, reason) => {
            set_health(OutboxWorkerHealth {
                healthy: false,
                publisher_type: "noop",
                degraded_reason: Some(reason.clone()),
                circuit_state: None,
                error_rate: None,
            });
            error!(
                reason = %reason,
                "Outbox worker using NoOp publisher - EVENTS WILL BE DROPPED! \
                 This is a DATA LOSS situation. Fix Kafka configuration or set \
                 SOCIAL_OUTBOX_FAIL_ON_KAFKA_UNAVAILABLE=true to fail fast."
            );
            Arc::new(p)
        }
        BuildPublisherResult::Failed(reason) => {
            set_health(OutboxWorkerHealth {
                healthy: false,
                publisher_type: "none",
                degraded_reason: Some(reason.clone()),
                circuit_state: None,
                error_rate: None,
            });
            error!(reason = %reason, "Outbox worker failed to start - Kafka unavailable and fail-fast enabled");
            return Err(anyhow::anyhow!(
                "Failed to initialize outbox publisher: {}. \
                 Set SOCIAL_OUTBOX_FAIL_ON_KAFKA_UNAVAILABLE=false to allow NoOp fallback.",
                reason
            ));
        }
    };

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
            error!("Outbox processor exited with error: {}", e);
            set_health(OutboxWorkerHealth {
                healthy: false,
                publisher_type: "unknown",
                degraded_reason: Some(format!("Processor error: {}", e)),
                circuit_state: None,
                error_rate: None,
            });
        }
    });

    // Keep worker alive alongside service lifetime.
    let _ = db; // db kept for lifetime alignment
    Ok(())
}

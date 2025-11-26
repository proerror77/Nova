use prometheus::{IntCounter, IntGauge, Opts};
use tracing::warn;

#[derive(Clone)]
pub struct OutboxMetrics {
    pub pending: IntGauge,
    pub oldest_pending_age_seconds: IntGauge,
    pub published: IntCounter,
}

impl OutboxMetrics {
    pub fn new(service: &str) -> Self {
        let registry = prometheus::default_registry();

        let pending = IntGauge::with_opts(
            Opts::new(
                "outbox_pending_count",
                "Number of unpublished outbox events currently pending",
            )
            .const_label("service", service.to_string()),
        )
        .expect("valid metric opts for outbox_pending_count");

        let oldest_pending_age_seconds = IntGauge::with_opts(
            Opts::new(
                "outbox_oldest_pending_age_seconds",
                "Age in seconds of the oldest pending outbox event",
            )
            .const_label("service", service.to_string()),
        )
        .expect("valid metric opts for outbox_oldest_pending_age_seconds");

        let published = IntCounter::with_opts(
            Opts::new(
                "outbox_published_total",
                "Total number of outbox events marked as published",
            )
            .const_label("service", service.to_string()),
        )
        .expect("valid metric opts for outbox_published_total");

        for metric in [
            Box::new(pending.clone()) as Box<dyn prometheus::core::Collector>,
            Box::new(oldest_pending_age_seconds.clone()),
            Box::new(published.clone()),
        ] {
            if let Err(e) = registry.register(metric) {
                warn!("Failed to register outbox metric: {}", e);
            }
        }

        Self {
            pending,
            oldest_pending_age_seconds,
            published,
        }
    }
}

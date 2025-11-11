use actix_web::{HttpResponse, Responder};
use once_cell::sync::Lazy;
use prometheus::{
    exponential_buckets, Encoder, HistogramOpts, HistogramVec, IntCounter, IntCounterVec, IntGauge,
    Opts, TextEncoder,
};
use sqlx::PgPool;
use std::time::Duration;

/// Handler that serialises Prometheus metrics in text format.
pub async fn metrics_handler() -> impl Responder {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    match encoder.encode(&metric_families, &mut buffer) {
        Ok(_) => HttpResponse::Ok()
            .content_type(encoder.format_type())
            .body(buffer),
        Err(err) => HttpResponse::InternalServerError().body(err.to_string()),
    }
}

// =========================
// Outbox backlog gauge
// =========================

/// Initialize outbox metrics gauge (call from main() for better error handling)
#[allow(dead_code)]
pub fn initialize_outbox_gauge() -> Result<(), Box<dyn std::error::Error>> {
    let g = IntGauge::new(
        "outbox_unpublished_events",
        "Number of unpublished events in outbox table",
    )?;
    prometheus::default_registry().register(Box::new(g.clone()))?;

    // Cache the gauge for later use
    let _ = &*OUTBOX_UNPUBLISHED_EVENTS; // Force lazy init
    Ok(())
}

static OUTBOX_UNPUBLISHED_EVENTS: Lazy<IntGauge> = Lazy::new(|| {
    // This is called lazily only if the gauge is accessed
    // For proper error handling, call initialize_outbox_gauge() from main()
    match IntGauge::new(
        "outbox_unpublished_events",
        "Number of unpublished events in outbox table",
    ) {
        Ok(g) => {
            // Try to register, but if it fails, we'll still return the gauge
            // (it might have been registered by initialize_outbox_gauge already)
            let _ = prometheus::default_registry().register(Box::new(g.clone()));
            g
        }
        Err(e) => {
            tracing::error!("failed to create outbox gauge: {}", e);
            // Return a dummy gauge to avoid panicking in lazy_static context
            IntGauge::new("dummy", "dummy").expect("dummy gauge")
        }
    }
});

pub fn spawn_metrics_updater(db: PgPool) {
    tokio::spawn(async move {
        let interval = Duration::from_secs(10);
        loop {
            if let Err(e) = update_outbox_gauge(&db).await {
                tracing::debug!("outbox metrics updater failed: {}", e);
            }
            tokio::time::sleep(interval).await;
        }
    });
}

async fn update_outbox_gauge(db: &PgPool) -> Result<(), sqlx::Error> {
    let count: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*)
        FROM outbox_events
        WHERE published_at IS NULL
          AND retry_count < 3
        "#,
    )
    .fetch_one(db)
    .await?;

    OUTBOX_UNPUBLISHED_EVENTS.set(count as i64);
    Ok(())
}

#[allow(dead_code)]
static OUTBOX_EVENTS_PROCESSED_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "outbox_events_processed_total",
        "Total number of outbox events successfully published to Kafka",
        &["event_type"],
    )
});

#[allow(dead_code)]
static OUTBOX_EVENTS_FAILED_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "outbox_events_failed_total",
        "Total number of outbox events that failed to publish",
        &["event_type", "reason"],
    )
});

#[allow(dead_code)]
static OUTBOX_RETRY_ATTEMPTS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "outbox_retry_attempts_total",
        "Total retry attempts made by the outbox consumer",
        &["event_type", "attempt"],
    )
});

#[allow(dead_code)]
static OUTBOX_DLQ_MESSAGES_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "outbox_dlq_messages_total",
        "Total number of outbox events routed to the DLQ",
        &["event_type"],
    )
});

#[allow(dead_code)]
static OUTBOX_CONSUMER_LATENCY_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    let buckets =
        exponential_buckets(0.1, 2.0, 8).unwrap_or_else(|_| vec![0.1, 0.5, 1.0, 2.0, 5.0, 10.0]);
    register_histogram_vec(
        "outbox_consumer_latency_seconds",
        "Latency between outbox insert and Kafka publish (seconds)",
        &["event_type"],
        buckets,
    )
});

#[allow(dead_code)]
pub fn record_outbox_processed(event_type: &str) {
    OUTBOX_EVENTS_PROCESSED_TOTAL
        .with_label_values(&[event_type])
        .inc();
}

#[allow(dead_code)]
pub fn record_outbox_failure(event_type: &str, reason: &str) {
    OUTBOX_EVENTS_FAILED_TOTAL
        .with_label_values(&[event_type, reason])
        .inc();
}

#[allow(dead_code)]
pub fn record_outbox_retry_attempt(event_type: &str, attempt: u32) {
    let attempt_label = attempt.to_string();
    OUTBOX_RETRY_ATTEMPTS_TOTAL
        .with_label_values(&[event_type, &attempt_label])
        .inc();
}

#[allow(dead_code)]
pub fn record_outbox_dlq_message(event_type: &str) {
    OUTBOX_DLQ_MESSAGES_TOTAL
        .with_label_values(&[event_type])
        .inc();
}

#[allow(dead_code)]
pub fn record_outbox_latency(event_type: &str, latency_seconds: f64) {
    OUTBOX_CONSUMER_LATENCY_SECONDS
        .with_label_values(&[event_type])
        .observe(latency_seconds);
}

// =========================
// T050: Auth Service Metrics
// =========================

/// Initialize auth service metrics counters (call from main() for better error handling)
#[allow(dead_code)]
pub fn initialize_auth_metrics() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize all counters by forcing lazy evaluation
    let _ = &*REGISTER_REQUESTS_TOTAL;
    let _ = &*LOGIN_REQUESTS_TOTAL;
    let _ = &*LOGIN_FAILURES_TOTAL;
    let _ = &*ACCOUNT_LOCKOUTS_TOTAL;
    Ok(())
}

/// Counter for total Register RPC calls (incremented for each register attempt)
static REGISTER_REQUESTS_TOTAL: Lazy<IntCounter> = Lazy::new(|| {
    IntCounter::new(
        "register_requests_total",
        "Total number of Register RPC requests",
    )
    .and_then(|c| {
        prometheus::default_registry().register(Box::new(c.clone()))?;
        Ok(c)
    })
    .unwrap_or_else(|e| {
        tracing::error!("failed to create register_requests counter: {}", e);
        IntCounter::new("dummy_register", "dummy").expect("dummy counter")
    })
});

/// Counter for total Login RPC calls (incremented for each login attempt)
static LOGIN_REQUESTS_TOTAL: Lazy<IntCounter> = Lazy::new(|| {
    IntCounter::new("login_requests_total", "Total number of Login RPC requests")
        .and_then(|c| {
            prometheus::default_registry().register(Box::new(c.clone()))?;
            Ok(c)
        })
        .unwrap_or_else(|e| {
            tracing::error!("failed to create login_requests counter: {}", e);
            IntCounter::new("dummy_login", "dummy").expect("dummy counter")
        })
});

/// Counter for total login failures (wrong password or user not found)
static LOGIN_FAILURES_TOTAL: Lazy<IntCounter> = Lazy::new(|| {
    IntCounter::new(
        "login_failures_total",
        "Total number of failed login attempts (wrong password or user not found)",
    )
    .and_then(|c| {
        prometheus::default_registry().register(Box::new(c.clone()))?;
        Ok(c)
    })
    .unwrap_or_else(|e| {
        tracing::error!("failed to create login_failures counter: {}", e);
        IntCounter::new("dummy_failures", "dummy").expect("dummy counter")
    })
});

/// Counter for account lockouts (triggered after 5 failed login attempts)
static ACCOUNT_LOCKOUTS_TOTAL: Lazy<IntCounter> = Lazy::new(|| {
    IntCounter::new(
        "account_lockouts_total",
        "Total number of account lockouts triggered (5+ failed attempts)",
    )
    .and_then(|c| {
        prometheus::default_registry().register(Box::new(c.clone()))?;
        Ok(c)
    })
    .unwrap_or_else(|e| {
        tracing::error!("failed to create account_lockouts counter: {}", e);
        IntCounter::new("dummy_lockouts", "dummy").expect("dummy counter")
    })
});

static REGISTRATION_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "auth_registration_total",
        "Total number of user registrations",
        &["status"],
    )
});

static OAUTH_LOGINS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "auth_oauth_logins_total",
        "Total number of OAuth logins",
        &["provider", "status"],
    )
});

static OAUTH_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec(
        "auth_oauth_duration_seconds",
        "Time spent processing OAuth requests",
        &["provider", "operation"],
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0],
    )
});

static TWOFA_SETUP_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "auth_2fa_setup_total",
        "Total number of 2FA setup attempts",
        &["operation", "status"],
    )
});

static TWOFA_SETUP_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec(
        "auth_2fa_setup_duration_seconds",
        "Time spent processing 2FA setup operations",
        &["operation"],
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
    )
});

static TWOFA_ATTEMPTS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_counter_vec(
        "auth_2fa_attempts_total",
        "Total number of 2FA verification attempts",
        &["status"],
    )
});

// Public functions to increment metrics from gRPC handlers (T050)

/// Increment register requests counter
#[inline]
#[allow(dead_code)]
pub fn inc_register_requests() {
    REGISTER_REQUESTS_TOTAL.inc();
}

/// Increment login requests counter
#[inline]
#[allow(dead_code)]
pub fn inc_login_requests() {
    LOGIN_REQUESTS_TOTAL.inc();
}

/// Increment login failures counter
#[inline]
#[allow(dead_code)]
pub fn inc_login_failures() {
    LOGIN_FAILURES_TOTAL.inc();
}

/// Increment account lockouts counter
#[inline]
#[allow(dead_code)]
pub fn inc_account_lockouts() {
    ACCOUNT_LOCKOUTS_TOTAL.inc();
}

#[inline]
pub fn record_registration(success: bool) {
    let status = if success { "success" } else { "failed" };
    REGISTRATION_TOTAL.with_label_values(&[status]).inc();
}

#[inline]
pub fn record_oauth_login(provider: &str, success: bool, duration_ms: u64) {
    let status = if success { "success" } else { "failed" };
    OAUTH_LOGINS_TOTAL
        .with_label_values(&[provider, status])
        .inc();
    OAUTH_DURATION_SECONDS
        .with_label_values(&[provider, "authorize"])
        .observe(duration_ms as f64 / 1000.0);
}

#[inline]
pub fn record_two_fa_setup(operation: &str, success: bool, duration_ms: u64) {
    let status = if success { "success" } else { "failed" };
    TWOFA_SETUP_TOTAL
        .with_label_values(&[operation, status])
        .inc();
    TWOFA_SETUP_DURATION_SECONDS
        .with_label_values(&[operation])
        .observe(duration_ms as f64 / 1000.0);
}

#[inline]
pub fn record_two_fa_verification(success: bool) {
    let status = if success { "success" } else { "failed" };
    TWOFA_ATTEMPTS_TOTAL.with_label_values(&[status]).inc();
}

#[allow(dead_code)]
fn register_counter_vec(name: &str, help: &str, labels: &[&str]) -> IntCounterVec {
    let opts = Opts::new(name, help);
    match IntCounterVec::new(opts, labels) {
        Ok(counter) => {
            if let Err(err) = prometheus::default_registry().register(Box::new(counter.clone())) {
                tracing::error!("failed to register {} counter: {}", name, err);
            }
            counter
        }
        Err(err) => {
            tracing::error!("failed to create {} counter: {}", name, err);
            let fallback_name = format!("{}_fallback", name);
            let counter = IntCounterVec::new(Opts::new(&fallback_name, help), labels)
                .expect("failed to create fallback counter vec");
            let _ = prometheus::default_registry().register(Box::new(counter.clone()));
            counter
        }
    }
}

#[allow(dead_code)]
fn register_histogram_vec(
    name: &str,
    help: &str,
    labels: &[&str],
    buckets: Vec<f64>,
) -> HistogramVec {
    let opts = HistogramOpts::new(name, help).buckets(buckets);
    match HistogramVec::new(opts, labels) {
        Ok(histogram) => {
            if let Err(err) = prometheus::default_registry().register(Box::new(histogram.clone())) {
                tracing::error!("failed to register {} histogram: {}", name, err);
            }
            histogram
        }
        Err(err) => {
            tracing::error!("failed to create {} histogram: {}", name, err);
            let fallback_name = format!("{}_fallback", name);
            let fallback_opts = HistogramOpts::new(&fallback_name, help)
                .buckets(vec![0.1, 0.5, 1.0, 2.0, 5.0, 10.0]);
            let histogram = HistogramVec::new(fallback_opts, labels)
                .expect("failed to create fallback histogram vec");
            let _ = prometheus::default_registry().register(Box::new(histogram.clone()));
            histogram
        }
    }
}

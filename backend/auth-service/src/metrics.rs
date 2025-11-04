use actix_web::{HttpResponse, Responder};
use once_cell::sync::Lazy;
use prometheus::{Encoder, IntCounter, IntGauge, TextEncoder};
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
    IntCounter::new(
        "login_requests_total",
        "Total number of Login RPC requests",
    )
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

// Public functions to increment metrics from gRPC handlers (T050)

/// Increment register requests counter
#[inline]
pub fn inc_register_requests() {
    REGISTER_REQUESTS_TOTAL.inc();
}

/// Increment login requests counter
#[inline]
pub fn inc_login_requests() {
    LOGIN_REQUESTS_TOTAL.inc();
}

/// Increment login failures counter
#[inline]
pub fn inc_login_failures() {
    LOGIN_FAILURES_TOTAL.inc();
}

/// Increment account lockouts counter
#[inline]
pub fn inc_account_lockouts() {
    ACCOUNT_LOCKOUTS_TOTAL.inc();
}

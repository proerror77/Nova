use actix_web::HttpResponse;
use once_cell::sync::Lazy;
use prometheus::{Encoder, HistogramOpts, HistogramVec, IntCounterVec, IntGauge, Opts, TextEncoder};
use sqlx::{PgPool};
use std::time::Duration;

static HTTP_REQUESTS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    let counter = IntCounterVec::new(
        Opts::new(
            "messaging_service_http_requests_total",
            "Total HTTP requests handled by messaging-service",
        ),
        &["method", "path", "status"],
    )
    .expect("failed to create messaging_service_http_requests_total");
    prometheus::default_registry()
        .register(Box::new(counter.clone()))
        .expect("failed to register messaging_service_http_requests_total");
    counter
});

static HTTP_REQUEST_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    let histogram = HistogramVec::new(
        HistogramOpts::new(
            "messaging_service_http_request_duration_seconds",
            "HTTP request latencies for messaging-service",
        )
        .buckets(vec![
            0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5,
        ]),
        &["method", "path", "status"],
    )
    .expect("failed to create messaging_service_http_request_duration_seconds");
    prometheus::default_registry()
        .register(Box::new(histogram.clone()))
        .expect("failed to register messaging_service_http_request_duration_seconds");
    histogram
});

pub async fn metrics_handler() -> HttpResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    if let Err(err) = encoder.encode(&metric_families, &mut buffer) {
        return HttpResponse::InternalServerError().body(err.to_string());
    }

    HttpResponse::Ok()
        .content_type(encoder.format_type())
        .body(buffer)
}

// =========================
// Queue depth gauges
// =========================

static NOTIFICATION_JOBS_PENDING: Lazy<IntGauge> = Lazy::new(|| {
    let g = IntGauge::new(
        "notification_jobs_pending",
        "Number of pending notification jobs (unclaimed or stale claims)",
    )
    .expect("create notification_jobs_pending gauge");
    prometheus::default_registry()
        .register(Box::new(g.clone()))
        .expect("register notification_jobs_pending");
    g
});

static NOTIFICATION_JOBS_FAILED: Lazy<IntGauge> = Lazy::new(|| {
    let g = IntGauge::new(
        "notification_jobs_failed",
        "Number of failed notification jobs",
    )
    .expect("create notification_jobs_failed gauge");
    prometheus::default_registry()
        .register(Box::new(g.clone()))
        .expect("register notification_jobs_failed");
    g
});

/// Spawn a background task that periodically updates queue depth gauges
pub fn spawn_metrics_updater(db: PgPool) {
    tokio::spawn(async move {
        let interval = Duration::from_secs(10);
        loop {
            if let Err(e) = update_gauges(&db).await {
                tracing::debug!("metrics updater failed: {}", e);
            }
            tokio::time::sleep(interval).await;
        }
    });
}

async fn update_gauges(db: &PgPool) -> Result<(), sqlx::Error> {
    // pending = status='pending' and (unclaimed or stale claim)
    let pending: i64 = sqlx::query_scalar(
        r#"
        SELECT COUNT(*)
        FROM notification_jobs
        WHERE status = 'pending'
          AND (claimed_at IS NULL OR claimed_at < NOW() - INTERVAL '5 minutes')
        "#,
    )
    .fetch_one(db)
    .await?;

    let failed: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM notification_jobs WHERE status = 'failed'",
    )
    .fetch_one(db)
    .await?;

    NOTIFICATION_JOBS_PENDING.set(pending as i64);
    NOTIFICATION_JOBS_FAILED.set(failed as i64);

    Ok(())
}

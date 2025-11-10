//! Prometheus metrics for database connection pool
//!
//! Tracks pool size, connection acquisition latency, and errors

use prometheus::{register_histogram_vec, register_int_gauge_vec, HistogramVec, IntGaugeVec};
use sqlx::{pool::PoolConnection, PgPool, Postgres};
use std::time::Instant;

lazy_static::lazy_static! {
    /// Database connection pool size by state (idle/active/max)
    static ref DB_POOL_CONNECTIONS: IntGaugeVec = register_int_gauge_vec!(
        "db_pool_connections",
        "Database pool connection count by state",
        &["service", "state"]
    ).expect("Prometheus metrics registration should succeed at startup");

    /// Time to acquire a connection from the pool
    static ref DB_POOL_ACQUIRE_DURATION: HistogramVec = register_histogram_vec!(
        "db_pool_acquire_duration_seconds",
        "Time to acquire connection from pool",
        &["service"],
        vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0]
    ).expect("Prometheus metrics registration should succeed at startup");

    /// Connection acquisition errors by type
    static ref DB_POOL_CONNECTION_ERRORS: IntGaugeVec = register_int_gauge_vec!(
        "db_pool_connection_errors_total",
        "Connection acquisition errors",
        &["service", "error_type"]
    ).expect("Prometheus metrics registration should succeed at startup");
}

/// Update connection pool metrics (called periodically)
pub(crate) fn update_pool_metrics(pool: &PgPool, service: &str) {
    let size = pool.size() as i64;
    let idle = pool.num_idle() as i64;
    let active = size - idle;

    DB_POOL_CONNECTIONS
        .with_label_values(&[service, "idle"])
        .set(idle);

    DB_POOL_CONNECTIONS
        .with_label_values(&[service, "active"])
        .set(active);

    DB_POOL_CONNECTIONS
        .with_label_values(&[service, "max"])
        .set(pool.options().get_max_connections() as i64);
}

/// Acquire a connection from the pool and record metrics
///
/// This is a drop-in replacement for `pool.acquire().await` that automatically
/// tracks acquisition latency and error rates.
///
/// # Example
/// ```no_run
/// # use db_pool::{create_pool, DbConfig, acquire_with_metrics};
/// # #[tokio::main]
/// # async fn main() -> Result<(), Box<dyn std::error::Error>> {
/// # let pool = create_pool(DbConfig::for_service("test")).await?;
/// let conn = acquire_with_metrics(&pool, "my-service").await?;
/// sqlx::query("SELECT 1").execute(&mut *conn).await?;
/// # Ok(())
/// # }
/// ```
pub async fn acquire_with_metrics(
    pool: &PgPool,
    service: &str,
) -> Result<PoolConnection<Postgres>, sqlx::Error> {
    let start = Instant::now();
    let result = pool.acquire().await;

    DB_POOL_ACQUIRE_DURATION
        .with_label_values(&[service])
        .observe(start.elapsed().as_secs_f64());

    if let Err(e) = &result {
        let error_type = match e {
            sqlx::Error::PoolTimedOut => "timeout",
            sqlx::Error::PoolClosed => "closed",
            _ => "other",
        };

        DB_POOL_CONNECTION_ERRORS
            .with_label_values(&[service, error_type])
            .inc();
    }

    result
}

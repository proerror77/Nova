//! Prometheus metrics for database connection pool
//!
//! Tracks pool size, connection acquisition latency, and errors

use prometheus::{register_histogram_vec, register_int_gauge_vec, HistogramVec, IntGaugeVec};
use deadpool_postgres::{Pool, Client};
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

    /// Pool exhaustion rejections counter
    static ref DB_POOL_EXHAUSTED: IntGaugeVec = register_int_gauge_vec!(
        "db_pool_exhausted_total",
        "Requests rejected due to pool exhaustion",
        &["service"]
    ).expect("Prometheus metrics registration should succeed at startup");

    /// Pool utilization ratio (0.0 to 1.0)
    static ref DB_POOL_UTILIZATION: prometheus::GaugeVec = prometheus::register_gauge_vec!(
        "db_pool_utilization_ratio",
        "Pool utilization ratio (active/max)",
        &["service"]
    ).expect("Prometheus metrics registration should succeed at startup");
}

/// Update connection pool metrics (called periodically)
pub(crate) fn update_pool_metrics(pool: &Pool, service: &str) {
    let size = pool.status().size as i64;
    let idle = pool.status().available as i64;
    let active = size - idle;
    let max = pool.status().max_size as i64;

    DB_POOL_CONNECTIONS
        .with_label_values(&[service, "idle"])
        .set(idle);

    DB_POOL_CONNECTIONS
        .with_label_values(&[service, "active"])
        .set(active);

    DB_POOL_CONNECTIONS
        .with_label_values(&[service, "max"])
        .set(max);

    // Update utilization ratio
    let utilization = if max > 0 {
        active as f64 / max as f64
    } else {
        0.0
    };
    DB_POOL_UTILIZATION
        .with_label_values(&[service])
        .set(utilization);
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
    pool: &Pool,
    service: &str,
) -> Result<Client, deadpool_postgres::PoolError> {
    let start = Instant::now();
    let result = pool.get().await;

    DB_POOL_ACQUIRE_DURATION
        .with_label_values(&[service])
        .observe(start.elapsed().as_secs_f64());

    if result.is_err() {
        DB_POOL_CONNECTION_ERRORS
            .with_label_values(&[service, "other"])
            .inc();
    }

    result
}

/// Configuration for pool exhaustion backpressure
#[derive(Debug, Clone, Copy)]
pub struct BackpressureConfig {
    /// Utilization threshold above which to reject requests (0.0-1.0)
    /// Default: 0.85 (reject when 85% of connections are active)
    pub threshold: f64,
}

impl Default for BackpressureConfig {
    fn default() -> Self {
        Self { threshold: 0.85 }
    }
}

impl BackpressureConfig {
    /// Create config from environment variable or use default
    ///
    /// Environment variable: DB_POOL_BACKPRESSURE_THRESHOLD (e.g., "0.90" for 90%)
    pub fn from_env() -> Self {
        let threshold = std::env::var("DB_POOL_BACKPRESSURE_THRESHOLD")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .filter(|&t| t > 0.0 && t <= 1.0)
            .unwrap_or(0.85);

        Self { threshold }
    }
}

/// Error returned when pool is exhausted
#[derive(Debug, Clone)]
pub struct PoolExhaustedError {
    pub service: String,
    pub utilization: f64,
    pub threshold: f64,
}

impl std::fmt::Display for PoolExhaustedError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Database pool exhausted (service={}, utilization={:.2}%, threshold={:.2}%)",
            self.service,
            self.utilization * 100.0,
            self.threshold * 100.0
        )
    }
}

impl std::error::Error for PoolExhaustedError {}

/// Acquire a connection with backpressure (early rejection when pool is exhausted)
///
/// This prevents cascading failures by rejecting requests immediately when the pool
/// is near capacity, rather than waiting for timeout. This is a critical resilience
/// pattern for preventing service degradation.
///
/// # Behavior
/// - Checks pool utilization before attempting to acquire
/// - If utilization > threshold: Rejects immediately with PoolExhaustedError
/// - If utilization <= threshold: Acquires connection normally
/// - Records metrics for rejections and utilization
///
/// # Example
/// ```no_run
/// # use db_pool::{create_pool, DbConfig, acquire_with_backpressure, BackpressureConfig};
/// # #[tokio::main]
/// # async fn main() -> Result<(), Box<dyn std::error::Error>> {
/// # let pool = create_pool(DbConfig::for_service("test")).await?;
/// let config = BackpressureConfig::default(); // 0.85 threshold
/// match acquire_with_backpressure(&pool, "my-service", config).await {
///     Ok(conn) => {
///         // Use connection
///         sqlx::query("SELECT 1").execute(&mut *conn).await?;
///     }
///     Err(e) => {
///         // Pool exhausted - fail fast, don't cascade
///         eprintln!("Pool exhausted: {}", e);
///         return Err(e.into());
///     }
/// }
/// # Ok(())
/// # }
/// ```
pub async fn acquire_with_backpressure(
    pool: &Pool,
    service: &str,
    config: BackpressureConfig,
) -> Result<Client, PoolExhaustedError> {
    // Check pool utilization BEFORE attempting to acquire
    let status = pool.status();
    let size = status.size as f64;
    let idle = status.available as f64;
    let active = size - idle;
    let max = status.max_size as f64;

    let utilization = if max > 0.0 { active / max } else { 0.0 };

    // Update utilization metric immediately
    DB_POOL_UTILIZATION
        .with_label_values(&[service])
        .set(utilization);

    // Early rejection if pool is exhausted
    if utilization > config.threshold {
        DB_POOL_EXHAUSTED.with_label_values(&[service]).inc();

        tracing::warn!(
            service = %service,
            utilization = %utilization,
            threshold = %config.threshold,
            active = %active,
            max = %max,
            "Pool exhaustion: Rejecting request (backpressure)"
        );

        return Err(PoolExhaustedError {
            service: service.to_string(),
            utilization,
            threshold: config.threshold,
        });
    }

    // Pool has capacity - acquire normally with metrics
    let start = Instant::now();
    let result = pool.get().await;

    DB_POOL_ACQUIRE_DURATION
        .with_label_values(&[service])
        .observe(start.elapsed().as_secs_f64());

    match result {
        Ok(conn) => Ok(conn),
        Err(e) => {
            // Log acquisition error
            let error_type = "other";

            DB_POOL_CONNECTION_ERRORS
                .with_label_values(&[service, error_type])
                .inc();

            tracing::error!(
                service = %service,
                error = %e,
                error_type = %error_type,
                "Connection acquisition failed after backpressure check"
            );

            // Convert sqlx error to exhaustion error for consistency
            Err(PoolExhaustedError {
                service: service.to_string(),
                utilization: 1.0, // Assume full if acquisition failed
                threshold: config.threshold,
            })
        }
    }
}

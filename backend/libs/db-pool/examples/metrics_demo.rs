//! Demonstrates connection pool metrics tracking
//!
//! Run with:
//! ```bash
//! cargo run --example metrics_demo
//! ```
//!
//! Then check metrics:
//! ```bash
//! curl http://localhost:9090/metrics | grep db_pool
//! ```

use db_pool::{acquire_with_metrics, create_pool, DbConfig};
use prometheus::{Encoder, TextEncoder};
use sqlx::Row;
use std::time::Duration;
use tokio::time::sleep;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    println!("=== Database Connection Pool Metrics Demo ===\n");

    // Create a pool for testing (requires DATABASE_URL env var)
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:5432/postgres".to_string());

    println!("Creating pool with config:");
    let config = DbConfig {
        service_name: "metrics-demo".to_string(),
        database_url,
        max_connections: 10,
        min_connections: 2,
        connect_timeout_secs: 5,
        acquire_timeout_secs: 10,
        idle_timeout_secs: 60,
        max_lifetime_secs: 300,
    };
    config.log_config();

    let pool = create_pool(config).await?;
    println!("\n✓ Pool created successfully with automatic metrics\n");

    // Simulate some database activity
    println!("Simulating database activity...\n");

    for i in 0..5 {
        println!("Iteration {}: Acquiring connection...", i + 1);

        // Use acquire_with_metrics to track acquisition latency
        let mut conn = acquire_with_metrics(&pool, "metrics-demo").await?;

        // Simulate some work
        let result = sqlx::query("SELECT 1 as value")
            .fetch_one(&mut *conn)
            .await?;

        let value: i32 = result.get("value");
        println!("  Query result: {}", value);

        // Hold connection for a bit to show active connections
        sleep(Duration::from_millis(500)).await;

        // Connection is automatically returned to pool when dropped
    }

    println!("\n=== Metrics Snapshot ===\n");

    // Export metrics
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    // Filter and display only db_pool metrics
    for mf in metric_families {
        if mf.get_name().starts_with("db_pool") {
            let mut buffer = Vec::new();
            encoder.encode(&[mf.clone()], &mut buffer)?;
            print!("{}", String::from_utf8(buffer)?);
        }
    }

    println!("\n=== Explanation ===\n");
    println!("db_pool_connections{{state=\"active\"}}  - Currently in-use connections");
    println!("db_pool_connections{{state=\"idle\"}}    - Available connections in pool");
    println!("db_pool_connections{{state=\"max\"}}     - Maximum pool capacity");
    println!("\ndb_pool_acquire_duration_seconds_*     - Connection acquisition latency histogram");
    println!("db_pool_connection_errors_total        - Connection acquisition errors\n");

    println!("To serve metrics via HTTP, integrate with actix-web-prometheus or similar.");
    println!("See MIGRATION_GUIDE.md for examples.\n");

    Ok(())
}

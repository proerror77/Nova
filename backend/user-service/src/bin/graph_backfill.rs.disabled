use std::sync::Arc;

use chrono::{DateTime, Utc};
use futures::{stream, StreamExt};
use sqlx::Row;
use tracing::{error, info, warn};
use user_service::{config::Config, db::create_pool, services::graph::GraphService};
use uuid::Uuid;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,sqlx=warn".into()),
        )
        .init();

    let cfg = Config::from_env()?;

    if !cfg.graph.enabled {
        warn!("NEO4J_ENABLED=false; nothing to do");
        return Ok(());
    }

    let pool = create_pool(&cfg.database.url, cfg.database.max_connections).await?;
    let graph = Arc::new(GraphService::new(&cfg.graph).await?);

    let batch_size: i64 = std::env::var("BACKFILL_BATCH_SIZE")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(5000);
    let concurrency: usize = std::env::var("BACKFILL_CONCURRENCY")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8);

    info!(batch_size, concurrency, "Starting follows → Neo4j backfill");

    // Count total
    let total: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM follows")
        .fetch_one(&pool)
        .await
        .unwrap_or(0);
    info!(total, "Total rows in follows");

    let mut last_id: Option<Uuid> = None;
    let since = std::env::var("BACKFILL_SINCE").ok();
    let lookback_min = std::env::var("BACKFILL_LOOKBACK_MINUTES")
        .ok()
        .and_then(|s| s.parse::<i64>().ok());
    let since_dt: Option<DateTime<Utc>> = if let Some(s) = since {
        match DateTime::parse_from_rfc3339(&s) {
            Ok(dt) => Some(dt.with_timezone(&Utc)),
            Err(_) => {
                warn!("Invalid BACKFILL_SINCE format, expected RFC3339. Ignoring");
                None
            }
        }
    } else if let Some(mins) = lookback_min {
        Some(Utc::now() - chrono::Duration::minutes(mins))
    } else {
        None
    };

    if let Some(s) = since_dt {
        info!(since = %s, "Running incremental backfill (created_at >= since)");
    }
    let mut processed: i64 = 0;

    loop {
        let rows = if let Some(since_dt) = since_dt {
            if let Some(id) = last_id {
                sqlx::query(
                    "SELECT id, follower_id, following_id FROM follows \
                     WHERE created_at >= $1 AND id > $2 \
                     ORDER BY id ASC LIMIT $3",
                )
                .bind(since_dt)
                .bind(id)
                .bind(batch_size)
                .fetch_all(&pool)
                .await?
            } else {
                sqlx::query(
                    "SELECT id, follower_id, following_id FROM follows \
                     WHERE created_at >= $1 \
                     ORDER BY id ASC LIMIT $2",
                )
                .bind(since_dt)
                .bind(batch_size)
                .fetch_all(&pool)
                .await?
            }
        } else {
            if let Some(id) = last_id {
                sqlx::query(
                    "SELECT id, follower_id, following_id FROM follows \
                     WHERE id > $1 ORDER BY id ASC LIMIT $2",
                )
                .bind(id)
                .bind(batch_size)
                .fetch_all(&pool)
                .await?
            } else {
                sqlx::query(
                    "SELECT id, follower_id, following_id FROM follows \
                     ORDER BY id ASC LIMIT $1",
                )
                .bind(batch_size)
                .fetch_all(&pool)
                .await?
            }
        };

        if rows.is_empty() {
            break;
        }

        let mut items = Vec::with_capacity(rows.len());
        for r in rows {
            let id: Uuid = r.try_get("id")?;
            let follower: Uuid = r.try_get("follower_id")?;
            let followee: Uuid = r.try_get("following_id")?;
            last_id = Some(id);
            items.push((follower, followee));
        }

        stream::iter(items)
            .map(|(follower, followee)| {
                let g = graph.clone();
                async move {
                    if let Err(e) = g.follow(follower, followee).await {
                        error!("backfill follow error: {} -> {}: {}", follower, followee, e);
                    }
                }
            })
            .buffer_unordered(concurrency)
            .collect::<Vec<_>>()
            .await;

        processed += batch_size;
        info!(processed, total, "Backfill progress");
    }

    info!("Backfill complete: processed {} rows", processed);
    Ok(())
}

/// Migration script: PostgreSQL follows table → Neo4j FOLLOWS edges
///
/// Usage:
///   cargo run --bin migrate_follows_to_neo4j
///
/// Environment variables:
///   DATABASE_URL - PostgreSQL connection string
///   NEO4J_URI - Neo4j bolt URI
///   NEO4J_USER - Neo4j username
///   NEO4J_PASSWORD - Neo4j password
///   BATCH_SIZE - Optional, default 1000
///   DRY_RUN - Optional, set to "true" for validation only
use anyhow::{Context, Result};
use neo4rs::{query, Graph};
use sqlx::postgres::PgPoolOptions;
use std::env;
use tracing::{error, info, warn};
use uuid::Uuid;

#[derive(sqlx::FromRow)]
struct FollowRow {
    follower_id: Uuid,
    following_id: Uuid,
    created_at: chrono::DateTime<chrono::Utc>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    info!("Starting PostgreSQL → Neo4j migration");

    // Load configuration
    dotenv::dotenv().ok();
    let database_url = env::var("DATABASE_URL").context("DATABASE_URL not set")?;
    let neo4j_uri = env::var("NEO4J_URI").context("NEO4J_URI not set")?;
    let neo4j_user = env::var("NEO4J_USER").context("NEO4J_USER not set")?;
    let neo4j_password = env::var("NEO4J_PASSWORD").context("NEO4J_PASSWORD not set")?;
    let batch_size: usize = env::var("BATCH_SIZE")
        .unwrap_or_else(|_| "1000".to_string())
        .parse()
        .unwrap_or(1000);
    let dry_run = env::var("DRY_RUN").unwrap_or_default() == "true";

    if dry_run {
        warn!("DRY RUN MODE - No data will be written to Neo4j");
    }

    // Connect to PostgreSQL
    info!("Connecting to PostgreSQL...");
    let pg_pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .context("Failed to connect to PostgreSQL")?;

    info!("Connected to PostgreSQL");

    // Connect to Neo4j
    info!("Connecting to Neo4j...");
    let neo4j_graph = Graph::new(&neo4j_uri, &neo4j_user, &neo4j_password)
        .await
        .context("Failed to connect to Neo4j")?;

    info!("Connected to Neo4j");

    // Count total follows in PostgreSQL
    let total_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM follows")
        .fetch_one(&pg_pool)
        .await
        .context("Failed to count follows")?;

    info!("Total follows in PostgreSQL: {}", total_count);

    if total_count == 0 {
        warn!("No follows found in PostgreSQL. Nothing to migrate.");
        return Ok(());
    }

    // Count existing FOLLOWS edges in Neo4j
    let mut neo4j_result = neo4j_graph
        .execute(query("MATCH ()-[r:FOLLOWS]->() RETURN count(r) AS count"))
        .await
        .context("Failed to count Neo4j FOLLOWS edges")?;

    let neo4j_count: i64 = if let Some(row) = neo4j_result.next().await? {
        row.get("count").unwrap_or(0)
    } else {
        0
    };

    info!("Existing FOLLOWS edges in Neo4j: {}", neo4j_count);

    if neo4j_count > 0 && !dry_run {
        warn!(
            "Neo4j already contains {} FOLLOWS edges. This migration will create duplicates if re-run.",
            neo4j_count
        );
        warn!("To reset, run: MATCH ()-[r:FOLLOWS]->() DELETE r");
    }

    // Fetch follows from PostgreSQL in batches
    let mut offset = 0;
    let mut migrated = 0;
    let mut errors = 0;

    loop {
        info!(
            "Fetching batch: offset={}, limit={} ({}/{} migrated)",
            offset, batch_size, migrated, total_count
        );

        let rows: Vec<FollowRow> = sqlx::query_as(
            r#"
            SELECT follower_id, following_id, created_at
            FROM follows
            ORDER BY created_at
            LIMIT $1 OFFSET $2
            "#,
        )
        .bind(batch_size as i64)
        .bind(offset as i64)
        .fetch_all(&pg_pool)
        .await
        .context("Failed to fetch follows from PostgreSQL")?;

        if rows.is_empty() {
            info!("No more rows to process");
            break;
        }

        info!("Processing {} follows in this batch", rows.len());

        // Migrate batch to Neo4j
        if !dry_run {
            for row in &rows {
                match migrate_single_follow(&neo4j_graph, row).await {
                    Ok(_) => migrated += 1,
                    Err(e) => {
                        error!(
                            "Failed to migrate follow {} -> {}: {}",
                            row.follower_id, row.following_id, e
                        );
                        errors += 1;
                    }
                }

                // Progress indicator every 100 follows
                if migrated % 100 == 0 {
                    info!("Progress: {}/{} migrated", migrated, total_count);
                }
            }
        } else {
            // Dry run: just validate data
            migrated += rows.len();
        }

        offset += batch_size;

        // Safety: break if we've processed more than expected
        if offset > total_count as usize + batch_size {
            warn!("Processed more rows than expected. Breaking loop.");
            break;
        }
    }

    // Final summary
    info!("========================================");
    info!("Migration completed!");
    info!("Total follows in PostgreSQL: {}", total_count);
    info!("Successfully migrated: {}", migrated);
    if errors > 0 {
        error!("Failed migrations: {}", errors);
    }

    if dry_run {
        info!("DRY RUN - No data was actually written to Neo4j");
    } else {
        // Verify final count in Neo4j
        let mut verify_result = neo4j_graph
            .execute(query("MATCH ()-[r:FOLLOWS]->() RETURN count(r) AS count"))
            .await
            .context("Failed to verify Neo4j count")?;

        let final_neo4j_count: i64 = if let Some(row) = verify_result.next().await? {
            row.get("count").unwrap_or(0)
        } else {
            0
        };

        info!("Final FOLLOWS edges in Neo4j: {}", final_neo4j_count);

        if final_neo4j_count == total_count + neo4j_count {
            info!("✅ Verification passed: Neo4j count matches expected");
        } else {
            warn!(
                "⚠️ Count mismatch: Expected {}, Got {}",
                total_count + neo4j_count,
                final_neo4j_count
            );
        }
    }

    info!("========================================");

    Ok(())
}

async fn migrate_single_follow(neo4j_graph: &Graph, row: &FollowRow) -> Result<()> {
    let cypher = r#"
        MERGE (a:User {id: $follower_id})
        MERGE (b:User {id: $followee_id})
        MERGE (a)-[r:FOLLOWS]->(b)
        ON CREATE SET r.created_at = $created_at
    "#;

    let created_at_timestamp = row.created_at.timestamp_millis();

    let mut result = neo4j_graph
        .execute(
            query(cypher)
                .param("follower_id", row.follower_id.to_string())
                .param("followee_id", row.following_id.to_string())
                .param("created_at", created_at_timestamp),
        )
        .await
        .context("Failed to execute Neo4j query")?;

    // Drain result stream
    while result.next().await?.is_some() {}

    Ok(())
}

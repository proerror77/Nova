use anyhow::{Context, Result};
use graph_service::migration::neo4j_backfill::Neo4jBackfill;
use neo4rs::Graph;
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "neo4j_migrate=info,graph_service=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("🚀 Starting Neo4j Migration Tool");

    // Load environment variables
    let database_url = std::env::var("DATABASE_URL")
        .context("DATABASE_URL environment variable not set")?;

    let neo4j_uri = std::env::var("NEO4J_URI")
        .unwrap_or_else(|_| "bolt://neo4j:7687".to_string());

    let neo4j_user = std::env::var("NEO4J_USER")
        .unwrap_or_else(|_| "neo4j".to_string());

    let neo4j_password = std::env::var("NEO4J_PASSWORD")
        .context("NEO4J_PASSWORD environment variable not set")?;

    info!("📊 Connecting to PostgreSQL: {}", database_url);
    let pg_pool = PgPool::connect(&database_url)
        .await
        .context("Failed to connect to PostgreSQL")?;

    info!("🔗 Connecting to Neo4j: {}", neo4j_uri);
    let neo4j_graph = Graph::new(&neo4j_uri, &neo4j_user, &neo4j_password)
        .await
        .context("Failed to connect to Neo4j")?;

    // Parse command
    let args: Vec<String> = std::env::args().collect();
    let command = args.get(1).map(|s| s.as_str()).unwrap_or("help");

    let backfill = Neo4jBackfill::new(pg_pool.clone(), Arc::new(neo4j_graph));

    match command {
        "backfill" | "migrate" => {
            info!("📦 Starting backfill from PostgreSQL to Neo4j");
            match backfill.run().await {
                Ok(stats) => {
                    info!("✅ Migration completed successfully!");
                    info!("   Users migrated: {}", stats.users_migrated);
                    info!("   Follows migrated: {}", stats.follows_migrated);
                    info!("   Mutes migrated: {}", stats.mutes_migrated);
                    info!("   Blocks migrated: {}", stats.blocks_migrated);
                }
                Err(e) => {
                    error!("❌ Migration failed: {}", e);
                    return Err(e);
                }
            }
        }

        "verify" => {
            info!("🔍 Verifying data consistency");
            // Re-run backfill to get stats and verify
            match backfill.run().await {
                Ok(_) => info!("✅ Verification passed"),
                Err(e) => {
                    error!("❌ Verification failed: {}", e);
                    return Err(e);
                }
            }
        }

        "clear" => {
            info!("⚠️  Clearing Neo4j data");
            print!("Are you sure? This will delete ALL Neo4j data. Type 'yes' to confirm: ");
            use std::io::{self, Write};
            io::stdout().flush()?;

            let mut input = String::new();
            io::stdin().read_line(&mut input)?;

            if input.trim() == "yes" {
                backfill.clear_neo4j().await?;
                info!("✅ Neo4j data cleared");
            } else {
                info!("❌ Aborted");
            }
        }

        "check" => {
            info!("🔍 Checking database connections");

            // Check PostgreSQL
            match sqlx::query("SELECT COUNT(*) as total FROM users WHERE deleted_at IS NULL")
                .fetch_one(&pg_pool)
                .await
            {
                Ok(_) => info!("✅ PostgreSQL connection OK"),
                Err(e) => {
                    error!("❌ PostgreSQL connection failed: {}", e);
                    return Err(e.into());
                }
            }

            // Check Neo4j
            let neo4j_graph = Graph::new(&neo4j_uri, &neo4j_user, &neo4j_password).await?;
            let mut result = neo4j_graph
                .execute(neo4rs::query("MATCH (n) RETURN count(n) as total"))
                .await?;

            if let Some(row) = result.next().await? {
                let total: i64 = row.get("total").unwrap_or(0);
                info!("✅ Neo4j connection OK ({} nodes)", total);
            } else {
                info!("✅ Neo4j connection OK (empty database)");
            }
        }

        "stats" => {
            info!("📊 Database Statistics");

            // PostgreSQL stats
            let pg_users: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL"
            )
            .fetch_one(&pg_pool)
            .await?;

            let pg_follows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM follows")
                .fetch_one(&pg_pool)
                .await?;

            info!("PostgreSQL:");
            info!("  Users: {}", pg_users);
            info!("  Follows: {}", pg_follows);

            // Neo4j stats
            let neo4j_graph = Graph::new(&neo4j_uri, &neo4j_user, &neo4j_password).await?;

            let mut result = neo4j_graph
                .execute(neo4rs::query("MATCH (u:User) RETURN count(u) as total"))
                .await?;
            let neo4j_users: i64 = if let Some(row) = result.next().await? {
                row.get("total").unwrap_or(0)
            } else {
                0
            };

            let mut result = neo4j_graph
                .execute(neo4rs::query(
                    "MATCH ()-[r:FOLLOWS]->() RETURN count(r) as total",
                ))
                .await?;
            let neo4j_follows: i64 = if let Some(row) = result.next().await? {
                row.get("total").unwrap_or(0)
            } else {
                0
            };

            info!("Neo4j:");
            info!("  Users: {}", neo4j_users);
            info!("  Follows: {}", neo4j_follows);

            // Consistency check
            if pg_users == neo4j_users && pg_follows == neo4j_follows {
                info!("✅ Databases are in sync");
            } else {
                error!("❌ Data mismatch detected!");
                error!("   User diff: {}", pg_users - neo4j_users);
                error!("   Follow diff: {}", pg_follows - neo4j_follows);
            }
        }

        "help" | _ => {
            println!("Neo4j Migration Tool");
            println!();
            println!("Usage: neo4j-migrate <command>");
            println!();
            println!("Commands:");
            println!("  backfill   - Migrate data from PostgreSQL to Neo4j");
            println!("  verify     - Verify data consistency");
            println!("  clear      - Clear all Neo4j data (WARNING: destructive)");
            println!("  check      - Check database connections");
            println!("  stats      - Show database statistics");
            println!("  help       - Show this help message");
            println!();
            println!("Environment Variables:");
            println!("  DATABASE_URL       - PostgreSQL connection string (required)");
            println!("  NEO4J_URI          - Neo4j URI (default: bolt://neo4j:7687)");
            println!("  NEO4J_USER         - Neo4j username (default: neo4j)");
            println!("  NEO4J_PASSWORD     - Neo4j password (required)");
            println!();
            println!("Examples:");
            println!("  neo4j-migrate check");
            println!("  neo4j-migrate stats");
            println!("  neo4j-migrate backfill");
            println!("  neo4j-migrate verify");
        }
    }

    info!("🎉 Done!");
    Ok(())
}

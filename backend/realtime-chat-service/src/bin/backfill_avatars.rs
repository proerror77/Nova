/// Backfill script for syncing existing Nova avatars to Matrix
///
/// This script queries all users from the identity service and syncs their avatars
/// to Matrix media repository, caching the mxc:// URLs in the database.
///
/// Usage:
/// ```bash
/// cargo run --bin backfill-avatars -- [OPTIONS]
/// ```
///
/// Options:
/// - `--dry-run`: Preview what would be synced without making changes
/// - `--batch-size <N>`: Number of users to process per batch (default: 100)
/// - `--start-from <user_id>`: Resume from a specific user UUID
use anyhow::{Context, Result};
use deadpool_postgres::Pool;
use realtime_chat_service::services::{AvatarSyncService, MatrixAdminClient};
use std::sync::Arc;
use tokio_postgres::NoTls;
use tracing::{error, info, warn};
use uuid::Uuid;

#[derive(Debug)]
struct UserProfile {
    user_id: Uuid,
    username: String,
    avatar_url: Option<String>,
}

#[derive(Debug, Clone)]
struct BackfillConfig {
    dry_run: bool,
    batch_size: usize,
    start_from: Option<Uuid>,
}

impl Default for BackfillConfig {
    fn default() -> Self {
        Self {
            dry_run: false,
            batch_size: 100,
            start_from: None,
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    // Parse command line arguments
    let config = parse_args()?;

    info!("Starting avatar backfill with config: {:?}", config);

    // Load environment variables
    dotenvy::dotenv().ok();

    // Get database URLs from environment
    let chat_db_url = std::env::var("DATABASE_URL")
        .context("DATABASE_URL must be set for realtime-chat-service database")?;
    let identity_db_url = std::env::var("IDENTITY_DATABASE_URL")
        .context("IDENTITY_DATABASE_URL must be set to query user profiles")?;

    // Get Matrix configuration
    let matrix_homeserver = std::env::var("MATRIX_HOMESERVER_URL")
        .context("MATRIX_HOMESERVER_URL must be set")?;
    let matrix_admin_token = std::env::var("MATRIX_ADMIN_TOKEN")
        .context("MATRIX_ADMIN_TOKEN must be set")?;
    let matrix_server_name = std::env::var("MATRIX_SERVER_NAME")
        .context("MATRIX_SERVER_NAME must be set")?;

    // Initialize database pools
    info!("Connecting to databases...");
    let chat_pool = create_pool(&chat_db_url).await?;
    let identity_pool = create_pool(&identity_db_url).await?;

    // Initialize Matrix admin client
    let matrix_admin = Arc::new(MatrixAdminClient::new(
        matrix_homeserver,
        matrix_admin_token,
        matrix_server_name,
        None, // No auto-refresh for backfill script
    ));

    // Initialize avatar sync service
    let avatar_sync = Arc::new(AvatarSyncService::new(
        (*matrix_admin).clone(),
        chat_pool.clone(),
    ));

    // Run backfill
    run_backfill(identity_pool, avatar_sync, config).await?;

    info!("✅ Avatar backfill completed successfully");
    Ok(())
}

async fn create_pool(database_url: &str) -> Result<Pool> {
    let config = tokio_postgres::Config::from(
        database_url
            .parse::<tokio_postgres::Config>()
            .context("Invalid database URL")?,
    );

    let manager = deadpool_postgres::Manager::new(config, NoTls);
    let pool = Pool::builder(manager)
        .max_size(10)
        .build()
        .context("Failed to create database pool")?;

    Ok(pool)
}

async fn run_backfill(
    identity_pool: Pool,
    avatar_sync: Arc<AvatarSyncService>,
    config: BackfillConfig,
) -> Result<()> {
    let mut offset = 0;
    let mut total_processed = 0;
    let mut total_synced = 0;
    let mut total_skipped = 0;
    let mut total_errors = 0;

    // If resuming, skip to the start_from user
    if let Some(start_from_id) = config.start_from {
        info!("Resuming from user_id: {}", start_from_id);
        // We'll filter in the query instead
    }

    loop {
        // Fetch batch of users
        let users = fetch_user_batch(&identity_pool, config.batch_size, offset, config.start_from).await?;

        if users.is_empty() {
            info!("No more users to process");
            break;
        }

        info!(
            "Processing batch: offset={}, count={}, total_processed={}",
            offset,
            users.len(),
            total_processed
        );

        for user in users {
            total_processed += 1;

            // Skip users without avatar URLs
            if user.avatar_url.is_none() || user.avatar_url.as_ref().unwrap().is_empty() {
                total_skipped += 1;
                continue;
            }

            let avatar_url = user.avatar_url.as_ref().unwrap();

            // Skip non-HTTP URLs
            if !avatar_url.starts_with("http://") && !avatar_url.starts_with("https://") {
                warn!(
                    "Skipping user {} with non-HTTP avatar: {}",
                    user.user_id, avatar_url
                );
                total_skipped += 1;
                continue;
            }

            if config.dry_run {
                info!(
                    "[DRY RUN] Would sync avatar for user {}: {}",
                    user.user_id, avatar_url
                );
                total_synced += 1;
            } else {
                // Sync avatar to Matrix
                match avatar_sync
                    .sync_avatar_to_matrix(user.user_id, Some(avatar_url.clone()))
                    .await
                {
                    Ok(Some(mxc_url)) => {
                        info!(
                            "✅ Synced avatar for user {} ({}): {} -> {}",
                            user.username, user.user_id, avatar_url, mxc_url
                        );
                        total_synced += 1;
                    }
                    Ok(None) => {
                        warn!("Skipped avatar for user {}: no mxc URL returned", user.user_id);
                        total_skipped += 1;
                    }
                    Err(e) => {
                        error!(
                            "❌ Failed to sync avatar for user {} ({}): {}",
                            user.username, user.user_id, e
                        );
                        total_errors += 1;
                    }
                }
            }
        }

        offset += config.batch_size;

        // Progress report every 10 batches
        if offset % (config.batch_size * 10) == 0 {
            info!(
                "Progress: processed={}, synced={}, skipped={}, errors={}",
                total_processed, total_synced, total_skipped, total_errors
            );
        }
    }

    info!("=== Backfill Summary ===");
    info!("Total processed: {}", total_processed);
    info!("Total synced: {}", total_synced);
    info!("Total skipped: {}", total_skipped);
    info!("Total errors: {}", total_errors);

    Ok(())
}

async fn fetch_user_batch(
    pool: &Pool,
    batch_size: usize,
    offset: usize,
    start_from: Option<Uuid>,
) -> Result<Vec<UserProfile>> {
    let client = pool.get().await.context("Failed to get database connection")?;

    let query = if let Some(start_from_id) = start_from {
        // Resume from specific user ID
        "SELECT user_id, username, avatar_url
         FROM users
         WHERE user_id >= $1
         ORDER BY user_id
         LIMIT $2 OFFSET $3"
    } else {
        // Normal query
        "SELECT user_id, username, avatar_url
         FROM users
         ORDER BY user_id
         LIMIT $1 OFFSET $2"
    };

    let rows = if let Some(start_from_id) = start_from {
        client
            .query(query, &[&start_from_id, &(batch_size as i64), &(offset as i64)])
            .await
            .context("Failed to query users")?
    } else {
        client
            .query(query, &[&(batch_size as i64), &(offset as i64)])
            .await
            .context("Failed to query users")?
    };

    let users = rows
        .into_iter()
        .map(|row| UserProfile {
            user_id: row.get("user_id"),
            username: row.get("username"),
            avatar_url: row.get("avatar_url"),
        })
        .collect();

    Ok(users)
}

fn parse_args() -> Result<BackfillConfig> {
    let mut config = BackfillConfig::default();
    let args: Vec<String> = std::env::args().collect();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--dry-run" => {
                config.dry_run = true;
                i += 1;
            }
            "--batch-size" => {
                if i + 1 >= args.len() {
                    anyhow::bail!("--batch-size requires a value");
                }
                config.batch_size = args[i + 1]
                    .parse()
                    .context("Invalid batch size")?;
                i += 2;
            }
            "--start-from" => {
                if i + 1 >= args.len() {
                    anyhow::bail!("--start-from requires a UUID value");
                }
                config.start_from = Some(
                    Uuid::parse_str(&args[i + 1])
                        .context("Invalid UUID for --start-from")?,
                );
                i += 2;
            }
            "--help" | "-h" => {
                print_help();
                std::process::exit(0);
            }
            _ => {
                anyhow::bail!("Unknown argument: {}", args[i]);
            }
        }
    }

    Ok(config)
}

fn print_help() {
    println!("Avatar Backfill Script");
    println!();
    println!("Usage: backfill-avatars [OPTIONS]");
    println!();
    println!("Options:");
    println!("  --dry-run              Preview what would be synced without making changes");
    println!("  --batch-size <N>       Number of users to process per batch (default: 100)");
    println!("  --start-from <UUID>    Resume from a specific user UUID");
    println!("  --help, -h             Show this help message");
    println!();
    println!("Environment Variables:");
    println!("  DATABASE_URL              Realtime chat service database URL");
    println!("  IDENTITY_DATABASE_URL     Identity service database URL");
    println!("  MATRIX_HOMESERVER_URL     Matrix Synapse homeserver URL");
    println!("  MATRIX_ADMIN_TOKEN        Matrix admin access token");
    println!("  MATRIX_SERVER_NAME        Matrix server name");
}

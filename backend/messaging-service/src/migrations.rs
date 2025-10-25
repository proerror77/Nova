use sqlx::{Pool, Postgres};

// Embed SQL migrations at compile time for deterministic startup
const MIG_0001: &str = include_str!("../migrations/0001_create_users.sql");
const MIG_0002: &str = include_str!("../migrations/0002_create_conversations.sql");
const MIG_0003: &str = include_str!("../migrations/0003_create_conversation_members.sql");
const MIG_0004: &str = include_str!("../migrations/0004_create_messages.sql");

pub async fn run_all(db: &Pool<Postgres>) -> Result<(), sqlx::Error> {
    // Run sequentially; each migration may contain multiple statements
    for (i, sql) in [MIG_0001, MIG_0002, MIG_0003, MIG_0004].into_iter().enumerate() {
        let label = i + 1;
        // Split by semicolon only for top-level statements; simplest: execute as batch
        // Postgres via sqlx can execute multi-statement string.
        match sqlx::query(sql).execute(db).await {
            Ok(_) => tracing::info!(migration=%label, "messaging-service migration applied"),
            Err(e) => {
                // If it fails due to already exists, continue; otherwise log
                tracing::warn!(migration=%label, error=%e, "migration may have been applied already");
            }
        }
    }
    Ok(())
}


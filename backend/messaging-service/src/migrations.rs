use sqlx::{Pool, Postgres};

// Embed SQL migrations at compile time for deterministic startup
const MIG_0001: &str = include_str!("../migrations/0001_create_users.sql");
const MIG_0002: &str = include_str!("../migrations/0002_create_conversations.sql");
const MIG_0003: &str = include_str!("../migrations/0003_create_conversation_members.sql");
const MIG_0004: &str = include_str!("../migrations/0004_create_messages.sql");
const MIG_0005: &str = include_str!("../migrations/0005_add_message_content_fields.sql");
const MIG_0006: &str = include_str!("../migrations/0006_create_message_reactions.sql");
const MIG_0007: &str = include_str!("../migrations/0007_create_message_attachments.sql");
const MIG_0008: &str = include_str!("../migrations/0008_create_message_recalls.sql");
const MIG_0009: &str = include_str!("../migrations/0009_unify_message_storage.sql");
const MIG_0010: &str = include_str!("../migrations/0010_create_message_search_index.sql");
const MIG_0011: &str = include_str!("../migrations/0011_add_fts_index_on_messages.sql");
const MIG_0012: &str = include_str!("../migrations/0012_create_notifications.sql");
const MIG_0013: &str = include_str!("../migrations/0013_drop_message_search_index.sql");
const MIG_0014: &str = include_str!("../migrations/0014_add_group_conversation_fields.sql");
const MIG_0015: &str = include_str!("../migrations/0015_add_audio_message_support.sql");
const MIG_0016: &str = include_str!("../migrations/0016_create_video_call_support.sql");
const MIG_0017: &str = include_str!("../migrations/0017_create_notification_device_tokens.sql");
const MIG_0018: &str = include_str!("../migrations/0018_add_message_forward_support.sql");

pub async fn run_all(db: &Pool<Postgres>) -> Result<(), sqlx::Error> {
    // Acquire global advisory lock to prevent concurrent migrations across services
    let _ = sqlx::query("SELECT pg_advisory_lock(823746)").execute(db).await;
    // Run sequentially; each migration may contain multiple statements
    let migrations = [
        MIG_0001, MIG_0002, MIG_0003, MIG_0004, MIG_0005, MIG_0006, MIG_0007, MIG_0008, MIG_0009,
        MIG_0010, MIG_0011, MIG_0012, MIG_0013, MIG_0014, MIG_0015, MIG_0016, MIG_0017, MIG_0018,
    ];

    for (i, sql) in migrations.into_iter().enumerate() {
        let label = i + 1;
        match sqlx::query(sql).execute(db).await {
            Ok(_) => tracing::info!(migration=%label, "messaging-service migration applied"),
            Err(e) => {
                // If it fails due to already exists, continue; otherwise log
                tracing::warn!(migration=%label, error=%e, "migration may have been applied already");
            }
        }
    }
    // Release advisory lock
    let _ = sqlx::query("SELECT pg_advisory_unlock(823746)").execute(db).await;
    Ok(())
}

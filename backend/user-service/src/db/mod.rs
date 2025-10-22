use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;

pub mod ch_client;
pub mod messaging_repo;
pub mod oauth_repo;
pub mod password_reset_repo;
pub mod post_repo;
pub mod user_repo;

// Compatibility shim for messaging module path expected by services
// Re-exports types and repository from `messaging_repo` under `db::messaging`
pub mod messaging {
    pub use super::messaging_repo::{
        Conversation, ConversationMember, ConversationType, MemberRole, Message, MessageType,
        MessagingRepository,
    };
}

pub async fn create_pool(database_url: &str, max_connections: u32) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(max_connections)
        .acquire_timeout(Duration::from_secs(10))
        .idle_timeout(Duration::from_secs(300))
        .max_lifetime(Duration::from_secs(1800))
        .connect(database_url)
        .await
}

pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    sqlx::migrate!("../migrations").run(pool).await
}

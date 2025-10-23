use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;

pub mod ch_client;
pub mod messaging_repo;
pub mod oauth_repo;
pub mod password_reset_repo;
pub mod post_repo;
pub mod user_repo;
pub mod video_repo;

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
    // 兼容舊版（MySQL 風格）011_videos_table 遷移：預先標記為已執行，
    // 讓全新 Postgres 環境不會去真正跑該檔案（會觸發語法錯誤）。
    if let Err(e) = ensure_legacy_video_migration_marker(pool).await {
        tracing::warn!("Failed to prepare legacy video migration marker: {}", e);
    }

    let mut migrator = sqlx::migrate!("../migrations");
    // 忽略数据库中已存在但本地缺失的迁移版本（用于对齐历史环境）
    migrator.set_ignore_missing(true);
    migrator.run(pool).await
}

pub async fn ensure_legacy_video_migration_marker(pool: &PgPool) -> Result<(), sqlx::Error> {
    // 建立 _sqlx_migrations（若尚未存在）
    if let Err(e) = sqlx::query(
        r#"
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public'
                  AND table_name = '_sqlx_migrations'
            ) THEN
                CREATE TABLE public._sqlx_migrations (
                    version BIGINT PRIMARY KEY,
                    description TEXT NOT NULL,
                    installed_on TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    success BOOLEAN NOT NULL,
                    checksum BYTEA NOT NULL,
                    execution_time BIGINT NOT NULL
                );
            END IF;
        END
        $$;
        "#,
    )
    .execute(pool)
    .await
    {
        let ignore_duplicate_type = e
            .as_database_error()
            .and_then(|err| err.code().map(|code| code.to_string()))
            .map_or(false, |code| code == "23505");

        if !ignore_duplicate_type {
            return Err(e);
        }
    }

    // 將 legacy 011 標記為已執行（對新庫避免執行 MySQL 語法）
    const LEGACY_V11_CHECKSUM: &str =
        "77c0ee73b9b22df7a25c0f7f69cfdd8556c9037ffe240c49217313989714b54803dea6070b53d3d60136dd1a51d2975c";

    sqlx::query(
        r#"
        INSERT INTO _sqlx_migrations (version, description, success, checksum, execution_time)
        VALUES (11, 'Create Videos Table', TRUE, decode($1, 'hex'), 0)
        ON CONFLICT (version) DO NOTHING
        "#,
    )
    .bind(LEGACY_V11_CHECKSUM)
    .execute(pool)
    .await?;

    const LEGACY_V10_CHECKSUM: &str =
        "410b255b6c2422b3b04aaaadd28868810120561a7c13a4272a32ed64451e1578bc3b98fa973d9e133d9b61e4017b1f4db4981ca86f33078bf8b0e12e446f8ae2";

    sqlx::query(
        r#"
        INSERT INTO _sqlx_migrations (version, description, success, checksum, execution_time)
        VALUES (10, 'JWT signing key rotation support', TRUE, decode($1, 'hex'), 0)
        ON CONFLICT (version) DO NOTHING
        "#,
    )
    .bind(LEGACY_V10_CHECKSUM)
    .execute(pool)
    .await?;

    Ok(())
}

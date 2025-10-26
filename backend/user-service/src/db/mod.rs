use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;

pub mod bookmark_repo;
pub mod ch_client;
pub mod comment_repo;
pub mod experiment_repo;
// pub mod messaging_repo; // REMOVED - moved to messaging-service
pub mod like_repo;
pub mod oauth_repo;
pub mod password_reset_repo;
pub mod post_repo;
pub mod post_share_repo;
pub mod trending_repo;
pub mod upload_repo;
pub mod user_repo;
pub mod video_repo;
pub mod webhook_repo;

// NOTE: Messaging repository removed - use messaging-service API (port 8085)
// All messaging operations moved to messaging-service crate

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

    // 將 legacy 011 checkum 與描述對齊，避免舊 MySQL 語法造成校驗失敗
    const LEGACY_V11_CHECKSUM: &str =
        "2d56dd2dcf7d92303c120a3eb47a7038ddc0e1efd77dbf09e64619a4f74b406bc69f509e4d01c9e0389c5d56be694db42ae5c1ade5c692cfd45c7dbae9020b6c";

    sqlx::query(
        r#"
        UPDATE _sqlx_migrations
           SET checksum = decode($1, 'hex'),
               description = 'Create Videos Table',
               success = TRUE
         WHERE version = 11
           AND description <> 'videos table'
        "#,
    )
    .bind(LEGACY_V11_CHECKSUM)
    .execute(pool)
    .await?;

    const LEGACY_V10_CHECKSUM: &str =
        "6a928190843d45c586a1e6152ea0f2a0a90186ce77617e8f48555d3445545661b9f3ed07737c1519f23e791d71f84953173cf3b9c13b09fc0a0c740586ed454b";

    // 如果舊資料庫已存在版本 10，對齊 checksum，讓新的 Postgres 版本遷移可順利比對
    sqlx::query(
        r#"
        UPDATE _sqlx_migrations
           SET checksum = decode($1, 'hex'),
               description = 'JWT signing key rotation support',
               success = TRUE
         WHERE version = 10
           AND description <> 'jwt key rotation'
        "#,
    )
    .bind(LEGACY_V10_CHECKSUM)
    .execute(pool)
    .await?;

    Ok(())
}

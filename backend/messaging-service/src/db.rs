use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig};
use sqlx::migrate::Migrator;
use sqlx::{Pool, Postgres};

pub static MIGRATOR: Migrator = sqlx::migrate!("./migrations");

pub async fn init_pool(database_url: &str) -> Result<Pool<Postgres>, sqlx::Error> {
    let mut cfg = DbPoolConfig::from_env().unwrap_or_default();
    if cfg.database_url.is_empty() {
        cfg.database_url = database_url.to_string();
    }
    let pool = create_pg_pool(cfg).await?;
    Ok(pool)
}

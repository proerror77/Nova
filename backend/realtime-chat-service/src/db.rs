use db_pool::{create_pool as create_pg_pool, DbConfig as DbPoolConfig, PgPool};

pub async fn init_pool(database_url: &str) -> Result<PgPool, db_pool::PoolError> {
    let mut cfg = DbPoolConfig::from_env("messaging-service").unwrap_or_default();
    if cfg.database_url.is_empty() {
        cfg.database_url = database_url.to_string();
    }
    cfg.log_config();
    let pool = create_pg_pool(cfg).await?;
    Ok(pool)
}

pub async fn run_migrations(_pool: &PgPool) -> Result<(), db_pool::PoolError> {
    // TODO: reimplement migrations without sqlx
    Ok(())
}

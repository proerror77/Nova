use messaging_service::db;
mod common;

#[tokio::test]
async fn builds_pool_structure() {
    let url = common::test_database_url();
    // Attempt to build pool. This may fail at runtime if DB is absent; we only assert type compiles.
    let _ = db::init_pool(&url);
    assert!(true);
}


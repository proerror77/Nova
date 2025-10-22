use std::env;

#[allow(dead_code)]
pub fn test_database_url() -> String {
    env::var("DATABASE_URL").unwrap_or_else(|_| "postgres://postgres:postgres@localhost:5432/messaging_test".into())
}


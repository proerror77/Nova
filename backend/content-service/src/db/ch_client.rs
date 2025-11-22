use clickhouse::{query::Query, Client};
use serde::de::DeserializeOwned;
use std::time::Duration;
use tracing::{debug, error, warn};

use crate::error::{AppError, Result};

#[derive(Clone)]
pub struct ClickHouseClient {
    client: Client,
    query_timeout: Duration,
}

impl ClickHouseClient {
    pub fn new(
        url: &str,
        database: &str,
        username: &str,
        password: &str,
        query_timeout_ms: u64,
    ) -> Self {
        Self::new_with_mode(url, database, username, password, query_timeout_ms, true)
    }

    pub fn new_writable(
        url: &str,
        database: &str,
        username: &str,
        password: &str,
        query_timeout_ms: u64,
    ) -> Self {
        Self::new_with_mode(url, database, username, password, query_timeout_ms, false)
    }

    fn new_with_mode(
        url: &str,
        database: &str,
        username: &str,
        password: &str,
        query_timeout_ms: u64,
        _readonly: bool,
    ) -> Self {
        let client = Client::default()
            .with_url(url)
            .with_database(database)
            .with_user(username)
            .with_password(password)
            .with_option("max_execution_time", (query_timeout_ms / 1000).to_string());

        Self {
            client,
            query_timeout: Duration::from_millis(query_timeout_ms),
        }
    }

    pub async fn query<T>(&self, query: &str) -> Result<Vec<T>>
    where
        T: DeserializeOwned + clickhouse::Row,
    {
        debug!(
            "Executing ClickHouse query (first 200 chars): {}",
            &query[..query.len().min(200)]
        );

        self.client
            .query(query)
            .fetch_all::<T>()
            .await
            .map_err(|e| {
                error!("ClickHouse query failed: {}", e);
                AppError::Internal(format!("ClickHouse query error: {}", e))
            })
    }

    pub async fn query_with_params<T, F>(&self, template: &str, binder: F) -> Result<Vec<T>>
    where
        T: DeserializeOwned + clickhouse::Row,
        F: FnOnce(Query) -> Query,
    {
        let query = binder(self.client.query(template));
        query.fetch_all::<T>().await.map_err(|e| {
            error!("ClickHouse query failed: {}", e);
            AppError::Internal(format!("ClickHouse query error: {}", e))
        })
    }

    pub async fn query_with_fallback<T>(&self, query: &str) -> Vec<T>
    where
        T: DeserializeOwned + clickhouse::Row,
    {
        match tokio::time::timeout(self.query_timeout, self.query::<T>(query)).await {
            Ok(Ok(results)) => results,
            Ok(Err(e)) => {
                warn!("ClickHouse query failed, returning empty: {}", e);
                Vec::new()
            }
            Err(_) => {
                warn!("ClickHouse query timed out after {:?}", self.query_timeout);
                Vec::new()
            }
        }
    }

    pub async fn query_with_retry<T>(&self, query: &str, max_retries: u32) -> Result<Vec<T>>
    where
        T: DeserializeOwned + clickhouse::Row,
    {
        let mut retry_count = 0;
        let mut delay_ms = 100;

        loop {
            match self.query::<T>(query).await {
                Ok(results) => return Ok(results),
                Err(e) => {
                    retry_count += 1;
                    if retry_count >= max_retries {
                        error!(
                            "ClickHouse query failed after {} retries: {}",
                            max_retries, e
                        );
                        return Err(e);
                    }

                    warn!(
                        "ClickHouse query failed (attempt {}/{}), retrying in {}ms: {}",
                        retry_count, max_retries, delay_ms, e
                    );

                    tokio::time::sleep(Duration::from_millis(delay_ms)).await;
                    delay_ms *= 2;
                }
            }
        }
    }

    pub async fn execute(&self, query: &str) -> Result<()> {
        debug!(
            "Executing ClickHouse write query (first 200 chars): {}",
            &query[..query.len().min(200)]
        );

        self.client.query(query).execute().await.map_err(|e| {
            error!("ClickHouse execute failed: {}", e);
            AppError::Internal(format!("ClickHouse execute error: {}", e))
        })
    }

    pub async fn health_check(&self) -> Result<()> {
        #[derive(clickhouse::Row, serde::Deserialize)]
        struct HealthCheck {
            _result: u32,
        }

        let q = "SELECT toUInt32(1) AS result";

        self.client
            .query(q)
            .fetch_one::<HealthCheck>()
            .await
            .map(|_| ())
            .map_err(|e| {
                error!("ClickHouse health check failed: {}", e);
                AppError::Internal(format!("ClickHouse health check error: {}", e))
            })
    }
}

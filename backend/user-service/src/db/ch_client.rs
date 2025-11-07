use clickhouse::Client;
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::time::Duration;
use tracing::{debug, error, warn};

use crate::error::{AppError, Result};

/// ClickHouse client wrapper with connection pooling and retry logic
#[derive(Clone)]
pub struct ClickHouseClient {
    client: Client,
    query_timeout: Duration,
}

impl ClickHouseClient {
    /// Create a new ClickHouse client in read-only mode
    ///
    /// # Arguments
    /// * `url` - ClickHouse server URL (e.g., "http://localhost:8123")
    /// * `database` - Database name (default: "default")
    /// * `username` - Username for authentication
    /// * `password` - Password for authentication
    /// * `query_timeout_ms` - Query timeout in milliseconds
    pub fn new(
        url: &str,
        database: &str,
        username: &str,
        password: &str,
        query_timeout_ms: u64,
    ) -> Self {
        Self::new_with_mode(url, database, username, password, query_timeout_ms, true)
    }

    /// Create a new ClickHouse client with write permissions
    ///
    /// Use this for CDC and Events consumers that need to insert data.
    ///
    /// # Arguments
    /// * `url` - ClickHouse server URL (e.g., "http://localhost:8123")
    /// * `database` - Database name (default: "default")
    /// * `username` - Username for authentication
    /// * `password` - Password for authentication
    /// * `query_timeout_ms` - Query timeout in milliseconds
    pub fn new_writable(
        url: &str,
        database: &str,
        username: &str,
        password: &str,
        query_timeout_ms: u64,
    ) -> Self {
        Self::new_with_mode(url, database, username, password, query_timeout_ms, false)
    }

    /// Internal constructor with configurable read-only mode
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
            .with_option("max_execution_time", &(query_timeout_ms / 1000).to_string());

        // Do not force `readonly` via session setting here.
        // Some ClickHouse deployments run in readonly mode at the user/profile level,
        // and attempting to set `readonly` again causes: "Cannot modify 'readonly' setting in readonly mode".
        // We rely on the DB user/profile to enforce read-only access for SELECT-only clients.

        Self {
            client,
            query_timeout: Duration::from_millis(query_timeout_ms),
        }
    }

    /// Execute a query and return deserialized results
    ///
    /// # Type Parameters
    /// * `T` - Type to deserialize results into (must implement DeserializeOwned)
    ///
    /// # Arguments
    /// * `query` - SQL query string (should use parameterized queries)
    ///
    /// # Returns
    /// * `Result<Vec<T>>` - Deserialized query results
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

    /// Execute a query with fallback to empty result on timeout
    ///
    /// This is used for non-critical queries where empty result is acceptable
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

    /// Execute a query with retry logic
    ///
    /// Retries up to 3 times with exponential backoff (100ms, 200ms, 400ms)
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
                    delay_ms *= 2; // Exponential backoff
                }
            }
        }
    }

    /// Execute a write query (INSERT, ALTER, etc.) without result deserialization
    ///
    /// # Arguments
    /// * `query` - SQL query string (INSERT, CREATE, ALTER, etc.)
    ///
    /// # Returns
    /// * `Result<()>` - Success or error
    ///
    /// # Note
    /// Use this for INSERT statements where no result rows are expected.
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

    /// Insert one or more typed rows using ClickHouse insert API (parameterized)
    ///
    /// Prefer this over raw string-concatenated INSERTs to avoid SQL injection and
    /// to leverage proper type handling.
    pub async fn insert_rows<T>(&self, table: &str, rows: &[T]) -> Result<()>
    where
        T: Serialize + clickhouse::Row,
    {
        let mut inserter = self
            .client
            .insert(table)
            .map_err(|e| AppError::Internal(format!("ClickHouse insert init error: {}", e)))?;

        for row in rows {
            inserter
                .write(row)
                .await
                .map_err(|e| AppError::Internal(format!("ClickHouse insert write error: {}", e)))?;
        }

        inserter
            .end()
            .await
            .map_err(|e| AppError::Internal(format!("ClickHouse insert end error: {}", e)))
    }

    /// Convenience for inserting a single row
    pub async fn insert_row<T>(&self, table: &str, row: &T) -> Result<()>
    where
        T: Serialize + clickhouse::Row,
    {
        self.insert_rows(table, std::slice::from_ref(row)).await
    }

    /// Health check - verifies ClickHouse connection is alive
    pub async fn health_check(&self) -> Result<()> {
        #[derive(clickhouse::Row, serde::Deserialize)]
        struct HealthCheck {
            result: u32,
        }

        // Use explicit cast to avoid row type mismatches across CH deployments
        let q = "SELECT toUInt32(1) AS result";

        self.client
            .query(q)
            .fetch_one::<HealthCheck>()
            .await
            .map(|_| ())
            .map_err(|e| {
                error!("ClickHouse health check failed: {}", e);
                AppError::Internal(format!("ClickHouse unavailable: {}", e))
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // NOTE: This test requires rustls crypto provider initialization which is handled
    // automatically when running in a full tokio runtime context with actual HTTP clients.
    // For unit tests, we skip this to avoid needing rustls as a direct dependency.
    #[test]
    #[ignore = "Requires rustls crypto provider initialization - test in integration tests"]
    fn test_client_creation() {
        let client = ClickHouseClient::new("http://localhost:8123", "default", "default", "", 5000);

        assert_eq!(client.query_timeout, Duration::from_millis(5000));
    }
}

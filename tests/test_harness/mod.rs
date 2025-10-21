//! Test Harness Module
//!
//! Provides infrastructure for integration tests including:
//! - Test environment setup and teardown
//! - Kafka producer client
//! - ClickHouse client
//! - PostgreSQL client
//! - Redis client
//! - Feed API client

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;
use std::time::Duration;

/// Generic event row for ClickHouse queries
#[derive(Debug, Clone, Serialize, Deserialize, clickhouse::Row)]
pub struct EventRow {
    pub event_type: String,
    pub user_id: String,
    pub post_id: String,
}

/// Test Environment
pub struct TestEnvironment {
    pub pg_url: String,
    pub kafka_brokers: String,
    pub ch_url: String,
    pub redis_url: String,
    pub api_url: String,
}

impl TestEnvironment {
    pub async fn new() -> Self {
        // Read from environment or use defaults
        let pg_url = std::env::var("DATABASE_URL").unwrap_or_else(|_| {
            "postgres://postgres:postgres@localhost:5432/nova_test".to_string()
        });

        let kafka_brokers =
            std::env::var("KAFKA_BROKERS").unwrap_or_else(|_| "localhost:9092".to_string());

        let ch_url =
            std::env::var("CLICKHOUSE_URL").unwrap_or_else(|_| "http://localhost:8123".to_string());

        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());

        let api_url =
            std::env::var("API_URL").unwrap_or_else(|_| "http://localhost:8080".to_string());

        Self {
            pg_url,
            kafka_brokers,
            ch_url,
            redis_url,
            api_url,
        }
    }

    pub async fn cleanup(&self) {
        // Cleanup test data
        eprintln!("Cleaning up test environment...");
    }

    pub async fn stop_clickhouse(&self) {
        eprintln!("Stopping ClickHouse container...");
        let _ = tokio::process::Command::new("docker")
            .args(&["stop", "clickhouse"])
            .output()
            .await;
    }

    pub async fn start_clickhouse(&self) {
        eprintln!("Starting ClickHouse container...");
        let _ = tokio::process::Command::new("docker")
            .args(&["start", "clickhouse"])
            .output()
            .await;
    }
}

/// Kafka Producer Client
pub struct KafkaProducer {
    producer: Arc<rdkafka::producer::FutureProducer>,
}

impl KafkaProducer {
    pub async fn new(brokers: &str) -> Self {
        use rdkafka::config::ClientConfig;
        use rdkafka::producer::FutureProducer;

        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("message.timeout.ms", "5000")
            .create()
            .expect("Failed to create Kafka producer");

        Self {
            producer: Arc::new(producer),
        }
    }

    pub async fn send(&self, topic: &str, payload: Value) -> Result<(), String> {
        use rdkafka::producer::FutureRecord;
        use rdkafka::util::Timeout;

        let payload_str = serde_json::to_string(&payload)
            .map_err(|e| format!("Failed to serialize payload: {}", e))?;

        let record = FutureRecord::to(topic).payload(&payload_str).key("");

        self.producer
            .send(record, Timeout::After(Duration::from_secs(5)))
            .await
            .map_err(|(err, _)| format!("Failed to send to Kafka: {}", err))?;

        Ok(())
    }
}

/// ClickHouse Client
pub struct ClickHouseClient {
    client: clickhouse::Client,
}

impl ClickHouseClient {
    pub async fn new(url: &str) -> Self {
        let client = clickhouse::Client::default().with_url(url);

        Self { client }
    }

    pub async fn query_one<T: for<'de> Deserialize<'de> + clickhouse::Row>(
        &self,
        query: &str,
        params: &[&str],
    ) -> Result<T, String> {
        let mut q = self.client.query(query);

        for param in params {
            q = q.bind(param);
        }

        q.fetch_one()
            .await
            .map_err(|e| format!("ClickHouse query failed: {}", e))
    }

    pub async fn execute_batch(&self, queries: &[&str]) -> Result<(), String> {
        for query in queries {
            self.client
                .query(query)
                .execute()
                .await
                .map_err(|e| format!("ClickHouse execute failed: {}", e))?;
        }
        Ok(())
    }
}

/// PostgreSQL Client
pub struct PostgresClient {
    pool: sqlx::PgPool,
}

impl PostgresClient {
    pub async fn new(url: &str) -> Self {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .max_connections(5)
            .connect(url)
            .await
            .expect("Failed to connect to PostgreSQL");

        Self { pool }
    }

    pub async fn execute_simple(
        &self,
        query: &str,
        params: &[&str],
    ) -> Result<(), String> {
        let mut q = sqlx::query(query);

        for param in params {
            q = q.bind(param);
        }

        q.execute(&self.pool)
            .await
            .map_err(|e| format!("PostgreSQL execute failed: {}", e))?;

        Ok(())
    }
}

/// Redis Client
pub struct RedisClient {
    client: redis::Client,
}

impl RedisClient {
    pub async fn new(url: &str) -> Self {
        let client = redis::Client::open(url).expect("Failed to create Redis client");

        Self { client }
    }

    pub async fn set(&self, key: &str, value: String, ttl: usize) -> Result<(), String> {
        let mut conn = self
            .client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| format!("Failed to get Redis connection: {}", e))?;

        redis::pipe()
            .cmd("SET")
            .arg(key)
            .arg(value)
            .cmd("EXPIRE")
            .arg(key)
            .arg(ttl)
            .query_async(&mut conn)
            .await
            .map_err(|e| format!("Failed to set Redis key: {}", e))
    }

    pub async fn del(&self, key: &str) -> Result<(), String> {
        let mut conn = self
            .client
            .get_multiplexed_async_connection()
            .await
            .map_err(|e| format!("Failed to get Redis connection: {}", e))?;

        redis::cmd("DEL")
            .arg(key)
            .query_async(&mut conn)
            .await
            .map_err(|e| format!("Failed to delete Redis key: {}", e))
    }
}

/// Feed API Client
#[derive(Clone)]
pub struct FeedApiClient {
    base_url: String,
    client: reqwest::Client,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct FeedPost {
    pub post_id: String,
    pub score: f64,
    #[serde(default)]
    pub author_id: String,
}

impl FeedApiClient {
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            client: reqwest::Client::new(),
        }
    }

    pub async fn get_feed(&self, user_id: &str, limit: usize) -> Result<Vec<FeedPost>, String> {
        let url = format!("{}/api/feed/{}", self.base_url, user_id);

        let response = self
            .client
            .get(&url)
            .query(&[("limit", limit)])
            .send()
            .await
            .map_err(|e| format!("Feed API request failed: {}", e))?;

        if !response.status().is_success() {
            return Err(format!("Feed API returned error: {}", response.status()));
        }

        response
            .json::<Vec<FeedPost>>()
            .await
            .map_err(|e| format!("Failed to parse feed response: {}", e))
    }
}

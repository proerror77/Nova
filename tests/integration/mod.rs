//! Integration Tests for Streaming Infrastructure
//!
//! This module provides end-to-end testing for the RTMP → HLS → WebSocket streaming pipeline.
//! All tests use REAL infrastructure (Nginx-RTMP, PostgreSQL, Redis, Kafka, ClickHouse).

pub mod rtmp_client;
pub mod streaming_lifecycle_test;
pub mod websocket_broadcast_test;
pub mod e2e_multiviewer_test;
pub mod hls_validation_test;
pub mod metrics_collection_test;

use std::sync::Arc;
use tokio::sync::Mutex;

/// Shared test environment configuration
pub struct StreamingTestEnv {
    pub rtmp_host: String,
    pub rtmp_port: u16,
    pub api_host: String,
    pub api_port: u16,
    pub pg_url: String,
    pub redis_url: String,
    pub kafka_brokers: String,
    pub ch_url: String,
}

impl StreamingTestEnv {
    pub fn from_env() -> Self {
        Self {
            rtmp_host: std::env::var("RTMP_HOST").unwrap_or_else(|_| "localhost".to_string()),
            rtmp_port: std::env::var("RTMP_PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(1935),
            api_host: std::env::var("API_HOST").unwrap_or_else(|_| "localhost".to_string()),
            api_port: std::env::var("API_PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8081),
            pg_url: std::env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:55433/nova_auth_test".to_string()),
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://:redis123@localhost:6380/0".to_string()),
            kafka_brokers: std::env::var("KAFKA_BROKERS")
                .unwrap_or_else(|_| "localhost:29093".to_string()),
            ch_url: std::env::var("CLICKHOUSE_URL")
                .unwrap_or_else(|_| "http://localhost:8124".to_string()),
        }
    }

    pub fn api_url(&self) -> String {
        format!("http://{}:{}", self.api_host, self.api_port)
    }

    pub fn ws_url(&self, stream_id: &str) -> String {
        format!(
            "ws://{}:{}/api/v1/streams/{}/ws",
            self.api_host, self.api_port, stream_id
        )
    }

    pub fn rtmp_addr(&self) -> String {
        format!("{}:{}", self.rtmp_host, self.rtmp_port)
    }
}

/// Stream test fixture - created for each test scenario
pub struct StreamFixture {
    pub stream_id: String,
    pub rtmp_client: Option<rtmp_client::RtmpClient>,
    pub created_at: std::time::SystemTime,
}

impl StreamFixture {
    pub fn new() -> Self {
        Self {
            stream_id: uuid::Uuid::new_v4().to_string(),
            rtmp_client: None,
            created_at: std::time::SystemTime::now(),
        }
    }

    pub fn with_stream_id(stream_id: String) -> Self {
        Self {
            stream_id,
            rtmp_client: None,
            created_at: std::time::SystemTime::now(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_streaming_test_env_creation() {
        let env = StreamingTestEnv::from_env();
        assert!(!env.rtmp_host.is_empty());
        assert_eq!(env.rtmp_port, 1935);
        assert!(!env.api_url().is_empty());
    }

    #[test]
    fn test_stream_fixture_creation() {
        let fixture = StreamFixture::new();
        assert!(!fixture.stream_id.is_empty());
    }
}

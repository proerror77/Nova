//! Kafka configuration

use secrecy::SecretString;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use validator::Validate;

/// Kafka configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct KafkaConfig {
    /// Bootstrap servers
    #[validate(length(min = 1))]
    pub brokers: Vec<String>,

    /// Client ID
    #[validate(length(min = 1, max = 255))]
    #[serde(default = "default_client_id")]
    pub client_id: String,

    /// Producer configuration
    #[serde(default)]
    pub producer: ProducerConfig,

    /// Consumer configuration
    #[serde(default)]
    pub consumer: ConsumerConfig,

    /// Security configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub security: Option<KafkaSecurityConfig>,

    /// Schema registry URL (for Avro/Protobuf)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub schema_registry_url: Option<String>,

    /// Connection timeout in seconds
    #[serde(default = "default_connection_timeout")]
    pub connection_timeout_secs: u64,

    /// Request timeout in seconds
    #[serde(default = "default_request_timeout")]
    pub request_timeout_secs: u64,
}

fn default_client_id() -> String {
    "nova-service".to_string()
}

fn default_connection_timeout() -> u64 {
    10
}

fn default_request_timeout() -> u64 {
    30
}

impl KafkaConfig {
    /// Get bootstrap servers as comma-separated string
    pub fn bootstrap_servers(&self) -> String {
        self.brokers.join(",")
    }

    /// Get connection timeout as Duration
    pub fn connection_timeout(&self) -> Duration {
        Duration::from_secs(self.connection_timeout_secs)
    }

    /// Get request timeout as Duration
    pub fn request_timeout(&self) -> Duration {
        Duration::from_secs(self.request_timeout_secs)
    }
}

/// Producer configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct ProducerConfig {
    /// Acknowledgment level
    #[serde(default = "default_acks")]
    pub acks: Acks,

    /// Compression type
    #[serde(default)]
    pub compression: CompressionType,

    /// Batch size in bytes
    #[validate(range(min = 1, max = 1048576))] // 1B - 1MB
    #[serde(default = "default_batch_size")]
    pub batch_size: u32,

    /// Linger time in milliseconds
    #[serde(default = "default_linger_ms")]
    pub linger_ms: u64,

    /// Maximum request size in bytes
    #[validate(range(min = 1024, max = 104857600))] // 1KB - 100MB
    #[serde(default = "default_max_request_size")]
    pub max_request_size: u32,

    /// Retries
    #[serde(default = "default_retries")]
    pub retries: u32,

    /// Idempotence
    #[serde(default = "default_idempotent")]
    pub enable_idempotence: bool,
}

fn default_acks() -> Acks {
    Acks::All
}

fn default_batch_size() -> u32 {
    16384 // 16KB
}

fn default_linger_ms() -> u64 {
    100
}

fn default_max_request_size() -> u32 {
    1048576 // 1MB
}

fn default_retries() -> u32 {
    3
}

fn default_idempotent() -> bool {
    true
}

impl Default for ProducerConfig {
    fn default() -> Self {
        Self {
            acks: default_acks(),
            compression: CompressionType::default(),
            batch_size: default_batch_size(),
            linger_ms: default_linger_ms(),
            max_request_size: default_max_request_size(),
            retries: default_retries(),
            enable_idempotence: default_idempotent(),
        }
    }
}

/// Consumer configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct ConsumerConfig {
    /// Consumer group ID
    #[validate(length(min = 1, max = 255))]
    pub group_id: String,

    /// Auto offset reset
    #[serde(default)]
    pub auto_offset_reset: OffsetReset,

    /// Enable auto commit
    #[serde(default = "default_enable_auto_commit")]
    pub enable_auto_commit: bool,

    /// Auto commit interval in milliseconds
    #[serde(default = "default_auto_commit_interval_ms")]
    pub auto_commit_interval_ms: u64,

    /// Session timeout in milliseconds
    #[serde(default = "default_session_timeout_ms")]
    pub session_timeout_ms: u64,

    /// Maximum poll records
    #[validate(range(min = 1, max = 10000))]
    #[serde(default = "default_max_poll_records")]
    pub max_poll_records: u32,

    /// Fetch min bytes
    #[serde(default = "default_fetch_min_bytes")]
    pub fetch_min_bytes: u32,

    /// Fetch max wait in milliseconds
    #[serde(default = "default_fetch_max_wait_ms")]
    pub fetch_max_wait_ms: u64,
}

fn default_enable_auto_commit() -> bool {
    true
}

fn default_auto_commit_interval_ms() -> u64 {
    5000
}

fn default_session_timeout_ms() -> u64 {
    30000
}

fn default_max_poll_records() -> u32 {
    500
}

fn default_fetch_min_bytes() -> u32 {
    1
}

fn default_fetch_max_wait_ms() -> u64 {
    500
}

impl Default for ConsumerConfig {
    fn default() -> Self {
        Self {
            group_id: "nova-consumer".to_string(),
            auto_offset_reset: OffsetReset::default(),
            enable_auto_commit: default_enable_auto_commit(),
            auto_commit_interval_ms: default_auto_commit_interval_ms(),
            session_timeout_ms: default_session_timeout_ms(),
            max_poll_records: default_max_poll_records(),
            fetch_min_bytes: default_fetch_min_bytes(),
            fetch_max_wait_ms: default_fetch_max_wait_ms(),
        }
    }
}

/// Acknowledgment level
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Acks {
    /// No acknowledgment
    #[serde(rename = "0")]
    None,
    /// Leader acknowledgment
    #[serde(rename = "1")]
    One,
    /// All replicas acknowledgment
    #[default]
    #[serde(rename = "all")]
    All,
}

/// Compression type
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum CompressionType {
    /// No compression
    #[default]
    None,
    /// Gzip compression
    Gzip,
    /// Snappy compression
    Snappy,
    /// LZ4 compression
    Lz4,
    /// Zstd compression
    Zstd,
}

/// Offset reset strategy
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum OffsetReset {
    /// Start from earliest offset
    Earliest,
    /// Start from latest offset
    #[default]
    Latest,
    /// Throw error if no offset
    None,
}

/// Kafka security configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct KafkaSecurityConfig {
    /// Security protocol
    pub protocol: SecurityProtocol,

    /// SASL mechanism
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sasl_mechanism: Option<SaslMechanism>,

    /// SASL username
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sasl_username: Option<String>,

    /// SASL password
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sasl_password: Option<SecretString>,

    /// SSL configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ssl: Option<KafkaSslConfig>,
}

/// Security protocol
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SecurityProtocol {
    /// Plain text (no security)
    Plaintext,
    /// SSL/TLS
    Ssl,
    /// SASL over plaintext
    SaslPlaintext,
    /// SASL over SSL
    SaslSsl,
}

/// SASL mechanism
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "SCREAMING-KEBAB-CASE")]
pub enum SaslMechanism {
    /// PLAIN mechanism
    Plain,
    /// SCRAM-SHA-256
    ScramSha256,
    /// SCRAM-SHA-512
    ScramSha512,
    /// OAUTHBEARER
    OauthBearer,
}

/// Kafka SSL configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct KafkaSslConfig {
    /// CA certificate path
    pub ca_cert_path: String,

    /// Client certificate path
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_cert_path: Option<String>,

    /// Client key path
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_key_path: Option<String>,

    /// Verify hostname
    #[serde(default = "default_verify_hostname")]
    pub verify_hostname: bool,
}

fn default_verify_hostname() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kafka_config() {
        let config = KafkaConfig {
            brokers: vec!["localhost:9092".to_string(), "localhost:9093".to_string()],
            client_id: "test-client".to_string(),
            producer: ProducerConfig::default(),
            consumer: ConsumerConfig::default(),
            security: None,
            schema_registry_url: None,
            connection_timeout_secs: 10,
            request_timeout_secs: 30,
        };

        assert_eq!(config.bootstrap_servers(), "localhost:9092,localhost:9093");
        assert_eq!(config.connection_timeout(), Duration::from_secs(10));
    }

    #[test]
    fn test_producer_defaults() {
        let producer = ProducerConfig::default();
        assert!(matches!(producer.acks, Acks::All));
        assert_eq!(producer.batch_size, 16384);
        assert!(producer.enable_idempotence);
    }
}
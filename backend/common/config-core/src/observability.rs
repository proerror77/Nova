//! Observability configuration (logging, metrics, tracing)

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use validator::Validate;

/// Observability configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct ObservabilityConfig {
    /// Logging configuration
    pub logging: LoggingConfig,

    /// Metrics configuration
    #[serde(default)]
    pub metrics: MetricsConfig,

    /// Tracing configuration
    #[serde(default)]
    pub tracing: TracingConfig,

    /// Health check configuration
    #[serde(default)]
    pub health: HealthConfig,

    /// Profiling configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profiling: Option<ProfilingConfig>,
}

impl Default for ObservabilityConfig {
    fn default() -> Self {
        Self {
            logging: LoggingConfig::default(),
            metrics: MetricsConfig::default(),
            tracing: TracingConfig::default(),
            health: HealthConfig::default(),
            profiling: None,
        }
    }
}

/// Logging configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct LoggingConfig {
    /// Log level
    #[serde(default = "default_log_level")]
    pub level: LogLevel,

    /// Log format
    #[serde(default)]
    pub format: LogFormat,

    /// Log output
    #[serde(default)]
    pub output: LogOutput,

    /// Enable ANSI colors (terminal only)
    #[serde(default)]
    pub enable_colors: bool,

    /// Include source location
    #[serde(default = "default_include_location")]
    pub include_location: bool,

    /// Include thread IDs
    #[serde(default)]
    pub include_thread_ids: bool,

    /// Include thread names
    #[serde(default)]
    pub include_thread_names: bool,

    /// Log filters per module
    #[serde(default)]
    pub filters: HashMap<String, LogLevel>,

    /// Structured fields to include
    #[serde(default)]
    pub fields: StructuredFields,
}

fn default_log_level() -> LogLevel {
    LogLevel::Info
}

fn default_include_location() -> bool {
    true
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: default_log_level(),
            format: LogFormat::default(),
            output: LogOutput::default(),
            enable_colors: false,
            include_location: true,
            include_thread_ids: false,
            include_thread_names: false,
            filters: HashMap::new(),
            fields: StructuredFields::default(),
        }
    }
}

impl LoggingConfig {
    /// Get log filter string for tracing-subscriber
    pub fn get_filter_string(&self) -> String {
        let mut filters = vec![self.level.to_string()];

        for (module, level) in &self.filters {
            filters.push(format!("{}={}", module, level));
        }

        filters.join(",")
    }
}

/// Log level
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl std::fmt::Display for LogLevel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LogLevel::Trace => write!(f, "trace"),
            LogLevel::Debug => write!(f, "debug"),
            LogLevel::Info => write!(f, "info"),
            LogLevel::Warn => write!(f, "warn"),
            LogLevel::Error => write!(f, "error"),
        }
    }
}

/// Log format
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFormat {
    /// JSON format (for log aggregation)
    #[default]
    Json,
    /// Pretty format (for development)
    Pretty,
    /// Compact format
    Compact,
    /// Full format (most verbose)
    Full,
}

/// Log output destination
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LogOutput {
    /// Standard output
    #[default]
    Stdout,
    /// Standard error
    Stderr,
    /// File output
    File {
        path: String,
        #[serde(default = "default_log_rotation")]
        rotation: LogRotation,
    },
    /// Multiple outputs
    Multiple(Vec<LogOutput>),
}

fn default_log_rotation() -> LogRotation {
    LogRotation::Daily
}

/// Log rotation strategy
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LogRotation {
    /// No rotation
    Never,
    /// Daily rotation
    Daily,
    /// Hourly rotation
    Hourly,
    /// Size-based rotation
    Size {
        #[serde(default = "default_rotation_size")]
        max_bytes: u64,
    },
}

fn default_rotation_size() -> u64 {
    100 * 1024 * 1024 // 100MB
}

/// Structured fields to include in logs
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct StructuredFields {
    /// Include service name
    #[serde(default = "default_true")]
    pub service_name: bool,

    /// Include service version
    #[serde(default = "default_true")]
    pub service_version: bool,

    /// Include environment
    #[serde(default = "default_true")]
    pub environment: bool,

    /// Include instance ID
    #[serde(default = "default_true")]
    pub instance_id: bool,

    /// Include hostname
    #[serde(default)]
    pub hostname: bool,

    /// Custom fields
    #[serde(default)]
    pub custom: HashMap<String, String>,
}

fn default_true() -> bool {
    true
}

/// Metrics configuration
#[derive(Debug, Clone, Deserialize, Serialize, Validate)]
pub struct MetricsConfig {
    /// Enable metrics collection
    #[serde(default = "default_metrics_enabled")]
    pub enabled: bool,

    /// Metrics exporter
    #[serde(default)]
    pub exporter: MetricsExporter,

    /// Export interval in seconds
    #[validate(range(min = 1, max = 3600))]
    #[serde(default = "default_export_interval")]
    pub export_interval_secs: u64,

    /// Histogram buckets
    #[serde(default = "default_histogram_buckets")]
    pub histogram_buckets: Vec<f64>,

    /// Enable runtime metrics
    #[serde(default = "default_runtime_metrics")]
    pub runtime_metrics: bool,

    /// Metric labels
    #[serde(default)]
    pub labels: HashMap<String, String>,
}

fn default_metrics_enabled() -> bool {
    true
}

fn default_export_interval() -> u64 {
    10
}

fn default_histogram_buckets() -> Vec<f64> {
    vec![0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
}

fn default_runtime_metrics() -> bool {
    true
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            enabled: default_metrics_enabled(),
            exporter: MetricsExporter::default(),
            export_interval_secs: default_export_interval(),
            histogram_buckets: default_histogram_buckets(),
            runtime_metrics: default_runtime_metrics(),
            labels: HashMap::new(),
        }
    }
}

/// Metrics exporter
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum MetricsExporter {
    /// Prometheus exporter
    #[default]
    Prometheus {
        #[serde(default = "default_prometheus_port")]
        port: u16,
        #[serde(default = "default_prometheus_path")]
        path: String,
    },
    /// OpenTelemetry exporter
    OpenTelemetry {
        endpoint: String,
        protocol: OtlpProtocol,
    },
    /// StatsD exporter
    Statsd {
        host: String,
        port: u16,
        prefix: Option<String>,
    },
}

fn default_prometheus_port() -> u16 {
    9090
}

fn default_prometheus_path() -> String {
    "/metrics".to_string()
}

/// OTLP protocol
#[derive(Debug, Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum OtlpProtocol {
    Grpc,
    Http,
}

/// Tracing configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TracingConfig {
    /// Enable distributed tracing
    #[serde(default)]
    pub enabled: bool,

    /// Tracing exporter
    #[serde(default)]
    pub exporter: TracingExporter,

    /// Sampling configuration
    #[serde(default)]
    pub sampling: SamplingConfig,

    /// Propagation format
    #[serde(default)]
    pub propagation: PropagationFormat,

    /// Service name override
    #[serde(skip_serializing_if = "Option::is_none")]
    pub service_name: Option<String>,

    /// Additional resource attributes
    #[serde(default)]
    pub resource_attributes: HashMap<String, String>,
}

impl Default for TracingConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            exporter: TracingExporter::default(),
            sampling: SamplingConfig::default(),
            propagation: PropagationFormat::default(),
            service_name: None,
            resource_attributes: HashMap::new(),
        }
    }
}

/// Tracing exporter
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum TracingExporter {
    /// No exporter (traces stay in-process)
    #[default]
    None,
    /// Jaeger exporter
    Jaeger {
        endpoint: String,
        #[serde(default = "default_jaeger_port")]
        port: u16,
    },
    /// OpenTelemetry exporter
    OpenTelemetry {
        endpoint: String,
        protocol: OtlpProtocol,
    },
    /// Zipkin exporter
    Zipkin {
        endpoint: String,
    },
}

fn default_jaeger_port() -> u16 {
    6831
}

/// Sampling configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SamplingConfig {
    /// Sampling strategy
    #[serde(default)]
    pub strategy: SamplingStrategy,

    /// Sample rate (0.0 - 1.0)
    #[serde(default = "default_sample_rate")]
    pub rate: f64,

    /// Parent-based sampling
    #[serde(default = "default_parent_based")]
    pub parent_based: bool,
}

fn default_sample_rate() -> f64 {
    0.1 // 10%
}

fn default_parent_based() -> bool {
    true
}

impl Default for SamplingConfig {
    fn default() -> Self {
        Self {
            strategy: SamplingStrategy::default(),
            rate: default_sample_rate(),
            parent_based: default_parent_based(),
        }
    }
}

/// Sampling strategy
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum SamplingStrategy {
    /// Always sample
    Always,
    /// Never sample
    Never,
    /// Probabilistic sampling
    #[default]
    Probabilistic,
    /// Rate limiting
    RateLimited,
}

/// Propagation format
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum PropagationFormat {
    /// W3C Trace Context
    #[default]
    W3C,
    /// Jaeger format
    Jaeger,
    /// B3 format (Zipkin)
    B3,
    /// B3 single header
    B3Single,
}

/// Health check configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct HealthConfig {
    /// Enable health endpoints
    #[serde(default = "default_health_enabled")]
    pub enabled: bool,

    /// Health check path
    #[serde(default = "default_health_path")]
    pub path: String,

    /// Readiness check path
    #[serde(default = "default_readiness_path")]
    pub readiness_path: String,

    /// Liveness check path
    #[serde(default = "default_liveness_path")]
    pub liveness_path: String,

    /// Include detailed health info
    #[serde(default)]
    pub include_details: bool,

    /// Health check timeout in seconds
    #[serde(default = "default_health_timeout")]
    pub timeout_secs: u64,
}

fn default_health_enabled() -> bool {
    true
}

fn default_health_path() -> String {
    "/health".to_string()
}

fn default_readiness_path() -> String {
    "/ready".to_string()
}

fn default_liveness_path() -> String {
    "/live".to_string()
}

fn default_health_timeout() -> u64 {
    5
}

impl Default for HealthConfig {
    fn default() -> Self {
        Self {
            enabled: default_health_enabled(),
            path: default_health_path(),
            readiness_path: default_readiness_path(),
            liveness_path: default_liveness_path(),
            include_details: false,
            timeout_secs: default_health_timeout(),
        }
    }
}

/// Profiling configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProfilingConfig {
    /// Enable CPU profiling
    #[serde(default)]
    pub cpu: bool,

    /// Enable memory profiling
    #[serde(default)]
    pub memory: bool,

    /// Profile output path
    pub output_path: String,

    /// Profiling duration in seconds
    #[serde(default = "default_profile_duration")]
    pub duration_secs: u64,

    /// Sampling frequency (Hz)
    #[serde(default = "default_sampling_frequency")]
    pub sampling_frequency: u32,
}

fn default_profile_duration() -> u64 {
    30
}

fn default_sampling_frequency() -> u32 {
    100
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_logging_filter_string() {
        let mut config = LoggingConfig::default();
        config.level = LogLevel::Info;
        config.filters.insert("hyper".to_string(), LogLevel::Warn);
        config.filters.insert("tokio".to_string(), LogLevel::Error);

        let filter = config.get_filter_string();
        assert!(filter.contains("info"));
        assert!(filter.contains("hyper=warn"));
        assert!(filter.contains("tokio=error"));
    }

    #[test]
    fn test_metrics_defaults() {
        let config = MetricsConfig::default();
        assert!(config.enabled);
        assert_eq!(config.export_interval_secs, 10);
        assert!(!config.histogram_buckets.is_empty());
    }
}
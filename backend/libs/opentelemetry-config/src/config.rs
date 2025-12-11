//! Tracing configuration structures

use serde::{Deserialize, Serialize};

/// Type of trace exporter to use
///
/// Currently only OTLP is supported as `opentelemetry-jaeger` is deprecated.
/// Modern Jaeger installations support OTLP natively on port 4317.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum ExporterType {
    /// OpenTelemetry Protocol (OTLP) - modern standard
    /// Works with Jaeger, Tempo, and other OTLP-compatible backends
    #[default]
    Otlp,
}

/// Configuration for distributed tracing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TracingConfig {
    /// Enable tracing (default: false in development, true in production)
    pub enabled: bool,

    /// Type of exporter to use (currently only OTLP supported)
    pub exporter: ExporterType,

    /// OTLP collector endpoint
    /// Example: "http://jaeger:4317" (Jaeger with OTLP support)
    /// Example: "http://tempo:4317" (Grafana Tempo)
    pub otlp_endpoint: Option<String>,

    /// Sample rate (0.0 to 1.0)
    /// - 0.0: No traces
    /// - 0.1: Sample 10% of traces (recommended for production)
    /// - 1.0: Sample all traces (development/debugging)
    pub sample_rate: f64,

    /// Service version (from Git tag or semantic versioning)
    pub service_version: String,

    /// Deployment environment (development, staging, production)
    pub environment: String,
}

impl Default for TracingConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            exporter: ExporterType::Otlp,
            otlp_endpoint: Some("http://jaeger:4317".to_string()),
            sample_rate: 0.1,
            service_version: "dev".to_string(),
            environment: "development".to_string(),
        }
    }
}

impl TracingConfig {
    /// Create configuration from environment variables
    ///
    /// Environment variables:
    /// - `TRACING_ENABLED`: Enable tracing (true/false)
    /// - `OTLP_ENDPOINT`: OTLP collector endpoint (default: http://jaeger:4317)
    /// - `TRACING_SAMPLE_RATE`: Sample rate (0.0-1.0)
    /// - `SERVICE_VERSION`: Service version
    /// - `APP_ENV`: Environment (development/staging/production)
    pub fn from_env() -> Self {
        let enabled = std::env::var("TRACING_ENABLED")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(false);

        let otlp_endpoint = std::env::var("OTLP_ENDPOINT")
            .ok()
            .or_else(|| Some("http://jaeger:4317".to_string()));

        let sample_rate = std::env::var("TRACING_SAMPLE_RATE")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .unwrap_or(0.1)
            .clamp(0.0, 1.0);

        let service_version =
            std::env::var("SERVICE_VERSION").unwrap_or_else(|_| "dev".to_string());

        let environment = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());

        Self {
            enabled,
            exporter: ExporterType::Otlp,
            otlp_endpoint,
            sample_rate,
            service_version,
            environment,
        }
    }

    /// Create production configuration
    pub fn production(service_version: &str) -> Self {
        Self {
            enabled: true,
            exporter: ExporterType::Otlp,
            otlp_endpoint: Some("http://jaeger-collector:4317".to_string()),
            sample_rate: 0.1, // Sample 10% in production
            service_version: service_version.to_string(),
            environment: "production".to_string(),
        }
    }

    /// Create staging configuration
    pub fn staging(service_version: &str) -> Self {
        Self {
            enabled: true,
            exporter: ExporterType::Otlp,
            otlp_endpoint: Some("http://jaeger-collector:4317".to_string()),
            sample_rate: 0.5, // Sample 50% in staging
            service_version: service_version.to_string(),
            environment: "staging".to_string(),
        }
    }

    /// Create development configuration (trace all requests)
    pub fn development() -> Self {
        Self {
            enabled: true,
            exporter: ExporterType::Otlp,
            otlp_endpoint: Some("http://localhost:4317".to_string()),
            sample_rate: 1.0, // Sample 100% in development
            service_version: "dev".to_string(),
            environment: "development".to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = TracingConfig::default();
        assert!(!config.enabled);
        assert_eq!(config.sample_rate, 0.1);
    }

    #[test]
    fn test_production_config() {
        let config = TracingConfig::production("1.2.3");
        assert!(config.enabled);
        assert_eq!(config.sample_rate, 0.1);
        assert_eq!(config.service_version, "1.2.3");
        assert_eq!(config.environment, "production");
    }

    #[test]
    fn test_development_config() {
        let config = TracingConfig::development();
        assert!(config.enabled);
        assert_eq!(config.sample_rate, 1.0);
    }

    #[test]
    fn test_sample_rate_clamping() {
        std::env::set_var("TRACING_SAMPLE_RATE", "2.5");
        let config = TracingConfig::from_env();
        assert_eq!(config.sample_rate, 1.0); // Should be clamped to 1.0
        std::env::remove_var("TRACING_SAMPLE_RATE");
    }
}

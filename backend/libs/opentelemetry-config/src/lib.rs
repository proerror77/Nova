//! OpenTelemetry Configuration Library
//!
//! Provides centralized configuration for distributed tracing across all Nova backend services.
//! Uses OTLP (OpenTelemetry Protocol) exporter which is the modern standard supported by
//! Jaeger, Tempo, and other observability backends.

use opentelemetry::{global, KeyValue};
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{
    propagation::TraceContextPropagator,
    runtime,
    trace::{RandomIdGenerator, Sampler, Tracer},
    Resource,
};
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

pub mod config;
#[cfg(feature = "grpc-interceptors")]
pub mod interceptors;

pub use config::{ExporterType, TracingConfig};
#[cfg(feature = "grpc-interceptors")]
pub use interceptors::{grpc_tracing_interceptor, http_tracing_layer};

/// Initialize OpenTelemetry tracing for a service
///
/// # Arguments
/// * `service_name` - Name of the service (e.g., "auth-service")
/// * `config` - Tracing configuration
///
/// # Returns
/// * `Tracer` - OpenTelemetry tracer instance
///
/// # Example
/// ```no_run
/// use opentelemetry_config::{init_tracing, TracingConfig, ExporterType};
///
/// #[tokio::main]
/// async fn main() {
///     let config = TracingConfig {
///         enabled: true,
///         exporter: ExporterType::Otlp,
///         otlp_endpoint: Some("http://jaeger:4317".to_string()),
///         sample_rate: 0.1,
///         service_version: "1.0.0".to_string(),
///         environment: "production".to_string(),
///     };
///
///     let _tracer = init_tracing("my-service", config)
///         .expect("Failed to initialize tracing");
/// }
/// ```
pub fn init_tracing(
    service_name: &str,
    config: TracingConfig,
) -> Result<Tracer, Box<dyn std::error::Error>> {
    if !config.enabled {
        tracing::info!("Tracing is disabled");
        return Err("Tracing disabled".into());
    }

    // Set up global trace context propagator
    global::set_text_map_propagator(TraceContextPropagator::new());

    // Create resource with service metadata
    let resource = Resource::new(vec![
        KeyValue::new("service.name", service_name.to_string()),
        KeyValue::new("service.version", config.service_version.clone()),
        KeyValue::new("deployment.environment", config.environment.clone()),
    ]);

    // Create tracer using OTLP exporter (modern standard, works with Jaeger, Tempo, etc.)
    let tracer = init_otlp_tracer(service_name, &config, resource)?;

    // Set up tracing subscriber with OpenTelemetry layer
    let telemetry_layer = tracing_opentelemetry::layer().with_tracer(tracer.clone());

    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"))
        .add_directive(
            "identity_service=debug"
                .parse()
                .expect("Invalid filter directive"),
        )
        .add_directive(
            "auth_service=debug"
                .parse()
                .expect("Invalid filter directive"),
        )
        .add_directive(
            "content_service=debug"
                .parse()
                .expect("Invalid filter directive"),
        );

    tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt::layer().with_target(true).with_level(true))
        .with(telemetry_layer)
        .init();

    tracing::info!(
        service = service_name,
        exporter = "otlp",
        sample_rate = config.sample_rate,
        "OpenTelemetry tracing initialized"
    );

    Ok(tracer)
}

/// Initialize OTLP exporter (works with Jaeger, Tempo, and other OTLP-compatible backends)
fn init_otlp_tracer(
    _service_name: &str,
    config: &TracingConfig,
    resource: Resource,
) -> Result<Tracer, Box<dyn std::error::Error>> {
    let endpoint = config
        .otlp_endpoint
        .clone()
        .unwrap_or_else(|| "http://jaeger:4317".to_string());

    let exporter = opentelemetry_otlp::new_exporter()
        .tonic()
        .with_endpoint(endpoint);

    let tracer = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(exporter)
        .with_trace_config(
            opentelemetry_sdk::trace::config()
                .with_sampler(Sampler::TraceIdRatioBased(config.sample_rate))
                .with_id_generator(RandomIdGenerator::default())
                .with_resource(resource),
        )
        .install_batch(runtime::Tokio)
        .expect("Failed to install OTLP tracer");

    Ok(tracer)
}

/// Shutdown tracing gracefully
///
/// Call this before shutting down the service to ensure all spans are exported
pub fn shutdown_tracing() {
    global::shutdown_tracer_provider();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tracing_config_creation() {
        let config = TracingConfig {
            enabled: true,
            exporter: ExporterType::Otlp,
            otlp_endpoint: Some("http://localhost:4317".to_string()),
            sample_rate: 0.1,
            service_version: "1.0.0".to_string(),
            environment: "test".to_string(),
        };

        assert!(config.enabled);
        assert_eq!(config.sample_rate, 0.1);
    }

    #[test]
    fn test_otlp_exporter_type() {
        let config = TracingConfig {
            enabled: true,
            exporter: ExporterType::Otlp,
            otlp_endpoint: Some("http://localhost:4317".to_string()),
            sample_rate: 1.0,
            service_version: "1.0.0".to_string(),
            environment: "test".to_string(),
        };

        assert!(matches!(config.exporter, ExporterType::Otlp));
    }
}

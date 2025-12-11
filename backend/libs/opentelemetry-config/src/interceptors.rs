//! OpenTelemetry interceptors for gRPC and HTTP
//!
//! This module requires the `grpc-interceptors` feature to be enabled.

use opentelemetry::{global, propagation::Extractor, trace::SpanKind};
use std::task::{Context as TaskContext, Poll};
use tonic::{
    body::BoxBody, metadata::MetadataMap, transport::Body, Request, Status as TonicStatus,
};
use tower::{Layer, Service};
use tracing_opentelemetry::OpenTelemetrySpanExt;

/// gRPC metadata extractor for trace context propagation
struct MetadataExtractor<'a>(&'a MetadataMap);

impl Extractor for MetadataExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).and_then(|v| v.to_str().ok())
    }

    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(|k| k.as_str()).collect()
    }
}

/// gRPC tracing interceptor for server-side requests
///
/// Extracts trace context from incoming requests and creates spans
pub fn grpc_tracing_interceptor(req: Request<()>) -> Result<Request<()>, TonicStatus> {
    let metadata = req.metadata();
    let parent_context = global::get_text_map_propagator(|propagator| {
        propagator.extract(&MetadataExtractor(metadata))
    });

    let span = tracing::info_span!(
        "grpc_request",
        otel.kind = ?SpanKind::Server,
        rpc.service = req.uri().path(),
        rpc.method = req.uri().path().split('/').last().unwrap_or("unknown"),
    );

    span.set_parent(parent_context);

    let _ = span.enter();

    Ok(req)
}

/// HTTP tracing layer using Tower middleware
pub fn http_tracing_layer() -> TracingLayer {
    TracingLayer
}

/// Tower layer for HTTP tracing
#[derive(Clone)]
pub struct TracingLayer;

impl<S> Layer<S> for TracingLayer {
    type Service = TracingService<S>;

    fn layer(&self, service: S) -> Self::Service {
        TracingService { inner: service }
    }
}

/// Tower service for HTTP tracing
#[derive(Clone)]
pub struct TracingService<S> {
    inner: S,
}

impl<S> Service<http::Request<Body>> for TracingService<S>
where
    S: Service<http::Request<Body>, Response = http::Response<BoxBody>>,
    S::Error: std::fmt::Display,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = S::Future;

    fn poll_ready(&mut self, cx: &mut TaskContext<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: http::Request<Body>) -> Self::Future {
        // Extract trace context from HTTP headers
        let parent_context = global::get_text_map_propagator(|propagator| {
            propagator.extract(&HeaderExtractor(req.headers()))
        });

        let span = tracing::info_span!(
            "http_request",
            otel.kind = ?SpanKind::Server,
            http.method = %req.method(),
            http.target = %req.uri().path(),
            http.scheme = ?req.uri().scheme_str(),
        );

        span.set_parent(parent_context);
        let _enter = span.enter();

        self.inner.call(req)
    }
}

/// HTTP header extractor for trace context propagation
struct HeaderExtractor<'a>(&'a http::HeaderMap);

impl Extractor for HeaderExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).and_then(|v| v.to_str().ok())
    }

    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(|k| k.as_str()).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metadata_extractor() {
        let mut metadata = MetadataMap::new();
        metadata.insert(
            "traceparent",
            "00-trace-id-span-id-01".parse().expect("Valid header"),
        );

        let extractor = MetadataExtractor(&metadata);
        assert_eq!(extractor.get("traceparent"), Some("00-trace-id-span-id-01"));
    }

    #[test]
    fn test_header_extractor() {
        let mut headers = http::HeaderMap::new();
        headers.insert(
            "traceparent",
            "00-trace-id-span-id-01".parse().expect("Valid header"),
        );

        let extractor = HeaderExtractor(&headers);
        assert_eq!(extractor.get("traceparent"), Some("00-trace-id-span-id-01"));
    }
}

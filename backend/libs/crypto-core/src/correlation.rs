//! Correlation ID utilities for distributed tracing
//!
//! Manages correlation IDs across HTTP, gRPC, and Kafka boundaries.
//! Enables request tracing across all Nova microservices.
//!
//! ## Architecture
//! ```text
//! Client HTTP Request
//!   ↓ (X-Correlation-ID header)
//! API Gateway / Load Balancer
//!   ↓ (Actix CorrelationIdMiddleware extracts/generates ID)
//! Service Handler
//!   ↓ (gRPC call to another service)
//! gRPC Client Interceptor (adds correlation_id to metadata)
//!   ↓ (correlation-id metadata field)
//! Remote Service (extracts from gRPC metadata)
//!   ↓ (Kafka publish)
//! Kafka Producer Interceptor (adds correlation_id to headers)
//!   ↓ (correlation-id message header)
//! Kafka Consumer (extracts and stores in context)
//! ```
//!
//! ## Implementation Pattern
//! 1. HTTP: Extract from X-Correlation-ID header or generate UUID
//! 2. gRPC: Pass in request metadata under key "correlation-id"
//! 3. Kafka: Include as message header
//! 4. Logging: Automatically captured by tracing instrumentation

use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

/// Thread-local (tokio task-local) correlation ID context
/// Stored in task context for access by all code in that task
pub struct CorrelationContext {
    correlation_id: Arc<RwLock<String>>,
}

impl CorrelationContext {
    /// Create new correlation context with ID
    pub fn new(correlation_id: String) -> Self {
        Self {
            correlation_id: Arc::new(RwLock::new(correlation_id)),
        }
    }

    /// Generate new correlation ID
    pub fn generate() -> Self {
        Self::new(Uuid::new_v4().to_string())
    }

    /// Get current correlation ID
    pub async fn get(&self) -> String {
        self.correlation_id.read().await.clone()
    }

    /// Set correlation ID
    pub async fn set(&self, id: String) {
        *self.correlation_id.write().await = id;
    }
}

/// gRPC metadata key for correlation ID
pub const GRPC_CORRELATION_ID_KEY: &str = "correlation-id";

/// HTTP header for correlation ID
pub const HTTP_CORRELATION_ID_HEADER: &str = "x-correlation-id";

/// Kafka message header for correlation ID
pub const KAFKA_CORRELATION_ID_HEADER: &str = "correlation-id";

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_correlation_context_generation() {
        let ctx = CorrelationContext::generate();
        let id = ctx.get().await;
        assert_eq!(id.len(), 36); // UUID v4 format
    }

    #[tokio::test]
    async fn test_correlation_context_set_get() {
        let ctx = CorrelationContext::new("test-id-123".to_string());
        assert_eq!(ctx.get().await, "test-id-123");

        ctx.set("new-id-456".to_string()).await;
        assert_eq!(ctx.get().await, "new-id-456");
    }
}

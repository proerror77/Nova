//! gRPC correlation ID interceptor utilities
use tonic::{Request, Status, service::Interceptor};
use crate::correlation::{GRPC_CORRELATION_ID_KEY, CorrelationContext};

#[derive(Clone, Default)]
pub struct GrpcCorrelationInjector;

impl Interceptor for GrpcCorrelationInjector {
    fn call(&mut self, mut req: Request<()>) -> Result<Request<()>, Status> {
        // If caller set correlation-id in extensions, use it; otherwise generate
        let id = req
            .extensions()
            .get::<String>()
            .cloned()
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        req.metadata_mut().insert(
            GRPC_CORRELATION_ID_KEY,
            id.parse().unwrap_or_default(),
        );
        Ok(req)
    }
}

/// Extract correlation-id from incoming gRPC metadata and set into context
pub fn extract_from_request<T>(req: &Request<T>, ctx: &CorrelationContext) {
    if let Some(val) = req.metadata().get(GRPC_CORRELATION_ID_KEY) {
        if let Ok(s) = val.to_str() { 
            let ctx = ctx.clone();
            let s = s.to_string();
            tokio::spawn(async move { ctx.set(s).await; });
        }
    }
}


/// Tower Layer integration for composable resilience patterns
use crate::circuit_breaker::{CircuitBreaker, CircuitBreakerError};
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use tower::{Layer, Service};

/// Circuit Breaker Layer for Tower services
#[derive(Clone)]
pub struct CircuitBreakerLayer {
    circuit_breaker: CircuitBreaker,
}

impl CircuitBreakerLayer {
    pub fn new(circuit_breaker: CircuitBreaker) -> Self {
        Self { circuit_breaker }
    }
}

impl<S> Layer<S> for CircuitBreakerLayer {
    type Service = CircuitBreakerService<S>;

    fn layer(&self, service: S) -> Self::Service {
        CircuitBreakerService {
            inner: service,
            circuit_breaker: self.circuit_breaker.clone(),
        }
    }
}

#[derive(Clone)]
pub struct CircuitBreakerService<S> {
    inner: S,
    circuit_breaker: CircuitBreaker,
}

impl<S, Request> Service<Request> for CircuitBreakerService<S>
where
    S: Service<Request> + Clone + Send + 'static,
    S::Future: Send,
    S::Error: std::fmt::Display,
    Request: Send + 'static,
{
    type Response = S::Response;
    type Error = CircuitBreakerError;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner
            .poll_ready(cx)
            .map_err(|e| CircuitBreakerError::CallFailed(e.to_string()))
    }

    fn call(&mut self, req: Request) -> Self::Future {
        let circuit_breaker = self.circuit_breaker.clone();
        let mut inner = self.inner.clone();

        Box::pin(async move {
            circuit_breaker
                .call(|| async {
                    inner
                        .call(req)
                        .await
                        .map_err(|e| e.to_string())
                })
                .await
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};
    use std::sync::Arc;
    use tower::ServiceExt;

    #[derive(Clone)]
    struct MockService {
        counter: Arc<AtomicU32>,
        fail_until: u32,
    }

    impl Service<()> for MockService {
        type Response = String;
        type Error = String;
        type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

        fn poll_ready(&mut self, _cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
            Poll::Ready(Ok(()))
        }

        fn call(&mut self, _req: ()) -> Self::Future {
            let count = self.counter.fetch_add(1, Ordering::SeqCst);
            let fail_until = self.fail_until;

            Box::pin(async move {
                if count < fail_until {
                    Err("Service error".to_string())
                } else {
                    Ok("Success".to_string())
                }
            })
        }
    }

    #[tokio::test]
    async fn test_circuit_breaker_layer() {
        let counter = Arc::new(AtomicU32::new(0));
        let mock_service = MockService {
            counter: counter.clone(),
            fail_until: 3,
        };

        let cb_config = crate::circuit_breaker::CircuitBreakerConfig {
            failure_threshold: 2,
            ..Default::default()
        };
        let circuit_breaker = CircuitBreaker::new(cb_config);
        let layer = CircuitBreakerLayer::new(circuit_breaker);

        let mut service = layer.layer(mock_service);

        // First 2 calls fail
        let _ = service.ready().await.unwrap().call(()).await;
        let _ = service.ready().await.unwrap().call(()).await;

        // Circuit should be open now
        let result = service.ready().await.unwrap().call(()).await;
        assert!(matches!(result, Err(CircuitBreakerError::Open)));
    }
}

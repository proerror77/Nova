# Correlation ID Propagation Audit

**Date**: 2025-11-11
**Status**: ⚠️ **PARTIAL IMPLEMENTATION** - Infrastructure exists but not integrated
**Priority**: P1 (Codex GPT-5 Week 5-6 Recommendation)
**Impact**: Distributed tracing incomplete, debugging cross-service issues difficult

---

## Executive Summary

**Infrastructure Status**:
- ✅ `crypto-core` library has complete correlation_id utilities (HTTP + gRPC + Kafka)
- ✅ Kafka producer in auth-service correctly uses `inject_headers()`
- ❌ Zero gRPC services use `GrpcCorrelationInjector`
- ❌ GraphQL Gateway does not extract/propagate `X-Correlation-ID` header
- ❌ No standardized HTTP → gRPC → Kafka tracing chain

**Estimated Integration Effort**: 6-8 hours (Week 5-6 priority)

---

## Current Implementation Status

### ✅ Working Components

**1. crypto-core Library** (`/backend/libs/crypto-core/src/`)
```rust
// correlation.rs (92 lines)
- CorrelationContext: Thread-local context storage
- Constants: HTTP_CORRELATION_ID_HEADER, GRPC_CORRELATION_ID_KEY, KAFKA_CORRELATION_ID_HEADER

// grpc_correlation.rs (35 lines)
- GrpcCorrelationInjector: Tonic interceptor for client-side injection
- extract_from_request(): Server-side extraction

// kafka_correlation.rs (28 lines)
- inject_headers(): Add correlation_id to Kafka message headers
- extract_to_context(): Extract from consumed Kafka messages
```

**2. Kafka Events (auth-service)** ✅
```rust
// /backend/auth-service/src/services/kafka_events.rs:159
let correlation_id = envelope
    .correlation_id
    .unwrap_or(envelope.event_id)
    .to_string();
let headers = inject_headers(OwnedHeaders::new(), &correlation_id);
let record = FutureRecord::to(&self.topic)
    .key(&partition_key)
    .payload(&payload)
    .headers(headers);  // ✅ CORRECT
```

### ❌ Missing Components

**1. GraphQL Gateway HTTP Layer**
- ❌ No middleware to extract `X-Correlation-ID` from incoming HTTP requests
- ❌ No middleware to inject correlation ID into outgoing gRPC calls
- ❌ No correlation ID in GraphQL context

**2. gRPC Services**
- ❌ user-service: No `GrpcCorrelationInjector` usage
- ❌ auth-service: No gRPC interceptor configured
- ❌ content-service: No correlation ID propagation
- ❌ feed-service: No correlation ID extraction

**3. Kafka Consumers**
- ⚠️ Limited usage of `extract_to_context()` across services
- ❌ No standardized pattern for consumer-side extraction

---

## Recommended Architecture (Codex GPT-5 Best Practices)

### Full Tracing Chain

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Client HTTP Request                                                  │
│   Header: X-Correlation-ID: abc123 (or generated if missing)        │
└─────────────────────┬────────────────────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ GraphQL Gateway (Actix-Web)                                          │
│   1. CorrelationIdMiddleware::extract()  // Extract from HTTP header│
│   2. Set in GraphQL Context              // Available to resolvers  │
│   3. GrpcCorrelationInjector::call()     // Inject into gRPC calls  │
└─────────────────────┬────────────────────────────────────────────────┘
                      │
                      ▼ gRPC metadata: correlation-id = abc123
┌──────────────────────────────────────────────────────────────────────┐
│ user-service (gRPC Server)                                           │
│   1. extract_from_request()              // Extract from metadata   │
│   2. Set CorrelationContext              // Store in task context   │
│   3. tracing::info!(correlation_id=%id)  // Log with correlation    │
│   4. [Optional] Call another service with GrpcCorrelationInjector   │
└─────────────────────┬────────────────────────────────────────────────┘
                      │
                      ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Kafka Producer (user-service publishes event)                       │
│   1. inject_headers(headers, &correlation_id)  // Add to headers   │
│   2. FutureRecord::headers(headers)            // Attach to message │
└─────────────────────┬────────────────────────────────────────────────┘
                      │
                      ▼ Kafka message headers: correlation-id = abc123
┌──────────────────────────────────────────────────────────────────────┐
│ Kafka Consumer (events-service)                                     │
│   1. extract_to_context(msg, &ctx)       // Extract from headers   │
│   2. Process event with correlation_id in logs                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Integration Checklist

### Phase 1: GraphQL Gateway HTTP Layer (2-3 hours)

**File**: `backend/graphql-gateway/src/middleware/correlation_id.rs` (NEW)

```rust
use actix_web::{
    dev::{Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage,
};
use crypto_core::correlation::{HTTP_CORRELATION_ID_HEADER, CorrelationContext};
use futures::future::{ok, Ready};
use std::task::{Context, Poll};
use uuid::Uuid;

/// Extract X-Correlation-ID from HTTP header or generate new
pub struct CorrelationIdMiddleware;

impl<S, B> Transform<S, ServiceRequest> for CorrelationIdMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Transform = CorrelationIdMiddlewareService<S>;
    type InitError = ();
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ok(CorrelationIdMiddlewareService { service })
    }
}

pub struct CorrelationIdMiddlewareService<S> {
    service: S,
}

impl<S, B> Service<ServiceRequest> for CorrelationIdMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = S::Future;

    fn poll_ready(&self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.service.poll_ready(cx)
    }

    fn call(&self, req: ServiceRequest) -> Self::Future {
        // Extract or generate correlation ID
        let correlation_id = req
            .headers()
            .get(HTTP_CORRELATION_ID_HEADER)
            .and_then(|v| v.to_str().ok())
            .map(String::from)
            .unwrap_or_else(|| Uuid::new_v4().to_string());

        // Store in request extensions for GraphQL context
        req.extensions_mut()
            .insert(CorrelationContext::new(correlation_id.clone()));

        tracing::debug!(correlation_id = %correlation_id, "HTTP request correlation ID set");

        self.service.call(req)
    }
}
```

**File**: `backend/graphql-gateway/src/main.rs` (UPDATE)

```rust
mod middleware;

use middleware::correlation_id::CorrelationIdMiddleware;

#[actix_web::main]
async fn main() -> Result<()> {
    HttpServer::new(move || {
        App::new()
            .wrap(CorrelationIdMiddleware)  // ✅ ADD THIS
            .wrap(Logger::default())
            .wrap(rate_limiter.clone())
            .wrap(JwtMiddleware::new())
            // ... rest of config
    })
}
```

**File**: `backend/graphql-gateway/src/schema/mod.rs` (UPDATE GraphQL Context)

```rust
use crypto_core::correlation::CorrelationContext;

pub struct AppContext {
    pub clients: ServiceClients,
    pub correlation_ctx: CorrelationContext,  // ✅ ADD THIS
}

// In graphql_handler:
async fn graphql_handler(
    schema: web::Data<AppSchema>,
    req: GraphQLRequest,
    http_req: actix_web::HttpRequest,
) -> GraphQLResponse {
    // Extract correlation context from request extensions
    let correlation_ctx = http_req
        .extensions()
        .get::<CorrelationContext>()
        .cloned()
        .unwrap_or_else(CorrelationContext::generate);

    let ctx = AppContext {
        clients: /* ... */,
        correlation_ctx,  // ✅ ADD THIS
    };

    schema.execute(req.into_inner().data(ctx)).await.into()
}
```

### Phase 2: gRPC Client Interceptor (GraphQL Gateway → Services) (1-2 hours)

**File**: `backend/graphql-gateway/src/clients/grpc_client.rs` (UPDATE)

```rust
use crypto_core::grpc_correlation::GrpcCorrelationInjector;
use tonic::transport::Channel;

impl ServiceClients {
    pub async fn new(/* ... */) -> Result<Self> {
        // Create channel with correlation interceptor
        let channel = Channel::from_static(USER_SERVICE_URL)
            .connect()
            .await?;

        let user_client = UserServiceClient::with_interceptor(
            channel,
            GrpcCorrelationInjector::default()  // ✅ ADD THIS
        );

        // Repeat for all service clients
        Ok(Self { user_client, /* ... */ })
    }
}
```

**File**: `backend/graphql-gateway/src/schema/user.rs` (UPDATE Resolver)

```rust
#[Object]
impl UserQuery {
    async fn user(&self, ctx: &Context<'_>, user_id: String) -> Result<Option<User>> {
        let app_ctx = ctx.data::<AppContext>()?;
        let correlation_id = app_ctx.correlation_ctx.get().await;

        // Pass correlation ID in gRPC request extensions
        let mut request = Request::new(GetUserRequest { user_id });
        request.extensions_mut().insert(correlation_id);  // ✅ ADD THIS

        let response = app_ctx.clients.user_client.get_user(request).await?;
        Ok(response.into_inner().user)
    }
}
```

### Phase 3: gRPC Server Extraction (All Services) (2-3 hours)

**File**: `backend/user-service/src/main.rs` (UPDATE)

```rust
use crypto_core::{
    correlation::CorrelationContext,
    grpc_correlation::extract_from_request,
};

#[tonic::async_trait]
impl UserService for UserServiceImpl {
    async fn get_user(&self, request: Request<GetUserRequest>) -> Result<Response<GetUserResponse>, Status> {
        // Extract correlation ID from gRPC metadata
        let ctx = CorrelationContext::generate();
        extract_from_request(&request, &ctx);

        let correlation_id = ctx.get().await;
        tracing::info!(
            correlation_id = %correlation_id,
            user_id = %request.get_ref().user_id,
            "GetUser request received"
        );

        // Process request...
    }
}
```

**Repeat for**:
- auth-service (2 gRPC methods)
- content-service (4 gRPC methods)
- feed-service (3 gRPC methods)
- notification-service (2 gRPC methods)
- messaging-service (3 gRPC methods)

### Phase 4: Kafka Consumer Extraction (1-2 hours)

**File**: `backend/events-service/src/consumers/*.rs` (UPDATE)

```rust
use crypto_core::{
    correlation::CorrelationContext,
    kafka_correlation::extract_to_context,
};

async fn process_kafka_message(msg: BorrowedMessage<'_>) -> Result<()> {
    let ctx = CorrelationContext::generate();
    extract_to_context(&msg, &ctx).await;

    let correlation_id = ctx.get().await;
    tracing::info!(
        correlation_id = %correlation_id,
        topic = %msg.topic(),
        partition = %msg.partition(),
        offset = %msg.offset(),
        "Processing Kafka message"
    );

    // Process message...
}
```

**Repeat for**:
- user-service (Kafka consumers if any)
- notification-service (event consumers)
- feed-service (event consumers)

---

## Testing Strategy

### Unit Tests (Per Service)

```rust
#[tokio::test]
async fn test_correlation_id_propagation_grpc() {
    // 1. Create mock gRPC request with correlation-id metadata
    let mut req = Request::new(GetUserRequest { user_id: "123".into() });
    req.metadata_mut().insert(
        "correlation-id",
        "test-correlation-123".parse().unwrap(),
    );

    // 2. Extract into context
    let ctx = CorrelationContext::generate();
    extract_from_request(&req, &ctx);

    // 3. Verify extraction
    tokio::time::sleep(Duration::from_millis(10)).await;  // Allow async set
    assert_eq!(ctx.get().await, "test-correlation-123");
}

#[tokio::test]
async fn test_correlation_id_kafka_headers() {
    let correlation_id = "test-kafka-456";
    let headers = inject_headers(OwnedHeaders::new(), correlation_id);

    // Verify header added
    let h = headers.get(0);
    assert_eq!(h.key, "correlation-id");
    assert_eq!(h.value, Some(correlation_id.as_bytes()));
}
```

### Integration Tests (Cross-Service)

```rust
#[tokio::test]
async fn test_end_to_end_correlation_id_tracing() {
    let correlation_id = Uuid::new_v4().to_string();

    // 1. HTTP Request to GraphQL Gateway
    let client = reqwest::Client::new();
    let response = client
        .post("http://localhost:8080/graphql")
        .header("X-Correlation-ID", &correlation_id)
        .json(&json!({
            "query": "{ user(id: \"123\") { name } }"
        }))
        .send()
        .await?;

    // 2. Verify correlation ID propagated through logs
    // Check logs for correlation_id in:
    // - GraphQL Gateway request log
    // - user-service gRPC handler log
    // - Kafka producer log (if user update triggers event)

    // 3. Verify response includes correlation ID in header (optional)
    assert_eq!(
        response.headers().get("X-Correlation-ID").unwrap(),
        &correlation_id
    );
}
```

---

## Monitoring & Observability

### Structured Logging (Already Implemented)

```rust
// All services already use tracing with JSON format
tracing::info!(
    correlation_id = %correlation_id,
    user_id = %user_id,
    service = "user-service",
    method = "get_user",
    "Processing request"
);
```

### Log Aggregation (CloudWatch / Datadog / ELK)

```json
{
  "timestamp": "2025-11-11T10:30:00Z",
  "level": "INFO",
  "target": "user_service::handlers",
  "correlation_id": "abc-123-def-456",
  "service": "user-service",
  "method": "get_user",
  "user_id": "789",
  "message": "Processing request"
}
```

**Query Example** (CloudWatch Insights):
```sql
fields @timestamp, correlation_id, service, method, message
| filter correlation_id = "abc-123-def-456"
| sort @timestamp asc
```

### Grafana Dashboard Panels

```yaml
- title: "Request Trace Timeline"
  query: |
    {correlation_id="$correlation_id"}
    | json
    | line_format "{{.timestamp}} [{{.service}}] {{.method}}: {{.message}}"

- title: "Cross-Service Latency"
  query: |
    sum by (service) (
      histogram_quantile(0.95,
        rate(request_duration_seconds_bucket{correlation_id=~".+"}[5m])
      )
    )
```

---

## Performance Impact

**Expected Overhead**:
- HTTP header extraction: < 0.1ms
- gRPC metadata injection: < 0.1ms
- Kafka header addition: < 0.05ms
- **Total end-to-end overhead**: < 0.5ms (negligible compared to network latency)

**Benefits**:
- **Debugging Time Reduction**: 80% faster incident investigation
- **Cross-Service Issue Identification**: Minutes vs hours
- **Production Observability**: Complete request path visibility

---

## Migration Timeline (Week 5-6)

### Day 1-2: GraphQL Gateway (Phase 1-2)
- Implement CorrelationIdMiddleware
- Add GrpcCorrelationInjector to service clients
- Integration tests

### Day 3: Core gRPC Services (Phase 3)
- user-service: 3 gRPC methods
- auth-service: 2 gRPC methods
- content-service: 4 gRPC methods

### Day 4: Remaining Services (Phase 3 continued)
- feed-service, notification-service, messaging-service

### Day 5: Kafka Consumers (Phase 4)
- events-service consumers
- Verify end-to-end tracing

---

## Success Criteria

### Functional Requirements
- ✅ All HTTP requests generate or extract X-Correlation-ID
- ✅ All gRPC calls propagate correlation_id in metadata
- ✅ All Kafka messages include correlation-id header
- ✅ All logs include correlation_id field

### Observability Requirements
- ✅ Log aggregation queries work across services
- ✅ Grafana dashboards show cross-service traces
- ✅ CloudWatch Insights can trace full request path
- ✅ < 0.5ms overhead per hop

### Testing Requirements
- ✅ Unit tests pass (95%+ coverage)
- ✅ Integration tests verify end-to-end propagation
- ✅ Load testing confirms < 1ms overhead

---

## Rollback Plan

If correlation ID propagation causes issues:

1. **Disable HTTP Middleware**:
```rust
// Temporarily remove CorrelationIdMiddleware from App::new()
// .wrap(CorrelationIdMiddleware)  // COMMENTED OUT
```

2. **Disable gRPC Interceptor**:
```rust
// Fallback to client without interceptor
let user_client = UserServiceClient::new(channel);
// UserServiceClient::with_interceptor(channel, GrpcCorrelationInjector)  // DISABLED
```

3. **Make Extraction Optional**:
```rust
// Don't fail if correlation_id missing
if let Some(val) = req.metadata().get(GRPC_CORRELATION_ID_KEY) {
    // Extract only if present
}
```

---

## References

- **crypto-core Library**: `/backend/libs/crypto-core/src/{correlation.rs, grpc_correlation.rs, kafka_correlation.rs}`
- **Existing Usage**: `/backend/auth-service/src/services/kafka_events.rs:159` (Kafka inject_headers)
- **Codex Recommendation**: Week 5-6 P1 - "Standardize correlation ID propagation"
- **OpenTelemetry Compatibility**: Can migrate to W3C Trace Context later if needed

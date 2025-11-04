# P1 Fix: Request Correlation ID Propagation

## Problem

**Issue**: Unable to trace requests across microservices
```
Client Request → API Gateway
  ↓
user-service (handles HTTP)
  ↓
content-service (gRPC call) → No correlation ID in request metadata
  ↓
messaging-service (gRPC call) → Lost request context
  ↓
Kafka publish → No way to correlate events back to original request
```

**Impact**:
- Distributed debugging difficult: request trace is fragmented
- Kafka events not traceable to original user action
- P99 latencies hard to debug (don't know which service is slow)
- GDPR data deletion: can't audit which operations affected a user

---

## Solution: Distributed Correlation IDs

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Client HTTP Request                                         │
│ GET /feed HTTP/1.1                                          │
│ X-Correlation-ID: 550e8400-e29b-41d4-a716-446655440000  │
└─────────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────────┐
│ Load Balancer / API Gateway                                 │
│ (Passes through or generates X-Correlation-ID)              │
└─────────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────────┐
│ feed-service (Actix)                                        │
│ CorrelationIdMiddleware:                                    │
│  - Extract: X-Correlation-ID from headers                   │
│  - Store: in request extensions                             │
│  - Response: echo back in X-Correlation-ID header           │
└─────────────────────────────────────────────────────────────┘
           ↓
    (Handle HTTP request, then)
           ↓
┌─────────────────────────────────────────────────────────────┐
│ gRPC Call to content-service                                │
│ tonic::Request metadata:                                    │
│  - correlation-id: 550e8400-e29b-41d4-a716-446655440000  │
│ (Interceptor adds this automatically)                       │
└─────────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────────┐
│ content-service (Tonic gRPC)                                │
│ GrpcCorrelationInterceptor:                                 │
│  - Extract: correlation-id from metadata                    │
│  - Store: in request context                                │
└─────────────────────────────────────────────────────────────┘
           ↓
    (Handle gRPC request, then)
           ↓
┌─────────────────────────────────────────────────────────────┐
│ Kafka Publish (e.g., post-created event)                    │
│ Message headers:                                            │
│  - correlation-id: 550e8400-e29b-41d4-a716-446655440000  │
│  - trace-id: (optional, for full OpenTelemetry)            │
└─────────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────────┐
│ Kafka Consumer (e.g., search-indexer)                       │
│ Extract: correlation-id from message headers                │
│ All operations tagged with this ID                          │
└─────────────────────────────────────────────────────────────┘
```

### Three Boundaries

#### 1. HTTP ↔ Service

**Middleware**: `actix_middleware::CorrelationIdMiddleware`

```rust
// In service main.rs
let app = App::new()
    .wrap(CorrelationIdMiddleware);  // Automatically extracts/generates ID
```

**Behavior**:
- Extract header: `X-Correlation-ID`
- If missing: generate UUID v4
- Store in request extensions
- Echo back in response header

#### 2. Service ↔ gRPC Service

**Interceptor**: `GrpcCorrelationInterceptor` (to be created)

```rust
// In gRPC client initialization
let channel = Channel::from_static("http://content-service:8081")
    .connect()
    .await?;

// Add interceptor
let client = ContentServiceClient::with_interceptor(
    channel,
    GrpcCorrelationInterceptor::new(),
);
```

**Behavior**:
- Automatically adds `correlation-id` to request metadata
- Reads from request context (set by middleware)
- If no context: generates new UUID

#### 3. Service ↔ Kafka

**Interceptor**: `KafkaCorrelationInterceptor` (to be created)

```rust
// In Kafka producer
let producer = kafka
    .producer()
    .with_interceptor(KafkaCorrelationInterceptor::new());

// Publish with context
producer.send(topic, key, value).await?;
// Interceptor automatically adds correlation-id to message headers
```

---

## Implementation

### Phase 1: HTTP Correlation (Week 1)

**File**: `/libs/actix-middleware/src/correlation_id.rs` ✅ (Already created)

All Actix services automatically enabled with:
```rust
let app = App::new()
    .wrap(CorrelationIdMiddleware);
```

**Services affected**:
- user-service
- content-service
- messaging-service
- feed-service
- media-service

**Testing**:
```bash
# Test header propagation
curl -H "X-Correlation-ID: test-123" http://localhost:8080/api/users

# Should see in response:
# X-Correlation-ID: test-123

# Test UUID generation
curl http://localhost:8080/api/users
# Response should have X-Correlation-ID: <generated-uuid>
```

---

### Phase 2: gRPC Correlation (Week 2)

**File**: `/libs/actix-middleware/src/grpc_correlation.rs` (create)

Create gRPC interceptor:
```rust
//! gRPC correlation ID interceptor
//!
//! Automatically propagates correlation IDs in gRPC metadata

use actix_web::HttpRequest;
use tonic::service::Interceptor;
use tonic::{metadata::MetadataValue, Request};
use uuid::Uuid;

#[derive(Clone)]
pub struct GrpcCorrelationInterceptor {
    correlation_id: Option<String>,
}

impl GrpcCorrelationInterceptor {
    /// Create from HTTP request context
    pub fn from_request(req: &HttpRequest) -> Self {
        let correlation_id = req
            .extensions()
            .get::<String>()
            .map(|s| s.clone());

        Self { correlation_id }
    }

    /// Create with explicit ID
    pub fn with_id(id: String) -> Self {
        Self {
            correlation_id: Some(id),
        }
    }

    /// Generate new ID if not provided
    pub fn new() -> Self {
        Self { correlation_id: None }
    }
}

impl Interceptor for GrpcCorrelationInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, tonic::Status> {
        let correlation_id = self
            .correlation_id
            .clone()
            .unwrap_or_else(|| Uuid::new_v4().to_string());

        // Add to gRPC metadata
        let metadata = request.metadata_mut();
        metadata.insert(
            "correlation-id",
            MetadataValue::from_str(&correlation_id)
                .map_err(|_| tonic::Status::internal("Invalid correlation ID"))?,
        );

        Ok(request)
    }
}
```

**Update gRPC clients in each service**:

Example: content-service calling auth-service
```rust
// File: content-service/src/grpc/clients/auth_client.rs

use actix_middleware::GrpcCorrelationInterceptor;
use actix_web::HttpRequest;

pub fn create_auth_client(http_req: &HttpRequest) -> AuthServiceClient<...> {
    let channel = Channel::from_static("http://auth-service:8083")
        .connect()
        .await?;

    let interceptor = GrpcCorrelationInterceptor::from_request(http_req);

    AuthServiceClient::with_interceptor(channel, interceptor)
}
```

**Receiver side** (auth-service):
```rust
// File: auth-service/src/grpc/mod.rs

use tonic::{Request, Response, Status};

pub async fn validate_token(
    &self,
    req: Request<ValidateTokenRequest>,
) -> Result<Response<ValidateTokenResponse>, Status> {
    // Extract correlation ID from metadata
    let correlation_id = req
        .metadata()
        .get("correlation-id")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown");

    // Log with correlation ID
    tracing::info!(correlation_id, "validating token");

    // ... rest of implementation
}
```

---

### Phase 3: Kafka Correlation (Week 3)

**File**: `/libs/redis-utils/src/kafka_correlation.rs` (create)

Create Kafka producer wrapper:
```rust
//! Kafka correlation ID interceptor
//!
//! Automatically adds correlation-id to all Kafka message headers

use rdkafka::producer::{FutureProducer, FutureRecord};
use std::time::Duration;

#[derive(Clone)]
pub struct KafkaCorrelationInterceptor {
    correlation_id: String,
}

impl KafkaCorrelationInterceptor {
    pub fn new(correlation_id: String) -> Self {
        Self { correlation_id }
    }

    /// Publish with correlation ID header
    pub async fn send<'a>(
        &self,
        producer: &FutureProducer,
        topic: &str,
        key: &str,
        value: &[u8],
    ) -> Result<_, rdkafka::error::KafkaError> {
        let record = FutureRecord::to(topic)
            .key(key)
            .payload(value)
            .header("correlation-id", self.correlation_id.as_bytes());

        producer.send(record, Duration::from_secs(30)).await
    }
}
```

**Usage in services**:
```rust
// In content-service handler
let interceptor = KafkaCorrelationInterceptor::new(
    get_correlation_id(&req)
);

interceptor.send(
    &kafka_producer,
    "post-events",
    &post.id.to_string(),
    &serde_json::to_vec(&post_created_event)?,
).await?;
```

**Kafka consumer side**:
```rust
// In any consumer (search-indexer, feed-service, etc.)
use rdkafka::consumer::stream_consumer::StreamConsumer;

let consumer: StreamConsumer = ClientConfig::new()
    .set("group.id", "search-indexer")
    .create()
    .await?;

consumer.subscribe(&["post-events"])?;

while let Some(message) = consumer.recv().await {
    match message {
        Ok(borrowed_message) => {
            // Extract correlation ID from headers
            let correlation_id = borrowed_message
                .headers()
                .and_then(|h| h.iter().find(|(name, _)| name == "correlation-id"))
                .and_then(|(_, value)| {
                    value.and_then(|v| std::str::from_utf8(v).ok())
                })
                .unwrap_or("unknown");

            // All operations tagged with this ID
            tracing::info!(correlation_id, "Processing post event");
        }
        Err(e) => {
            tracing::error!("Consumer error: {}", e);
        }
    }
}
```

---

## Logging Integration

### Structured Logging with Tracing

**Goal**: All logs automatically include correlation ID without explicit parameter passing

#### Setup (in each service)

```rust
// In main.rs
use tracing_subscriber::prelude::*;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing with JSON output
    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer().json())
        .init();

    // ... rest of service setup
}
```

#### Usage in handlers

```rust
// In any handler
#[tracing::instrument(skip(req))]
pub async fn create_post(
    req: HttpRequest,
    body: Json<CreatePostRequest>,
) -> Result<Json<Post>> {
    // Extract correlation ID from request
    let correlation_id = get_correlation_id(&req);

    // Create span with correlation ID
    let span = tracing::info_span!(
        "create_post",
        correlation_id = %correlation_id,
        user_id = %body.user_id,
    );

    let _enter = span.enter();

    // All log statements in this scope automatically include correlation_id
    tracing::info!("Creating post"); // logs with correlation_id
    // ...
    tracing::info!("Post created successfully"); // logs with correlation_id

    Ok(Json(post))
}
```

**Log Output Example**:
```json
{
  "timestamp": "2025-11-04T12:30:00Z",
  "level": "INFO",
  "message": "Creating post",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "user-123",
  "service": "content-service",
  "target": "content_service::handlers"
}

{
  "timestamp": "2025-11-04T12:30:00Z",
  "level": "INFO",
  "message": "Calling auth-service to validate token",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "service": "content-service",
  "target": "content_service::grpc::clients"
}

{
  "timestamp": "2025-11-04T12:30:00Z",
  "level": "INFO",
  "message": "Validating token",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "service": "auth-service",
  "target": "auth_service::grpc"
}
```

---

## Monitoring & Tracing

### Grafana Loki Setup

Query all logs for a request:
```logql
{correlation_id="550e8400-e29b-41d4-a716-446655440000"}
| json
| line_format "{{.timestamp}} {{.service}} {{.message}}"
```

Returns full request flow:
```
2025-11-04T12:30:00.000Z user-service Received HTTP POST /api/posts
2025-11-04T12:30:00.001Z content-service Calling auth-service
2025-11-04T12:30:00.005Z auth-service Validating token
2025-11-04T12:30:00.006Z auth-service Token valid
2025-11-04T12:30:00.007Z content-service Token validated
2025-11-04T12:30:00.010Z content-service Inserting post to database
2025-11-04T12:30:00.025Z content-service Publishing to Kafka
2025-11-04T12:30:00.030Z search-indexer Received post event
2025-11-04T12:30:00.035Z search-indexer Indexing post
2025-11-04T12:30:00.100Z user-service Response sent (100ms latency)
```

### Jaeger/OpenTelemetry (Future Enhancement)

Correlation ID can be extended to full distributed tracing:
```rust
// Future: Export to Jaeger
use opentelemetry::global;
use opentelemetry_jaeger as jaeger;

let tracer = jaeger::new_pipeline()
    .install_simple()?;

// Root span = correlation ID
let root_span = tracer.start("request");
// Child spans linked to root
```

---

## Rollout Plan

### Week 1: HTTP Layer
- [ ] Add CorrelationIdMiddleware to all Actix services
- [ ] Test: curl with X-Correlation-ID header
- [ ] Verify: Response includes same ID

### Week 2: gRPC Layer
- [ ] Create GrpcCorrelationInterceptor
- [ ] Update all gRPC clients (user→auth, content→user, etc.)
- [ ] Update all gRPC handlers to extract and log ID
- [ ] Test: trace request across 2+ services

### Week 3: Kafka Layer
- [ ] Create KafkaCorrelationInterceptor
- [ ] Update all producers
- [ ] Update all consumers
- [ ] Test: correlation ID visible in message headers

### Week 4: Monitoring Setup
- [ ] Deploy Loki + Grafana dashboard
- [ ] Create saved queries for request tracing
- [ ] Document query patterns for team
- [ ] Train on-call team

---

## Testing

```rust
#[tokio::test]
async fn test_correlation_id_http_propagation() {
    // Create test client with correlation ID header
    let client = test::init_service(
        App::new().wrap(CorrelationIdMiddleware)
    );

    let req = test::TestRequest::get()
        .insert_header(("x-correlation-id", "test-123"))
        .to_request();

    let resp = test::call_service(&client, req).await;

    // Verify response includes same ID
    assert_eq!(
        resp.headers().get("x-correlation-id").unwrap(),
        "test-123"
    );
}

#[tokio::test]
async fn test_correlation_id_grpc_propagation() {
    // Create gRPC interceptor with ID
    let interceptor = GrpcCorrelationInterceptor::with_id(
        "test-456".to_string()
    );

    // Verify metadata contains ID
    let mut req = tonic::Request::new(());
    let updated_req = interceptor.call(req)?;

    assert_eq!(
        updated_req.metadata().get("correlation-id").unwrap(),
        "test-456"
    );
}

#[tokio::test]
async fn test_correlation_id_kafka_propagation() {
    let interceptor = KafkaCorrelationInterceptor::new(
        "test-789".to_string()
    );

    // Verify header is added to record
    // (test by inspecting FutureRecord headers)
}
```

---

## Troubleshooting

### Issue: Correlation ID lost between services

**Symptoms**: Log traces start at a service boundary

**Causes**:
1. Interceptor not added to gRPC client
2. gRPC client initialized without HTTP request context
3. Receiver not extracting from metadata

**Fix**:
```rust
// ✅ Correct: Pass HTTP request context
fn create_grpc_client(http_req: &HttpRequest) -> MyServiceClient<...> {
    let interceptor = GrpcCorrelationInterceptor::from_request(http_req);
    MyServiceClient::with_interceptor(channel, interceptor)
}

// ❌ Wrong: No context
fn create_grpc_client() -> MyServiceClient<...> {
    MyServiceClient::new(channel)  // Lost correlation ID
}
```

### Issue: Correlation ID not in logs

**Causes**:
1. Tracing not initialized
2. Span not created with correlation_id field
3. JSON formatter not configured

**Fix**:
```rust
// Ensure tracing initialized
tracing_subscriber::fmt()
    .json()  // JSON output
    .with_target(true)
    .with_thread_ids(true)
    .init();

// Create span with correlation_id
let span = tracing::info_span!(
    "handler",
    correlation_id = %id  // Must include this field
);
```

---

## References

- HTTP Header: [X-Correlation-ID convention](https://en.wikipedia.org/wiki/Correlation_IDs)
- gRPC Metadata: [tonic metadata](https://docs.rs/tonic/latest/tonic/metadata/)
- Kafka Headers: [KIP-467](https://cwiki.apache.org/confluence/display/KAFKA/KIP-467%3A+Kafka+Message+Headers)
- Distributed Tracing: [OpenTelemetry Specification](https://opentelemetry.io/docs/concepts/signals/traces/)

## Status

- **Created**: 2025-11-04
- **Priority**: P1 (High)
- **Estimated Effort**: 2 weeks (all 3 phases)
- **Impact**: Enables distributed debugging, request tracing across all services
- **Blocks**: OpenTelemetry integration, production observability

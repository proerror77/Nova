# Feature Store Service

Real-time ML feature serving service for the Nova platform. Provides low-latency access to user and content features for ranking, recommendation, and personalization systems.

## Architecture

### Storage Layers

1. **Hot Storage (Redis)**
   - Ultra-low latency (<10ms p99)
   - Frequently accessed features
   - TTL-based expiration
   - Key format: `features:{entity_type}:{entity_id}:{feature_name}`

2. **Near-Line Storage (ClickHouse)**
   - Medium latency (<100ms p99)
   - Historical features
   - Analytical queries
   - 90-day retention

3. **Metadata Storage (PostgreSQL)**
   - Feature definitions
   - Entity type schemas
   - Feature metadata

### Service Ports

- **HTTP**: 8010 (health checks, metrics)
- **gRPC**: 9010 (feature serving)

## Features

### Core Operations

- `GetFeatures` - Get features for a single entity
- `BatchGetFeatures` - Get features for multiple entities (batch optimization)
- `SetFeature` - Set/update feature value
- `GetFeatureMetadata` - Get feature definition and metadata

### Feature Types

- `Double` - Floating-point values (e.g., scores, ratios)
- `Int` - Integer values (e.g., counts, timestamps)
- `String` - Text values (e.g., categories, labels)
- `Bool` - Boolean flags
- `DoubleList` - Embedding vectors (e.g., content embeddings)
- `Timestamp` - Unix timestamps

## Usage

### Starting the Service

```bash
# Copy environment variables
cp .env.example .env

# Edit configuration
vim .env

# Run the service
cargo run --bin feature-store
```

### gRPC API Examples

#### Get Features

```rust
use feature_store::{
    feature_store_client::FeatureStoreClient,
    GetFeaturesRequest,
};

let mut client = FeatureStoreClient::connect("http://localhost:9010").await?;

let request = GetFeaturesRequest {
    entity_id: "user_123".to_string(),
    entity_type: "user".to_string(),
    feature_names: vec![
        "engagement_score".to_string(),
        "last_active_timestamp".to_string(),
    ],
};

let response = client.get_features(request).await?;
```

#### Set Feature

```rust
use feature_store::{
    SetFeatureRequest,
    FeatureValue,
};

let request = SetFeatureRequest {
    entity_id: "user_123".to_string(),
    entity_type: "user".to_string(),
    feature_name: "engagement_score".to_string(),
    value: Some(FeatureValue {
        value: Some(feature_value::Value::DoubleValue(0.85)),
    }),
    ttl_seconds: 3600, // 1 hour
};

let response = client.set_feature(request).await?;
```

## Development

### Building

```bash
cargo build --bin feature-store
```

### Testing

```bash
# Unit tests
cargo test

# Integration tests (requires Redis and ClickHouse)
cargo test --test integration_test -- --ignored
```

### Database Migrations

#### PostgreSQL (Metadata)

```bash
# Apply migrations
sqlx migrate run --database-url $DATABASE_URL

# Create new migration
sqlx migrate add <migration_name>
```

#### ClickHouse (Feature Storage)

```bash
# Execute ClickHouse schema
clickhouse-client --host localhost --port 9000 < migrations/002_clickhouse_schema.sql
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_HOST` | `0.0.0.0` | HTTP server bind address |
| `HTTP_PORT` | `8010` | HTTP server port |
| `GRPC_HOST` | `0.0.0.0` | gRPC server bind address |
| `GRPC_PORT` | `9010` | gRPC server port |
| `DATABASE_URL` | - | PostgreSQL connection string |
| `REDIS_URL` | - | Redis connection string |
| `REDIS_DEFAULT_TTL_SECONDS` | `3600` | Default TTL for Redis keys |
| `CLICKHOUSE_URL` | - | ClickHouse HTTP endpoint |
| `CLICKHOUSE_DATABASE` | `feature_store` | ClickHouse database name |
| `CLICKHOUSE_SYNC_INTERVAL_SECONDS` | `300` | Sync interval from Redis to ClickHouse |
| `FEATURE_CACHE_SIZE` | `10000` | In-memory feature cache size |
| `BATCH_FETCH_MAX_SIZE` | `100` | Max entities per batch request |

## Monitoring

### Health Endpoints

- `GET /health` - Basic health check
- `GET /ready` - Readiness check (verifies Redis, ClickHouse, PostgreSQL)

### Metrics

TODO: Add Prometheus metrics

- `feature_store_requests_total` - Total requests by operation
- `feature_store_request_duration_seconds` - Request latency histogram
- `feature_store_cache_hits_total` - Redis cache hits
- `feature_store_cache_misses_total` - Redis cache misses
- `feature_store_clickhouse_queries_total` - ClickHouse fallback queries

## Performance Targets

- **Get Features (Hot)**: <10ms p99 (Redis)
- **Get Features (Cold)**: <100ms p99 (ClickHouse)
- **Batch Get Features**: <50ms p99 for 100 entities
- **Set Feature**: <5ms p99

## Dependencies

### External Services

- PostgreSQL 14+ (metadata)
- Redis 7+ (hot storage)
- ClickHouse 23+ (near-line storage)

### Rust Crates

- `tonic` - gRPC framework
- `sqlx` - PostgreSQL client
- `redis` - Redis client
- `clickhouse` - ClickHouse client
- `ndarray` - Vector operations
- `tract-onnx` - ONNX model serving (future)

## TODO

- [ ] Implement ClickHouse query methods
- [ ] Add background sync worker (Redis → ClickHouse)
- [ ] Implement feature metadata CRUD
- [ ] Add Prometheus metrics
- [ ] Add distributed tracing
- [ ] Implement feature cache with LRU eviction
- [ ] Add feature versioning support
- [ ] Implement feature validation
- [ ] Add feature access logging
- [ ] Implement ONNX model serving for real-time scoring

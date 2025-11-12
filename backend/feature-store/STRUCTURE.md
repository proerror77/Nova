# Feature Store Service Structure

## Overview

Complete scaffold for the feature-store microservice, ready for Phase D implementation (Ranking + Feature Store).

## Directory Structure

```
feature-store/
├── Cargo.toml                    # Dependencies and build configuration
├── build.rs                      # Proto compilation build script
├── README.md                     # Service documentation
├── .env.example                  # Example configuration
│
├── proto/
│   └── feature_store.proto       # gRPC API contract
│
├── migrations/
│   ├── 001_feature_metadata.sql  # PostgreSQL metadata tables
│   └── 002_clickhouse_schema.sql # ClickHouse feature storage
│
├── src/
│   ├── main.rs                   # Service entry point
│   ├── lib.rs                    # Library exports
│   │
│   ├── config/
│   │   └── mod.rs                # Configuration management
│   │
│   ├── db/
│   │   └── mod.rs                # Database repositories
│   │
│   ├── grpc/
│   │   └── mod.rs                # gRPC service implementation
│   │
│   ├── models/
│   │   └── mod.rs                # Domain models
│   │
│   ├── services/
│   │   ├── mod.rs                # Service layer exports
│   │   ├── online/               # Redis hot features
│   │   │   └── mod.rs
│   │   └── near_line/            # ClickHouse near-line features
│   │       └── mod.rs
│   │
│   └── utils/
│       └── mod.rs                # Utility functions (vector ops)
│
└── tests/
    └── integration_test.rs       # Integration tests
```

## Key Components

### 1. Proto Definition (`proto/feature_store.proto`)

Defines the gRPC API contract with operations:
- `GetFeatures` - Single entity feature retrieval
- `BatchGetFeatures` - Multi-entity batch retrieval
- `SetFeature` - Feature value updates
- `GetFeatureMetadata` - Feature definition queries

Supports multiple feature types:
- Double, Int, String, Bool
- DoubleList (embedding vectors)
- Timestamp

### 2. Storage Layers

#### Hot Storage (Redis) - `services/online/mod.rs`
- Ultra-low latency (<10ms p99)
- Frequently accessed features
- TTL-based expiration
- Key format: `features:{entity_type}:{entity_id}:{feature_name}`

#### Near-Line Storage (ClickHouse) - `services/near_line/mod.rs`
- Medium latency (<100ms p99)
- Historical features
- Analytical queries
- 90-day retention

#### Metadata Storage (PostgreSQL) - `db/mod.rs`
- Feature definitions
- Entity type schemas
- Feature metadata

### 3. Configuration (`config/mod.rs`)

Environment-based configuration with validation:
- Server ports (HTTP: 8010, gRPC: 9010)
- Database connections (PostgreSQL, Redis, ClickHouse)
- Feature serving parameters
- Observability settings

### 4. Models (`models/mod.rs`)

Domain models:
- `FeatureDefinition` - Feature metadata
- `FeatureType` - Type enumeration
- `FeatureValueData` - Value wrapper
- `Feature` - Complete feature with metadata

### 5. Utilities (`utils/mod.rs`)

Vector operations for embeddings:
- `feature_to_vector` - Convert to ndarray
- `cosine_similarity` - Similarity computation
- `normalize_vector` - Vector normalization

## Database Schemas

### PostgreSQL Metadata

**Tables:**
- `entity_types` - Entity type definitions (user, post, comment)
- `feature_definitions` - Feature metadata (name, type, TTL, description)

**Indexes:**
- `entity_type` and `name` for fast lookups

### ClickHouse Features

**Tables:**
- `features` - Main feature storage (ReplacingMergeTree)
- `feature_embeddings` - Optimized vector storage
- `feature_access_log` - Access monitoring
- `feature_access_stats` - Materialized view for analytics

**Optimizations:**
- Partitioned by month
- Bloom filter indexes
- 90-day TTL
- ReplacingMergeTree for deduplication

## Dependencies

### Workspace Dependencies
- `actix-web` - HTTP server
- `tokio` - Async runtime
- `sqlx` - PostgreSQL client
- `redis` - Redis client
- `tonic` - gRPC framework
- `prost` - Protocol buffers

### Feature-Specific
- `ndarray` - Vector operations
- `tract-onnx` - ONNX model serving (future)
- `clickhouse` - ClickHouse client

### Shared Libraries
- `error-types` - Common error handling
- `db-pool` - Database connection pooling
- `grpc-tls` - gRPC TLS configuration
- `resilience` - Retry/circuit breaker patterns

## Service Ports

- **HTTP**: 8010 (health checks)
- **gRPC**: 9010 (feature serving)

## Health Endpoints

- `GET /health` - Basic health check
- `GET /ready` - Readiness check (Redis, ClickHouse, PostgreSQL)

## Next Steps

### Phase D Implementation Tasks

1. **Complete Online Service**
   - Implement connection pooling for Redis
   - Add pipeline optimization for batch operations
   - Implement cache warming strategies

2. **Complete Near-Line Service**
   - Implement ClickHouse query methods
   - Add background sync worker (Redis → ClickHouse)
   - Implement feature metadata CRUD

3. **Add Observability**
   - Prometheus metrics
   - Distributed tracing
   - Feature access logging

4. **Implement Feature Cache**
   - LRU eviction policy
   - Configurable size limits
   - Cache hit/miss metrics

5. **Add Advanced Features**
   - Feature versioning
   - Feature validation
   - ONNX model serving for real-time scoring

## Testing

### Unit Tests
- Configuration validation
- Redis key building
- Vector operations

### Integration Tests
- Redis feature operations
- ClickHouse fallback
- Batch operations
- TTL expiration

## Performance Targets

- **Get Features (Hot)**: <10ms p99 (Redis)
- **Get Features (Cold)**: <100ms p99 (ClickHouse)
- **Batch Get Features**: <50ms p99 for 100 entities
- **Set Feature**: <5ms p99

## Development Commands

```bash
# Build service
cargo build --bin feature-store

# Run service
cargo run --bin feature-store

# Run tests
cargo test

# Run integration tests
cargo test --test integration_test -- --ignored

# Apply PostgreSQL migrations
sqlx migrate run --database-url $DATABASE_URL

# Apply ClickHouse schema
clickhouse-client < migrations/002_clickhouse_schema.sql
```

## Security Considerations

- No hardcoded credentials (environment variables only)
- Connection timeout configuration
- Input validation for entity IDs and feature names
- Rate limiting for batch operations (max 100 entities)

## Status

**Complete**: Directory structure, core scaffolding, configuration, models, proto definitions
**TODO**: Service implementation, background workers, observability, advanced features

---

*This service is ready for Phase D implementation of the ranking and recommendation system.*

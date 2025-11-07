# Recent Architecture Changes (2025-01)

## Spec 007: Database Consolidation - COMPLETED ✅

**Status**: All 4 phases merged to main (PR #58, commit 5b77b170)

### Overview
Complete microservice independence achieved by removing database-level foreign key constraints and implementing application-level validation via gRPC.

### Phases Completed

#### Phase 1: messaging-service
- **Orphan Cleaner**: Background job for conversations/messages/participants cleanup
- **Tables**: `conversations`, `messages`, `conversation_participants`
- **Batch API**: Check 100 users per gRPC call (N+1 elimination)
- **Tests**: 409 lines of integration tests using testcontainers

#### Phase 2: content-service
- **Orphan Cleaner**: Posts cleanup
- **Tables**: `posts`
- **Integration Tests**: Full gRPC simulation with MockAuthClient

#### Phase 3: feed-service
- **Orphan Cleaner**: Feed items cleanup
- **Tables**: `feed_items`
- **Integration Tests**: Comprehensive test coverage

#### Phase 4: streaming-service
- **Stream Cleaner**: Streams, keys, and sessions cleanup
- **Tables**: `streams`, `stream_keys`, `viewer_sessions`
- **NULL Handling**: Anonymous viewers preserved (viewer_id IS NOT NULL filter)
- **Tests**: 409 lines with 6 integration test cases

### Architecture Components

#### Unified gRPC AuthClient
**Location**: `backend/libs/grpc-clients/src/auth_client.rs` (228 lines)

**Features**:
- Connection pooling via `GrpcClientPool`
- Batch API: `check_users_exist_batch(Vec<Uuid>) -> HashMap<Uuid, bool>`
- Two initialization patterns:
  - `AuthClient::from_pool()` - Recommended (centralized pool)
  - `AuthClient::new(url)` - Legacy compatibility
- Request timeout: 500ms optimized for existence checks

**Usage Pattern**:
```rust
// Initialize pool
let grpc_config = GrpcConfig::from_env()?;
let grpc_pool = Arc::new(GrpcClientPool::new(&grpc_config).await?);
let auth_client = Arc::new(AuthClient::from_pool(grpc_pool.clone()));

// Batch check users
let results = auth_client.check_users_exist_batch(user_ids).await?;
```

#### Orphan Cleaner Pattern
**Common Implementation** (across 4 services):
- **Interval**: 24 hours
- **Retention**: 30 days before hard delete
- **Batch Size**: 100 users per gRPC call
- **Metrics**: Prometheus counters, histograms, gauges

**Cleanup Steps**:
1. Collect all unique user IDs from service tables
2. Batch call auth-service to check which users are deleted
3. Soft delete content (set deleted_at, preserve audit trail)
4. Hard delete non-audited data (sessions, keys)

#### Prometheus Metrics
Each service exposes:
- `{service}_orphan_cleaner_runs_total` - Counter
- `{service}_orphan_cleaner_duration_seconds` - Histogram
- `{service}_orphan_cleaner_users_checked` - Gauge
- `{service}_orphan_cleaner_deleted_total` - Counter by content type

### Integration Testing
**Framework**: testcontainers + PostgreSQL + MockAuthClient

**Test Coverage**:
- Soft delete verification
- Hard delete verification
- N+1 elimination proof (batch API usage)
- NULL value handling
- 30-day retention period validation

### Documentation
- `/docs/specs/spec007-pr-summary.md` - Complete implementation summary
- `/docs/architecture/foreign_key_inventory.md` - FK constraint audit
- `/docs/architecture/foreign_key_removal_plan.md` - Consolidation strategy
- `/docs/operations/spec007-phase1-runbook.md` - Operations guide

---

## gRPC Infrastructure

### Status
- ✅ All services expose gRPC on `HTTP_PORT + 1000`
- ✅ Health checks via `tonic_health`
- ✅ Correlation-id middleware for request tracing
- ✅ Metrics collection via custom middleware

### Service Ports
- **auth-service**: REST 8081, gRPC 9081
- **messaging-service**: REST 8080, gRPC 9080
- **content-service**: REST 8082, gRPC 9082
- **feed-service**: REST 8084, gRPC 9084
- **streaming-service**: REST 8083, gRPC 9083

### gRPC Client Libraries
**Location**: `backend/libs/grpc-clients/`

**Components**:
- `GrpcClientPool` - Centralized connection management
- `GrpcConfig` - Environment-based configuration
- `AuthClient` - Unified auth-service client
- Custom middleware for metrics and tracing

---

## Infrastructure Updates

### EKS Cluster
**Status**: Deployed to AWS ap-northeast-1
**Cluster**: `nova-staging`
**Config**: `terraform/eks.tf` (268 lines)

**Features**:
- Node group with auto-scaling
- Kubeconfig generation
- IAM roles and policies
- VPC and subnet configuration

### E2E Testing Framework
**Guide**: `docs/E2E_TESTING_GUIDE.md` (588 lines)

**Components**:
- Seed data scripts (`backend/scripts/seed_data/`)
- Cross-service test scenarios
- Real database testing with Docker

### CI/CD Enhancements
- Protobuf compiler in CI pipeline
- AWS ECR automated builds with OIDC
- User-service dedicated deployment workflows
- Docker image optimization (Rust 1.88-slim)

---

## Removed/Obsolete Work

### Deleted Branch: feature/phase1-grpc-migration
**Deleted**: 2025-01-07
**Reason**: All work superseded by Spec 007 implementation

**Analysis**: `docs/branch-analysis-phase1-grpc-FINAL.md`

This branch (32 commits) attempted gRPC refactoring but:
- Had zero unique value (all duplicated by Spec 007)
- Used inferior implementation (no connection pooling, no batch API)
- Would have deleted 3,675 lines of production code/docs
- Contained mostly fix commits (72%) showing poor development approach

The main branch's Spec 007 implementation is superior in every aspect.

---

## Current Best Practices

### gRPC Client Usage
1. **Always use GrpcClientPool** for centralized connection management
2. **Use batch APIs** to eliminate N+1 queries
3. **Add request timeouts** (500ms for EXISTS checks)
4. **Implement retry logic** with exponential backoff
5. **Monitor with Prometheus** (track call duration, error rates)

### Orphan Cleanup Implementation
1. **24-hour intervals** prevent excessive load
2. **30-day retention** provides safety buffer
3. **Batch processing** (100 users per call) optimizes network
4. **Separate soft/hard deletes** based on audit requirements
5. **NULL handling** for optional foreign keys

### Testing Strategy
1. **testcontainers** for real PostgreSQL integration tests
2. **MockAuthClient** for isolated unit tests
3. **Verify N+1 elimination** by checking gRPC call count
4. **Test edge cases**: NULL values, empty results, errors

---

## Next Steps (Completed)

✅ Phase 1-4: All services migrated to application-level validation
✅ gRPC infrastructure deployed across all services
✅ Integration tests covering all cleanup scenarios
✅ Prometheus metrics for production monitoring
✅ Documentation and runbooks complete

**Status**: Database consolidation fully complete. All services are microservice-independent.

---

*Last Updated: 2025-01-07*
*Reference Commit: 9ef32948*

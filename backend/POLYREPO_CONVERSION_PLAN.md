# Polyrepo Conversion Plan - Phase 9.3

## Overview

This document outlines the strategic plan for migrating from a monorepo to a polyrepo architecture for Nova's microservices. The conversion will enable independent deployment, faster CI/CD pipelines, and clearer service ownership.

## Current State (Monorepo)

### Services in workspace
```
backend/
├── auth-service/          (Port 8084)
├── content-service/       (Port 8081)
├── feed-service/          (Port 8089)
├── media-service/         (Port 8082)
├── messaging-service/     (Port 8085)
├── search-service/        (Port 8086)
├── streaming-service/     (Port 8088)
├── user-service/          (Port 8080)
└── libs/
    ├── error-types/
    ├── nova-fcm-shared/
    ├── crypto-core/
    ├── db-pool/
    ├── redis-utils/
    └── ...other shared
```

### Test Execution Current (Phase 8)
- Single CI job with all services
- Monolithic compilation and testing
- Interdependent failures block entire pipeline
- Build time: ~35-50 seconds
- Tests: ~137 passing

## Proposed Polyrepo Structure

### Phase 1: Core Infrastructure Repos (Weeks 1-2)

#### Repo 1: nova-shared
**Purpose**: Shared libraries and types

```
nova-shared/
├── Cargo.toml (workspace root)
├── libs/
│   ├── error-types/
│   ├── crypto-core/
│   ├── db-pool/
│   ├── redis-utils/
│   ├── nova-fcm-shared/
│   └── Cargo.toml
├── .github/workflows/
│   └── ci.yml (library CI)
└── README.md
```

**Dependencies**: None (base)
**Published to**: crates.io (internal registry)
**CI Strategy**: Fast library validation

---

#### Repo 2: nova-api-gateway
**Purpose**: API routing and service discovery

```
nova-api-gateway/
├── Cargo.toml
├── src/
├── protos/
│   ├── health.proto
│   └── discovery.proto
├── Dockerfile
├── docker-compose.yml (local testing)
├── .github/workflows/
│   └── ci.yml
└── k8s/
    └── gateway-config.yaml
```

**Dependencies**:
- nova-shared (error-types, db-pool)

**CI Strategy**:
- Health check tests
- Service routing validation
- Docker build

---

### Phase 2: Core Services (Weeks 3-4)

#### Repo 3: nova-auth-service
**Purpose**: Authentication and JWT management

```
nova-auth-service/
├── Cargo.toml
├── src/
│   ├── handlers/
│   ├── services/
│   │   ├── oauth/
│   │   ├── jwt.rs
│   │   ├── two_fa.rs
│   │   └── email_service.rs
│   ├── db/
│   └── main.rs
├── migrations/
│   └── 001_initial_schema.sql
├── Dockerfile
├── .github/workflows/
│   ├── ci.yml
│   └── deploy.yml
└── k8s/
    └── deployment.yaml
```

**Dependencies**:
- nova-shared (error-types, crypto-core)
- External: sqlx, tokio, actix-web, lettre

**CI Strategy**:
- Fast turnaround (25-30 seconds)
- OAuth provider testing
- 2FA/JWT validation
- Email service mocking

**Critical Decision**: Split from user-service communication
- Use gRPC for auth verification (stateless validation)
- User-service calls auth-service API for token verification

---

#### Repo 4: nova-user-service
**Purpose**: User profiles and social relationships

```
nova-user-service/
├── Cargo.toml
├── src/
│   ├── handlers/
│   │   ├── users.rs
│   │   ├── relationships.rs
│   │   └── preferences.rs
│   ├── services/
│   │   ├── graph/
│   │   └── social_graph_sync.rs
│   ├── db/
│   └── main.rs
├── migrations/
│   ├── 001_users.sql
│   ├── 004_social_graph.sql
│   └── ...
├── Dockerfile
├── .github/workflows/
│   └── ci.yml
└── k8s/
    └── deployment.yaml
```

**Dependencies**:
- nova-shared
- nova-auth-service (gRPC client)
- External: sqlx, neo4rs, redis, tokio

**CI Strategy**:
- Medium speed (30-40 seconds)
- Neo4j relationship tests
- Redis caching tests
- Social graph consistency tests

---

### Phase 3: Content & Feed Services (Weeks 5-6)

#### Repo 5: nova-content-service
**Purpose**: Posts and user-generated content

```
nova-content-service/
├── Cargo.toml
├── src/
├── migrations/
└── .github/workflows/
```

**Dependencies**:
- nova-shared
- nova-user-service (gRPC - user info)
- nova-auth-service (gRPC - auth)

**Service Comm**: gRPC for user validation

---

#### Repo 6: nova-feed-service
**Purpose**: Feed generation and ranking

```
nova-feed-service/
├── Cargo.toml
├── src/
│   ├── handlers/
│   │   ├── feed.rs
│   │   ├── trending.rs
│   │   └── experiments.rs
│   ├── services/
│   │   ├── ranking/
│   │   ├── experiments/
│   │   └── trending/
│   └── cache/
├── migrations/
└── .github/workflows/
```

**Dependencies**:
- nova-shared
- nova-user-service (gRPC)
- nova-content-service (gRPC)
- External: clickhouse, onnx models

**Service Comm**:
- gRPC for user/content data
- Kafka for feed invalidation events

---

### Phase 4: Media Services (Week 7)

#### Repo 7: nova-media-service
**Purpose**: Uploads, videos, and media processing

```
nova-media-service/
├── Cargo.toml
├── src/
├── migrations/
└── .github/workflows/
```

**Dependencies**:
- nova-shared
- nova-user-service (gRPC)
- External: aws-sdk-s3, ffmpeg, image libraries

---

### Phase 5: Real-time Services (Week 8)

#### Repo 8: nova-messaging-service
**Purpose**: Messages, WebSocket, and real-time

```
nova-messaging-service/
├── Cargo.toml
├── src/
├── migrations/
└── .github/workflows/
```

**Dependencies**:
- nova-shared
- nova-user-service (gRPC)
- External: tokio, ws, actix-web-actors

---

## Migration Strategy

### Step 1: Prepare Shared Libraries (Week 1)

1. **Extract nova-shared repo**
   ```bash
   # Separate nova-shared from monorepo
   git clone --filter=blob:none nova-monorepo nova-shared
   git filter-branch --subdirectory-filter backend/libs
   git push origin main
   ```

2. **Publish to internal crates.io**
   - Configure cargo private registry
   - Publish versions 0.1.0

3. **Update workspace dependencies**
   - All services reference shared libraries from registry

### Step 2: Extract First Service (Week 2-3)

**Choose auth-service** - least dependent, good test case

```bash
# Create nova-auth-service repo
git init nova-auth-service
git add backend/auth-service
git add backend/migrations/002*.sql  # auth migrations
git add backend/libs/crypto-core    # local copy
git commit -m "Initial auth-service"
git push
```

**Testing before deletion**:
1. Stand up nova-shared as local dependency
2. Verify auth-service builds independently
3. Run full auth-service test suite
4. Mock user-service API calls

### Step 3: Establish Service Communication (Week 3)

**Create service client libraries**:
- `nova-auth-client` - JWT verification client
- `nova-user-client` - User info retrieval client
- etc.

**Pattern** (for auth-service example):
```rust
// In nova-shared/nova-auth-client/src/lib.rs
pub async fn verify_token(token: &str) -> Result<UserClaims> {
    // gRPC call to auth-service:8084
}
```

### Step 4: Extract Remaining Services (Weeks 4-8)

**Sequential extraction** (dependency order):
1. nova-user-service (once auth-service works)
2. nova-content-service (depends on user + auth)
3. nova-feed-service (depends on content + user)
4. nova-media-service (independent)
5. nova-messaging-service (mostly independent)

### Step 5: Local Development Setup (Week 8-9)

**mono-repo for local dev** (optional):
```bash
# Root level docker-compose for full stack
docker-compose.yml:
  auth-service: builds locally
  user-service: builds locally
  content-service: builds locally
  ...
```

**Or**: Publish prebuilt containers to Docker Hub

## CI/CD Strategy per Repo

### nova-shared (Fastest)
```
Jobs:
├── Code Quality (5s)
├── Build Libraries (10s)
└── Publish to Registry (5s)
Total: ~20 seconds
```

### Service Repos (Medium Speed)
```
Jobs:
├── Code Quality (5s)
├── Build Service (15s)
├── Unit Tests (20s)
├── Integration Tests (30s)
└── Docker Build & Push (30s)
Total: ~100 seconds (parallel) vs 150+ monorepo
```

**Benefit**: Independent services can merge while others are testing

## Data & Database Strategy

### Schema Management
**Challenge**: Services need independent PostgreSQL instances with their own schemas

**Solution**:
```sql
-- One physical DB, multiple schemas per service
CREATE SCHEMA auth;        -- auth-service owns this
CREATE SCHEMA users;       -- user-service owns this
CREATE SCHEMA content;     -- content-service owns this
...
```

**CDC Pipelines** (data consistency):
```
auth.users → Kafka → users.users (sync)
users.relationships → Kafka → graph_db (Neo4j)
content.posts → Kafka → analytics.posts
```

## Rollback Plan

If polyrepo causes issues:

1. **Week 1-2**: Can quickly merge back - minimal changes
2. **Week 3+**: Harder - need to resolve service comm patterns
3. **Decision point (Week 3)**: Go/no-go on full conversion

**Exit criteria**:
- ❌ gRPC calls across services have >500ms latency
- ❌ CI/CD pipelines slower than monorepo
- ❌ Teams report development friction

## Success Metrics

### Build Speed
- Current: ~50 seconds (all services)
- Target: ~100 seconds per service (parallel → overall faster)

### Deployment Speed
- Current: All services must pass before deploy
- Target: Deploy auth-service in 2 minutes, user-service in 3 minutes (independent)

### Developer Experience
- Clearer code ownership (one repo = one team)
- Faster local feedback loops
- Independent release cycles

### Scalability
- Services can scale independently
- Different tech stacks possible (one repo uses Rust, another Go)
- Easier onboarding (smaller codebases)

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Service discovery failures | High | Implement circuit breakers, health checks |
| Network latency overhead | Medium | Use gRPC, connection pooling |
| Data consistency | High | CDC pipelines, event sourcing |
| Dependency version conflicts | Low | Shared library versioning strategy |
| Developer confusion | Medium | Clear documentation, runbooks |

## Timeline

```
Week 1:   Extract nova-shared, publish to registry
Week 2:   Extract nova-auth-service, setup gRPC
Week 3:   Extract nova-user-service
Week 4-6: Extract content, feed, media services
Week 7:   Full polyrepo, all independent
Week 8:   Stabilize, monitor metrics
Week 9:   Document, team training
```

## Decision Gate (After Week 3)

**Go/No-Go Meeting**:
- Assess service communication latency
- Review developer experience feedback
- Check CI/CD metrics
- Decide: continue or rollback

## Implementation Notes

### Shared Code Organization
```bash
# Option A: Separate repos for shared libs
nova-shared/
  ├── error-types/
  ├── crypto-core/
  └── db-pool/

# Option B: Monorepo for shared, polyrepo for services
nova-core/
  ├── backend/libs/
  ├── backend/auth-service/
  ├── backend/user-service/
  └── ...
```

**Recommendation**: Option A (cleanest separation)

### Private Crates Registry
- Use Artifactory or GitHub Packages
- Or self-host crates.io instance
- Versioning: SemVer for all shared libraries

### Service Dependencies Graph
```
nova-shared
├─ nova-auth-service
├─ nova-api-gateway
└─ (all others)

nova-auth-service
├─ nova-shared
└─ external

nova-user-service
├─ nova-shared
├─ nova-auth-service
└─ external

nova-content-service
├─ nova-shared
├─ nova-user-service
├─ nova-auth-service
└─ external
```

## Conclusion

Polyrepo conversion is a **strategic** decision with significant benefits (independent scaling, faster CI/CD) and costs (operational complexity).

**Recommended approach**:
1. Start with Phase 9.3 planning (this document)
2. Execute Phase 10 (Week-by-week extraction)
3. Monitor metrics closely
4. Be prepared to rollback if issues emerge

---

**Created**: 2024-10-30
**Phase**: 9.3 - Polyrepo Conversion Planning
**Status**: PLANNING - Ready for stakeholder review

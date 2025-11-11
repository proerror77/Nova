# P0 Implementation Checklist

**Date**: 2025-11-11
**Based on**: Codex GPT-5 Architectural Review
**Priority**: P0 (Critical Security & Stability)
**Target**: Complete before AWS deployment

---

## Overview

This document tracks the implementation of P0 (highest priority) security and stability improvements identified by Codex GPT-5 architectural review. These items MUST be completed before deploying V2 to production.

---

## Current Status Summary

### ✅ Already Implemented (70% complete)

1. **GraphQL Complexity Limits** ✅
   - Location: `backend/graphql-gateway/src/security.rs`
   - Location: `backend/graphql-gateway/src/schema/complexity.rs`
   - Status: **Complete** - Full implementation with tests
   - Features:
     - Query complexity calculation (max: 1000)
     - Query depth limits (max: 10)
     - Persisted queries support
     - Request budget enforcement
     - Per-user rate limiting

2. **Timeout & Circuit Breaker Library** ✅
   - Location: `backend/libs/resilience/src/lib.rs`
   - Status: **Complete** - Reusable library with tests
   - Features:
     - `with_timeout()` for DB, gRPC, cache operations
     - Circuit breaker pattern implementation
     - Retry with exponential backoff
     - Request budgeting
     - Load shedding

3. **mTLS Infrastructure** ✅
   - Location: `backend/libs/grpc-tls/src/lib.rs`
   - Status: **Complete** - Production-ready library
   - Features:
     - Server TLS with certificate validation
     - Client mTLS authentication
     - Certificate rotation support
     - Dev cert generation for testing

### 🟡 Partially Implemented (Need Integration)

4. **Service Health Checks** 🟡
   - Current: Basic HTTP endpoints (`/health`, `/ready`)
   - Example: `backend/identity-service/src/main.rs:120`
   - Missing: gRPC health check protocol (tonic-health)
   - Action: Add `tonic_health` to all V2 services

5. **PgBouncer Connection Pooling** 🟡
   - Current: ConfigMaps have optimized settings (max: 12)
   - Location: `k8s/microservices/*-configmap.yaml`
   - Missing: Actual PgBouncer deployment in K8s
   - Action: Deploy PgBouncer StatefulSet

### ❌ Not Yet Integrated

6. **mTLS Enforcement** ❌
   - Library exists but NOT integrated into service startup
   - Action: Update all gRPC servers to use `grpc-tls`

7. **GraphQL Security Extensions** ❌
   - Extensions exist but NOT registered in Gateway
   - Action: Add `ComplexityLimit` extension to schema builder

8. **Resilience Wrappers** ❌
   - Library exists but NOT used in service-to-service calls
   - Action: Wrap all gRPC clients with `with_grpc_timeout()`

---

## Detailed Implementation Plan

### P0-1: Integrate mTLS to All gRPC Services

**Priority**: 🔴 Critical
**Effort**: 4 hours
**Dependencies**: `grpc-tls` library (already complete)

#### Tasks:

1. **Update each service's `main.rs`** to enable TLS:
   ```rust
   use grpc_tls::GrpcServerTlsConfig;

   // In main():
   let tls_config = if cfg!(debug_assertions) {
       GrpcServerTlsConfig::development()?
   } else {
       GrpcServerTlsConfig::from_env()?
   };

   Server::builder()
       .tls_config(tls_config.build_server_tls()?)? // ADD THIS
       .add_service(...)
       .serve(addr)
       .await?;
   ```

2. **Services to update**:
   - [x] identity-service (NEW V2)
   - [x] user-service
   - [x] content-service
   - [x] social-service (NEW V2)
   - [x] media-service
   - [x] communication-service (NEW V2)
   - [x] search-service
   - [x] events-service

3. **Update K8s Secrets** with TLS certificates:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: grpc-tls-certs
   type: kubernetes.io/tls
   data:
     tls.crt: <base64-encoded-cert>
     tls.key: <base64-encoded-key>
     ca.crt: <base64-encoded-ca>
   ```

4. **Mount secrets in Deployments**:
   ```yaml
   volumeMounts:
   - name: tls-certs
     mountPath: /etc/grpc/tls
     readOnly: true

   volumes:
   - name: tls-certs
     secret:
       secretName: grpc-tls-certs
   ```

5. **Set environment variables** in Deployments:
   ```yaml
   env:
   - name: GRPC_SERVER_CERT_PATH
     value: /etc/grpc/tls/tls.crt
   - name: GRPC_SERVER_KEY_PATH
     value: /etc/grpc/tls/tls.key
   - name: GRPC_CLIENT_CA_CERT_PATH
     value: /etc/grpc/tls/ca.crt
   - name: GRPC_REQUIRE_CLIENT_CERT
     value: "true"  # Enable mTLS
   ```

#### Validation:
- [ ] All services start with TLS enabled
- [ ] gRPC calls require client certificates
- [ ] Prometheus metrics show `grpc_tls_enabled=1`

---

### P0-2: Add GraphQL Security Extensions

**Priority**: 🔴 Critical
**Effort**: 2 hours
**Dependencies**: `graphql-gateway/src/security.rs` (already complete)

#### Tasks:

1. **Update `graphql-gateway/src/main.rs`**:
   ```rust
   use crate::security::{ComplexityLimit, PersistedQueries, RequestBudget, SecurityConfig};

   // In schema builder:
   let security_config = SecurityConfig::default(); // Or from env

   let schema = Schema::build(QueryRoot, MutationRoot, SubscriptionRoot)
       .extension(ComplexityLimit::new(
           security_config.max_complexity,
           security_config.max_depth,
       ))
       .extension(RequestBudget::new(security_config.max_backend_calls))
       .data(PersistedQueries::new(security_config.use_persisted_queries))
       .finish();
   ```

2. **Add security config to Gateway ConfigMap**:
   ```yaml
   # k8s/microservices/graphql-gateway-configmap.yaml
   data:
     graphql-max-complexity: "1000"
     graphql-max-depth: "10"
     graphql-max-backend-calls: "10"
     graphql-allow-introspection: "false"  # Disable in production
     graphql-use-persisted-queries: "true"
   ```

3. **Load persisted queries from file**:
   ```rust
   if security_config.use_persisted_queries {
       let queries = PersistedQueries::new(false);  // Don't allow arbitrary
       queries.load_from_file("/etc/graphql/persisted-queries.json").await?;
       schema = schema.data(queries);
   }
   ```

4. **Create persisted queries file**:
   ```json
   {
     "login_query": "query Login($email: String!, $password: String!) { ... }",
     "feed_query": "query Feed($first: Int) { posts(first: $first) { ... } }"
   }
   ```

#### Validation:
- [ ] Complex queries are rejected (complexity > 1000)
- [ ] Deep queries are rejected (depth > 10)
- [ ] Introspection disabled in production
- [ ] Persisted queries work
- [ ] Non-persisted queries rejected (if enabled)

---

### P0-3: Deploy PgBouncer to Kubernetes

**Priority**: 🔴 Critical
**Effort**: 3 hours
**Dependencies**: PostgreSQL 14 already deployed

#### Tasks:

1. **Create PgBouncer ConfigMap**:
   ```yaml
   # k8s/infrastructure/pgbouncer-configmap.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: pgbouncer-config
     namespace: nova
   data:
     pgbouncer.ini: |
       [databases]
       nova_identity = host=postgres port=5432 dbname=nova_identity
       nova_user = host=postgres port=5432 dbname=nova_user
       nova_content = host=postgres port=5432 dbname=nova_content
       nova_social = host=postgres port=5432 dbname=nova_social
       nova_communication = host=postgres port=5432 dbname=nova_communication

       [pgbouncer]
       listen_addr = 0.0.0.0
       listen_port = 5432
       auth_type = md5
       auth_file = /etc/pgbouncer/userlist.txt
       pool_mode = transaction
       max_client_conn = 1000
       default_pool_size = 25
       reserve_pool_size = 5
       reserve_pool_timeout = 3
       server_lifetime = 3600
       server_idle_timeout = 600
   ```

2. **Create PgBouncer Deployment**:
   ```yaml
   # k8s/infrastructure/pgbouncer-deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: pgbouncer
     namespace: nova
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: pgbouncer
     template:
       metadata:
         labels:
           app: pgbouncer
       spec:
         containers:
         - name: pgbouncer
           image: pgbouncer/pgbouncer:1.21
           ports:
           - containerPort: 5432
           volumeMounts:
           - name: config
             mountPath: /etc/pgbouncer
         volumes:
         - name: config
           configMap:
             name: pgbouncer-config
   ```

3. **Create PgBouncer Service**:
   ```yaml
   # k8s/infrastructure/pgbouncer-service.yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: pgbouncer
     namespace: nova
   spec:
     selector:
       app: pgbouncer
     ports:
     - port: 5432
       targetPort: 5432
   ```

4. **Update service connection strings** to use PgBouncer:
   ```yaml
   # Before:
   database-url: "postgresql://user:pass@postgres:5432/dbname"

   # After:
   database-url: "postgresql://user:pass@pgbouncer:5432/dbname"
   ```

#### Validation:
- [ ] PgBouncer pods running (2 replicas)
- [ ] Services can connect through PgBouncer
- [ ] Connection count < 25 per service (transaction pooling)
- [ ] Prometheus shows `pgbouncer_active_clients`

---

### P0-4: Add tonic-health to All Services

**Priority**: 🟡 High
**Effort**: 3 hours
**Dependencies**: `tonic-health` crate

#### Tasks:

1. **Add dependency** to `Cargo.toml`:
   ```toml
   [dependencies]
   tonic-health = "0.10"
   ```

2. **Update each service's `main.rs`**:
   ```rust
   use tonic_health::server::{health_reporter, HealthReporter};

   #[tokio::main]
   async fn main() -> Result<()> {
       // ...existing setup...

       // Create health reporter
       let (mut health_reporter, health_service) = health_reporter();

       // Mark as serving
       health_reporter
           .set_serving::<IdentityServiceServer<IdentityServiceImpl>>()
           .await;

       // Start gRPC server with health service
       Server::builder()
           .add_service(health_service)  // ADD THIS
           .add_service(IdentityServiceServer::new(identity_impl))
           .serve(addr)
           .await?;

       Ok(())
   }
   ```

3. **Add health checks in K8s Deployments**:
   ```yaml
   livenessProbe:
     exec:
       command: ["/bin/grpc_health_probe", "-addr=:50051"]
     initialDelaySeconds: 5

   readinessProbe:
     exec:
       command: ["/bin/grpc_health_probe", "-addr=:50051"]
     initialDelaySeconds: 10
   ```

4. **Add grpc_health_probe to container image**:
   ```dockerfile
   # In each service's Dockerfile:
   RUN wget -qO/bin/grpc_health_probe https://github.com/grpc-ecosystem/grpc-health-probe/releases/download/v0.4.19/grpc_health_probe-linux-amd64 && \
       chmod +x /bin/grpc_health_probe
   ```

#### Validation:
- [ ] `grpc_health_probe` returns SERVING
- [ ] K8s readiness probe passes
- [ ] K8s liveness probe passes
- [ ] Health status updates on failures

---

### P0-5: Integrate Resilience Library

**Priority**: 🟡 High
**Effort**: 4 hours
**Dependencies**: `libs/resilience` (already complete)

#### Tasks:

1. **Wrap all database calls**:
   ```rust
   use resilience::with_db_timeout;

   // Before:
   let user = sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", id)
       .fetch_one(pool)
       .await?;

   // After:
   let user = with_db_timeout(async {
       sqlx::query_as!(User, "SELECT * FROM users WHERE id = $1", id)
           .fetch_one(pool)
           .await
           .context("Failed to fetch user")
   })
   .await?;
   ```

2. **Wrap all gRPC calls** in Gateway:
   ```rust
   use resilience::with_grpc_timeout;

   // Before:
   let response = client.get_user(request).await?;

   // After:
   let response = with_grpc_timeout(async {
       client.get_user(request)
           .await
           .context("gRPC call to user-service failed")
   })
   .await?;
   ```

3. **Wrap cache operations**:
   ```rust
   use resilience::with_cache_timeout;

   // Before:
   let cached: Option<User> = redis.get(&key).await?;

   // After:
   let cached: Option<User> = with_cache_timeout(async {
       redis.get(&key)
           .await
           .context("Cache get failed")
   })
   .await
   .unwrap_or(None);  // Degrade gracefully on cache failure
   ```

4. **Add circuit breakers for critical paths**:
   ```rust
   use resilience::CircuitBreaker;
   use std::sync::Arc;

   // In service struct:
   struct UserService {
       db: Pool,
       circuit_breaker: Arc<CircuitBreaker>,
   }

   impl UserService {
       fn new(db: Pool) -> Self {
           Self {
               db,
               circuit_breaker: Arc::new(CircuitBreaker::new(5, 2, Duration::from_secs(60))),
           }
       }

       async fn get_user(&self, id: UserId) -> Result<User> {
           self.circuit_breaker.call(async {
               with_db_timeout(async {
                   sqlx::query_as!(...)
                       .fetch_one(&self.db)
                       .await
                       .context("DB query failed")
               })
               .await
           })
           .await
       }
   }
   ```

5. **Update ConfigMaps** with timeout values:
   ```yaml
   # Already in V2 ConfigMaps:
   db-timeout: "5s"
   redis-timeout: "2s"
   kafka-timeout: "10s"
   circuit-breaker-failure-threshold: "5"
   circuit-breaker-success-threshold: "2"
   circuit-breaker-timeout: "60s"
   ```

#### Validation:
- [ ] All DB queries have timeouts
- [ ] All gRPC calls have timeouts
- [ ] Circuit breaker opens after 5 failures
- [ ] Circuit breaker closes after 2 successes
- [ ] Prometheus shows `circuit_breaker_state` metric

---

## Implementation Order

Based on dependencies and criticality:

1. **Week 1** (16 hours):
   - [x] P0-2: GraphQL Security Extensions (2h) - **START HERE**
   - [x] P0-4: tonic-health to Services (3h)
   - [x] P0-5: Integrate Resilience Library (4h)
   - [x] P0-3: Deploy PgBouncer (3h)
   - [x] P0-1: mTLS Integration (4h) - **MOST CRITICAL**

2. **Week 2** (Post-P0):
   - [ ] Deploy to staging with P0 complete
   - [ ] Load testing and validation
   - [ ] AWS deployment via GitHub Actions

---

## Validation Criteria

Before marking P0 as complete:

### Security Validation
- [ ] All gRPC traffic encrypted with TLS
- [ ] Client certificates required (mTLS enabled)
- [ ] GraphQL complexity limits enforced
- [ ] Introspection disabled in production
- [ ] No hardcoded secrets in code

### Performance Validation
- [ ] All database queries < 5s timeout
- [ ] All gRPC calls < 10s timeout
- [ ] PgBouncer connection count < 25 per service
- [ ] Circuit breakers prevent cascading failures

### Reliability Validation
- [ ] Health checks pass in K8s
- [ ] Services restart automatically on failures
- [ ] Circuit breakers recover after failures
- [ ] No panics or unwraps in production paths

### Monitoring Validation
- [ ] Prometheus metrics show all P0 features enabled
- [ ] Grafana dashboards show timeout/circuit breaker stats
- [ ] Alerts configured for P0 feature failures

---

## Rollback Plan

If P0 implementation causes issues:

1. **Disable mTLS**: Set `GRPC_REQUIRE_CLIENT_CERT=false`
2. **Disable GraphQL limits**: Set `graphql-max-complexity=999999`
3. **Bypass PgBouncer**: Update connection strings to direct PostgreSQL
4. **Disable circuit breakers**: Set `circuit-breaker-failure-threshold=999999`

---

## References

- Codex GPT-5 Review: (Background task output)
- GraphQL Security: `backend/graphql-gateway/src/security.rs`
- Resilience Library: `backend/libs/resilience/src/lib.rs`
- mTLS Library: `backend/libs/grpc-tls/src/lib.rs`
- K8s Migration Plan: `k8s/K8S_MIGRATION_PLAN.md`

---

**Last Updated**: 2025-11-11
**Status**: 70% Complete (Libraries built, need integration)
**Next Action**: Start P0-2 (GraphQL Security Extensions)

---
description: Create a new gRPC microservice with complete scaffolding (proto, server, client, tests, K8s manifests)
---

## User Input

```text
$ARGUMENTS
```

Expected format: `<service-name> <description>`

Example: `/grpc.new-service payment-service Handle payment processing and transactions`

## Execution Flow

### 1. Parse Service Details

Extract from arguments:
- **Service name**: First word (e.g., "payment-service")
- **Description**: Remaining text (e.g., "Handle payment processing...")

If missing, prompt user for required information.

### 2. Invoke rust-microservices-architect Agent

Use the Task tool to invoke the `rust-microservices-architect` agent:

```
Task: Design service boundaries and architecture
Agent: rust-microservices-architect
Prompt: |
  Design a new microservice with the following requirements:

  Service Name: {service-name}
  Description: {description}

  Provide:
  1. Service boundary definition (what's in scope, what's out)
  2. Data model (entities this service owns)
  3. gRPC service definition outline (key RPCs)
  4. Integration points with existing services:
     - user-service, content-service, feed-service, media-service
     - messaging-service, auth-service, search-service
     - notification-service, events-service, streaming-service
  5. Event sourcing requirements (Kafka topics to produce/consume)
  6. Database schema outline
```

### 3. Invoke grpc-service-builder Agent

Use the Task tool to invoke the `grpc-service-builder` agent:

```
Task: Generate gRPC service implementation
Agent: grpc-service-builder
Prompt: |
  Based on the architecture designed by rust-microservices-architect, implement:

  1. Proto schema (proto/{service-name}/v1/{service-name}.proto)
     - Service definition with RPCs
     - Message types
     - Enums and common types

  2. Tonic server implementation (backend/{service-name}/src/main.rs)
     - gRPC service trait implementation
     - Request handlers with proper error handling
     - Authentication interceptor integration
     - Metrics and tracing interceptors

  3. Client library (backend/grpc-clients/src/{service-name}_client.rs)
     - Type-safe client wrapper
     - Retry logic with exponential backoff
     - Circuit breaker integration
     - Connection pooling

  4. Integration tests (backend/{service-name}/tests/grpc_tests.rs)
     - Test server setup
     - Happy path tests for each RPC
     - Error case tests
     - Authentication tests

  Use skills: rust-async-patterns, grpc-best-practices
```

### 4. Invoke database-migration-expert Agent

Use the Task tool to invoke the `database-migration-expert` agent:

```
Task: Create initial database migration
Agent: database-migration-expert
Prompt: |
  Create the initial database schema migration for {service-name}:

  1. Migration file: backend/{service-name}/migrations/001_create_{service-name}_tables.sql
  2. Include:
     - All tables based on data model from rust-microservices-architect
     - Primary keys, foreign keys (with ON DELETE strategy)
     - Indexes for common queries
     - Constraints (NOT NULL, UNIQUE, CHECK)
     - Created_at/updated_at timestamps

  3. Follow expand-contract pattern for future changes
  4. Include rollback SQL in comments

  Use skill: database-optimization
```

### 5. Invoke k8s-deployment-engineer Agent

Use the Task tool to invoke the `k8s-deployment-engineer` agent:

```
Task: Generate Kubernetes manifests
Agent: k8s-deployment-engineer
Prompt: |
  Create production-ready Kubernetes manifests for {service-name}:

  Files to create:
  1. k8s/microservices/{service-name}-deployment.yaml
     - Deployment with 3 replicas
     - Resource requests/limits (CPU: 100m-500m, Memory: 128Mi-512Mi)
     - Liveness, readiness, startup probes
     - Environment variables from ConfigMap/Secret

  2. k8s/microservices/{service-name}-service.yaml
     - ClusterIP Service
     - gRPC port (50051)
     - Metrics port (9090)

  3. k8s/microservices/{service-name}-hpa.yaml
     - HorizontalPodAutoscaler
     - Min replicas: 3, Max replicas: 10
     - CPU target: 70%, Memory target: 80%

  4. k8s/microservices/{service-name}-secret.yaml (template)
     - DATABASE_URL placeholder
     - REDIS_URL placeholder
     - KAFKA_BROKERS placeholder

  Use skill: k8s-deployment-patterns
```

### 6. Generate Supporting Files

Create additional project files:

1. **Cargo.toml** (backend/{service-name}/Cargo.toml)
   - Workspace member configuration
   - Dependencies: tokio, tonic, sqlx, redis, kafka, serde, tracing
   - Shared libraries: error-types, grpc-metrics, grpc-clients, crypto-core

2. **Build configuration** (backend/{service-name}/build.rs)
   - Tonic build for proto compilation
   - Proto file path configuration

3. **README.md** (backend/{service-name}/README.md)
   - Service description
   - Architecture overview
   - Development setup
   - Running tests
   - Deployment instructions

4. **Docker configuration** (backend/{service-name}/Dockerfile)
   - Multi-stage build (cargo-chef for caching)
   - Minimal runtime image
   - Health check configuration

### 7. Validation and Summary

1. Verify all files created successfully
2. Run `cargo check` in backend/{service-name}
3. Verify proto compilation works
4. Display service creation summary:

```markdown
## ✅ Service Created: {service-name}

### Files Generated
- Proto schema: proto/{service-name}/v1/{service-name}.proto
- Server: backend/{service-name}/src/main.rs
- Client: backend/grpc-clients/src/{service-name}_client.rs
- Migration: backend/{service-name}/migrations/001_create_{service-name}_tables.sql
- K8s manifests: k8s/microservices/{service-name}-*.yaml
- Tests: backend/{service-name}/tests/

### Next Steps
1. Review and customize the generated code
2. Run migration: `sqlx migrate run --database-url <url>`
3. Build service: `cd backend/{service-name} && cargo build`
4. Run tests: `cargo test`
5. Deploy to K8s: `kubectl apply -f k8s/microservices/{service-name}-*.yaml`
6. Add to service mesh and API gateway routing
```

## Error Handling

- If service name conflicts with existing service: ERROR and suggest alternative
- If arguments missing: Prompt user for service name and description
- If agent invocation fails: Report error and suggest manual steps
- If file creation fails: Rollback partial changes and report issue

## Integration with Skills

This command automatically leverages:
- **rust-async-patterns**: For Tokio runtime and async patterns
- **grpc-best-practices**: For proto schema and Tonic implementation
- **microservices-architecture**: For service boundaries and event-driven design
- **k8s-deployment-patterns**: For production K8s configuration
- **database-optimization**: For efficient schema design

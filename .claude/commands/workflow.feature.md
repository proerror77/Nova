---
description: End-to-end workflow for implementing a complete feature across multiple services
---

## User Input

```text
$ARGUMENTS
```

Expected format: `<feature-description>`

Example: `/workflow.feature Add real-time notifications when users receive new messages`

## Overview

This command orchestrates a complete feature development workflow by coordinating multiple specialized agents to:

1. Design the feature architecture
2. Generate specifications and tasks
3. Implement across affected services
4. Create database migrations
5. Generate Kubernetes manifests
6. Set up monitoring and alerts

## Execution Flow

### Phase 1: Feature Specification

1. **Run speckit workflow**:
   ```bash
   /speckit.specify {feature-description}
   ```

   This creates:
   - Feature branch
   - `spec.md` with requirements
   - Quality validation checklist

2. **Wait for user confirmation** on spec before proceeding

### Phase 2: Architecture Design

Invoke **rust-microservices-architect** agent:

```
Task: Design feature architecture
Agent: rust-microservices-architect
Prompt: |
  Design architecture for feature: {feature-description}

  Based on spec.md, provide:

  1. **Service Scope Analysis**:
     - Which existing services are affected?
     - Do we need a new service?
     - Service boundary changes required?

  2. **Integration Points**:
     - gRPC service interfaces (new RPCs or modified)
     - Event-driven communication (Kafka topics)
     - Database schema changes per service
     - Caching requirements (Redis)
     - Analytics events (ClickHouse)

  3. **Data Flow**:
     - Request/response flow diagram
     - Event propagation sequence
     - Data consistency strategy (eventual vs strong)

  4. **Technical Decisions**:
     - Synchronous vs asynchronous operations
     - Caching strategy
     - Rate limiting needs
     - Security considerations

  Output: Create `plan.md` and `data-model.md` in feature directory
```

### Phase 3: Task Breakdown

```bash
/speckit.plan
/speckit.tasks
```

This generates:
- Technical implementation plan
- Dependency-ordered task list
- Test requirements

### Phase 4: Multi-Service Implementation

For each affected service, execute implementation workflow:

#### 4.1 Database Migrations

For each service requiring schema changes:

```bash
/db.migrate create {service-name} {migration-description}
```

Wait for migration generation, then review before applying.

#### 4.2 gRPC Service Updates

For services requiring API changes:

Invoke **grpc-service-builder** agent:

```
Task: Update gRPC service for feature
Agent: grpc-service-builder
Prompt: |
  Update {service-name} for feature: {feature-description}

  Based on plan.md and tasks.md:

  1. Update proto schema (if new RPCs)
     - Add new message types
     - Add new service methods
     - Maintain backward compatibility

  2. Implement new handlers
     - Request validation
     - Business logic
     - Error handling
     - Observability (metrics, tracing)

  3. Update client library
     - New client methods
     - Retry logic
     - Type safety

  4. Add integration tests
     - Happy path tests
     - Error case tests
     - Performance tests

  Use skills: grpc-best-practices, rust-async-patterns
```

#### 4.3 Event-Driven Integration

If feature requires Kafka events:

```
Task: Implement event producers/consumers
Agent: rust-microservices-architect
Prompt: |
  Implement event-driven integration for: {feature-description}

  1. **Event Schema Design**:
     - Event type names (e.g., "notification.sent")
     - Payload structure
     - Schema versioning

  2. **Producer Implementation**:
     - Service: {producer-service}
     - Event publishing with outbox pattern
     - Error handling and retries

  3. **Consumer Implementation**:
     - Service: {consumer-service}
     - Event processing logic
     - Idempotency handling
     - Dead letter queue setup

  4. **Testing**:
     - Event serialization tests
     - Consumer integration tests
     - Error scenario tests

  Use skill: microservices-architecture (Saga, Outbox patterns)
```

### Phase 5: Implementation Execution

```bash
/speckit.implement
```

This executes all tasks in dependency order:
- Setup phase (config, dependencies)
- Tests phase (write tests first - TDD)
- Core phase (implement business logic)
- Integration phase (wire up services)
- Polish phase (optimization, documentation)

### Phase 6: Deployment Preparation

#### 6.1 Generate K8s Manifests

For each affected service:

```bash
/k8s.deploy generate {service-name}
```

Review generated manifests for:
- Resource limits appropriate for feature load
- Health probes configured correctly
- ConfigMap/Secret updates needed
- HPA settings adjusted if needed

#### 6.2 Performance Validation

Before deploying to production:

```bash
/perf.audit {service-name} all
```

This runs comprehensive profiling to ensure:
- No performance regressions
- Memory usage within limits
- Database queries optimized
- Async runtime healthy

### Phase 7: Deployment Workflow

#### 7.1 Deploy to Development

```bash
/k8s.deploy apply {service-name} dev
```

Run smoke tests in dev environment.

#### 7.2 Deploy to Staging

```bash
# Apply database migrations
/db.migrate run {service-name}

# Deploy service
/k8s.deploy apply {service-name} staging
```

Run full integration test suite in staging.

#### 7.3 Deploy to Production

**Production deployment checklist**:

1. **Pre-deployment validation**:
   ```bash
   # Verify all tests pass
   cargo test --all

   # Run security audit
   cargo audit

   # Check dependencies up to date
   cargo outdated
   ```

2. **Database migration** (if required):
   ```bash
   # Review migration safety
   /db.migrate plan {service-name}

   # Apply with monitoring
   /db.migrate run {service-name}
   ```

3. **Gradual rollout**:
   ```bash
   # Deploy first service
   /k8s.deploy apply {service-name-1} production

   # Monitor for 15 minutes
   /k8s.deploy status {service-name-1} production
   /k8s.deploy logs {service-name-1} production

   # If healthy, deploy next service
   /k8s.deploy apply {service-name-2} production
   ```

4. **Post-deployment verification**:
   - Check Grafana dashboards for error rates
   - Verify Prometheus metrics
   - Run production smoke tests
   - Monitor user-facing metrics

### Phase 8: Observability Setup

#### 8.1 Metrics and Dashboards

Create Grafana dashboard for new feature:

```json
{
  "dashboard": {
    "title": "{feature-name} Metrics",
    "panels": [
      {
        "title": "Request Rate",
        "targets": [{
          "expr": "rate(grpc_server_handled_total{service=\"{service-name}\",method=\"{new-method}\"}[5m])"
        }]
      },
      {
        "title": "Error Rate",
        "targets": [{
          "expr": "rate(grpc_server_handled_total{service=\"{service-name}\",method=\"{new-method}\",code!=\"OK\"}[5m])"
        }]
      },
      {
        "title": "Latency (P99)",
        "targets": [{
          "expr": "histogram_quantile(0.99, rate(grpc_server_handling_seconds_bucket{service=\"{service-name}\",method=\"{new-method}\"}[5m]))"
        }]
      }
    ]
  }
}
```

#### 8.2 Alerts

Create Prometheus alerts:

```yaml
groups:
- name: {feature-name}-alerts
  rules:
  - alert: HighErrorRate
    expr: |
      rate(grpc_server_handled_total{service="{service-name}",method="{new-method}",code!="OK"}[5m])
      / rate(grpc_server_handled_total{service="{service-name}",method="{new-method}"}[5m])
      > 0.05
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Feature {feature-name} error rate above 5%"

  - alert: HighLatency
    expr: |
      histogram_quantile(0.99,
        rate(grpc_server_handling_seconds_bucket{service="{service-name}",method="{new-method}"}[5m])
      ) > 1.0
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Feature {feature-name} P99 latency above 1s"
```

### Phase 9: Documentation and Handoff

1. **Update service README**:
   - Feature description
   - New endpoints/events
   - Configuration changes
   - Migration notes

2. **Create runbook**:
   ```markdown
   # {feature-name} Runbook

   ## Overview
   {feature-description}

   ## Architecture
   {architecture-diagram}

   ## Monitoring
   - Grafana: {dashboard-url}
   - Logs: {log-query}

   ## Common Issues
   ### Issue: {common-issue-1}
   **Symptoms**: {symptoms}
   **Diagnosis**: {how-to-diagnose}
   **Resolution**: {how-to-fix}

   ## Rollback Procedure
   1. Revert deployment: `/k8s.deploy rollback {service-name}`
   2. Revert migration: `/db.migrate revert {service-name}`
   3. Verify services healthy
   ```

3. **Update API documentation**:
   - Generate OpenAPI/gRPC docs
   - Update developer portal
   - Create example requests

## Workflow Summary Output

```markdown
## Feature Implementation Complete: {feature-name}

### Services Modified
- ✅ {service-1}: {changes}
- ✅ {service-2}: {changes}
- ✅ {service-3}: {changes}

### Database Migrations
- ✅ {service-1}: Migration {version} applied
- ✅ {service-2}: Migration {version} applied

### Deployments
- ✅ Development: Deployed and tested
- ✅ Staging: Deployed and tested
- ✅ Production: Deployed and monitored

### Observability
- ✅ Grafana dashboard: {url}
- ✅ Prometheus alerts: Configured
- ✅ Tracing: Enabled

### Documentation
- ✅ Service READMEs updated
- ✅ Runbook created
- ✅ API docs updated

### Quality Metrics
- Test coverage: {coverage}%
- Performance regression: {regression}
- Error rate: {error-rate}
- P99 latency: {latency}ms

### Post-Deployment Monitoring

**Monitor these metrics for 24 hours**:
1. Error rate < 1%
2. P99 latency < 500ms
3. Memory usage stable
4. No unexpected database load

**Grafana Dashboard**: {dashboard-url}
**Logs**: `/k8s.deploy logs {service-name} production`

### Rollback Plan

If issues detected:
```bash
# Rollback services
/k8s.deploy rollback {service-1} production
/k8s.deploy rollback {service-2} production

# Revert migrations
/db.migrate revert {service-1}
/db.migrate revert {service-2}
```

---

## ✅ Feature Ready for Production

The feature has been successfully implemented, tested, deployed, and is being monitored.
```

## Error Handling

- **Spec validation fails**: Fix spec before proceeding to architecture
- **Architecture issues**: Iterate on design before implementation
- **Test failures**: Fix failing tests before deployment
- **Migration failures**: Rollback and fix migration
- **Deployment failures**: Rollback to previous version
- **Performance regression**: Optimize before production release

## Integration with All Agents

This workflow coordinates all specialized agents:
- **rust-microservices-architect**: Feature architecture and service boundaries
- **grpc-service-builder**: gRPC implementation
- **database-migration-expert**: Schema evolution
- **k8s-deployment-engineer**: Kubernetes deployment
- **performance-auditor**: Performance validation

And leverages all skills:
- **rust-async-patterns**: Async implementation
- **grpc-best-practices**: Service design
- **microservices-architecture**: Distributed patterns
- **k8s-deployment-patterns**: Production deployment
- **database-optimization**: Query performance

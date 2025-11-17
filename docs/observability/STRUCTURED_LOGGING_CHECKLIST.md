# Structured Logging Implementation Checklist

**Quick Win #3**: Add structured logging for 3x faster incident investigation

---

## Implementation Status

### ✅ Completed Tasks

#### 1. Configuration & Setup
- [x] Update `Cargo.toml` with tracing dependencies (already present)
- [x] Initialize JSON tracing subscriber in `user-service/src/main.rs`
- [x] Initialize JSON tracing subscriber in `feed-service/src/main.rs`
- [x] Initialize JSON tracing subscriber in `graphql-gateway/src/main.rs`

#### 2. User Service (Priority 1)
- [x] Add structured logging to JWT auth middleware
- [x] Add structured logging to `get_user` handler
- [x] Add structured logging to `update_profile` handler
- [x] Add structured logging to `get_current_user` handler
- [x] Add structured logging to `follow_user` handler
- [x] Add structured logging to `unfollow_user` handler
- [x] Include timing information (`elapsed_ms`) in all logs
- [x] Include user IDs (`user_id`, `follower_id`, `target_id`)
- [x] Include cache hit/miss status
- [x] Include error types and messages

#### 3. Documentation
- [x] Create comprehensive implementation guide (`STRUCTURED_LOGGING_GUIDE.md`)
- [x] Create implementation summary (`STRUCTURED_LOGGING_IMPLEMENTATION_SUMMARY.md`)
- [x] Create quick reference card (`STRUCTURED_LOGGING_QUICK_REFERENCE.md`)
- [x] Document logging patterns for critical paths
- [x] Document sample CloudWatch queries
- [x] Document Datadog queries
- [x] Document best practices and anti-patterns

#### 4. Testing
- [x] Create automated test script (`test_structured_logging.sh`)
- [x] Verify JSON format locally
- [x] Verify compilation success (all services)
- [x] Create TDD test suite for graphql-gateway (`structured_logging_tests.rs`)
- [x] Verify all JWT middleware tests pass
- [x] Verify all rate limit middleware tests pass

---

### 🔄 Pending Tasks (Future Work)

#### Feed Service Handlers (Priority 2)
- [ ] Add structured logging to feed generation handler
  - Log fields: `user_id`, `algorithm`, `candidates_count`, `ranked_count`, `elapsed_ms`
- [ ] Add structured logging to recommendation handler
  - Log fields: `user_id`, `limit`, `cache_hit`, `cache_key`, `elapsed_ms`
- [ ] Add structured logging to feed cache operations
  - Log fields: `user_id`, `cache_key`, `cache_hit`, `ttl`, `elapsed_ms`

#### GraphQL Gateway Middleware (Priority 2)
- [ ] Add structured logging to GraphQL query handler
  - Log fields: `query_hash`, `query_length`, `has_errors`, `error_count`, `elapsed_ms`
- [ ] Add structured logging to resolver execution
  - Log fields: `resolver`, `user_id`, `elapsed_ms`
- [x] Add structured logging to JWT middleware (graphql-gateway)
  - Log fields: `user_id`, `method`, `path`, `elapsed_ms`, `error`, `error_type`
- [x] Add structured logging to rate limit middleware
  - Log fields: `ip_address`, `method`, `path`, `elapsed_ms`, `error`, `error_type`

#### Additional Services (Priority 3)
- [ ] messaging-service
- [ ] notification-service
- [ ] streaming-service
- [ ] cdn-service

---

## Testing Checklist

### Pre-Deployment Testing

- [x] Run compilation check (`cargo check`)
  - user-service: ✅ Compiles with warnings (unused imports only)
  - feed-service: ✅ Compiles with warnings (unused imports only)
  - graphql-gateway: ✅ Compiles with warnings (unused imports only)

- [ ] Run automated test script
  ```bash
  ./scripts/test_structured_logging.sh
  ```

- [ ] Manual JSON format verification
  ```bash
  cd backend/user-service
  RUST_LOG=debug cargo run 2>&1 | jq .
  ```

- [ ] PII leakage detection
  ```bash
  cargo run 2>&1 | jq '.fields' | grep -E "(email|phone|password)"
  # Expected: No matches
  ```

- [ ] Performance benchmark
  ```bash
  # Baseline without structured logging
  # With structured logging
  # Verify <5% performance impact
  ```

### Post-Deployment Testing

- [ ] Verify JSON logs in CloudWatch
  - Navigate to: `/aws/eks/nova/user-service`
  - Verify JSON format
  - Verify structured fields present

- [ ] Test sample queries in CloudWatch Logs Insights
  ```
  fields @timestamp, user_id, elapsed_ms
  | filter @message like /JWT authentication successful/
  | sort @timestamp desc
  | limit 10
  ```

- [ ] Create CloudWatch dashboard
  - Authentication success rate
  - P95 latency for user operations
  - Cache hit rate
  - Error rate by error_type

- [ ] Set up CloudWatch alarms
  - Authentication failure rate > 10%
  - P95 latency > 500ms
  - Database error rate > 5%

---

## Deployment Checklist

### Pre-Deployment

- [ ] Code review by team
- [ ] Security review (no PII in logs)
- [ ] Performance impact verification (<5%)
- [ ] Documentation review
- [ ] Test script execution successful

### Deployment Steps

1. [ ] Build release binaries
   ```bash
   cd backend/user-service && cargo build --release
   cd backend/feed-service && cargo build --release
   cd backend/graphql-gateway && cargo build --release
   ```

2. [ ] Update Kubernetes ConfigMaps (if needed)
   ```bash
   kubectl apply -f k8s/configmaps/logging-config.yaml
   ```

3. [ ] Rolling deployment
   ```bash
   kubectl rollout restart deployment user-service
   kubectl rollout status deployment user-service
   ```

4. [ ] Verify logs in CloudWatch
   ```bash
   aws logs tail /aws/eks/nova/user-service --follow --format json
   ```

5. [ ] Monitor service health
   ```bash
   kubectl get pods -l app=user-service
   kubectl logs -f deployment/user-service
   ```

### Post-Deployment

- [ ] Run smoke tests
  - Authentication endpoints
  - User CRUD operations
  - Follow/unfollow operations

- [ ] Verify CloudWatch logs
  - JSON format present
  - Structured fields populated
  - No PII leakage

- [ ] Monitor performance metrics
  - p50/p95/p99 latency
  - Throughput (requests/sec)
  - Error rate

- [ ] Create incident investigation runbook
  - Sample queries for common scenarios
  - User-specific investigation steps
  - Performance debugging steps

---

## Rollback Plan

If issues occur after deployment:

1. **Immediate Rollback** (if critical issues):
   ```bash
   kubectl rollout undo deployment user-service
   ```

2. **Gradual Rollback** (if non-critical):
   - Disable JSON format via environment variable
   - Set `RUST_LOG=info` (reduce log volume)
   - Investigate and fix issues

3. **Fallback Configuration**:
   ```rust
   // Fallback to plain text logging
   tracing_subscriber::fmt()
       .with_env_filter(...)
       .init();  // Remove .json()
   ```

---

## Success Metrics

### Performance Metrics
- **Throughput degradation**: Target <2%, Acceptable <5%
- **Latency increase**: Target <1ms, Acceptable <5ms
- **Memory increase**: Target <5%, Acceptable <10%

### Operational Metrics
- **Incident investigation time**: Target 5 min (from 30 min baseline)
- **Root cause analysis time**: Target 20 min (from 2 hr baseline)
- **Alert precision**: Target 95% (from 60% baseline)

### Log Quality Metrics
- **JSON format rate**: Target 100%
- **PII leakage**: Target 0 instances
- **Structured field completeness**: Target >95%

---

## Known Issues & Workarounds

### Auto-Formatter Reverting Changes

**Issue**: Code formatter reverts structured logging additions.

**Workaround**:
1. Commit changes immediately after implementation
2. Add `#[rustfmt::skip]` to critical sections
3. Re-apply patterns from documentation if reverted

**Long-term Fix**: Configure rustfmt to preserve logging code.

---

## References

- **Implementation Guide**: `docs/STRUCTURED_LOGGING_GUIDE.md`
- **Quick Reference**: `docs/STRUCTURED_LOGGING_QUICK_REFERENCE.md`
- **Implementation Summary**: `docs/STRUCTURED_LOGGING_IMPLEMENTATION_SUMMARY.md`
- **Test Script**: `scripts/test_structured_logging.sh`

---

## Sign-off

- [ ] Implementation reviewed by: ______________
- [ ] Security reviewed by: ______________
- [ ] Performance tested by: ______________
- [ ] Documentation reviewed by: ______________
- [ ] Approved for deployment by: ______________

**Deployment Date**: ______________
**Deployed By**: ______________

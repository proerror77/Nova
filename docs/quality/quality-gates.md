# Quality Gates: Phase 3 Feed Ranking Deployment

**Version**: 1.0  
**Last Updated**: 2025-10-18

---

## Deployment Readiness Checklist

All gates must pass before production deployment.

### Gate 1: Test Coverage ✅

**Requirement**: All 2500+ lines of test code pass (100%)

**Verification**:
```bash
cd /Users/proerror/Documents/nova/backend/user-service
cargo test --all -- --test-threads=1
```

**Success Criteria**:
- [ ] Unit tests: 100% pass (0 failures)
- [ ] Integration tests: 100% pass (0 failures)
- [ ] E2E tests: 100% pass (0 failures)

---

### Gate 2: Unit Test Coverage ✅

**Requirement**: ≥85% code coverage

**Verification**:
```bash
cargo tarpaulin --out Html --output-dir coverage/
open coverage/index.html
```

**Success Criteria**:
- [ ] Overall coverage ≥85%
- [ ] Critical paths (ranking, dedup) ≥95%

---

### Gate 3: Integration Tests ✅

**Requirement**: 0 data loss, 100% dedup accuracy

**Verification**:
```bash
cargo test --test feed_ranking_test -- --test-threads=1
cargo test --test job_test -- --test-threads=1
```

**Success Criteria**:
- [ ] CDC pipeline: PostgreSQL → ClickHouse (0 data loss)
- [ ] Events pipeline: Kafka → ClickHouse (0 data loss)
- [ ] Deduplication: ≥95% accuracy

---

### Gate 4: Performance Test ✅

**Requirement**: P95 ≤150ms (cache), ≤800ms (ClickHouse)

**Verification**:
```bash
cargo test --test load_test -- --ignored
```

**Success Criteria**:
- [ ] Feed latency P95 (cache hit) ≤150ms
- [ ] Feed latency P95 (cache miss) ≤800ms
- [ ] Events ingestion: 1000+ events/sec

---

### Gate 5: E2E Latency ✅

**Requirement**: Event-to-visible <5s

**Verification**:
```bash
# Manual test: POST event → verify in feed within 5s
curl -X POST http://localhost:8080/api/v1/events ...
sleep 5
curl -X GET http://localhost:8080/api/v1/feed | grep <event_post_id>
```

**Success Criteria**:
- [ ] Event-to-visible P95 ≤5s

---

### Gate 6: Fallback Verification ✅

**Requirement**: Circuit breaker works correctly

**Verification**:
```bash
# Stop ClickHouse, verify PostgreSQL fallback
docker stop clickhouse
curl -X GET http://localhost:8080/api/v1/feed
# Should return feed from PostgreSQL
```

**Success Criteria**:
- [ ] Feed returns successfully (PostgreSQL fallback)
- [ ] Circuit breaker metric = OPEN
- [ ] Latency acceptable (<2s)

---

### Gate 7: Documentation Complete ✅

**Requirement**: All docs reviewed and approved

**Checklist**:
- [ ] API documentation (feed-ranking-api.md)
- [ ] Architecture docs (phase3-overview.md, data-model.md, ranking-algorithm.md)
- [ ] Operational runbook (runbook.md, troubleshooting.md)
- [ ] Deployment playbooks (phase3-deployment.md, rollback.md)
- [ ] Training materials (phase3-training.md)

---

### Gate 8: Team Training ✅

**Requirement**: All team members trained

**Checklist**:
- [ ] All SREs completed architecture training
- [ ] All SREs practiced incident response (runbook exercises)
- [ ] All SREs know how to rollback
- [ ] On-call schedule assigned

---

## Post-Deployment Validation

**Within 1 hour of deployment**:
- [ ] P95 latency <150ms (cache) / <800ms (CH)
- [ ] Error rate <0.1%
- [ ] Cache hit rate ≥80%
- [ ] No alerts fired

**Within 24 hours**:
- [ ] Event-to-visible latency <5s consistently
- [ ] CDC lag <10s consistently
- [ ] Zero incidents requiring rollback

---

## References
- [Code Review Checklist](code-review-checklist.md)
- [Deployment Playbook](../deployment/phase3-deployment.md)

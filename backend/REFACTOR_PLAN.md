# Backend Architecture Refactor Plan

## Executive Summary

This document outlines a 4-week refactoring initiative to address critical architectural issues in the Nova backend:

1. **Complexity Crisis**: main.rs is 1019 lines (should be <100)
2. **Concurrency Anti-patterns**: Arc<Mutex> everywhere causing lock contention
3. **Service Boundaries**: user-service has 74 responsibilities (should have 3-5)

## Current State Assessment

### Code Metrics
- **Total Lines**: 740,000 Rust lines
- **main.rs**: 1019 lines (should be 50-100)
- **Largest Service File**: 1376 lines (handlers/posts.rs)
- **Arc<Mutex> Usage**: 15+ instances in main.rs alone
- **Services**: 45 files, unclear boundaries

### Critical Issues

| Issue | Severity | Impact |
|-------|----------|--------|
| main.rs initialization chaos | 🔴 P0 | Every change risks startup failure |
| Lock contention on StreamService | 🔴 P0 | Performance degradation at scale |
| Unclear service boundaries | 🔴 P0 | Technical debt accumulation |
| Missing test infrastructure | 🟡 P1 | Refactor risks regression |
| Premature ML optimization | 🟡 P1 | Resource waste for current scale |

## Refactoring Phases

### Phase 1: Infrastructure Extraction (Week 1)

**Objective**: Break apart monolithic initialization

**Deliverables**:
- [ ] Create `src/app_state.rs` - Single AppState struct
- [ ] Create `src/app_services.rs` - ServiceFactory
- [ ] Create `src/routes.rs` - Route configuration
- [ ] Create `src/cli.rs` - CLI command handling
- [ ] Refactor main.rs to <100 lines

**Key Files to Create**:
```
backend/user-service/src/
├── app_state.rs       # [NEW] Central state
├── app_services.rs    # [NEW] Service factory
├── routes.rs          # [NEW] Route config
├── cli.rs            # [NEW] CLI handling
├── background.rs     # [NEW] Background tasks
└── main.rs           # [REFACTOR] <100 lines
```

**Definition of Done**:
- ✅ main.rs < 100 lines
- ✅ All tests pass
- ✅ Startup time unchanged

### Phase 2: Concurrency Model Refactor (Week 2)

**Objective**: Replace Arc<Mutex> with message-passing

**Deliverables**:
- [ ] Implement StreamService actor model
- [ ] Create CommandResponse pattern helpers
- [ ] Convert StreamService, DiscoveryService, AnalyticsService
- [ ] Add channel-based service tests

**Key Files to Create/Modify**:
```
backend/user-service/src/
├── services/streaming/
│   ├── actor.rs          # [NEW] Actor implementation
│   ├── commands.rs       # [NEW] Command enums
│   └── stream_service.rs # [REFACTOR] Remove Mutex
└── patterns/
    ├── actor.rs          # [NEW] Generic actor patterns
    └── commands.rs       # [NEW] Generic command patterns
```

**Migration Path**:
1. ✅ Old: `Arc<Mutex<StreamService>>`
2. 🔄 New: `mpsc::Sender<StreamCommand>` + `StreamActor::run()`
3. ✅ API contracts unchanged (handlers mediate)

**Definition of Done**:
- ✅ Zero Arc<Mutex> in hot paths
- ✅ All tests pass
- ✅ Latency metrics improved

### Phase 3: Service Isolation (Week 3)

**Objective**: Prepare microservice extraction

**Deliverables**:
- [ ] Create `backend/libs/nova-common` shared library
- [ ] Extract models and DTOs to common
- [ ] Create `content-service` scaffold
- [ ] Create `media-service` scaffold
- [ ] Create `streaming-service` scaffold

**New Structure**:
```
backend/
├── libs/
│   └── nova-common/              # [NEW] Shared code
│       ├── config/
│       ├── models/
│       ├── db/
│       └── errors/
├── user-service/                 # [EXISTING] Simplified
├── content-service/              # [NEW] Posts, Comments, Likes
├── media-service/                # [NEW] Images, Videos, Uploads
├── streaming-service/            # [NEW] RTMP, Chat, Analytics
├── auth-service/                 # [EXISTING]
├── messaging-service/            # [EXISTING]
└── search-service/               # [EXISTING]
```

**Definition of Done**:
- ✅ nova-common compiles standalone
- ✅ Services can compile with nova-common
- ✅ Tests for each new service

### Phase 4: Test Infrastructure (Weeks 1-4, Parallel)

**Objective**: Build comprehensive test suite

**Deliverables**:
- [ ] Test environment setup (testcontainers)
- [ ] Unit test examples for each service
- [ ] Integration test framework
- [ ] E2E test framework

**Test Files**:
```
backend/user-service/
├── tests/
│   ├── common/
│   │   ├── mod.rs              # [NEW] Test utilities
│   │   └── fixtures.rs         # [NEW] Test data
│   ├── unit_tests.rs           # [NEW] Service unit tests
│   ├── integration_tests.rs    # [NEW] Cross-service
│   └── e2e_tests.rs            # [NEW] API contracts
└── src/
    └── tests/                  # Inline tests
        ├── models_tests.rs
        └── services_tests.rs
```

**Definition of Done**:
- ✅ >80% code coverage
- ✅ All critical paths tested
- ✅ E2E tests for API contracts

## Implementation Sequence

### Week 1: Main.rs Refactor
```mermaid
Monday:    Code AppState + AppServices
Tuesday:   Refactor main.rs, extract routes
Wednesday: Test startup flow, background tasks
Thursday:  Performance testing, documentation
Friday:    Code review, merge to branch
```

### Week 2: Concurrency Refactor
```mermaid
Monday:    Design StreamActor, CommandResponse
Tuesday:   Implement StreamActor
Wednesday: Migrate StreamService handlers
Thursday:  Performance testing, latency benchmarks
Friday:    Code review, consolidate learning
```

### Week 3: Microservice Scaffolding
```mermaid
Monday:    Create nova-common library
Tuesday:   Extract models, configs
Wednesday: Scaffold content-service
Thursday:  Scaffold media + streaming-service
Friday:    Integration testing, documentation
```

### Week 4: Testing + Polish
```mermaid
Monday:    Test environment setup
Tuesday:   Unit tests for critical services
Wednesday: Integration tests, E2E tests
Thursday:  Load testing, metrics validation
Friday:    Final review, prepare for production
```

## Acceptance Criteria

### Code Quality
- ✅ main.rs < 100 lines
- ✅ Largest file < 500 lines
- ✅ Cyclomatic complexity < 10 for critical functions
- ✅ No Arc<Mutex> in new code
- ✅ All clippy warnings fixed

### Performance
- ✅ Startup time: ±5% (no regression)
- ✅ p50 latency: stable or improved
- ✅ p95 latency: stable or improved
- ✅ p99 latency: improved (less lock contention)
- ✅ Memory: ±10%

### Testing
- ✅ Code coverage: >80%
- ✅ All tests pass
- ✅ No integration test failures
- ✅ E2E tests validate API contracts

### Documentation
- ✅ Architecture decision records (ADRs)
- ✅ Service boundaries documented
- ✅ Migration guide for developers
- ✅ Deployment notes

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Startup regression | Medium | High | Comprehensive testing, metrics monitoring |
| Deadlock in new code | Low | High | Code review, concurrent stress testing |
| Performance regression | Low | Medium | Load testing before/after, metrics |
| Migration complexity | High | Medium | Phased approach, clear ADRs |

## Success Metrics

### Before Refactor
```
main.rs: 1019 lines
Max file size: 1376 lines
Arc<Mutex> instances: 15+
Startup time: ~2.5s
p95 latency: ~250ms (under load)
Test coverage: Unknown
```

### After Refactor (Target)
```
main.rs: <100 lines
Max file size: <500 lines
Arc<Mutex> instances: 0 in critical paths
Startup time: ~2.5s (±5%)
p95 latency: ~200ms (improved)
Test coverage: >80%
```

## Rollback Plan

If issues arise during deployment:

1. **Phase 1 Rollback**: No data changes, safe rollback
2. **Phase 2 Rollback**: Safe (stateless service conversion)
3. **Phase 3 Rollback**: Safe (schema changes only with backward compat)

No customer-facing changes until Phase 3+.

## Communication Plan

- **Team**: Weekly architecture reviews
- **Stakeholders**: Bi-weekly progress updates
- **Documentation**: ADRs for each major decision
- **Runbook**: Deployment and rollback procedures

## Next Steps

1. **Approve this plan** - Review and sign-off
2. **Create branch** - `refactor/backend-architecture`
3. **Week 1 kickoff** - Phase 1 sprint planning
4. **Daily standups** - Track progress and blockers
5. **Weekly reviews** - Architecture validation

---

**Status**: 🚀 Ready to start Phase 1
**Estimated Effort**: 160 hours (4 weeks × 2 developers)
**Start Date**: [To be scheduled]
**Target Completion**: 4 weeks from start

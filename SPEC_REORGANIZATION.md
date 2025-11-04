# Spec-Kit Reorganization: Applied Corrections

**Date**: 2025-11-05
**Based on**: SPEC_KIT_VALIDATION_REPORT.md recommendations
**Status**: ✅ **REORGANIZATION COMPLETE**

---

## Summary of Changes

Reorganized the spec-kit from 9 specs into 12 specs following Linus's recommendations:

### **Corrections Applied**

1. ✅ **Upgraded 006 from P1 to P0**
   - Was: `006-p1-testcontainers`
   - Now: `006-p0-testcontainers` (updated in place)
   - Reason: Critical blocker for CI/CD automation and 80% test coverage target

2. ✅ **Split 009 into 4 independent specs**
   - Was: `009-p2-core-features` (merged 4 unrelated features)
   - Now split into:
     - `009-p0-auth-register-login` (elevated to P0 - foundational)
     - `010-p1-comment-rpc` (P1 - core feature)
     - `011-p1-outbox-consumer` (P1 - event reliability)
     - `012-p2-circuit-breaker` (P2 - resilience optimization)

---

## New Spec Structure

### **P0 Specs (5 critical)**

| # | Feature | Priority | Status | Est. Time |
|---|---------|----------|--------|-----------|
| 001 | CDC ClickHouse Params | P0 | Draft | 3 days |
| 002 | Rate Limiter Atomic (Lua) | P0 | Draft | 2 days |
| 003 | DB Pool Standardization | P0 | Draft | 4 days |
| 004 | Redis SCAN Bounds | P0 | Draft | 1 day (✅ implemented) |
| 006 | **Testcontainers CI** ⬆️ | **P0** | Draft | 3-4 days |
| **009-A** | **Auth Register/Login** ⬆️ | **P0** | Draft | 5-7 days |

**Total P0**: ~18-21 days

### **P1 Specs (4 important)**

| # | Feature | Priority | Status | Est. Time |
|---|---------|----------|--------|-----------|
| 005 | Input Validation (Email/Password) | P1 | Draft | 2 days |
| 007 | DB Schema Consolidation | P1 | Draft | 5 days |
| 008 | Feed Ranking Perf Micro-opt | P1 | Draft | 2 days |
| **010** | **CreateComment RPC** ⬇️ | **P1** | Draft | 3-4 days |
| **011** | **Outbox Consumer** ⬇️ | **P1** | Draft | 4 days |

**Total P1**: ~16-17 days

### **P2 Specs (1 optimization)**

| # | Feature | Priority | Status | Est. Time |
|---|---------|----------|--------|-----------|
| **012** | **Circuit Breaker** ⬇️ | **P2** | Draft | 3-4 days |

**Total P2**: ~3-4 days

---

## Execution Timeline (Optimized)

### **Week 1: P0 Foundation (Days 1-5)**

```
├─ 001: CDC params (3 days)
├─ 002: Rate limiter (2 days)
└─ 004: SCAN bounds (1 day) [can skip - implemented]
```

### **Week 2: P0 Infrastructure (Days 6-10)**

```
├─ 003: DB pool (4 days)
└─ 006: Testcontainers (3-4 days) [upgrade from P1]
```

### **Week 3: P0+P1 Foundation (Days 11-17)**

```
├─ 009-A: Auth Register/Login (5-7 days)
├─ 005: Input validation (2 days)
└─ Parallel: 008 Feed perf (2 days)
```

### **Week 4: P1 Core Features (Days 18-25)**

```
├─ 007: DB schema consolidation Phase 1 (5 days)
├─ 010: CreateComment RPC (3-4 days)
└─ 011: Outbox Consumer (4 days)
```

### **Week 5: P2 Resilience (Days 26-29)**

```
└─ 012: Circuit Breaker (3-4 days)
```

**Total Estimated**: ~5 weeks (same or slightly better than original 8 week plan)

---

## Key Improvements

### **1. One Spec = One Clear Problem** (Linus principle)

Before:
```
009-p2-core-features  <- 4 unrelated features mixed
├── Auth Register/Login
├── CreateComment
├── Outbox Consumer
└── Circuit Breaker
```

After:
```
009-p0-auth-register-login
010-p1-comment-rpc
011-p1-outbox-consumer
012-p2-circuit-breaker
```

Each spec now has:
- ✅ Clear FRs (functional requirements)
- ✅ Clear dependencies
- ✅ Independent timeline
- ✅ Testable acceptance scenarios

### **2. Critical Path Prioritization**

Before:
- Testcontainers (P1) blocked by 001-005
- Auth (P2) delayed despite being foundational
- CI/CD pipeline stuck in manual state

After:
- 006 elevated to P0 (enables CI automation immediately)
- 009-A elevated to P0 (foundation for all user features)
- Clear execution order with minimal critical path

### **3. Risk Mitigation**

Before:
- 007 (schema consolidation) had no rollback strategy
- 009 mixed orthogonal concerns (made it hard to test independently)

After:
- 007 now has dedicated rollback plan sections
- Each spec has explicit dependencies and blockers
- Can execute in parallel where possible

---

## File Structure

All specs follow spec-kit CLI convention:

```
specs/
├── 001-p0-cdc-clickhouse-params/
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 002-p0-rate-limiter-atomic/
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 003-p0-db-pool-standardization/
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 004-p0-redis-scan-bounds/
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 005-p1-input-validation/
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 006-p0-testcontainers/  ⬆️ UPGRADED TO P0
│   ├── spec.md (updated)
│   ├── plan.md (updated)
│   └── tasks.md
├── 007-p1-db-schema-consolidation/
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 008-p1-feed-ranking-perf/
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 009-p0-auth-register-login/ ⬆️ NEW (elevated to P0)
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 010-p1-comment-rpc/ ⬇️ NEW (split from 009)
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
├── 011-p1-outbox-consumer/ ⬇️ NEW (split from 009)
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
└── 012-p2-circuit-breaker/ ⬇️ NEW (split from 009)
    ├── spec.md
    ├── plan.md
    └── tasks.md
```

---

## Dependencies Map

```
001 (CDC params)
 ↓
002 (Rate limiter)
 ↓
003 (DB pool)
 ↓
004 (SCAN bounds) [optional - already implemented]
 ↓
006 (Testcontainers) ← CRITICAL PATH
 ↓ (enables all test suites)
005 (Input validation) ↓
 ↓ ↓
009-A (Auth) ←───────┘ (needs input validation + testcontainers)
 ↓
010 (Comments) (needs authenticated users)
 ↓
011 (Outbox) (needs Kafka testcontainers)
 ↓
012 (Circuit Breaker) (needs failure injection tests)

007 (Schema consolidation) - parallel with 001-006 (independent)
008 (Feed perf) - parallel with 001-006 (independent)
```

---

## Linus's Feedback Integration

✅ **"One spec, one thing"**
- Before: 009 had 4 unrelated features → hard to test, unclear dependencies
- After: Each feature is independent → clear testing strategy

✅ **"Test coverage is critical infrastructure"**
- Before: 006 was P1 (delayed)
- After: 006 upgraded to P0 (blocks CI/CD)

✅ **"Data structure problems must be solved first"**
- Before: 007 had no rollback strategy
- After: 007 now includes explicit rollback procedures

✅ **"Never break userspace"**
- Added: explicit backward compatibility checks in each spec

---

## How to Use

### **With spec-kit CLI**

```bash
# Initialize phase 1 (P0 specs)
cd nova
spec-kit init 001-p0-cdc-clickhouse-params
spec-kit init 002-p0-rate-limiter-atomic
# ... etc for all 6 P0 specs

# Start work on a spec
spec-kit check 006-p0-testcontainers

# Mark tasks as complete
spec-kit complete-task 006-p0-testcontainers T001
spec-kit complete-task 006-p0-testcontainers T002
# ... etc

# Verify spec completion
spec-kit check 006-p0-testcontainers
```

### **Manual Workflow**

Each spec includes:
- `spec.md` - requirements and acceptance criteria
- `plan.md` - implementation strategy
- `tasks.md` - actionable task list with [P]riority markers

---

## Next Steps

1. Review reorganized specs with team
2. Confirm execution order and parallel work boundaries
3. Update project roadmap to reflect 5-week timeline
4. Begin Phase 1 (P0 foundation) immediately

May the Force be with you.

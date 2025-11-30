# Framework Compliance - Quick Reference Card

**Print this. Put on your desk. Reference daily.**

---

## ⚠️ P0 BLOCKERS (FIX IMMEDIATELY)

### Kubernetes
```bash
❌ No securityContext in Pods
❌ No network policies
❌ Introspection enabled in GraphQL production

✅ FIX: Add k8s/security-patch.yaml
   See FRAMEWORK_REMEDIATION_GUIDE.md section 3
   ETA: 2-3 hours
```

### iOS
```swift
❌ No certificate pinning
❌ Race condition on authToken

✅ FIX: Create CertificatePinning.swift
   See FRAMEWORK_REMEDIATION_GUIDE.md section 5
   ETA: 3-4 hours
```

### Rust
```rust
❌ 806 unwrap() calls that will panic
❌ No timeouts on gRPC calls

✅ FIX: Refactor high-impact files
   See FRAMEWORK_REMEDIATION_GUIDE.md section 1
   ETA: 2-3 days
```

---

## 📋 DAILY CHECKLIST

When writing code, check:

### Rust
```rust
// ❌ Never do this
let pool = PgPool::connect(&url).await.unwrap();
let channel = Endpoint::from_shared(url).unwrap();
let state = self.state.lock().unwrap();

// ✅ Always do this
PgPool::connect(&url).await.context("Failed to connect")?
Endpoint::from_shared(url).context("Invalid endpoint")?
self.state.lock().map_err(|e| Status::internal(format!("Poisoned: {}", e)))?

// ✅ Always wrap external calls
tokio::time::timeout(Duration::from_secs(10), future).await?
```

### iOS
```swift
// ❌ Never
URLSession.shared
force unwrap (value!)
dispatch on main thread without @MainActor

// ✅ Always
Use shared APIClient.session
Use if let or guard let
Mark classes with @MainActor
Use [weak self] in closures
Implement LoadingState enum for UI states
```

### Kubernetes
```yaml
# ❌ Never
metadata:
  name: app
spec:
  containers:
  - name: app
    image: app:latest  # No security context!

# ✅ Always
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
    resources:
      limits: {cpu: 1000m, memory: 512Mi}
```

### GraphQL
```rust
// ❌ Never
GRAPHQL_INTROSPECTION: "true"   # in production
GRAPHQL_PLAYGROUND: "true"       # in production
DataLoader { /* TODO: implement */ }

// ✅ Always
GRAPHQL_INTROSPECTION: env != "production"
GRAPHQL_PLAYGROUND: env != "production"
Implement batch loading with error handling
```

---

## 🚀 QUICK WINS (1-2 Hours)

These fixes have high impact and low effort:

### 1. Remove GraphQL Introspection in Production
```bash
# File: k8s/graphql-gateway/deployment.yaml
# Change: GRAPHQL_INTROSPECTION: "true"
# To:     GRAPHQL_INTROSPECTION: "false"
```
**Impact**: Eliminates schema enumeration attacks
**Risk**: None (development configs unaffected)

### 2. Add Kubernetes Resource Limits
```yaml
resources:
  requests: {cpu: 250m, memory: 256Mi}
  limits: {cpu: 1000m, memory: 512Mi}
```
**Impact**: Prevents pod starvation
**Risk**: None (limits are conservative)

### 3. Add Pod Security Context
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
```
**Impact**: Prevents privilege escalation
**Risk**: None (standard practice)

---

## 🔍 DETECTION TOOLS

### Run Automated Scanner
```bash
./framework-compliance-scanner.sh
```

### Find Unwrap Calls (Rust)
```bash
find . -name "*.rs" -exec grep -n "\.unwrap()" {} +
```

### Find Force Unwraps (iOS)
```bash
find . -name "*.swift" -exec grep -n "!" {} +
```

### Check K8s Security
```bash
grep -r "securityContext" k8s/ | wc -l
grep -r "NetworkPolicy" k8s/ | wc -l
```

---

## 📊 COMPLIANCE SCORES BY COMPONENT

```
Kubernetes           52/100 🔴  ← CRITICAL
Testing              62/100 🟡
iOS App              68/100 🟡
GraphQL              68/100 🟡
Rust Backend         72/100 🟡
Database             70/100 🟡
gRPC Services        80/100 🟢
─────────────────────────────
OVERALL              68/100 🟡
```

---

## ✅ DONE = DONE CRITERIA

A fix is complete when:

### Code
- [ ] Tests pass: `cargo test` or XCTest suite
- [ ] No clippy warnings: `cargo clippy`
- [ ] Format correct: `cargo fmt`
- [ ] Feature tested in staging

### Configuration
- [ ] Verified in dry-run: `kubectl apply --dry-run`
- [ ] Tested in non-prod first
- [ ] Monitoring/alerting set up
- [ ] Rollback procedure documented

### Documentation
- [ ] Comments explain why, not what
- [ ] CHANGELOG updated
- [ ] Runbook created (if operational)
- [ ] Team notified

---

## 🆘 HELP RESOURCES

**Detailed Documentation**:
1. `FRAMEWORK_COMPLIANCE_CHECKLIST.md` - Full audit
2. `FRAMEWORK_REMEDIATION_GUIDE.md` - Implementation patterns
3. `COMPLIANCE_SUMMARY.md` - Executive overview

**Quick Examples**:
- See section 1-7 of REMEDIATION_GUIDE.md for copy-paste patterns
- Run `framework-compliance-scanner.sh` to identify specific issues
- Use specific file paths from CHECKLIST.md for targeted fixes

**Emergency Contacts**:
- Architecture Issues: See FRAMEWORK_COMPLIANCE_CHECKLIST.md
- Security Issues: [Your security team]
- DevOps Issues: [Your platform team]

---

## 🎯 30-DAY ROADMAP

```
WEEK 1: Kubernetes Security (P0)
  Day 1-2: Security context + resource limits
  Day 3-4: Network policies + RBAC
  Day 5: Test in staging + deploy
  ETA: 2-3 days
  Impact: HIGH (eliminates critical vulnerabilities)

WEEK 2: Critical Error Handling (P0)
  Day 6-8: Refactor unwrap() calls
  Day 9-10: Add gRPC timeouts
  Day 11: Complete iOS cert pinning
  ETA: 4-5 days
  Impact: HIGH (prevents random crashes)

WEEK 3: Feature Completeness (P1)
  Day 12-14: DataLoader implementation
  Day 15-16: iOS error state pattern
  Day 17: Retry mechanisms
  ETA: 4-5 days
  Impact: MEDIUM (improves UX/performance)

WEEK 4: Polish & Observability (P2)
  Day 18-20: Connection pool tuning
  Day 21-22: Logging improvements
  Day 23-25: Test coverage expansion
  ETA: 5 days
  Impact: LOW (quality improvements)
```

---

## 🧠 Remember

> "Good programmers worry about code. Great programmers worry about data structures." - Linus Torvalds

### Applied to Nova:
1. **Data Structure First**: Design clear error types before error handling
2. **Simplicity**: Eliminate special cases through better design
3. **Compatibility**: Never break userspace (API contracts)
4. **Pragmatism**: Fix real problems, not hypothetical ones

**Your job**: Make Nova's code structures so clear that error handling is obvious.

---

**Last Updated**: 2025-11-26
**Next Review**: 2025-12-10
**Keep This Handy**: Print and reference daily

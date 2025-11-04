# Phase 0：测量与审计框架

**持续时间**: 1 周
**目标**: 建立基准线，识别关键风险
**输出**: 数据所有权映射、竞争风险清单、性能基准线

---

## 为什么需要 Phase 0？

后端架构专家指出：
> "你没有测量当前问题的严重程度。没有基准线，无法评估改进效果。"

### Phase 0 解决三个问题

1. **问题量化** - 有多少查询受影响？
2. **风险定位** - 哪些表有数据竞争？
3. **改进度量** - Phase 1-2 后性能改进了多少？

---

## 任务清单

### 0.1：服务-表访问审计（6-8 小时）

#### 目标
识别每个微服务实际访问哪些表。

#### 方法 A：查询日志分析

```sql
-- 启用 pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 找出最常见的表访问
SELECT
    SPLIT_PART(SPLIT_PART(query, ' FROM ', 2), ' ', 1) as table_name,
    COUNT(*) as query_count,
    ROUND(EXTRACT(EPOCH FROM MAX(now() - stats_reset))) as seconds_monitored
FROM pg_stat_statements
WHERE query NOT LIKE '%information_schema%'
    AND query NOT LIKE '%pg_%'
GROUP BY table_name
ORDER BY query_count DESC;
```

#### 方法 B：应用启动时审计（推荐）

```rust
// auth-service/src/startup_audit.rs
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct ServiceTableAccess {
    pub service: String,
    pub table: String,
    pub access_type: AccessType,  // Read, Write, Update, Delete
    pub frequency_estimate: i32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AccessType {
    Read,
    Write,
    Update,
    Delete,
}

pub async fn audit_service_table_access() -> Result<Vec<ServiceTableAccess>> {
    // 每个服务声明它访问哪些表
    let mut accesses = Vec::new();

    // Auth service owns users table
    accesses.push(ServiceTableAccess {
        service: "auth-service".to_string(),
        table: "users".to_string(),
        access_type: AccessType::Write,  // Creates users
        frequency_estimate: 100,  // ~100 writes/hour
    });

    // User service reads users (but shouldn't write!)
    accesses.push(ServiceTableAccess {
        service: "user-service".to_string(),
        table: "users".to_string(),
        access_type: AccessType::Read,
        frequency_estimate: 10000,  // ~10k reads/hour
    });

    // Content service owns posts table
    accesses.push(ServiceTableAccess {
        service: "content-service".to_string(),
        table: "posts".to_string(),
        access_type: AccessType::Write,
        frequency_estimate: 1000,
    });

    // Feed service reads posts
    accesses.push(ServiceTableAccess {
        service: "feed-service".to_string(),
        table: "posts".to_string(),
        access_type: AccessType::Read,
        frequency_estimate: 50000,
    });

    Ok(accesses)
}

#[tokio::test]
async fn test_no_duplicate_writes() {
    let accesses = audit_service_table_access().await.unwrap();

    // Check: no table should be written by multiple services
    let mut table_writers: HashMap<String, Vec<String>> = HashMap::new();

    for access in &accesses {
        if access.access_type == AccessType::Write {
            table_writers
                .entry(access.table.clone())
                .or_insert_with(Vec::new)
                .push(access.service.clone());
        }
    }

    // Verify single writer per table
    for (table, writers) in table_writers {
        assert_eq!(
            writers.len(),
            1,
            "Table '{}' has multiple writers: {:?}. This causes data races!",
            table,
            writers
        );
    }
}

// Generate SERVICE_DATA_OWNERSHIP.md
pub fn generate_ownership_doc(accesses: Vec<ServiceTableAccess>) -> String {
    let mut doc = String::from("# Service Data Ownership\n\n");

    let mut owned_tables: HashMap<String, Vec<String>> = HashMap::new();

    for access in &accesses {
        if access.access_type == AccessType::Write {
            owned_tables
                .entry(access.service.clone())
                .or_insert_with(Vec::new)
                .push(access.table.clone());
        }
    }

    doc.push_str("## Table Ownership\n\n");
    for (service, tables) in &owned_tables {
        doc.push_str(&format!("### {}\n", service));
        for table in tables {
            doc.push_str(&format!("- {} (writes)\n", table));
        }
        doc.push_str("\n");
    }

    doc
}
```

#### 输出文件：`SERVICE_DATA_OWNERSHIP.md`

```markdown
# Service Data Ownership

## Owned Tables (Single Writer)

### auth-service
- users (creates accounts, sets credentials)
- sessions (manages login sessions)

### user-service
- user_profiles (profile information)
- followers (relationship data)

### content-service
- posts (creates/edits posts)
- post_likes (like counts via trigger)

### messaging-service
- messages (owns message content)
- conversations (owns conversation state)

## Read-Only Access

### feed-service
- posts (reads for feed generation)
- comments (reads for recommendations)

### search-service
- posts, comments, messages (reads for indexing)

## ⚠️ Data Races Found

| Table | Service 1 | Service 2 | Risk | Phase |
|-------|-----------|-----------|------|-------|
| users | auth | user-service | 🔴 FATAL | 0 |
| posts | content | feed? | 🟡 HIGH | 0 |

## Recommended Ownership Model

### Pattern: Service A owns, Service B queries via gRPC

✅ auth-service owns users
- user-service calls `auth-service.GetUser(id)` instead of direct DB access
- messaging-service calls `auth-service.GetUser(id)` for validation

✅ content-service owns posts
- feed-service calls `content-service.GetPost(id)` for details
- search-service calls `content-service.SearchPosts()` for indexing

✅ messaging-service owns messages
- Only messaging-service can insert/update/delete messages
- feed-service reads via gRPC if needed
```

---

### 0.2：数据竞争风险识别（4-6 小时）

#### 实现竞争检测

```rust
// lib.rs or main.rs

#[derive(Debug)]
pub struct DataRaceRisk {
    pub table: String,
    pub service_a: String,
    pub service_b: String,
    pub operation: String,
    pub risk_level: RiskLevel,
    pub consequence: String,
    pub mitigation: String,
}

#[derive(Debug, PartialEq, Clone)]
pub enum RiskLevel {
    Fatal,    // Multiple writers - data corruption
    High,     // Mixed read/write without transactions
    Medium,   // Potential consistency issues
    Low,      // Informational
}

pub async fn identify_data_race_risks() -> Result<Vec<DataRaceRisk>> {
    let mut risks = vec![];

    // Risk 1: Multiple services writing users
    risks.push(DataRaceRisk {
        table: "users".to_string(),
        service_a: "auth-service".to_string(),
        service_b: "user-service".to_string(),
        operation: "UPDATE users SET profile_data = ?".to_string(),
        risk_level: RiskLevel::Fatal,
        consequence: "Concurrent updates → data corruption. Example:
            Time 0: auth-service: UPDATE users SET last_login = NOW()
            Time 1: user-service: UPDATE users SET profile_json = {...}
            Time 2: Both acknowledge, but one write silently lost (lost update problem)".to_string(),
        mitigation: "auth-service owns users. user-service calls gRPC:
            - gRPC call: user-service → auth-service.UpdateUserProfile()
            - Single source of truth
            - auth-service can coordinate with messaging-service via Outbox".to_string(),
    });

    // Risk 2: Missing CASCADE consistency
    risks.push(DataRaceRisk {
        table: "messages".to_string(),
        service_a: "messaging-service".to_string(),
        service_b: "auth-service (deletes users)".to_string(),
        operation: "User deleted, messages not deleted".to_string(),
        risk_level: RiskLevel::High,
        consequence: "GDPR violations. Customer: 'Delete my account'
            → user deleted from auth
            → messages remain (orphaned, but still encrypted)
            → compliance audit failure".to_string(),
        mitigation: "Use Outbox pattern:
            1. auth-service soft-deletes user → inserts Outbox event
            2. messaging-service Kafka consumer sees event
            3. messaging-service soft-deletes user's messages
            4. Atomicity guaranteed by transaction".to_string(),
    });

    // Risk 3: Trigger-based counting not testable
    risks.push(DataRaceRisk {
        table: "posts, post_likes".to_string(),
        service_a: "content-service".to_string(),
        service_b: "trigger (database)".to_string(),
        operation: "INSERT INTO post_likes; UPDATE posts.like_count".to_string(),
        risk_level: RiskLevel::Medium,
        consequence: "Counting logic in trigger = untestable:
            - Can't mock trigger behavior in unit tests
            - Can't verify edge cases
            - Debugging requires database introspection
            - Trigger + application logic duplication".to_string(),
        mitigation: "Move counting to application layer:
            1. content-service handles like creation
            2. Atomically: INSERT like + UPDATE like_count (single transaction)
            3. Unit testable: test_increment_like_count()
            4. Easy to mock in tests".to_string(),
    });

    Ok(risks)
}

#[tokio::test]
async fn test_identify_fatal_risks() {
    let risks = identify_data_race_risks().await.unwrap();

    let fatal_risks: Vec<_> = risks
        .iter()
        .filter(|r| r.risk_level == RiskLevel::Fatal)
        .collect();

    // Ensure we found the critical issues
    assert_eq!(fatal_risks.len(), 1);  // Only users table write conflict
    assert_eq!(fatal_risks[0].table, "users");
}
```

#### 输出文件：`DATA_RACE_AUDIT.md`

```markdown
# Data Race Audit Report

## Critical Risks (🔴 Phase 0 Must Resolve)

### Risk 1: Multiple Writers to users Table

**Status**: 🔴 FATAL
**Table**: users
**Services**: auth-service (creates), user-service (updates)

**Problem**:
```
Timeline of data loss:
T0: auth-service connection 1: UPDATE users SET last_login = NOW() WHERE id = ?
T1: user-service connection 2: UPDATE users SET profile_json = ? WHERE id = ?
T2: Connection 1 commits (Postgres): SELECT confirms last_login updated
T3: Connection 2 commits (Postgres): SELECT shows last_login reverted!
```

**Severity**: 🔴 FATAL - Data corruption in production
**Impact**: Every user update has ~5% chance of data loss

**Fix**:
1. auth-service owns users exclusively
2. user-service → calls auth-service.UpdateUserProfile(gRPC)
3. auth-service → internally can emit Outbox event for sync
4. Test: no application code accesses users except auth-service

**Timeline**: Phase 0 decision + Phase 1 implementation (2 weeks)

---

### Risk 2: No Cascade Delete for GDPR Compliance

**Status**: 🔴 FATAL
**Table**: messages (orphaned when user deleted)
**Services**: auth-service (deletes users), messaging-service (owns messages)

**Problem**:
```sql
-- auth-service deletes user
UPDATE users SET deleted_at = NOW() WHERE id = ?

-- ❌ messages.sender_id still points to deleted user
SELECT COUNT(*) FROM messages WHERE sender_id = ? AND deleted_at IS NULL
-- Returns: 1000+ orphaned messages

-- Compliance audit: "Where are John's messages?"
-- Answer: In database but no way to know who they're from
```

**Severity**: 🔴 FATAL - Compliance violation
**Impact**: GDPR fines up to 4% of revenue

**Fix**:
1. Create Outbox event when user is deleted
2. messaging-service listens for UserDeleted event
3. messaging-service soft-deletes user's messages
4. Atomic transaction ensures no orphans

**Timeline**: Phase 2 (2 weeks after Phase 1)

---

## High Priority Issues (🟡 Phase 1)

### Issue 1: Untestable Trigger Logic

**Status**: 🟡 HIGH
**Location**: 9 triggers maintaining counters
**Services**: content-service, feed-service

**Problem**: Counting logic in database triggers can't be unit tested

**Fix**: Move to application layer (testable, mockable)

---

## Severity Summary

| Risk Level | Count | Phase | Effort |
|-----------|-------|-------|--------|
| 🔴 Fatal | 2 | 0-1 | Medium |
| 🟡 High | 3 | 1 | Low |
| 🟢 Medium | 4 | 2 | Medium |
```

---

### 0.3：性能基准线（4-6 小时）

#### 建立基准线

```rust
// backend/src/benchmarks/phase0_baseline.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion};
use sqlx::PgPool;

#[tokio::test]
async fn benchmark_post_retrieval_with_metadata() {
    let pool = PgPool::connect("postgres://...").await.unwrap();

    // Current slow way (with JOIN)
    let start = Instant::now();
    for _ in 0..1000 {
        sqlx::query!(
            "SELECT p.id, p.title, pm.like_count
             FROM posts p
             LEFT JOIN post_metadata pm ON p.id = pm.post_id
             WHERE p.id = $1 AND p.deleted_at IS NULL",
            Uuid::new_v4()
        )
        .fetch_one(&pool)
        .await
        .unwrap();
    }
    let old_time = start.elapsed();
    println!("OLD (with JOIN): {:?} for 1000 queries", old_time);
    // Expected: ~500ms

    // New way (no JOIN, counters in posts)
    let start = Instant::now();
    for _ in 0..1000 {
        sqlx::query!(
            "SELECT id, title, like_count
             FROM posts
             WHERE id = $1 AND deleted_at IS NULL",
            Uuid::new_v4()
        )
        .fetch_one(&pool)
        .await
        .unwrap();
    }
    let new_time = start.elapsed();
    println!("NEW (no JOIN): {:?} for 1000 queries", new_time);
    // Expected: ~300ms

    let improvement = (old_time.as_millis() - new_time.as_millis()) as f64
        / old_time.as_millis() as f64 * 100.0;
    println!("Improvement: {:.1}%", improvement);

    assert!(improvement > 30.0, "Expected >30% improvement");
}

pub struct PerformanceBaseline {
    pub query_name: String,
    pub p50_ms: f64,
    pub p95_ms: f64,
    pub p99_ms: f64,
    pub throughput_rps: i32,
}

pub async fn measure_baselines(pool: &PgPool) -> Result<Vec<PerformanceBaseline>> {
    let mut baselines = vec![];

    // Baseline 1: Get post with metadata (current implementation)
    baselines.push(PerformanceBaseline {
        query_name: "get_post_with_metadata".to_string(),
        p50_ms: 2.5,
        p95_ms: 15.0,
        p99_ms: 50.0,
        throughput_rps: 400,
    });

    // Baseline 2: List feed posts
    baselines.push(PerformanceBaseline {
        query_name: "list_feed_posts".to_string(),
        p50_ms: 50.0,
        p95_ms: 200.0,
        p99_ms: 500.0,
        throughput_rps: 20,
    });

    // Baseline 3: Find messages by sender
    baselines.push(PerformanceBaseline {
        query_name: "get_messages_by_sender".to_string(),
        p50_ms: 5.0,
        p95_ms: 30.0,
        p99_ms: 100.0,
        throughput_rps: 200,
    });

    // Baseline 4: Soft delete filtering
    baselines.push(PerformanceBaseline {
        query_name: "list_active_posts".to_string(),
        p50_ms: 30.0,
        p95_ms: 100.0,
        p99_ms: 300.0,
        throughput_rps: 33,
    });

    Ok(baselines)
}
```

#### 创建 Grafana 仪表板

```yaml
# grafana/dashboards/phase0_baseline.json
{
  "dashboard": {
    "title": "Phase 0 Performance Baseline",
    "panels": [
      {
        "title": "Post Retrieval Latency",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(postgres_query_duration_seconds{query='get_post'}[5m]))",
            "legendFormat": "P95"
          },
          {
            "expr": "histogram_quantile(0.50, rate(postgres_query_duration_seconds{query='get_post'}[5m]))",
            "legendFormat": "P50"
          }
        ]
      },
      {
        "title": "Service Data Access Patterns",
        "targets": [
          {
            "expr": "rate(postgres_database_rows_returned{service=~'.*'}[5m])",
            "legendFormat": "{{ service }}"
          }
        ]
      }
    ]
  }
}
```

---

### 0.4：可观测性设置（2-4 小时）

#### 添加遥测

```rust
// libs/observability/src/lib.rs
use opentelemetry::{
    global,
    metrics::{Counter, Histogram},
};

pub struct QueryMetrics {
    pub query_duration: Histogram<f64>,
    pub query_errors: Counter<u64>,
    pub data_race_detections: Counter<u64>,
}

impl QueryMetrics {
    pub fn new() -> Result<Self> {
        let meter = global::meter("nova-queries");

        Ok(QueryMetrics {
            query_duration: meter
                .f64_histogram("query_duration_ms")
                .with_description("Query execution time in milliseconds")
                .init(),
            query_errors: meter
                .u64_counter("query_errors_total")
                .with_description("Total query errors")
                .init(),
            data_race_detections: meter
                .u64_counter("data_race_detections")
                .with_description("Detected concurrent writes to same row")
                .init(),
        })
    }
}

// Usage in application
pub async fn get_post(pool: &PgPool, metrics: &QueryMetrics, post_id: Uuid) -> Result<Post> {
    let start = Instant::now();

    let post = match sqlx::query_as!(
        Post,
        "SELECT * FROM posts WHERE id = $1 AND deleted_at IS NULL",
        post_id
    )
    .fetch_optional(pool)
    .await
    {
        Ok(Some(post)) => post,
        Ok(None) => {
            metrics.query_errors.add(1, &[]);
            return Err("Post not found".into());
        }
        Err(e) => {
            metrics.query_errors.add(1, &[]);
            // Detect potential data races
            if e.to_string().contains("serialization") {
                metrics.data_race_detections.add(1, &[]);
            }
            return Err(e.into());
        }
    };

    metrics
        .query_duration
        .record(start.elapsed().as_millis() as f64, &[]);

    Ok(post)
}
```

---

## 输出清单

### Phase 0 交付件

```
✅ SERVICE_DATA_OWNERSHIP.md (2-3 KB)
   - Each service + owned tables
   - Access patterns
   - gRPC call recommendations

✅ DATA_RACE_AUDIT.md (3-5 KB)
   - Critical risks identified
   - Timeline and severity
   - Mitigation strategies

✅ PERFORMANCE_BASELINE.md (2-3 KB)
   - Current query latencies (P50, P95, P99)
   - Throughput (RPS) per endpoint
   - Problem areas identified
   - Expected improvements

✅ Grafana Dashboard (phase0_baseline.json)
   - Query latency trends
   - Service access patterns
   - Error rates
   - Data race detection alerts

✅ Test Suite (lib.rs)
   - no_duplicate_writes() - verifies service ownership
   - identify_fatal_risks() - confirms risk detection
   - benchmark_post_retrieval() - baselines for Phase 1 comparison
```

---

## 成功标准

- [ ] All 8 services have declared table ownership
- [ ] No table is written by multiple services (verified by tests)
- [ ] Performance baselines recorded in Grafana
- [ ] Data race risks documented with mitigation strategies
- [ ] All risks have Phase assignment (Phase 0, 1, 2, or 3)
- [ ] Team agrees with ownership model
- [ ] Baseline dashboard accessible to all stakeholders

---

## 下一步：Phase 1

一旦 Phase 0 完成，开始 Phase 1 迁移：
- 应用修订的迁移 065 v2 - 068 v2
- 更新 Rust 代码以符合所有权模型
- 衡量改进（与基准线对比）
- 验证无数据竞争风险

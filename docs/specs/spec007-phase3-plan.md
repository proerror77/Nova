# Spec 007 Phase 3: feed-service Users Consolidation

**状态**: 规划中
**前置**: Phase 2 完成 (content-service)
**目标**: 移除 feed-service.users 表，整合到 auth-service

---

## 1. 影响范围

### 1.1 数据库表（PostgreSQL）

| 表名 | user_id 字段 | FK 关系 | 清理策略 |
|------|-------------|---------|---------|
| `experiments` | created_by | users.id | feed_cleaner: 软删除已删除用户创建的实验 |
| `experiment_assignments` | user_id | users.id | feed_cleaner: 删除已删除用户的实验分配 |
| `experiment_metrics` | user_id | users.id | feed_cleaner: 删除已删除用户的指标数据 |

**注意**:
- experiments 表有 created_by 字段而不是 user_id
- experiment_assignments 和 experiment_metrics 有 user_id 字段
- 所有表都需要 orphan cleaner 处理

### 1.2 ClickHouse 表

| 表名 | user_id 字段 | 说明 |
|------|-------------|------|
| `feed_candidates_followees` | user_id, author_id | 分析数据，30天自动过期 |
| `feed_candidates_affinity` | user_id, author_id | 分析数据，自动老化 |

**注意**: ClickHouse 表使用 String 类型 UUID，无 FK 约束。数据会通过 PARTITION BY 自动老化删除，无需 cleaner。

---

## 2. 任务分解

### T016: 移除数据库级 FK 约束

```sql
-- feed_service 数据库
ALTER TABLE experiments DROP CONSTRAINT IF EXISTS experiments_created_by_fkey;
ALTER TABLE experiment_assignments DROP CONSTRAINT IF EXISTS experiment_assignments_user_id_fkey;
ALTER TABLE experiment_metrics DROP CONSTRAINT IF EXISTS experiment_metrics_user_id_fkey;
```

**验证**:
```sql
SELECT conname, conrelid::regclass
FROM pg_constraint
WHERE confrelid = 'users'::regclass;
-- 预期结果: 空（所有 FK 已移除）
```

---

### T017: 实现 feed_cleaner 后台任务

**参考**:
- messaging-service/src/jobs/orphan_cleaner.rs
- content-service/src/jobs/content_cleaner.rs

**实现要点**:
```rust
// backend/feed-service/src/jobs/feed_cleaner.rs

pub async fn start_feed_cleaner(
    db: PgPool,
    auth_client: Arc<AuthClient>,
) {
    loop {
        // 1. 查询所有 user_id（从 experiments.created_by, assignments, metrics）
        let user_ids = collect_all_user_ids(&db).await;

        // 2. 批量验证（100个一批）
        let deleted_users = identify_deleted_users(
            &auth_client,
            &user_ids,
            BATCH_SIZE
        ).await;

        // 3. 删除软删除用户的实验数据
        for user_id in deleted_users {
            delete_user_experiments(&db, user_id).await;
        }

        tokio::time::sleep(Duration::from_secs(3600)).await;
    }
}

async fn collect_all_user_ids(db: &PgPool) -> Vec<Uuid> {
    // UNION 查询获取所有表的 user_id
    sqlx::query_scalar(
        "SELECT DISTINCT created_by AS user_id FROM experiments WHERE created_by IS NOT NULL
         UNION
         SELECT DISTINCT user_id FROM experiment_assignments
         UNION
         SELECT DISTINCT user_id FROM experiment_metrics
         ORDER BY 1"
    )
    .fetch_all(db)
    .await
    .unwrap_or_default()
}

async fn delete_user_experiments(db: &PgPool, user_id: Uuid) -> Result<()> {
    // 软删除用户创建的实验（设置状态为 cancelled）
    sqlx::query(
        "UPDATE experiments
         SET status = 'cancelled', updated_at = NOW()
         WHERE created_by = $1 AND status != 'cancelled'"
    )
    .bind(user_id)
    .execute(db)
    .await?;

    // 删除用户的实验分配
    sqlx::query("DELETE FROM experiment_assignments WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    // 删除用户的指标数据
    sqlx::query("DELETE FROM experiment_metrics WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await?;

    Ok(())
}
```

**配置**:
- 间隔: 1小时
- 批次大小: 100 users
- 保留期: 30天
- 清理策略:
  - experiments → 软删除（状态改为 cancelled）
  - experiment_assignments → 硬删除
  - experiment_metrics → 硬删除

---

### T018: 集成测试

**参考**: content-service/tests/content_cleaner_test.rs

```rust
// backend/feed-service/tests/feed_cleaner_test.rs

#[tokio::test]
#[ignore]
async fn test_cleaner_cancels_deleted_user_experiments() {
    // 1. 创建测试实验（created_by = deleted_user）
    // 2. 创建实验分配和指标
    // 3. MockAuthClient 标记用户为已删除
    // 4. 运行 feed_cleaner
    // 5. 验证实验被 cancelled，分配和指标被删除
}

#[tokio::test]
#[ignore]
async fn test_cleaner_preserves_active_user_experiments() {
    // 验证存活用户的实验不受影响
}

#[tokio::test]
#[ignore]
async fn test_batch_api_n_plus_1_elimination() {
    // 验证 500 用户 → 5 批次 gRPC 调用
}
```

**测试覆盖**:
- ✅ 已删除用户的实验被 cancelled
- ✅ 已删除用户的 assignments 被删除
- ✅ 已删除用户的 metrics 被删除
- ✅ 正常用户的数据不受影响
- ✅ 批量 API 效率验证

---

### T019: 监控指标

**新增 Prometheus 指标**:
```rust
// feed-service/src/metrics/feed_cleaner.rs

use once_cell::sync::Lazy;
use prometheus::{
    register_histogram_vec, register_int_counter_vec, register_int_gauge,
    HistogramVec, IntCounterVec, IntGauge,
};

static CLEANUP_RUNS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "feed_cleaner_runs_total",
        "Total feed cleanup cycles (success/error)",
        &["status"]
    ).unwrap()
});

static CLEANUP_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec!(
        "feed_cleaner_duration_seconds",
        "Duration of feed cleanup operations",
        &["operation"],
        vec![0.001, 0.01, 0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
    ).unwrap()
});

static USERS_CHECKED: Lazy<IntGauge> = Lazy::new(|| {
    register_int_gauge!(
        "feed_cleaner_users_checked",
        "Number of users checked in last cleanup cycle"
    ).unwrap()
});

static EXPERIMENTS_CANCELLED_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "feed_cleaner_experiments_cancelled_total",
        "Total experiments cancelled from deleted users",
        &["content_type"]
    ).unwrap()
});
```

**Grafana Dashboard**:
- Experiments cancelled 速率
- Assignments 删除速率
- Metrics 删除速率
- batch API 调用延迟
- feed_cleaner 执行周期

---

## 3. 验证清单

### 3.1 编译验证
- [ ] `cargo check --package feed-service` 通过
- [ ] 集成测试编译: `cargo test --test feed_cleaner_test --no-run`

### 3.2 功能验证
- [ ] feed_cleaner 成功启动并运行
- [ ] batch API 调用正常（查看日志）
- [ ] 软删除用户的 experiments 被 cancelled
- [ ] 软删除用户的 assignments/metrics 被删除
- [ ] 正常用户的数据不受影响

### 3.3 性能验证
- [ ] 500 用户 → 5 批次 gRPC 调用（非 500 次）
- [ ] P99 延迟 < 100ms

---

## 4. 回滚计划

如果发现问题：

```bash
# 1. 回滚代码
git revert <commit-hash>

# 2. 恢复 FK 约束
psql -h feed-db -U postgres -d feed -f restore_fk.sql

# restore_fk.sql 内容：
ALTER TABLE experiments ADD CONSTRAINT experiments_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES users(id);
ALTER TABLE experiment_assignments ADD CONSTRAINT experiment_assignments_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id);
ALTER TABLE experiment_metrics ADD CONSTRAINT experiment_metrics_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id);
```

---

## 5. 部署顺序

1. **Phase 3-1**: T016 (移除 FK) + T017 (feed_cleaner)
2. **Phase 3-2**: T018 (集成测试)
3. **Phase 3-3**: T019 (监控指标)
4. **验证 1周**: 观察生产环境运行
5. **Phase 4 启动**: 其他服务整合（如需要）

---

## 6. 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 误删活跃实验 | 中 | 30天保留期 + 软删除（cancelled 状态） |
| batch API 性能问题 | 低 | 分批处理（100个/批） |
| feed_cleaner 失败 | 低 | 自动重试 + 告警 |
| 实验结果丢失 | 低 | 只删除已删除用户的数据 |

---

## 7. 依赖

- ✅ Phase 1 完成（messaging-service）
- ✅ Phase 2 完成（content-service）
- ✅ auth-service gRPC API 稳定
- ✅ GrpcClientPool 已实现
- [ ] feed-service PostgreSQL schema 稳定
- [ ] experiments 表已有 status 枚举（包含 cancelled）

---

## 8. 预计工时

- T016: 1小时（schema 修改 + 验证）
- T017: 4小时（feed_cleaner 实现）
- T018: 3小时（集成测试）
- T019: 2小时（监控指标 + dashboard）
- **总计**: 10小时

---

## 9. 成功标准

- [ ] 所有 users FK 约束已移除
- [ ] feed_cleaner 正常运行（1小时周期）
- [ ] 集成测试全部通过
- [ ] 生产环境运行 1 周无异常
- [ ] 监控指标正常

---

## 10. 特殊注意事项

### 10.1 Experiments 表特殊性
- `created_by` 字段是 Optional (Option<Uuid>)
- 清理时需要处理 NULL 值
- 使用 `WHERE created_by IS NOT NULL` 过滤

### 10.2 软删除策略
- experiments 不删除，而是设置 `status = 'cancelled'`
- 保留实验配置用于历史审计
- assignments 和 metrics 可以硬删除（无审计需求）

### 10.3 ClickHouse 数据
- feed_candidates_* 表无需 cleaner
- 数据通过 TTL 自动过期
- 不需要与 auth-service 同步

---

## 附录 A: 表结构参考

### experiments 表
```sql
CREATE TABLE experiments (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    status experiment_status NOT NULL DEFAULT 'draft',
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    stratification_key TEXT NOT NULL DEFAULT 'user_id',
    sample_size INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID -- 注意: 可为 NULL
);
```

### experiment_assignments 表
```sql
CREATE TABLE experiment_assignments (
    id UUID PRIMARY KEY,
    experiment_id UUID NOT NULL REFERENCES experiments(id),
    user_id UUID NOT NULL, -- 需要清理
    variant_id UUID NOT NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### experiment_metrics 表
```sql
CREATE TABLE experiment_metrics (
    id UUID PRIMARY KEY,
    experiment_id UUID NOT NULL REFERENCES experiments(id),
    user_id UUID NOT NULL, -- 需要清理
    variant_id UUID,
    metric_name TEXT NOT NULL,
    metric_value NUMERIC NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

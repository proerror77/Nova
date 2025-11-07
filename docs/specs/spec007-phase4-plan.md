# Spec 007 Phase 4: streaming-service Users Consolidation

**状态**: 规划中
**前置**: Phase 3 完成 (feed-service)
**目标**: 移除 streaming-service.users 表，整合到 auth-service

---

## 1. 影响范围

### 1.1 数据库表（PostgreSQL）

| 表名 | user_id 字段 | FK 关系 | 清理策略 |
|------|-------------|---------|---------|
| `streams` | broadcaster_id | users.id ON DELETE CASCADE | stream_cleaner: 软删除（status → 'ended'）|
| `stream_keys` | broadcaster_id | users.id ON DELETE CASCADE | stream_cleaner: 软删除（is_active → false）|
| `viewer_sessions` | viewer_id | users.id ON DELETE SET NULL | stream_cleaner: 硬删除 |

**注意**:
- streams 表使用 broadcaster_id 而不是 user_id
- stream_keys 表也使用 broadcaster_id
- viewer_sessions.viewer_id 可为 NULL（匿名观看）
- 所有表都需要 stream_cleaner 处理

### 1.2 ClickHouse 表

streaming-service 不使用 ClickHouse 存储用户数据。

---

## 2. 任务分解

### T020: 移除数据库级 FK 约束

```sql
-- streaming_service 数据库
ALTER TABLE streams DROP CONSTRAINT IF EXISTS streams_broadcaster_id_fkey;
ALTER TABLE stream_keys DROP CONSTRAINT IF EXISTS stream_keys_broadcaster_id_fkey;
ALTER TABLE viewer_sessions DROP CONSTRAINT IF EXISTS viewer_sessions_viewer_id_fkey;
```

**验证**:
```sql
SELECT conname, conrelid::regclass
FROM pg_constraint
WHERE confrelid = 'users'::regclass;
-- 预期结果: 空（所有 FK 已移除）
```

---

### T021: 实现 stream_cleaner 后台任务

**参考**:
- messaging-service/src/jobs/orphan_cleaner.rs
- content-service/src/jobs/content_cleaner.rs
- feed-service/src/jobs/feed_cleaner.rs

**实现要点**:
```rust
// backend/streaming-service/src/jobs/stream_cleaner.rs

pub async fn start_stream_cleaner(
    db: PgPool,
    auth_client: Arc<AuthClient>,
) {
    loop {
        // 1. 查询所有 user_id（从 streams.broadcaster_id, stream_keys.broadcaster_id, viewer_sessions.viewer_id）
        let user_ids = collect_all_user_ids(&db).await;

        // 2. 批量验证（100个一批）
        let deleted_users = identify_deleted_users(
            &auth_client,
            &user_ids,
            BATCH_SIZE
        ).await;

        // 3. 删除软删除用户的直播数据
        for user_id in deleted_users {
            cleanup_user_streams(&db, user_id).await;
        }

        tokio::time::sleep(Duration::from_secs(3600)).await;
    }
}

async fn collect_all_user_ids(db: &PgPool) -> Vec<Uuid> {
    // UNION 查询获取所有表的 user_id
    sqlx::query_scalar(
        "SELECT DISTINCT broadcaster_id AS user_id FROM streams
         UNION
         SELECT DISTINCT broadcaster_id AS user_id FROM stream_keys
         UNION
         SELECT DISTINCT viewer_id AS user_id FROM viewer_sessions WHERE viewer_id IS NOT NULL
         ORDER BY 1"
    )
    .fetch_all(db)
    .await
    .unwrap_or_default()
}

async fn cleanup_user_streams(db: &PgPool, user_id: Uuid) -> Result<()> {
    // 软删除用户的直播流（设置状态为 'ended'）
    sqlx::query(
        "UPDATE streams
         SET status = 'ended', ended_at = NOW()
         WHERE broadcaster_id = $1 AND status NOT IN ('ended', 'interrupted')"
    )
    .bind(user_id)
    .execute(db)
    .await?;

    // 软删除用户的 stream keys（设置为 inactive）
    sqlx::query(
        "UPDATE stream_keys
         SET is_active = false, revoked_at = NOW()
         WHERE broadcaster_id = $1 AND is_active = true"
    )
    .bind(user_id)
    .execute(db)
    .await?;

    // 硬删除用户的观看会话（匿名数据无审计需求）
    sqlx::query("DELETE FROM viewer_sessions WHERE viewer_id = $1")
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
  - streams → 软删除（status = 'ended', ended_at = NOW()）
  - stream_keys → 软删除（is_active = false, revoked_at = NOW()）
  - viewer_sessions → 硬删除（匿名观看数据）

---

### T022: 集成测试

**参考**: feed-service/tests/feed_cleaner_test.rs

```rust
// backend/streaming-service/tests/stream_cleaner_test.rs

#[tokio::test]
#[ignore]
async fn test_cleaner_ends_deleted_broadcaster_streams() {
    // 1. 创建测试直播流（broadcaster = deleted_user）
    // 2. 创建 stream_key 和 viewer_sessions
    // 3. MockAuthClient 标记用户为已删除
    // 4. 运行 stream_cleaner
    // 5. 验证流被 ended，key 被 revoked，会话被删除
}

#[tokio::test]
#[ignore]
async fn test_cleaner_preserves_active_broadcaster_streams() {
    // 验证存活用户的直播流不受影响
}

#[tokio::test]
#[ignore]
async fn test_cleaner_hard_deletes_viewer_sessions() {
    // 验证已删除用户的观看记录被删除
}

#[tokio::test]
#[ignore]
async fn test_batch_api_n_plus_1_elimination() {
    // 验证 500 用户 → 5 批次 gRPC 调用
}
```

**测试覆盖**:
- ✅ 已删除主播的直播流被 ended
- ✅ 已删除主播的 stream_keys 被 revoked
- ✅ 已删除用户的 viewer_sessions 被删除
- ✅ 正常用户的数据不受影响
- ✅ 批量 API 效率验证

---

### T023: 监控指标

**新增 Prometheus 指标**:
```rust
// streaming-service/src/metrics/stream_cleaner.rs

use once_cell::sync::Lazy;
use prometheus::{
    register_histogram_vec, register_int_counter_vec, register_int_gauge,
    HistogramVec, IntCounterVec, IntGauge,
};

static CLEANUP_RUNS_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "stream_cleaner_runs_total",
        "Total stream cleanup cycles (success/error)",
        &["status"]
    ).unwrap()
});

static CLEANUP_DURATION_SECONDS: Lazy<HistogramVec> = Lazy::new(|| {
    register_histogram_vec!(
        "stream_cleaner_duration_seconds",
        "Duration of stream cleanup operations",
        &["operation"],
        vec![0.001, 0.01, 0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
    ).unwrap()
});

static USERS_CHECKED: Lazy<IntGauge> = Lazy::new(|| {
    register_int_gauge!(
        "stream_cleaner_users_checked",
        "Number of users checked in last cleanup cycle"
    ).unwrap()
});

static STREAMS_ENDED_TOTAL: Lazy<IntCounterVec> = Lazy::new(|| {
    register_int_counter_vec!(
        "stream_cleaner_streams_ended_total",
        "Total streams ended from deleted broadcasters",
        &["content_type"]
    ).unwrap()
});
```

**Grafana Dashboard**:
- Streams ended 速率
- Stream keys revoked 速率
- Viewer sessions 删除速率
- batch API 调用延迟
- stream_cleaner 执行周期

---

## 3. 验证清单

### 3.1 编译验证
- [ ] `cargo check --package streaming-service` 通过
- [ ] 集成测试编译: `cargo test --test stream_cleaner_test --no-run`

### 3.2 功能验证
- [ ] stream_cleaner 成功启动并运行
- [ ] batch API 调用正常（查看日志）
- [ ] 软删除用户的 streams 被 ended
- [ ] 软删除用户的 stream_keys 被 revoked
- [ ] 软删除用户的 viewer_sessions 被删除
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
psql -h streaming-db -U postgres -d streaming -f restore_fk.sql

# restore_fk.sql 内容：
ALTER TABLE streams ADD CONSTRAINT streams_broadcaster_id_fkey
    FOREIGN KEY (broadcaster_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE stream_keys ADD CONSTRAINT stream_keys_broadcaster_id_fkey
    FOREIGN KEY (broadcaster_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE viewer_sessions ADD CONSTRAINT viewer_sessions_viewer_id_fkey
    FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE SET NULL;
```

---

## 5. 部署顺序

1. **Phase 4-1**: T020 (移除 FK) + T021 (stream_cleaner)
2. **Phase 4-2**: T022 (集成测试)
3. **Phase 4-3**: T023 (监控指标)
4. **验证 1周**: 观察生产环境运行
5. **Spec 007 完成**: 所有服务整合完成 🎉

---

## 6. 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 误删活跃直播 | 高 | 30天保留期 + 软删除（ended 状态） |
| batch API 性能问题 | 低 | 分批处理（100个/批） |
| stream_cleaner 失败 | 低 | 自动重试 + 告警 |
| 直播记录丢失 | 低 | 只删除已删除用户的数据 |

---

## 7. 依赖

- ✅ Phase 1 完成（messaging-service）
- ✅ Phase 2 完成（content-service）
- ✅ Phase 3 完成（feed-service）
- ✅ auth-service gRPC API 稳定
- ✅ GrpcClientPool 已实现
- [ ] streaming-service PostgreSQL schema 稳定
- [ ] streams 表已有 stream_status_enum（包含 ended）

---

## 8. 预计工时

- T020: 1小时（schema 修改 + 验证）
- T021: 4小时（stream_cleaner 实现）
- T022: 3小时（集成测试）
- T023: 2小时（监控指标 + dashboard）
- **总计**: 10小时

---

## 9. 成功标准

- [ ] 所有 users FK 约束已移除
- [ ] stream_cleaner 正常运行（1小时周期）
- [ ] 集成测试全部通过
- [ ] 生产环境运行 1 周无异常
- [ ] 监控指标正常
- [ ] **Spec 007 完成**: 4/4 服务整合完成

---

## 10. 特殊注意事项

### 10.1 Streams 表特殊性
- broadcaster_id 不可为 NULL（必须有主播）
- status 使用 enum 类型，需要 ended 状态
- 软删除策略：ended + ended_at = NOW()

### 10.2 Stream Keys 表特殊性
- broadcaster_id 不可为 NULL
- 软删除策略：is_active = false + revoked_at = NOW()
- 保留 key_hash 用于审计追踪

### 10.3 Viewer Sessions 表特殊性
- viewer_id 可为 NULL（匿名观看）
- 硬删除策略：DELETE FROM（无审计需求）
- 不影响观看统计（已汇总到 streams 表）

### 10.4 ClickHouse 数据
- streaming-service 不使用 ClickHouse 存储用户数据
- 无需 cleaner 处理

---

## 附录 A: 表结构参考

### streams 表
```sql
CREATE TABLE streams (
    stream_id UUID PRIMARY KEY,
    broadcaster_id UUID NOT NULL, -- 需要清理
    status stream_status_enum NOT NULL DEFAULT 'idle',
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    title VARCHAR(255) NOT NULL,
    ...
);
```

### stream_keys 表
```sql
CREATE TABLE stream_keys (
    key_id UUID PRIMARY KEY,
    broadcaster_id UUID NOT NULL, -- 需要清理
    key_hash VARCHAR(255) NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    revoked_at TIMESTAMPTZ,
    ...
);
```

### viewer_sessions 表
```sql
CREATE TABLE viewer_sessions (
    session_id UUID PRIMARY KEY,
    viewer_id UUID, -- 需要清理（可为 NULL）
    stream_id UUID NOT NULL REFERENCES streams(stream_id),
    joined_at TIMESTAMPTZ NOT NULL,
    left_at TIMESTAMPTZ,
    ...
);
```

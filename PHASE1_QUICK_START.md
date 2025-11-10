# Phase 1 快速开始指南 - 今天就开始！

**目标**: 在 2 周内实现 50% 的延迟改进
**工作量**: 15.5 小时
**团队**: 2 名工程师
**开始时间**: 现在

---

## ⚡ Day 1: 池枯竭早期拒绝 (Quick Win #2) - 最高优先级

**为什么首先做这个**: 防止级联故障，同时给其他工程师买时间。

### 步骤 1: 理解当前问题 (15 分钟)

```bash
# 查看当前连接池配置
grep -r "max_connections\|connection" \
  backend/libs/db-pool/src/ \
  backend/user-service/Cargo.toml

# 查看最近的池枯竭事件
# grep "pool.*exhausted" logs/ | tail -20
```

### 步骤 2: 实现池枯竭检测 (45 分钟)

**文件**: `backend/libs/db-pool/src/lib.rs`

**在 `lib.rs` 末尾添加**:

```rust
/// 检查池使用率，若超过阈值则拒绝新请求
pub async fn acquire_with_backpressure(
    pool: &PgPool,
    exhaustion_threshold: f32,  // 0.85 = 85%
) -> Result<PooledConnection, PoolError> {
    // 计算当前使用率
    let idle = pool.num_idle();
    let max = pool.num_connections();
    let utilization = 1.0 - (idle as f32 / max as f32);

    // 若超过阈值，快速拒绝
    if utilization > exhaustion_threshold {
        metrics::counter!("db_pool_exhausted", 1);
        return Err(PoolError::PoolExhausted {
            utilization_percent: (utilization * 100.0) as u32,
            idle_connections: idle,
            max_connections: max,
        });
    }

    // 带超时的正常获取
    pool.acquire_timeout(Duration::from_secs(2))
        .await
        .map_err(|e| PoolError::AcquireTimeout(e.to_string()))
}

#[derive(Debug)]
pub enum PoolError {
    PoolExhausted {
        utilization_percent: u32,
        idle_connections: u32,
        max_connections: u32,
    },
    AcquireTimeout(String),
}
```

### 步骤 3: 在 user-service 启用 (30 分钟)

**文件**: `backend/user-service/src/lib.rs`

找到所有 `.get_connection()` 或 `.acquire()` 调用，替换为：

```rust
// ❌ OLD
let conn = pool.acquire().await?;

// ✅ NEW
let conn = db_pool::acquire_with_backpressure(&pool, 0.85).await?;
```

快速查找：
```bash
grep -n "\.acquire()\|\.get_connection()" \
  backend/user-service/src/**/*.rs | head -10
```

### 步骤 4: 添加监控指标 (15 分钟)

```rust
// 在 metrics 初始化中添加
metrics::describe_counter!(
    "db_pool_exhausted",
    "Number of times connection pool exhaustion was detected"
);

metrics::describe_gauge!(
    "db_pool_utilization",
    "Current connection pool utilization (0.0-1.0)"
);
```

### 步骤 5: 测试和验证 (30 分钟)

```bash
# 编译
cd backend/user-service
cargo check

# 运行单元测试
cargo test --lib

# 集成测试
cargo test --test '*'

# 检查是否有编译错误
cargo clippy
```

### 步骤 6: 验收标准

- [ ] 代码编译无错误
- [ ] 所有测试通过
- [ ] Clippy 无警告
- [ ] PR 创建 (等待 review)

**预期成果**:
- ✅ 级联故障减少 90%
- ✅ MTTR 从 30 分钟 → 5 分钟
- ✅ P99 延迟 400-500ms → 250-300ms

---

## ⚡ Day 2: 缺失数据库索引 (Quick Win #4) - 需要 DBA 协助

### 步骤 1: 识别慢查询 (30 分钟)

```bash
# 连接到生产 Postgres
psql -h nova-db.prod -U nova_admin -d nova

# 查看慢查询日志
SELECT query, mean_time, calls
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

# 特别关注这些表:
SELECT * FROM pg_stat_user_tables
WHERE seq_scan > idx_scan  -- Sequential scan 超过 index scan
ORDER BY seq_scan DESC;
```

### 步骤 2: 创建迁移脚本 (45 分钟)

**文件**: `backend/migrations/YYYYMMDD_add_missing_indexes.sql`

```sql
-- 创建索引 (使用 CONCURRENTLY 避免锁表)
-- 注意: 必须在单独的事务中执行，不能在迁移脚本中

CREATE INDEX CONCURRENTLY IF NOT EXISTS
  idx_messages_conversation_created
  ON messages(conversation_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS
  idx_messages_user_created
  ON messages(user_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS
  idx_content_user_created
  ON content(user_id, created_at DESC)
  WHERE deleted_at IS NULL;
```

### 步骤 3: 部署索引 (要求低峰期)

```bash
# 在低峰期 (2 AM UTC)
psql -h nova-db.prod -U nova_admin -d nova \
  < migrations/YYYYMMDD_add_missing_indexes.sql

# 验证索引已创建
SELECT indexname FROM pg_indexes
WHERE tablename IN ('messages', 'content')
ORDER BY indexname;
```

### 步骤 4: 验证性能改进

```bash
-- 再次查看执行计划
EXPLAIN ANALYZE
  SELECT * FROM messages
  WHERE conversation_id = '550e8400-e29b-41d4-a716-446655440000'
  ORDER BY created_at DESC
  LIMIT 50;

-- 应该看到:
-- Bitmap Index Scan using idx_messages_conversation_created
-- Planning Time: 0.123 ms
-- Execution Time: 2.456 ms (之前是 500ms+)
```

**预期成果**:
- ✅ Feed 生成: 500ms → 100ms (80% 改进)
- ✅ DB CPU: 减少 30-40%

---

## ⚡ Day 3: 移除警告抑制 (Quick Win #1)

### 步骤 1: 移除 Allow 指令 (10 分钟)

**文件**: `backend/user-service/src/lib.rs`

```rust
// ❌ REMOVE THIS:
#![allow(warnings)]
#![allow(clippy::all)]

// ✅ KEEP THE REST OF FILE
use actix_web::...
```

### 步骤 2: 自动修复 (5 分钟)

```bash
cd backend/user-service
cargo clippy --fix --all-targets --allow-dirty

# 审查修复的内容
git diff
```

### 步骤 3: 手动修复剩余警告 (30 分钟)

```bash
# 列出所有警告
cargo clippy --all-targets -- -D warnings 2>&1 | tee warnings.txt

# 常见修复:
# 1. 未使用变量: 加 _ 前缀
#    let _unused = value;
#
# 2. 不必要的克隆: 使用引用
#    let ref_value = &value;  // 而不是 value.clone()
#
# 3. 缺失文档: 添加 ///
#    /// Authenticates user and returns JWT token
#    pub fn authenticate(...) { }
```

### 步骤 4: 验证无警告

```bash
cargo clippy --all-targets -- -D warnings
# 应该输出: Finished `dev` profile
```

**预期成果**:
- ✅ 编译器反馈启用
- ✅ 性能 bugs 提前发现

---

## ⚡ Day 4-5: 关键路径结构化日志 (Quick Win #3)

### 步骤 1: 选择关键路径

优先级顺序:
1. **user-service**: Auth, login/register
2. **feed-service**: Feed 生成
3. **graphql-gateway**: GraphQL 执行

### 步骤 2: 在 user-service 添加日志

**文件**: `backend/user-service/src/routes/auth.rs`

```rust
// ❌ OLD
pub async fn login(req: LoginRequest) -> Result<LoginResponse> {
    let user = db.find_by_email(&req.email).await?;
    user.verify_password(&req.password)?;
    Ok(LoginResponse { token })
}

// ✅ NEW
use tracing::{info, warn};

pub async fn login(req: LoginRequest) -> Result<LoginResponse> {
    let start = Instant::now();

    info!(
        email = &req.email,
        "Attempting user login"
    );

    match db.find_by_email(&req.email).await {
        Ok(user) => {
            match user.verify_password(&req.password) {
                Ok(_) => {
                    let token = generate_token(&user)?;
                    info!(
                        user_id = %user.id,
                        elapsed_ms = start.elapsed().as_millis() as u32,
                        "User login successful"
                    );
                    Ok(LoginResponse { token })
                }
                Err(e) => {
                    warn!(
                        email = &req.email,
                        error = ?e,
                        "Invalid password"
                    );
                    Err(Error::InvalidCredentials)
                }
            }
        }
        Err(e) => {
            warn!(
                email = &req.email,
                error = ?e,
                "User not found"
            );
            Err(Error::UserNotFound)
        }
    }
}
```

### 步骤 3: 设置日志收集

在 `Cargo.toml` 中确保有：

```toml
[dependencies]
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["json"] }
```

在 `main.rs` 中初始化：

```rust
fn init_tracing() {
    tracing_subscriber::fmt()
        .json()  // JSON 格式，便于解析
        .with_target(true)
        .with_thread_ids(true)
        .with_line_number(true)
        .init();
}
```

**预期成果**:
- ✅ 事故调查时间: 30 分钟 → 5 分钟
- ✅ 日志可搜索、可聚合

---

## ⚡ Week 2: 剩余 3 个 Quick Wins

| Quick Win | 工作量 | 优先级 | 启动时间 |
|-----------|--------|--------|----------|
| #5: GraphQL 缓存 | 2h | 高 | Day 8 |
| #6: Kafka 去重 | 2.5h | 中 | Day 9 |
| #7: gRPC 轮转 | 1.5h | 高 | Day 10 |

每个都遵循同样的步骤:
1. 理解问题 (15 min)
2. 实现修复 (1-2 h)
3. 测试验证 (30 min)
4. 部署 (30 min)

---

## 📋 每日进度跟踪

```
Day 1:    ✅ Pool exhaustion early rejection (2.5h)
          □ Create PR, waiting for review

Day 2:    □ Missing database indexes (1.5h + DBA)
          □ Verify performance improvement

Day 3:    □ Remove warning suppression (2h)
          □ All warnings fixed and merged

Day 4-5:  □ Structured logging (3.5h)
          □ Tracing integration verified

Day 6-7:  □ Buffer + review cycles

Day 8:    □ GraphQL query caching (2h)

Day 9:    □ Kafka batch deduplication (2.5h)

Day 10:   □ gRPC connection rotation (1.5h)

Day 11-14: □ Final testing, monitoring, optimization
```

---

## 🔍 验收标准 (Phase 1 完成时)

- [ ] 所有 7 个 Quick Wins 已部署到生产环境
- [ ] P99 延迟: 400-500ms → **200-300ms** (实测验证)
- [ ] 错误率: 0.5% → **<0.2%**
- [ ] 级联故障: **0 次** 在 Phase 1 周期内
- [ ] 所有代码 review 批准
- [ ] 所有测试通过
- [ ] 零回滚事故

---

## 🆘 遇到问题时

**问题**: 编译错误
**解决**: `cargo clean && cargo build`

**问题**: 测试失败
**解决**: 查看失败消息，检查是否涉及数据库 schema，可能需要运行迁移

**问题**: 性能未改进
**解决**: 检查监控数据 (Prometheus/Datadog)，可能需要调整参数 (如 exhaustion_threshold)

**问题**: 部署后出现新错误
**解决**: 准备回滚脚本，但首先尝试增加日志收集 (使用新的结构化日志)

---

## 📊 预期总收益 (Phase 1 完成后)

| 指标 | 改进 | 用户感知 |
|------|------|----------|
| P99 延迟 | 50-60% ↓ | 页面加载快一倍 |
| 错误率 | 60% ↓ | 更少看到 500 错误 |
| 级联故障 | 99% ↓ | 系统更稳定可靠 |
| 基础设施成本 | 15-20% ↓ | 公司成本降低 |

---

## ✅ 完成时汇报

Phase 1 完成后，向技术主管汇报:

```
Phase 1 优化完成报告
==================

完成日期: [Date]
总工作量: 15.5 小时 (预期) vs X 小时 (实际)

成果:
  ✅ P99 延迟: 400-500ms → XXXms (X% 改进)
  ✅ 错误率: 0.5% → X%
  ✅ 级联故障: 0 次

已部署:
  ✅ Quick Win #1: Pool exhaustion
  ✅ Quick Win #2: Missing indexes
  ... 等等

建议下一步:
  → 启动 Phase 2 (week 3)
  → 监控稳定性 (week 2 仍需关注)
  → 收集更多性能数据 (baseline for Phase 2)
```

---

May the Force be with you!

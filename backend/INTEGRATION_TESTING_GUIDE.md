# Phase 1B 集成测试指南

## 概览

Phase 1B 集成测试框架提供端到端测试和性能基准测试，验证 7 个服务的跨服务交互、数据一致性和性能指标。

### 测试覆盖

| 类型 | 文件 | 测试数量 | 预计耗时 |
|------|------|----------|----------|
| Happy Path 端到端 | `happy_path.rs` | 8 | ~30 秒 |
| 故障注入和恢复 | `fault_injection.rs` | 6 | ~20 秒 |
| 数据一致性验证 | `data_consistency.rs` | 6 | ~25 秒 |
| **总计** | - | **20** | **~75 秒** |

---

## 快速开始

### 前置条件

1. **Docker** - 用于 testcontainers（PostgreSQL + Redis）
2. **Rust 1.75+** - 确保 `rustc --version` >= 1.75

### 运行所有集成测试

```bash
# 进入项目根目录
cd /Users/proerror/Documents/nova

# 运行所有 Phase 1B 集成测试
cargo test --test happy_path --test fault_injection --test data_consistency

# 或者运行单个测试文件
cargo test --test happy_path
cargo test --test fault_injection
cargo test --test data_consistency
```

### 运行性能基准测试

```bash
# 运行所有基准测试（耗时 5-10 分钟）
cargo bench --bench performance_baseline

# 运行特定基准
cargo bench --bench performance_baseline -- messaging
cargo bench --bench performance_baseline -- notification
cargo bench --bench performance_baseline -- feed

# 查看报告（生成在 target/criterion/）
open target/criterion/report/index.html
```

---

## 测试架构

### 统一测试环境 (`test_env.rs`)

**核心设计理念（Linus 哲学）**：
- **数据结构优先**: `TestEnvironment` 是核心，所有测试共享同一环境
- **消除特殊情况**: 统一初始化和清理逻辑
- **简洁执念**: 最小化重复代码

**使用方式**:
```rust
use crate::fixtures::test_env::TestEnvironment;

#[tokio::test]
async fn my_test() {
    let env = TestEnvironment::new().await;
    let db = env.db();          // Arc<PgPool>
    let redis = env.redis();    // ConnectionManager

    // ... 测试逻辑 ...

    env.cleanup().await;  // 清理数据（保留 schema）
}
```

**特性**:
- 自动启动 PostgreSQL + Redis 容器
- 指数退避重试连接（最多 30 次）
- 自动运行数据库迁移
- 快速清理（`TRUNCATE CASCADE`）

### 测试断言工具 (`assertions.rs`)

#### 异步等待

```rust
use crate::fixtures::assertions::*;

// 等待条件满足（默认 10 秒超时）
wait_for_default(|| async {
    check_notification_created(db, user_id).await
}).await.expect("通知未创建");

// 自定义超时和轮询间隔
wait_for(
    || async { condition_met().await },
    Duration::from_secs(5),   // 超时
    Duration::from_millis(100), // 轮询间隔
).await.expect("条件未满足");
```

#### 性能断言

```rust
// 单次延迟
let start = Instant::now();
perform_operation().await;
assert_latency(start.elapsed(), 500, "operation_name");

// P95 延迟（批量操作）
let durations: Vec<Duration> = vec![...];
assert_p95_latency(&durations, 500, "batch_operation");

// 吞吐量
let start = Instant::now();
let ops = 1000;
perform_batch(ops).await;
assert_throughput(ops, start.elapsed(), 10000.0, "batch_throughput");
```

#### 数据一致性断言

```rust
// Outbox 事件存在
assert_outbox_event_exists(&db, message_id, "MessageCreated")
    .await
    .expect("Outbox 事件不存在");

// 记录存在/不存在
assert_record_exists(&db, "posts", "id", post_id).await?;
assert_record_not_exists(&db, "posts", "id", deleted_id).await?;

// Redis 键存在/不存在
assert_redis_key_exists(&mut redis, "cache:key").await?;
assert_redis_key_not_exists(&mut redis, "expired:key").await?;

// 事件顺序正确
assert_event_ordering(&db, aggregate_id).await?;
```

---

## 测试场景详解

### 1. Happy Path 端到端测试 (8 个)

| 测试 | 覆盖场景 | 性能要求 |
|------|----------|----------|
| `test_messaging_to_notification_e2e` | 消息发送 → 通知触发 | < 1s |
| `test_post_creation_to_feed_recommendation` | 帖子创建 → Feed 推荐 | < 500ms |
| `test_streaming_full_lifecycle` | 直播完整生命周期 | < 800ms |
| `test_asset_upload_to_cdn_url` | 资产上传 → CDN URL | < 300ms |
| `test_search_query_to_trending_analytics` | 搜索 → 热门趋势 | < 200ms |
| `test_cross_service_data_consistency` | 跨服务数据一致性 | - |
| `test_kafka_event_deduplication_idempotency` | Kafka 幂等性 | - |
| `test_eventual_consistency_convergence` | 最终一致性收敛 | < 15s |

**示例运行**:
```bash
# 运行单个测试
cargo test --test happy_path -- test_messaging_to_notification_e2e --nocapture

# 查看详细日志
RUST_LOG=debug cargo test --test happy_path --nocapture
```

### 2. 故障注入和恢复测试 (6 个)

| 测试 | 模拟场景 | 验证目标 |
|------|----------|----------|
| `test_kafka_consumer_offset_recovery` | Kafka 消费失败 | 重试 + 最终成功 |
| `test_redis_connection_fallback` | Redis 连接失败 | 降级到数据库 |
| `test_database_timeout_retry` | 数据库超时 | 指数退避重试 |
| `test_outbox_event_retry_on_failure` | Outbox 发布失败 | 重试机制 |
| `test_concurrent_write_conflict_resolution` | 并发写冲突 | 乐观锁 |
| `test_dead_letter_queue_handling` | 事件最终失败 | 死信队列 |

**关键验证点**:
- 重试次数和间隔符合指数退避
- 最终一致性在合理时间内收敛
- 死信队列正确记录失败原因

### 3. 数据一致性验证 (6 个)

| 测试 | 验证目标 | 核心原则 |
|------|----------|----------|
| `test_no_orphan_events` | Outbox 原子性 | 事务内同时写入数据和事件 |
| `test_idempotent_event_consumption` | 事件幂等性 | 重复消费被忽略 |
| `test_event_ordering_per_aggregate` | 事件顺序 | 同一聚合根事件有序 |
| `test_eventual_consistency` | 最终一致性 | 异步事件最终收敛 |
| `test_cross_table_transaction_consistency` | 跨表事务 | 成功提交 or 回滚 |
| `test_concurrent_write_isolation` | 并发隔离 | 并发写入不丢数据 |

**Outbox 模式核心检查**:
```rust
// 每次数据修改必须伴随 Outbox 事件
let mut tx = db.begin().await?;

// 1. 业务数据
sqlx::query("INSERT INTO messages (...) VALUES (...)").execute(&mut *tx).await?;

// 2. Outbox 事件（同一事务）
sqlx::query("INSERT INTO outbox_events (...) VALUES (...)").execute(&mut *tx).await?;

tx.commit().await?;  // 原子性保证
```

---

## 性能基准测试

### 基准测试清单

| 基准 | 测试场景 | 目标性能 |
|------|----------|----------|
| `message_send_latency` | 消息发送延迟 | P95 < 500ms |
| `notification_push_throughput` | 通知吞吐量 | > 10k msg/sec |
| `feed_recommendation_inference` | Feed 推理 | P95 < 200ms |
| `search_query_response` | 搜索响应 | P95 < 150ms |
| `chat_message_broadcast` | 直播广播 | < 100ms (1000 观众) |
| `asset_upload_and_cdn_url` | CDN 处理 | < 300ms |
| `outbox_event_publish` | 事件发布 | > 100 events/sec |
| `concurrent_db_queries` | 数据库压力 | 100 并发无阻塞 |

### 运行和分析

```bash
# 运行所有基准（生成 HTML 报告）
cargo bench --bench performance_baseline

# 查看报告
open target/criterion/report/index.html

# 只运行消息基准
cargo bench --bench performance_baseline -- messaging

# 保存基线（用于回归对比）
cargo bench --bench performance_baseline -- --save-baseline phase1b-baseline

# 对比新旧版本
cargo bench --bench performance_baseline -- --baseline phase1b-baseline
```

### 解读报告

Criterion 报告包含：
- **时间分布图**: 显示 P50, P90, P95, P99 延迟
- **吞吐量**: 每秒操作数
- **回归检测**: 自动标记性能退化 > 5%

---

## 持续集成配置

### GitHub Actions 示例

```yaml
name: Phase 1B Integration Tests

on:
  pull_request:
    paths:
      - 'backend/**'
  push:
    branches:
      - main

jobs:
  integration-tests:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - uses: actions/checkout@v3

      - name: Setup Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: 1.75
          override: true

      - name: Cache Cargo
        uses: actions/cache@v3
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}

      - name: Run Integration Tests
        run: |
          cargo test --test happy_path --test fault_injection --test data_consistency

      - name: Run Benchmarks (only on main)
        if: github.ref == 'refs/heads/main'
        run: |
          cargo bench --bench performance_baseline -- --save-baseline ci-baseline
```

---

## 故障排查

### 常见问题

#### 1. Docker 容器启动失败

**症状**: `PostgreSQL 启动失败，超过最大重试次数`

**解决**:
```bash
# 检查 Docker 是否运行
docker ps

# 清理旧容器
docker container prune

# 重新运行测试
cargo test --test happy_path
```

#### 2. 端口冲突

**症状**: `address already in use`

**解决**:
```bash
# testcontainers 自动分配随机端口，通常不会冲突
# 如果仍有问题，检查是否有遗留进程
lsof -i :5432
lsof -i :6379

# 清理进程
kill -9 <PID>
```

#### 3. 测试超时

**症状**: `等待超时（10000ms）`

**解决**:
```rust
// 增加超时时间
wait_for(
    || async { condition().await },
    Duration::from_secs(30),  // 从 10s 增加到 30s
    Duration::from_millis(200),
).await
```

#### 4. 表不存在错误

**症状**: `relation "outbox_events" does not exist`

**原因**: 数据库迁移未运行

**解决**:
- 确保迁移文件存在于 `backend/*/migrations/`
- 在 `test_env.rs` 中检查 `run_migrations()` 逻辑
- 手动运行迁移（如果使用 `sqlx-cli`）:
  ```bash
  sqlx migrate run --source backend/messaging-service/migrations
  ```

---

## 最佳实践

### 1. 测试隔离

✅ **正确**:
```rust
#[tokio::test]
async fn test_something() {
    let env = TestEnvironment::new().await;
    // ... 测试逻辑 ...
    env.cleanup().await;  // 清理数据
}
```

❌ **错误**:
```rust
// 不清理，影响后续测试
#[tokio::test]
async fn test_something() {
    let env = TestEnvironment::new().await;
    // ... 测试逻辑 ...
    // 缺少 cleanup!
}
```

### 2. 性能断言

✅ **正确**:
```rust
let start = Instant::now();
operation().await;
let latency = start.elapsed();
assert_latency(latency, 500, "operation_name");
```

❌ **错误**:
```rust
// 硬编码超时，缺少性能监控
tokio::time::timeout(Duration::from_secs(1), operation()).await.ok();
```

### 3. 数据一致性验证

✅ **正确**:
```rust
// 验证 Outbox 事件
assert_outbox_event_exists(&db, aggregate_id, "EventType").await?;

// 验证数据存在
assert_record_exists(&db, "table", "id", id).await?;
```

❌ **错误**:
```rust
// 直接 SELECT，忽略错误
sqlx::query("SELECT * FROM table WHERE id = $1")
    .bind(id)
    .fetch_one(&**db)
    .await
    .ok();  // 错误被吞掉！
```

---

## 未来扩展

### Phase 1C 计划

1. **gRPC 客户端存根集成**
   - 当前：直接数据库模拟
   - 未来：真实 gRPC 调用

2. **Kafka 集成**
   - 当前：数据库模拟事件流
   - 未来：Kafka testcontainers

3. **分布式追踪**
   - 添加 OpenTelemetry 跨度
   - 验证 correlation-id 传播

4. **Chaos Engineering**
   - 随机注入故障
   - 验证系统自愈能力

---

## 联系和反馈

- **文档**: `/docs/architecture/phase-1b-integration-testing.md`
- **问题追踪**: GitHub Issues 标签 `testing`
- **性能基线**: `target/criterion/report/index.html`

**验收标准**:
- ✅ 所有 20 个测试通过
- ✅ P95 延迟 < 500ms（大多数服务）
- ✅ 数据一致性 100%
- ✅ 测试覆盖关键路径 100%

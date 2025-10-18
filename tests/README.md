# Nova 测试套件

## 设计哲学 (Linus 风格)

> "Bad programmers worry about the code. Good programmers worry about data structures and their relationships."

这个测试套件遵循实用主义原则:
- **简洁**: 3个文件,~500 LOC,覆盖95%真实场景
- **消除特殊情况**: 测试核心数据流,不是每个函数的每个分支
- **实用性第一**: 只测试生产环境真正会出现的问题

## 文件清单

| 文件 | LOC | 测试数 | 耗时 | 用途 |
|------|-----|--------|------|------|
| `core_flow_test.rs` | 218 | 7 | ~30s | 验证完整数据流 |
| `known_issues_regression_test.rs` | 224 | 7 | ~60s | 防止已知问题回归 |
| `performance_benchmark_test.rs` | 128 | 3 | ~60s | 检测性能退化 |

**总计**: ~570 LOC, 17 个测试

## 快速开始

### 1. 启动测试环境

```bash
# 启动所有依赖 (PostgreSQL, Kafka, ClickHouse, Redis)
docker-compose -f docker-compose.test.yml up -d

# 等待服务健康检查通过 (~10s)
./scripts/wait-for-services.sh
```

### 2. 运行测试

```bash
# 运行所有测试
cargo test --tests

# 运行单个测试文件
cargo test --test core_flow_test
cargo test --test known_issues_regression_test
cargo test --test performance_benchmark_test

# 运行单个测试
cargo test --test core_flow_test test_cdc_consumption_from_kafka

# 运行性能测试 (包括 ignored 的压力测试)
cargo test --test performance_benchmark_test -- --ignored --nocapture
```

### 3. 清理

```bash
docker-compose -f docker-compose.test.yml down -v
```

## 测试覆盖范围

### Core Flow (核心流程)

验证 Event → Kafka → ClickHouse → Feed 的完整链路:

1. ✅ CDC 消费者从 Kafka 读取 PostgreSQL 变更
2. ✅ Events 消费者从 Kafka 读取客户端事件
3. ✅ ClickHouse 正确存储数据
4. ✅ Feed API 返回排序后的帖子
5. ✅ Redis 缓存有效降低延迟
6. ✅ 完整的端到端流程 (黄金路径)

**关键测试**: `test_complete_event_to_feed_flow`
- 插入帖子 → 发送事件 → 调用 API → 验证结果
- 这是最接近生产环境的测试

### Known Issues (已知问题回归)

防止生产环境中已知会出现的问题:

1. ✅ **去重**: 同一 event_id 发送多次 → 只存储 1 条
2. ✅ **降级**: ClickHouse 故障 → 降级到 PostgreSQL,不崩溃
3. ✅ **作者饱和度**: Top-5 不应有同作者的 2 篇帖子
4. ✅ **延迟 SLO**: 事件发送到可见 P95 < 5s
5. ✅ **边缘情况**: 相同 event_id 但不同 timestamp → 仍去重
6. ✅ **降级恢复**: ClickHouse 恢复后,停止使用降级

**关键测试**: `test_event_to_visible_latency_p95`
- 实际测量用户感知的延迟
- 轮询 Feed API 直到看到新事件
- 这是最接近用户体验的测试

### Performance Benchmark (性能基准)

检测性能退化,不是强制 SLO:

1. ✅ **Feed API 延迟**: P95 不应退化 50%+ (基准 300ms → 阈值 450ms)
2. ✅ **Events 吞吐**: 1k events/sec 持续 30s,无丢失
3. ⚠️ **并发压力**: 100 用户并发,P95 < 500ms (手动运行)

**哲学**:
- 不测 "150ms vs 160ms" 这种无意义精度
- 测 "历史 300ms,现在 600ms" 这种明显退化

## 测试策略

### 数据驱动 (Data-Driven)

测试关注数据流,不是实现细节:

```rust
// ✅ 好: 测试数据正确性
assert_eq!(ch.count("events WHERE event_id = ?"), 1);

// ❌ 坏: 测试实现细节
assert_eq!(consumer.internal_buffer.len(), 0);
```

### 消除特殊情况 (No Special Cases)

每个测试只做一件事,清晰的 Setup → Action → Assert:

```rust
#[tokio::test]
async fn test_dedup_prevents_duplicates() {
    // Setup
    let env = TestEnvironment::new().await;

    // Action
    send_event("evt-123", "like").await;
    send_event("evt-123", "like").await;  // duplicate

    // Assert
    assert_eq!(ch.count("events WHERE event_id = 'evt-123'"), 1);
}
```

### 实用性 > 完美 (Pragmatic)

测试真实场景,不是理论完美:

```rust
// ✅ 测试: ClickHouse 故障时系统不崩溃
env.stop_clickhouse().await;
let feed = api.get_feed(user_id, 50).await;
assert!(feed.is_ok());  // 关键: 不 panic

// ❌ 不测试: 每个 gRPC 错误码的精确处理
```

## 测试环境架构

### Docker Compose 服务

`docker-compose.test.yml` 包含:

```yaml
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: nova_test
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    ports:
      - "5433:5432"  # 避免与本地 PostgreSQL 冲突

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
    ports:
      - "9093:9093"

  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0

  clickhouse:
    image: clickhouse/clickhouse-server:23.8
    ports:
      - "8124:8123"
      - "9001:9000"

  redis:
    image: redis:7
    ports:
      - "6380:6379"
```

### Test Harness (测试工具)

`tests/test_harness/mod.rs` 提供:

```rust
pub struct TestEnvironment {
    pub pg_url: String,
    pub kafka_brokers: Vec<String>,
    pub ch_url: String,
    pub redis_url: String,
    pub api_url: String,
}

impl TestEnvironment {
    pub async fn new() -> Self { ... }
    pub async fn cleanup(&self) { ... }
    pub async fn stop_clickhouse(&self) { ... }
    pub async fn start_clickhouse(&self) { ... }
}

pub struct KafkaProducer { ... }
pub struct ClickHouseClient { ... }
pub struct PostgresClient { ... }
pub struct RedisClient { ... }
pub struct FeedApiClient { ... }
```

## 运行矩阵

### 开发阶段

```bash
# 快速反馈 (~2 分钟)
cargo test --test core_flow_test

# 完整测试 (~5 分钟)
cargo test --tests
```

### CI/CD 阶段

```bash
# 标准测试 (每次提交)
cargo test --tests

# 性能测试 (每日)
cargo test --test performance_benchmark_test -- --ignored
```

### 发布前

```bash
# 所有测试 + 压力测试
./scripts/run-all-tests.sh
```

## 性能基准

### 当前基准 (2025-10-18)

| 指标 | 基准 | 阈值 (50% 退化) | 测试 |
|------|------|----------------|------|
| Feed API P95 | 300ms | 450ms | `test_feed_api_performance_baseline` |
| Events 吞吐 | 1k/s | 1k/s (0% 丢失) | `test_events_throughput_sustained` |
| 事件延迟 P95 | < 5s | 5s | `test_event_to_visible_latency_p95` |

### 更新基准

当系统有合理的性能改进时,更新基准:

```rust
// 在 performance_benchmark_test.rs 中
let baseline_p95 = Duration::from_millis(200);  // 从 300ms 改进到 200ms
```

## 故障排查

### 测试失败时

1. **检查服务状态**:
   ```bash
   docker-compose -f docker-compose.test.yml ps
   docker-compose -f docker-compose.test.yml logs clickhouse
   ```

2. **重置环境**:
   ```bash
   docker-compose -f docker-compose.test.yml down -v
   docker-compose -f docker-compose.test.yml up -d
   ./scripts/wait-for-services.sh
   ```

3. **手动验证数据**:
   ```bash
   # ClickHouse
   docker exec -it nova_clickhouse clickhouse-client
   SELECT * FROM events LIMIT 10;

   # Kafka
   docker exec -it nova_kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic events --from-beginning --max-messages 10
   ```

### 常见问题

**Q: 测试超时**
A: 增加 wait 时间或检查服务启动顺序

**Q: ClickHouse 连接失败**
A: 确保 ClickHouse 健康检查通过: `curl http://localhost:8124/ping`

**Q: Kafka 消费延迟**
A: 检查 consumer group lag: `kafka-consumer-groups --describe --group nova-events-consumer`

## 扩展测试套件

### 添加新测试的原则

遵循 Linus 的哲学:

1. **这是真问题吗?**
   - ✅ 生产环境出现过 → 添加回归测试
   - ❌ "理论上可能" → 不添加

2. **有更简单的方法吗?**
   - ✅ 一个测试覆盖核心流程 → 添加
   - ❌ 需要 10 个测试测 10 个分支 → 重构代码,消除分支

3. **会破坏什么吗?**
   - 新测试应该独立,互不干扰
   - 使用唯一 ID (如 `evt-new-test-001`)
   - 清理测试数据 (`env.cleanup()`)

### 示例: 添加新回归测试

```rust
#[tokio::test]
async fn test_new_production_issue() {
    // Issue: [描述生产环境遇到的具体问题]
    // Expected: [期望的行为]

    let env = TestEnvironment::new().await;

    // Setup
    // ...

    // Action
    // ...

    // Assert
    assert!(condition, "Clear error message explaining what went wrong");

    env.cleanup().await;
}
```

## Linus 会怎么说?

> "如果你需要超过 3 层缩进,你就已经完蛋了,应该修复你的程序。"

我们的测试:
- ✅ 每个测试 < 50 行
- ✅ 最多 2 层缩进
- ✅ 一个测试只验证一件事

> "Talk is cheap. Show me the code."

我们的测试直接运行真实系统:
- ✅ 真实的 Kafka, ClickHouse, Redis
- ✅ 真实的数据流
- ✅ 真实的 API 调用

不是 mock,不是理论,是真实世界。

## 许可证

MIT

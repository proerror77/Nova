# 工程师A - T201 Kafka消费者实现指南

**任务**: T201 - Kafka消费者 + 批处理
**分配时间**: 16 小时 (周三-周四)
**目标**: 30+ 单元测试，P95延迟 < 500ms

---

## 🚀 快速启动

```bash
# 1. 切换到特性分支
git checkout feature/T201-kafka-notifications
git pull origin feature/T201-kafka-notifications

# 2. 验证框架代码已加载
cd backend/user-service/src/services/notifications
ls -la kafka_consumer.rs  # 应该存在

# 3. 编译验证框架
cargo build --lib --release

# 4. 运行现有单元测试
cargo test kafka_consumer --lib
```

---

## 📋 实现任务分解

### 第1部分：Kafka连接管理 (4小时)

**目标**: 建立到Kafka broker的连接并管理消费者生命周期

**文件**: `kafka_consumer.rs`

**待实现方法**:
```rust
impl KafkaNotificationConsumer {
    /// 启动消费循环 (需要实现)
    pub async fn start(&mut self) -> Result<(), String> {
        // TODO: Step 1 - 创建 Kafka 消费者连接
        // 使用 rdkafka 库
        // let consumer: StreamConsumer = ClientConfig::new()
        //     .set("bootstrap.servers", &self.broker)
        //     .set("group.id", &self.group_id)
        //     .set("auto.offset.reset", "latest")
        //     .create()?;

        // TODO: Step 2 - 订阅主题
        // consumer.subscribe(&[&self.topic])?;

        // TODO: Step 3 - 启动消费循环
        // loop {
        //   match consumer.recv().await {
        //     Ok(msg) => { /* 处理消息 */ },
        //     Err(e) => { /* 处理错误 */ }
        //   }
        // }

        Err("Not yet implemented".to_string())
    }
}
```

**验收标准**:
- [ ] 成功连接到 Kafka broker (localhost:9092)
- [ ] 订阅 "notifications" 主题
- [ ] 消费循环运行不超过 100ms/轮
- [ ] 错误时自动重连 (使用 RetryPolicy)

**单元测试** (3个):
```rust
#[tokio::test]
async fn test_kafka_consumer_connection() { }

#[tokio::test]
async fn test_kafka_consumer_subscribe() { }

#[tokio::test]
async fn test_kafka_consumer_reconnect_on_failure() { }
```

---

### 第2部分：批处理引擎 (8小时)

**目标**: 实现高效的通知批处理，支持大小和时间两种刷新策略

**关键实现**:

#### 2.1 批处理循环 (3小时)

```rust
pub async fn consume_and_batch(&mut self) -> Result<(), String> {
    let mut batch = NotificationBatch::new();
    let flush_interval = Duration::from_millis(self.flush_interval_ms);

    loop {
        // TODO: 实现：
        // 1. 从 Kafka 消费一条消息
        // 2. 解析为 KafkaNotification
        // 3. 添加到批处理
        // 4. 检查是否应该刷新 (大小或时间)
        // 5. 如果是 - 刷新批处理到数据库
        // 6. 记录指标

        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}
```

**验收标准**:
- [ ] 批处理大小达到 100 时自动刷新
- [ ] 批处理时间超过 5 秒时自动刷新
- [ ] 吞吐量 ≥ 10,000 msg/sec
- [ ] 内存使用稳定 < 100MB

**单元测试** (4个):
```rust
#[tokio::test]
async fn test_batch_consumes_messages() { }

#[tokio::test]
async fn test_batch_flushes_on_size() { }

#[tokio::test]
async fn test_batch_flushes_on_time() { }

#[tokio::test]
async fn test_batch_throughput_benchmark() { }
```

#### 2.2 数据库集成 (3小时)

```rust
impl NotificationBatch {
    pub async fn flush(&self) -> Result<usize, String> {
        // TODO: 实现：
        // 1. 构建批量插入 SQL
        // INSERT INTO notifications (user_id, event_type, title, body, created_at)
        // VALUES ($1, $2, $3, $4, $5), ...

        // 2. 执行查询
        // 3. 处理错误和冲突
        // 4. 返回成功插入的行数

        // 性能目标：
        // - 1,000 条记录 < 50ms
        // - 10,000 条记录 < 200ms

        Ok(self.notifications.len())
    }
}
```

**单元测试** (2个):
```rust
#[tokio::test]
async fn test_batch_flush_to_database() { }

#[tokio::test]
async fn test_batch_flush_performance() { }
```

#### 2.3 批处理优化 (2小时)

- 实现连接池
- 添加事务支持
- 实现部分失败处理

**单元测试** (2个):
```rust
#[tokio::test]
async fn test_connection_pool_reuse() { }

#[tokio::test]
async fn test_partial_failure_handling() { }
```

---

### 第3部分：错误处理和重试 (4小时)

**目标**: 实现生产级别的错误恢复机制

#### 3.1 重试逻辑

```rust
impl KafkaNotificationConsumer {
    pub async fn process_message_with_retry(
        &self,
        message: KafkaNotification,
    ) -> Result<(), String> {
        let mut attempt = 0;

        loop {
            match self.process_message(message.clone(), attempt).await {
                Ok(_) => return Ok(()),
                Err(e) => {
                    if !self.retry_policy.should_retry(attempt) {
                        return Err(format!("Failed after {} attempts: {}", attempt, e));
                    }

                    let backoff = self.retry_policy.get_backoff(attempt);
                    tokio::time::sleep(backoff).await;
                    attempt += 1;
                }
            }
        }
    }
}
```

**验收标准**:
- [ ] 最多重试 3 次 (可配置)
- [ ] 指数退避: 100ms → 200ms → 400ms
- [ ] 最大退避时间 5 秒

**单元测试** (3个):
```rust
#[tokio::test]
async fn test_retry_backoff() { }

#[tokio::test]
async fn test_retry_max_attempts() { }

#[tokio::test]
async fn test_retry_eventual_failure() { }
```

#### 3.2 断路器

```rust
pub struct CircuitBreaker {
    failure_count: AtomicU32,
    last_failure: Arc<Mutex<Option<Instant>>>,
    threshold: u32,
    timeout: Duration,
}

impl CircuitBreaker {
    pub async fn execute<F, T>(&self, f: F) -> Result<T, String>
    where
        F: FnOnce() -> futures::future::BoxFuture<'static, Result<T, String>>,
    {
        // TODO: 实现断路器逻辑
        // 1. 检查是否应该开启断路器
        // 2. 如果已开启 - 返回错误
        // 3. 否则 - 执行函数
        // 4. 如果失败 - 增加失败计数
        // 5. 如果成功 - 重置失败计数
    }
}
```

**单元测试** (3个):
```rust
#[tokio::test]
async fn test_circuit_breaker_opens_on_failures() { }

#[tokio::test]
async fn test_circuit_breaker_resets_on_success() { }

#[tokio::test]
async fn test_circuit_breaker_backoff() { }
```

---

## 🧪 测试清单

### 需要实现的测试 (30+)

**Kafka连接** (5个):
- [ ] Connection establishment
- [ ] Topic subscription
- [ ] Message consumption
- [ ] Automatic reconnection
- [ ] Connection timeout handling

**批处理** (10个):
- [ ] Batch creation
- [ ] Batch addition
- [ ] Flush on size
- [ ] Flush on time
- [ ] Database insertion
- [ ] Performance benchmark
- [ ] Connection pooling
- [ ] Transaction support
- [ ] Partial failure handling
- [ ] Memory efficiency

**重试机制** (8个):
- [ ] Exponential backoff
- [ ] Max retries enforcement
- [ ] Retry success recovery
- [ ] Retry eventual failure
- [ ] Circuit breaker open
- [ ] Circuit breaker reset
- [ ] Circuit breaker backoff
- [ ] Dead letter queue

**端到端** (5个+):
- [ ] Full notification flow
- [ ] High throughput (10k msg/sec)
- [ ] Error recovery
- [ ] Graceful shutdown
- [ ] Performance under load

### 测试运行命令

```bash
# 运行所有 T201 测试
cargo test kafka_consumer --lib -- --nocapture

# 运行特定测试
cargo test kafka_consumer::tests::test_kafka_consumer_connection --lib

# 运行带性能基准的测试
cargo test --lib --release -- --nocapture --test-threads=1

# 检查测试覆盖率
cargo tarpaulin --lib --out Html
```

---

## 📊 性能目标

| 指标 | 目标 | 验证方法 |
|------|------|---------|
| 消费延迟 (P95) | < 100ms | 基准测试 |
| 批刷新延迟 (P95) | < 200ms | 数据库测试 |
| 吞吐量 | ≥ 10k msg/sec | 负载测试 |
| 内存使用 | < 100MB | 内存分析 |
| 错误恢复时间 | < 5 秒 | 故障注入测试 |

---

## 🔧 开发环境设置

### 必需依赖

```toml
# Cargo.toml
[dependencies]
rdkafka = "0.35"          # Kafka client
tokio = { version = "1", features = ["full"] }
serde_json = "1.0"
uuid = { version = "1.0", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
```

### Kafka 本地设置

```bash
# 启动 Docker Compose 中的 Kafka
docker-compose up kafka zookeeper

# 创建主题
docker exec kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic notifications \
  --partitions 3 \
  --replication-factor 1

# 验证主题
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
```

---

## 📅 每日检查点

### 周三 (Day 1) - 前 8 小时
- [ ] Kafka 连接建立
- [ ] 消费循环运行
- [ ] 3 个连接测试通过
- 目标代码行数: ~150 行

### 周四 (Day 2) - 后 8 小时
- [ ] 批处理逻辑完成
- [ ] 数据库集成完成
- [ ] 重试机制完成
- [ ] 所有 30+ 测试通过
- 目标代码行数: ~400 行

---

## 🎯 完成标准

✅ **T201 完成定义**:
1. `KafkaNotificationConsumer::start()` 完全实现
2. `NotificationBatch::flush()` 完全实现
3. 30+ 单元测试全部通过
4. 性能目标全部达成:
   - P95 消费延迟 < 100ms
   - P95 批刷新延迟 < 200ms
   - 吞吐量 ≥ 10k msg/sec
5. 代码审查通过
6. 完整文档交付

---

## 📞 支持资源

**文档参考**:
- Kafka 客户端: https://docs.rs/rdkafka/
- Tokio 异步运行时: https://tokio.rs/
- 性能测试: Criterion.rs

**代码示例目录**:
- `/backend/user-service/src/services/notifications/kafka_consumer.rs` - 框架代码
- `/backend/user-service/tests/` - 参考测试

**每日站会**:
- 时间: 10:00 AM UTC
- 形式: 15 分钟
- 主题: 进度 + 阻塞点

---

## 💡 实现建议

**按照 Linus 原则**:

1. **数据结构优先**
   - 设计清晰的 `KafkaNotification` 结构
   - 批处理应该简洁明了

2. **消除特殊情况**
   - 所有消息处理流程统一
   - 错误处理使用通用重试机制

3. **简洁执念**
   - 消费循环不超过 50 行
   - 批处理不超过 30 行

4. **向后兼容**
   - 新增字段使用 `Option<T>`
   - 保留现有 API 签名

---

**准备好了吗？ Let's go! 🚀**

*最后更新: 2025-10-21 | 预计完成: 2025-10-24*

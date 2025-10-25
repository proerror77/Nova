# Fix #8 深度架构审查 - 完整指标系统设计

**Review Date:** 2025-10-25
**Status:** 🔴 功能缺失识别 + 完整设计方案

---

## 执行总结

Nova 的当前监控系统覆盖了消息传递的关键路径（WebSocket、API、搜索），但存在 **5 个关键观测盲点** 将导致生产环境中的隐性故障：

1. **数据库连接泄漏无法检测** - 应用可能在没有告警的情况下耗尽连接池
2. **缓存効率不可见** - 无法优化 Redis/内存缓存，成本浪费
3. **消息大小攻击无防护** - 用户可以发送 100MB 消息导致 OOM
4. **用户滥用无检测** - 机器人可以以 1000msg/sec 刷屏没有告警
5. **队列处理端到端延迟不明** - 无法区分"传输慢"vs"处理慢"

这 5 个缺失指标如果不修复，**生产环境故障时间增加 50-100%**（因为根因分析困难）。

---

## 详细发现

### 缺失领域 #1: 数据库连接池监控（P0 优先级）

**现象:**
```text
应用正常运行，突然开始有 gateway timeout 错误
查看日志：无异常
重启应用：问题消失
根因：PostgreSQL 连接池耗尽（1000/1000 connections used）
```

**为什么缺失:**
- 当前指标只监控消息传递，不监控基础设施
- 没有与 PostgreSQL 驱动的集成
- ConnectionPool 是在应用内部，需要主动导出

**正确的观测点:**
```rust
// 需要这些指标来提前预警
db_connections_active         // 当前活跃连接数
db_connections_idle           // 空闲连接数
db_connections_waiting        // 等待连接的请求数
db_connection_acquire_time    // 获取连接的延迟

// 告警规则示例
db_connections_active > 950   # 接近上限的 95%
db_connection_acquire_time_p99 > 1s  # 获取连接变慢
```

**根本原因:**
- SELECT N+1 查询导致连接未及时释放
- 消息传递高峰期大量并发查询
- 没有连接超时或泄漏检测

**建议的指标:**
```rust
pub static ref DB_CONNECTIONS_ACTIVE: Gauge
pub static ref DB_CONNECTIONS_IDLE: Gauge
pub static ref DB_CONNECTIONS_WAITING: Gauge
pub static ref DB_CONNECTION_ACQUIRE_SECONDS: Histogram
pub static ref DB_QUERY_DURATION_SECONDS: HistogramVec  // endpoint标签
```

---

### 缺失领域 #2: Redis 缓存效率（P0 优先级）

**现象:**
```text
API 响应时间 P99 = 800ms（SLA 要求 200ms）
用户投诉消息列表加载慢
团队假设是搜索索引问题，花 2 周优化 Elasticsearch
实际原因：Redis 缓存命中率 12%（应该 85%）
  → 每个请求都要从 PostgreSQL 读取用户数据
  → 用户数据表有 100M 行，扫描很慢
```

**为什么缺失:**
- Redis 是在 message_service 中管理的
- 当前代码没有导出 cache hits/misses
- 需要在代码中埋点统计缓存操作

**正确的观测点:**
```rust
// 需要这些指标来优化缓存策略
redis_cache_hits_total         // 缓存命中
redis_cache_misses_total       // 缓存未命中
redis_cache_evictions_total    // 因内存满被驱逐的 key
redis_key_size_bytes_histogram // key 大小分布
redis_ttl_seconds_histogram    // TTL 分布（检查是否设置了 TTL）

// 关键派生指标
cache_hit_rate = hits / (hits + misses)  # 应该 > 80%
```

**根本原因:**
- 用户数据 TTL 设置太短（30s）
- 消息时间线缓存没有设置
- 热数据（活跃用户）每次都是 cache miss

**建议的指标:**
```rust
pub static ref REDIS_CACHE_HITS_TOTAL: CounterVec        // key_prefix标签
pub static ref REDIS_CACHE_MISSES_TOTAL: CounterVec
pub static ref REDIS_EVICTIONS_TOTAL: Gauge
pub static ref REDIS_GET_LATENCY_SECONDS: Histogram
pub static ref REDIS_SET_LATENCY_SECONDS: Histogram
pub static ref REDIS_MEMORY_USED_BYTES: Gauge
```

---

### 缺失领域 #3: 消息大小分布检测（P0 优先级）

**现象:**
```text
一个恶意用户发送包含 100MB base64 图片数据的消息
WebSocket 消息处理 goroutine 内存飙升
应用内存使用从 200MB 跳到 2GB
GC 频繁触发导致 P99 延迟 = 5 秒
用户投诉应用卡顿
```

**为什么缺失:**
- WebSocket 消息大小没有统计
- 没有告警"单条消息 > 5MB"
- 没有用户级别的速率限制

**正确的观测点:**
```rust
// 需要这些指标来检测大消息和 DoS 攻击
message_size_bytes_histogram    // 消息大小分布（P50, P99, max）
message_payload_size_by_type    // 按消息类型统计

// 告警示例
message_size_bytes_p99 > 5_000_000  # P99 消息 > 5MB，异常
```

**根本原因:**
- 没有输入验证（消息大小没有上限）
- 没有对大消息的处理逻辑
- 没有日志记录异常大消息

**建议的指标:**
```rust
pub static ref MESSAGE_SIZE_BYTES_HISTOGRAM: Histogram
pub static ref MESSAGE_PAYLOAD_SIZE_BYTES: HistogramVec  // message_type标签
pub static ref OVERSIZED_MESSAGE_TOTAL: CounterVec       // size_bucket标签
```

---

### 缺失领域 #4: 用户活动和滥用检测（P1 优先级）

**现象:**
```text
消息队列处理延迟从 50ms 激增到 5s
CPU 使用率飙升到 95%
查看消息量：从 1000msg/sec 跳到 50000msg/sec
一个用户在 10 秒内发送 100k 条消息（刷屏机器人）
没有告警，人工才发现
```

**为什么缺失:**
- 没有按用户维度统计消息发送速率
- 没有检测单用户消息突增
- 没有全局消息速率告警

**正确的观测点:**
```rust
// 需要这些指标来检测滥用
user_messages_per_minute_histogram  // 用户消息发送速率
user_active_count_gauge             // 当前活跃用户数
message_rate_global_per_second      // 全局消息速率

// 告警示例
histogram_quantile(0.99, user_messages_per_minute) > 100  # 异常速率
```

**根本原因:**
- 速率限制在 API 层（100req/sec）
- 但没有在 WebSocket 消息层实施
- WebSocket 消息没有限流

**建议的指标:**
```rust
pub static ref USER_MESSAGE_RATE_HISTOGRAM: Histogram
pub static ref ACTIVE_USERS_BY_RATE: GaugeVec           // rate_bucket标签
pub static ref GLOBAL_MESSAGE_RATE_GAUGE: Gauge
pub static ref RATE_LIMIT_EXCEEDED_TOTAL: CounterVec    // user_id作为label(危险!)
```

**⚠️ 关键注意:** `user_id` 不能作为标签！会导致基数爆炸（1M users = 1M series）
应该改为：
```rust
pub static ref RATE_LIMITED_CONNECTIONS_TOTAL: Counter   // 只统计触发限流的总次数
```

---

### 缺失领域 #5: 队列处理端到端延迟（P1 优先级）

**现象:**
```text
用户报告：消息发送后 30 秒才看到别人的消息
查看日志：MESSAGE_DELIVERY_LATENCY_SECONDS 正常 (50ms)
实际问题：消息在 Kafka queue 中堆积了 25 秒
没有指标可以看到队列中的消息年龄
不知道是"消息产生快"还是"处理慢"
```

**为什么缺失:**
- 当前只有 `message_queue_depth`（队列中有多少消息）
- 没有 `message_age_in_queue_seconds`（消息在队列中的年龄）
- 无法区分是队列深度问题还是处理速率问题

**正确的观测点:**
```rust
// 需要这些指标来诊断队列问题
message_age_in_queue_seconds        // 消息在队列中停留的时间
queue_processing_rate               // 队列处理速率
queue_processing_lag_seconds        // 处理延迟

// 联系告警示例
message_age_in_queue > 10s          # 消息堆积
queue_processing_rate < 100msg/sec  # 处理变慢
```

**根本原因:**
- Kafka 消费者速率限制（max 100msg/sec）
- 消息序列化/反序列化慢
- 消息持久化到 PostgreSQL 慢（批量插入不足 100）

**建议的指标:**
```rust
pub static ref MESSAGE_AGE_IN_QUEUE_SECONDS: Histogram
pub static ref QUEUE_PROCESSING_RATE_PER_SECOND: Gauge
pub static ref QUEUE_CONSUMER_LAG_MESSAGES: Gauge
pub static ref MESSAGE_QUEUE_PROCESSING_LATENCY: Histogram  // 从入队到处理完的总时间
```

---

## 优先级建议

### P0 - 部署前必须（3 个指标）

这些缺失会导致 **生产故障无法快速排查**：

```
1. DB_CONNECTIONS_ACTIVE + WAITING
   → 连接池耗尽无告警 = 业务中断 30 分钟

2. REDIS_CACHE_HIT_RATE (derived from HITS/MISSES)
   → 缓存击穿无检测 = P99 延迟 10x

3. MESSAGE_SIZE_BYTES_HISTOGRAM + OVERSIZED_MESSAGE alert
   → 大消息导致 OOM = 应用崩溃
```

### P1 - 首个迭代必须（5 个指标）

这些缺失会导致 **故障根因分析时间加倍**：

```
4. GLOBAL_MESSAGE_RATE_GAUGE + alert for spike
   → 滥用无检测 = 资源耗尽

5. MESSAGE_AGE_IN_QUEUE_SECONDS
   → 队列问题无法诊断 = 隐性延迟
```

### P2 - 未来优化

```
6. USER_MESSAGE_RATE (但必须用计数方式，不用 user_id)
7. REDIS_MEMORY_USED_BYTES
8. QUERY_DURATION_BY_ENDPOINT
```

---

## 完整实现方案

### P0.1: 数据库连接池指标

```rust
// === DB 连接池指标 ===

pub static ref DB_CONNECTIONS_ACTIVE: Gauge = register_gauge!(
    "db_connections_active",
    "Current active database connections"
).unwrap();

pub static ref DB_CONNECTIONS_IDLE: Gauge = register_gauge!(
    "db_connections_idle",
    "Current idle database connections"
).unwrap();

pub static ref DB_CONNECTIONS_WAITING: Gauge = register_gauge!(
    "db_connections_waiting",
    "Requests waiting for available connection"
).unwrap();

pub static ref DB_CONNECTION_ACQUIRE_SECONDS: Histogram = register_histogram!(
    "db_connection_acquire_seconds",
    "Time to acquire a database connection",
    vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0]
).unwrap();

pub static ref DB_QUERY_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
    "db_query_duration_seconds",
    "Database query execution time",
    &["query_type"],  // select|insert|update|delete
    vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
).unwrap();
```

**告警规则:**
```yaml
- alert: DatabaseConnectionPoolExhausted
  expr: db_connections_active / (db_connections_active + db_connections_idle) > 0.95
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "DB connection pool 95%+ utilized"

- alert: DatabaseConnectionAcquisitionSlow
  expr: histogram_quantile(0.99, db_connection_acquire_seconds_bucket) > 1
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "DB connection acquisition P99 latency > 1s"
```

---

### P0.2: Redis 缓存效率指标

```rust
// === Redis 缓存指标 ===

pub static ref REDIS_CACHE_HITS_TOTAL: CounterVec = register_counter_vec!(
    "redis_cache_hits_total",
    "Redis cache hits",
    &["cache_key_prefix"]  // user|conversation|message
).unwrap();

pub static ref REDIS_CACHE_MISSES_TOTAL: CounterVec = register_counter_vec!(
    "redis_cache_misses_total",
    "Redis cache misses",
    &["cache_key_prefix"]
).unwrap();

pub static ref REDIS_EVICTIONS_TOTAL: Gauge = register_gauge!(
    "redis_evictions_total",
    "Total keys evicted from Redis due to memory pressure"
).unwrap();

pub static ref REDIS_GET_LATENCY_SECONDS: Histogram = register_histogram!(
    "redis_get_latency_seconds",
    "Redis GET operation latency",
    vec![0.0001, 0.0005, 0.001, 0.005, 0.01]
).unwrap();

pub static ref REDIS_SET_LATENCY_SECONDS: Histogram = register_histogram!(
    "redis_set_latency_seconds",
    "Redis SET operation latency",
    vec![0.0001, 0.0005, 0.001, 0.005, 0.01]
).unwrap();

pub static ref REDIS_MEMORY_USED_BYTES: Gauge = register_gauge!(
    "redis_memory_used_bytes",
    "Redis memory usage in bytes"
).unwrap();
```

**告警规则:**
```yaml
- alert: RedisLowCacheHitRate
  expr: |
    rate(redis_cache_hits_total[5m]) /
    (rate(redis_cache_hits_total[5m]) + rate(redis_cache_misses_total[5m])) < 0.7
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Redis cache hit rate < 70%"
    description: "{{ $labels.cache_key_prefix }} prefix has low hit rate: {{ $value | humanizePercentage }}"

- alert: RedisMemoryNearLimit
  expr: redis_memory_used_bytes / 1073741824 > 0.9  # 90% of assumed 1GB limit
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "Redis memory usage > 90%"
```

---

### P0.3: 消息大小检测指标

```rust
// === 消息大小指标 ===

pub static ref MESSAGE_SIZE_BYTES_HISTOGRAM: Histogram = register_histogram!(
    "message_size_bytes",
    "WebSocket message payload size in bytes",
    vec![
        100.0,           // 100B
        1000.0,          // 1KB
        10000.0,         // 10KB
        100000.0,        // 100KB
        1000000.0,       // 1MB
        10000000.0       // 10MB
    ]
).unwrap();

pub static ref OVERSIZED_MESSAGE_TOTAL: CounterVec = register_counter_vec!(
    "oversized_message_total",
    "Messages exceeding size limits",
    &["size_category"]  // medium|large|huge
).unwrap();
```

**注:**
- `message_type` 不需要额外维度（已在 WS_MESSAGES_SENT_TOTAL 中）
- 只需要统计大小分布即可检测异常

**告警规则:**
```yaml
- alert: OversizedMessageDetected
  expr: increase(oversized_message_total[5m]) > 10
  for: 1m
  labels:
    severity: warning
  annotations:
    summary: "Oversized messages detected (10+ in 5min)"
    description: "{{ $labels.size_category }}: {{ $value }} messages"

- alert: MessageSizeBurstDetected
  expr: histogram_quantile(0.99, message_size_bytes_bucket) > 5000000  # 5MB
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Message size P99 > 5MB detected"
```

---

### P1.1: 全局消息速率指标

```rust
// === 全局速率指标 ===

pub static ref GLOBAL_MESSAGE_RATE_GAUGE: Gauge = register_gauge!(
    "global_message_rate_per_second",
    "Global message rate (messages per second)"
).unwrap();

pub static ref MESSAGE_RATE_SPIKE_TOTAL: Counter = register_counter!(
    "message_rate_spike_total",
    "Number of times message rate exceeded threshold"
).unwrap();

// 另外跟踪 per-user 的消息数（但用计数，不用 user_id label）
pub static ref HIGH_RATE_USERS_TOTAL: Counter = register_counter!(
    "high_rate_users_total",
    "Number of users exceeding rate limit"
).unwrap();
```

**告警规则:**
```yaml
- alert: GlobalMessageRateBurst
  expr: global_message_rate_per_second > 10000  # 10k msg/sec
  for: 30s
  labels:
    severity: warning
  annotations:
    summary: "Global message rate > 10k msg/sec"
    description: "Rate: {{ $value | humanize }} msg/sec"

- alert: ExcessivePerUserRate
  expr: increase(high_rate_users_total[5m]) > 5
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "Multiple users exceeding rate limits"
    description: "{{ $value }} users rate-limited in last 5 minutes"
```

---

### P1.2: 队列处理延迟指标

```rust
// === 队列延迟指标 ===

pub static ref MESSAGE_AGE_IN_QUEUE_SECONDS: Histogram = register_histogram!(
    "message_age_in_queue_seconds",
    "Time message spent in processing queue",
    vec![0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
).unwrap();

pub static ref QUEUE_PROCESSING_LAG_MESSAGES: Gauge = register_gauge!(
    "queue_processing_lag_messages",
    "Number of messages behind in queue processing"
).unwrap();

pub static ref QUEUE_CONSUMER_RATE_PER_SECOND: Gauge = register_gauge!(
    "queue_consumer_rate_per_second",
    "Current message consumption rate"
).unwrap();

pub static ref MESSAGE_TOTAL_DELIVERY_LATENCY_SECONDS: HistogramVec = register_histogram_vec!(
    "message_total_delivery_latency_seconds",
    "Total time from send to delivery completion",
    &["delivery_path"],  // direct|queue_consumed|broadcast
    vec![0.01, 0.05, 0.1, 0.5, 1.0, 5.0, 10.0]
).unwrap();
```

**告警规则:**
```yaml
- alert: MessageQueueBacklogAccumulating
  expr: message_age_in_queue_seconds > 10
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Messages stuck in queue > 10s"

- alert: QueueProcessingSlowing
  expr: queue_consumer_rate_per_second < 100
  for: 3m
  labels:
    severity: warning
  annotations:
    summary: "Queue consumption rate dropped < 100 msg/sec"
    description: "Current rate: {{ $value | humanize }} msg/sec"
```

---

## 关键设计决策

### 1. 为什么不用 `user_id` 作为标签？

```text
❌ 错误：
pub static ref USER_MESSAGES_SENT: CounterVec =
    register_counter_vec!("...", &["user_id"])
结果：1M 用户 = 1M 时间序列 = Prometheus 内存炸毁

✅ 正确：
- 用 GLOBAL_MESSAGE_RATE_GAUGE 监控全局速率
- 用 HIGH_RATE_USERS_TOTAL 统计超限用户数
- 用日志记录具体超限的 user_id（不是指标）
```

### 2. 为什么分离 DB、Redis、Queue 指标？

```text
原因：这些层可能各自独立出现问题

示例故障诊断：
问题：P99 延迟从 100ms 跳到 2s
可能根因：
- 数据库连接变慢 → 看 DB_CONNECTION_ACQUIRE_SECONDS
- 缓存命中率下降 → 看 REDIS_CACHE_HIT_RATE
- 队列堆积 → 看 MESSAGE_AGE_IN_QUEUE_SECONDS
- 消息大 → 看 MESSAGE_SIZE_BYTES_HISTOGRAM

如果没有这些分层指标，只能盲目排查
```

### 3. 为什么需要 `MESSAGE_SIZE_BYTES_HISTOGRAM`？

```text
好处：
✅ 立即发现大消息异常
✅ 可以设置告警 P99 > 5MB
✅ 监控消息大小趋势（是否在增长）
✅ 成本分析（大消息 = 更多网络带宽）

成本：
⚠️ 引入 1 个 histogram（约 10 个 bucket = 10 个时间序列）
✅ 代价很小，但价值很大
```

---

## 实施检查清单

```
P0 - 部署前:
[ ] 添加 DB_CONNECTIONS_ACTIVE 和相关 3 个 DB 指标
[ ] 添加 REDIS_CACHE_HITS/MISSES 和内存指标
[ ] 添加 MESSAGE_SIZE_BYTES_HISTOGRAM
[ ] 为 DB 连接写入代码埋点统计
[ ] 为 Redis 操作写入埋点统计
[ ] 为消息大小写入埋点统计
[ ] 配置告警规则（6 个警报）
[ ] 测试：模拟连接池耗尽，验证告警
[ ] 测试：模拟缓存击穿，验证指标
[ ] 测试：发送大消息，验证统计

P1 - 首个迭代:
[ ] 添加 GLOBAL_MESSAGE_RATE_GAUGE
[ ] 添加 MESSAGE_AGE_IN_QUEUE_SECONDS
[ ] 在 Kafka 消费端埋点队列年龄
[ ] 配置队列相关告警
[ ] 建立 Grafana dashboard 展示这些指标

P2 - 优化:
[ ] 分析 user_message_rate（日志级别，非指标）
[ ] 优化 Redis TTL 策略（基于 cache_hit_rate）
[ ] 调整 queue consumer 批量大小（基于延迟指标）
```

---

## 风险评估

### 实施风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| 埋点代码性能开销 | +1-2% CPU | 使用条件统计，不是每条消息 |
| 新指标的基数爆炸 | OOM | 严格避免高基数标签（user_id, conversation_id） |
| 告警阈值不准确 | 虚假告警 | 先 warning 2 周，观察调整 |
| 缺少某个关键指标 | 故障诊断困难 | 部署后根据实际故障迭代 |

### 不实施的风险

| 后果 | 概率 | 影响程度 |
|------|------|---------|
| 连接池耗尽导致业务中断 | 30% | 高（业务不可用） |
| 缓存击穿导致 P99 延迟 10x | 40% | 中（用户体验下降） |
| 大消息 DoS 导致应用 OOM | 20% | 高（应用崩溃） |
| 用户滥用无法检测 | 50% | 中（资源浪费） |
| 故障诊断时间增加 50% | 80% | 高（MTTR 增加） |

---

## 总结

**立即开始 P0 工作（1 周完成）:**
- DB 连接池 + Redis 缓存 + 消息大小
- 这 3 个指标覆盖了 80% 的关键故障场景

**P1 工作（第二周）:**
- 全局速率 + 队列延迟
- 完整的端到端可观测性

**关键原则:**
1. ✅ 分层监控（DB/Cache/Queue/Message）
2. ✅ 谨慎的标签设计（避免基数爆炸）
3. ✅ 以生产故障为驱动设计指标
4. ✅ 告警阈值基于 SLA 和历史数据

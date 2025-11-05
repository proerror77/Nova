# Nova 项目可观测性缺口总结

## 快速参考

### 关键文件位置

| 文件 | 问题 | 优先级 |
|------|------|--------|
| `backend/messaging-service/src/main.rs` | 无优雅关闭，后台任务未清理 | 🔴 P0 |
| `backend/libs/actix-middleware/src/metrics.rs` | 基数爆炸（path 标签） | 🔴 P0 |
| `backend/prometheus.rules.yml` | 虚拟告警（不存在的指标） | 🔴 P0 |
| `backend/messaging-service/src/config.rs` | 敏感信息日志泄露 | 🔴 P0 |
| `backend/**/**_metrics.rs` | 缺少关键业务指标 | 🟡 P1 |
| `backend/libs/actix-middleware/src/correlation_id.rs` | 仅在 HTTP 层，未传播到 gRPC/Kafka | 🟡 P1 |

---

## P0 风险清单（需要立即处理）

### 1. 无优雅关闭机制 ⚠️ 数据丢失风险

**位置**: `backend/messaging-service/src/main.rs:111-116`

```rust
// ❌ 问题代码
let _streams_listener: JoinHandle<()> = tokio::spawn(async move {
    // ... Redis 流监听器在这里运行
    // 当主程序退出时，这个任务被强制中断
});
// Note: 注释中写得很清楚：没有优雅关闭
```

**影响**:
- 🔴 在途消息丢失
- 🔴 Redis 连接未正确关闭
- 🔴 缓冲区中的数据丢失

**快速修复**: 添加 `tokio::signal::ctrl_c()` 监听和优雅关闭逻辑（2-3 小时）

---

### 2. 指标基数爆炸 ⚠️ Prometheus OOM 风险

**位置**: 所有 `metrics.rs` 文件

```rust
// ❌ 问题
&["method", "path", "status"]  // 如果有 100+ 路径，就是 100 * 5 * 10 = 5000+ 时间序列

// ✅ 解决方案
&["method", "route", "status"]  // 路径分组，最多几十个路由
```

**影响**:
- 🔴 Prometheus 内存使用量爆炸（100+ GB）
- 🔴 查询变慢
- 🔴 告警系统变缓慢

**受影响文件**:
- `backend/messaging-service/src/metrics.rs:75`
- `backend/notification-service/src/metrics.rs:43`
- `backend/media-service/src/metrics/mod.rs:44`
- `backend/auth-service/src/metrics.rs`（未检测，但可能有）

**快速修复**: 1 小时内完成所有文件的修改

---

### 3. 虚拟告警规则 ⚠️ 告警永不触发

**位置**: `backend/prometheus.rules.yml`

不存在的指标：
- `global_message_rate_per_second` (第 410 行)
- `db_connections_active` (第 288, 302 行)
- `db_connections_idle` (第 289, 302 行)
- `queue_consumer_rate_per_second` (第 444 行)
- `queue_processing_lag_messages` (第 456 行)

**影响**:
- 🔴 这些告警永远不会触发
- 🔴 关键问题无法被检测到

**快速修复**: 
- 选项 A：删除这些虚拟告警（30 分钟）
- 选项 B：在代码中实现这些指标（4-6 小时）

---

### 4. 日志敏感信息泄露 ⚠️ 安全漏洞

**位置**: `backend/messaging-service/src/config.rs`

```rust
// ❌ 问题
tracing::warn!(error=%e, "failed to initialize APNs client");
// 可能输出：error="ApnsError(InvalidCertificate(pem data...))"

tracing::debug!("metrics updater failed: {}", e);
// 可能输出：sqlx::Error(DatabaseConnectionString with password)
```

**影响**:
- 🔴 密钥暴露到日志系统
- 🔴 连接字符串泄露
- 🔴 合规性问题（GDPR、HIPAA）

**快速修复**: 1 小时，审计所有日志调用

---

## P1 风险清单（本周处理）

### 5. 缺少 Correlation ID 传播 ⚠️ 无法追踪分布式请求

**位置**: 所有跨服务调用

**当前状态**:
- ✅ HTTP 请求有 Correlation ID
- ❌ gRPC 调用没有传播
- ❌ Kafka 消息没有传播
- ❌ 异步任务丢失上下文

**影响**:
- 🟡 无法追踪跨服务请求
- 🟡 故障诊断困难

**需要修改的地方**:
1. `backend/messaging-service/src/services/auth_client.rs` - gRPC 调用
2. `backend/user-service/src/services/events/consumer.rs` - Kafka 消费
3. 所有 `tokio::spawn()` 调用 - 传播追踪上下文

**工作量**: 4-6 小时

---

### 6. 缺少关键 SLA 指标 ⚠️ 无法证明 SLA 合规

**缺失的指标**:

| 指标 | 说明 | 实现难度 |
|------|------|---------|
| `message_e2e_latency_seconds` | 从发送到接收 | 中等 |
| `ws_connection_establish_time_seconds` | WebSocket 连接建立时间 | 中等 |
| `message_delivery_failure_rate` | 失败率百分比 | 小 |
| `cache_hit_rate` | 缓存命中率 | 小 |
| `active_connections` | WebSocket 活跃连接数 | 小 |

**快速实现计划**:
- Day 1: 消息 E2E 延迟
- Day 2: WebSocket 指标
- Day 3: 缓存指标

**工作量**: 3-4 天

---

### 7. 日志采样缺失 ⚠️ 日志风暴风险

**位置**: 高频操作路径

**当前状态**:
```rust
// ❌ 每个消息都记录 debug 日志
debug!("Processing message from {}", sender_id);
// 如果每秒 10000 条消息，就是 10000 行日志/秒
```

**快速修复示例**:
```rust
static LOG_SAMPLE: AtomicU32 = AtomicU32::new(0);

if LOG_SAMPLE.fetch_add(1, Ordering::Relaxed) % 100 == 0 {
    debug!("Processing message from {}", sender_id);
}
```

---

## P2 风险清单（下个迭代）

### 8. 过度 `.clone()` 导致性能下降

**位置**: `backend/messaging-service/src/main.rs`

22 处 `.clone()` 调用，其中一些在热路径中。

**建议**:
- 优先审查 `AppState` 和 `PgPool` 的克隆
- 考虑使用 `Arc<T>` 替代裸克隆

---

### 9. 缺少错误类型分类

**位置**: 所有指标定义

```rust
// ❌ 现状
pub static ref LOGIN_FAILURES_TOTAL: Lazy<IntCounter> = ...;

// ✅ 应该是
pub static ref LOGIN_FAILURES_BY_REASON: Lazy<IntCounterVec> = ...;
// 标签: ["reason"]
// 值: "wrong_password" | "user_not_found" | "account_locked" | "2fa_failed"
```

---

## 改进优先级路线图

```
第 1 周 (P0 - 关键)
├─ Day 1-2: 修复虚拟告警 (1-2 小时)
├─ Day 2-3: 修复指标基数 (1 小时)
├─ Day 3-4: 移除敏感日志 (1 小时)
└─ Day 4-7: 实现优雅关闭 (2-3 小时)
  结果: 消除数据丢失、OOM、安全风险

第 2 周 (P1 - 高优先级)
├─ Correlation ID 传播 (4-6 小时)
├─ 消息 E2E 延迟指标 (4 小时)
├─ WebSocket 健康指标 (3 小时)
└─ 日志采样策略 (2 小时)
  结果: 可以追踪分布式请求、验证 SLA

第 3-4 周 (P2 - 优化)
├─ 缓存命中率指标 (2 小时)
├─ 错误类型分类 (3 小时)
└─ 性能优化审查 (4 小时)
  结果: 更细粒度的可观测性
```

---

## 验证清单

完成修复后，运行以下检查：

### P0 修复验证

- [ ] 启动应用，发送 Ctrl+C，验证优雅关闭
  ```bash
  $ cargo run --release
  # 等待初始化完成
  # Ctrl+C
  # 应看到 "Shutting down gracefully..." 并等待所有任务完成
  ```

- [ ] 运行 Prometheus，检查指标数量
  ```bash
  curl http://localhost:9090/api/v1/label/__name__/values | wc -l
  # 应该 < 5000
  ```

- [ ] 检查日志中是否有敏感信息
  ```bash
  grep -r "password\|secret\|token\|key\|credential" /var/log/nova/ 2>/dev/null
  # 应该返回空
  ```

### P1 修复验证

- [ ] 追踪 HTTP 请求到 gRPC 调用
  ```bash
  # 1. 发送 HTTP 请求
  curl -H "X-Correlation-ID: test-123" http://localhost:8080/api/v1/messages
  
  # 2. 检查日志中是否看到 correlation_id=test-123
  grep "test-123" /var/log/nova/messaging.log
  ```

- [ ] 验证消息延迟指标
  ```bash
  # 发送测试消息，然后查询指标
  curl http://localhost:9090/api/v1/query?query=message_e2e_latency_seconds
  # 应该看到值而非空
  ```

---

## 资源需求

| 资源 | 用途 | 优先级 |
|------|------|--------|
| Rust 知识 | 修复代码 | 必需 |
| Prometheus 知识 | 修复指标和告警 | 需要 |
| 时间（40 小时） | 完整修复 | 高 |
| 代码审查 | 确保质量 | 需要 |

---

## 参考链接

- Prometheus 基数爆炸: https://prometheus.io/docs/practices/naming/
- Tokio 优雅关闭: https://tokio.rs/tokio/overview
- gRPC metadata 传播: https://docs.rs/tonic/latest/tonic/
- 日志最佳实践: https://docs.rs/tracing/latest/tracing/


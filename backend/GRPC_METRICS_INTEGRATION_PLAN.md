# gRPC RED 指标集成计划 - Phase 2

## 概述

在所有 6 个核心 gRPC 服务中集成 `libs/grpc-metrics` 共用层，实现 RED（Request, Error, Duration）指标的全覆盖。

## 架构

```
┌─────────────────────────────────────────────────────────┐
│         Prometheus Metrics Collection System             │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │        shared libs/grpc-metrics                   │  │
│  ├────────────────────────────────────────────────┤  │
│  │ • GrpcMetrics (global prometheus metrics)       │  │
│  │ • RequestGuard (RAII pattern for in-flight)     │  │
│  │ • Helper functions (record, inc, dec)           │  │
│  └──────────────────────────────────────────────────┘  │
│                      ↑                                   │
│      ┌───────────────┼───────────────┐                 │
│      ↓               ↓               ↓                 │
│  ┌─────────────────────────────────────────────────┐   │
│  │ 6 Core Services (RequestGuard in RPC handlers)  │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ 1. auth-service      (authentication)           │   │
│  │ 2. user-service      (user management)          │   │
│  │ 3. content-service   (content operations)       │   │
│  │ 4. feed-service      (feed aggregation)         │   │
│  │ 5. messaging-service (messaging) ✅ DONE        │   │
│  │ 6. streaming-service (live streaming)           │   │
│  └─────────────────────────────────────────────────┘   │
│                      ↓                                   │
│  ┌─────────────────────────────────────────────────┐   │
│  │     Prometheus Endpoint /metrics                │   │
│  │  (grpc_server_requests_total)                   │   │
│  │  (grpc_server_request_duration_seconds)         │   │
│  │  (grpc_server_in_flight_requests)               │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## 实现流程

### Phase 2A: 核心基础设施（完成）

- ✅ 创建 `libs/grpc-metrics` 共用库
  - ✅ Prometheus CounterVec, HistogramVec, IntGaugeVec
  - ✅ RequestGuard RAII 模式
  - ✅ 通用辅助函数

- ✅ 配置 workspace 依赖
  - ✅ 添加 tower, pin-project, lazy_static
  - ✅ 将 grpc-metrics 添加到 members 列表

- ✅ 集成首个服务（messaging-service）
  - ✅ 导入 RequestGuard
  - ✅ 在 SendMessage 方法中集成
  - ✅ 在 GetMessage 方法中集成
  - ✅ 在 CreateConversation 方法中集成

### Phase 2B: 扩展到其他服务（进行中）

#### auth-service

**主要 RPC 方法**：
- `Register` - 用户注册
- `Login` - 登录
- `RefreshToken` - 刷新令牌
- `Logout` - 登出
- `ValidateToken` - 验证令牌

**集成步骤**：
```rust
// 1. 在 src/grpc/mod.rs 顶部添加
use grpc_metrics::layer::RequestGuard;

// 2. 为每个 async fn 添加
let guard = RequestGuard::new("auth-service", "MethodName");

// 3. 在所有错误路径和成功路径记录状态码
guard.complete("0");  // OK
guard.complete("3");  // INVALID_ARGUMENT
// ...
```

#### user-service

**主要 RPC 方法**：
- `GetUserProfile` - 获取用户信息
- `UpdateUserProfile` - 更新用户信息
- `GetUserStats` - 获取用户统计
- `BlockUser` - 拉黑用户
- `UnblockUser` - 取消拉黑

#### content-service

**主要 RPC 方法**：
- `CreatePost` - 创建文章
- `GetPost` - 获取文章
- `UpdatePost` - 更新文章
- `DeletePost` - 删除文章
- `ListPostsByUser` - 获取用户文章列表

#### feed-service

**主要 RPC 方法**：
- `GetFeed` - 获取个性化推荐
- `GetFollowingFeed` - 获取关注者推荐
- `GetTrendingFeed` - 获取热门推荐

#### streaming-service

**主要 RPC 方法**：
- `StartLiveStream` - 开始直播
- `GetLiveStream` - 获取直播信息
- `EndLiveStream` - 结束直播
- `SendStreamChat` - 发送直播评论

### Phase 2C: 验证与优化

- 验证所有服务 RED 指标采集
- 检查 Prometheus 输出格式
- 优化指标粒度
- 文档更新

## 关键指标说明

### 1. grpc_server_requests_total (Counter)

按 service, method, code 统计总请求数。

```
grpc_server_requests_total{service="messaging-service", method="SendMessage", code="0"} 1234
```

用途：
- 计算请求成功率: `success / total`
- 按错误类型分析故障

### 2. grpc_server_request_duration_seconds (Histogram)

请求延迟分布（秒）。

```
grpc_server_request_duration_seconds_bucket{service="messaging-service", method="SendMessage", le="0.1"} 950
grpc_server_request_duration_seconds_bucket{service="messaging-service", method="SendMessage", le="0.5"} 1000
```

用途：
- 计算 P95, P99 延迟
- 性能监控告警

### 3. grpc_server_in_flight_requests (Gauge)

当前进行中的请求数。

```
grpc_server_in_flight_requests{service="messaging-service", method="SendMessage"} 45
```

用途：
- 并发度监控
- 负载均衡决策

## 集成检查清单

### 对于每个 RPC 方法

- [ ] 在方法开始添加 `let guard = RequestGuard::new("service-name", "MethodName");`
- [ ] 对所有错误路径调用 `guard.complete(code)` 并返回
- [ ] 对成功路径调用 `guard.complete("0")` 后返回响应
- [ ] 验证编译: `cargo check -p <service-name> --lib`
- [ ] 验证库部分编译成功

### 全局验证

- [ ] 所有 6 个服务的库部分编译
- [ ] Prometheus metrics 端点可访问
- [ ] 指标数据正确收集

## 常见问题

### Q: 为什么使用 Clone 而不是消费所有权?

A: RequestGuard 现在是 Clone 的，允许在 map_err 闭包中使用而不破坏借用规则。完成状态通过原子布尔值跟踪。

### Q: 性能影响有多大?

A: 极小。只是调用 Prometheus 的原子操作，不涉及锁竞争。

### Q: 如何处理流式 RPC?

A: 对于双向流，在流处理循环的外层创建 guard，完成整个流后记录状态。

## 性能目标

| 指标 | 目标 |
|------|------|
| 指标采集延迟 | < 1ms per request |
| Prometheus 暴露端口延迟 | < 100ms |
| 并发请求支持 | 10k+ |
| 内存开销 | < 10MB (labels cardinality) |

## 参考资源

- [grpc-metrics 库文档](./libs/grpc-metrics/README.md)
- [Prometheus 官方文档](https://prometheus.io/docs/)
- [gRPC 状态码](https://grpc.io/docs/guides/status-codes/)
- [RED 指标框架](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)

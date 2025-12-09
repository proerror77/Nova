# gRPC Metrics Library

高性能 gRPC 服务的 RED 指标采集共用层（Prometheus）。

## 特性

- **Requests Counter** - 按 service/method/code 统计请求总数
- **Duration Histogram** - 按 service/method 统计请求延迟分布
- **In-flight Gauge** - 当前在途请求数

## 快速开始

### 1. 添加依赖

```toml
[dependencies]
grpc-metrics = { path = "../libs/grpc-metrics" }
```

### 2. 在 RPC 处理器中使用

```rust
use grpc_metrics::layer::RequestGuard;

async fn send_message(
    &self,
    request: Request<SendMessageRequest>,
) -> Result<Response<SendMessageResponse>, Status> {
    // 创建守卫 - 自动增加 in-flight 计数
    let guard = RequestGuard::new("messaging-service", "SendMessage");

    let req = request.into_inner();

    // ... 处理请求逻辑 ...

    // 如果出错，记录错误代码
    if request_invalid {
        guard.complete("3");  // INVALID_ARGUMENT
        return Err(Status::invalid_argument("..."));
    }

    // ... 继续处理 ...

    // 成功时记录状态码 "0" (OK)
    guard.complete("0");
    Ok(Response::new(response))
}
```

## gRPC 状态代码

使用以下状态代码调用 `guard.complete(code)`:

| 代码 | 状态 | 说明 |
|------|------|------|
| 0 | OK | 请求成功 |
| 1 | CANCELLED | 请求被取消 |
| 2 | UNKNOWN | 未知错误 |
| 3 | INVALID_ARGUMENT | 无效参数 |
| 4 | DEADLINE_EXCEEDED | 超时 |
| 5 | NOT_FOUND | 资源不存在 |
| 6 | ALREADY_EXISTS | 资源已存在 |
| 7 | PERMISSION_DENIED | 权限拒绝 |
| 8 | RESOURCE_EXHAUSTED | 资源耗尽 |
| 9 | FAILED_PRECONDITION | 前置条件失败 |
| 10 | ABORTED | 已中止 |
| 11 | OUT_OF_RANGE | 超出范围 |
| 12 | UNIMPLEMENTED | 未实现 |
| 13 | INTERNAL | 内部错误 |
| 14 | UNAVAILABLE | 服务不可用 |
| 15 | DATA_LOSS | 数据丢失 |
| 16 | UNAUTHENTICATED | 未认证 |

## 指标示例

启动服务后，可以在 Prometheus 中查询：

```
# 总请求数
grpc_server_requests_total{service="messaging-service", method="SendMessage", code="0"}

# 请求延迟（直方图）
grpc_server_request_duration_seconds_bucket{service="messaging-service", method="SendMessage", le="0.1"}

# 在途请求数
grpc_server_in_flight_requests{service="messaging-service", method="SendMessage"}
```

## 实现详情

### RequestGuard RAII 模式

`RequestGuard` 使用 Rust 的 RAII（资源获取即初始化）模式：

- **创建**: `RequestGuard::new(service, method)` 自动增加 in-flight 计数
- **完成**: 调用 `guard.complete(code)` 记录状态码并计算延迟
- **销毁**: `Drop` trait 自动减少 in-flight 计数

### 线程安全

所有指标都是线程安全的（使用 Prometheus 的 `CounterVec`/`HistogramVec`）。

### 性能

- 最小化锁竞争
- 使用原子操作记录状态
- 支持高并发场景（10k+ 并发请求）

## 集成 6 个核心服务

- ✅ messaging-service (已集成)
- ⏳ auth-service
- ⏳ user-service
- ⏳ content-service
- ⏳ feed-service
- ⏳ streaming-service

## 参考

- [Prometheus Rust Client](https://docs.rs/prometheus/latest/prometheus/)
- [gRPC Status Codes](https://grpc.io/docs/guides/status-codes/)
- [RED Metrics](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)

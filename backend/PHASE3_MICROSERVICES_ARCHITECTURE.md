# Phase 3: 微服务架构准备

**时间段**：第 3-4 周
**目标**：为从 monolithic user-service 分离出独立微服务做准备

## 概览

Phase 3 建立微服务通信基础设施，为未来将流媒体、内容和媒体处理等功能提取为独立服务做准备。

## 架构演进

### 当前架构 (Phase 1-2)
```
┌─────────────────────────────────┐
│      Monolithic User Service    │
├─────────────────────────────────┤
│ - Streaming                     │
│ - Feed Ranking                  │
│ - User Management               │
│ - Post Management               │
│ - Video Processing              │
│ - Analytics                     │
│ - etc.                          │
└─────────────────────────────────┘
```

**问题**：单一进程处理所有功能，扩展性有限

### 目标架构 (Phase 3+)
```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   Auth Svc   │  │  Stream Svc  │  │ Content Svc  │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
                   ┌──────▼──────┐
                   │  API Gateway│
                   └─────────────┘
                          │
                          │ Shared
                          │ Libraries
                          │
                   ┌──────▼──────┐
                   │nova-common  │
                   ├─────────────┤
                   │- Models     │
                   │- Errors     │
                   │- Clients    │
                   │- Protocols  │
                   └─────────────┘
```

**优势**：独立扩展、部署、开发各个服务

## 新增文件结构

### 1. nova-common 库 (`backend/libs/nova-common/`)

共享的类型、错误处理和通信协议。

**文件树**：
```
nova-common/
├── Cargo.toml
└── src/
    ├── lib.rs              # 主导出模块
    ├── error.rs            # 统一错误处理
    ├── models.rs           # 共享数据模型
    ├── grpc_proto.rs       # gRPC 定义（占位符）
    └── http_client.rs      # 服务间 HTTP 客户端
```

**关键模块**：

#### error.rs
- `ServiceError` - 所有服务的统一错误类型
- 包含 HTTP 状态码映射
- 支持重试判断 (is_retryable)

**示例**：
```rust
pub enum ServiceError {
    Authentication(String),
    Authorization(String),
    Validation(String),
    NotFound(String),
    ServiceUnavailable(String),
    // ...
}
```

#### models.rs
- `StreamEvent` - 域事件
- `CommandRequest<T>` - 标准请求格式
- `CommandResponse<T>` - 标准响应格式
- `PagedResponse<T>` - 分页响应
- `HealthStatus` - 服务健康检查

**示例**：
```rust
// 服务间调用
let request = CommandRequest::new(
    "user-service",      // 源服务
    "streaming-service",  // 目标服务
    GetStreamInfoCommand { stream_id },
);

// 标准化响应
let response = CommandResponse::ok(request.request_id, stream_info);
```

#### http_client.rs
- `ServiceClient` - 服务间 HTTP 通信
- 处理请求/响应包装
- 自动处理错误转换

**示例**：
```rust
let client = ServiceClient::new("user-service", "http://localhost:8080");
let stream_info = client.call(
    "streaming-service",
    "streams/info",
    GetStreamInfoRequest { stream_id }
).await?;
```

## 服务边界定义

### 流媒体服务 (Streaming Service)

**职责**：
- 流生命周期管理 (创建、开始、结束)
- 观众计数和连接管理
- 直播聊天
- 流媒体分析

**依赖**：
- PostgreSQL (stream 元数据)
- Redis (实时计数)
- Kafka (事件发布)
- Milvus (向量搜索)

**公开 API**：
```
POST   /api/v1/streams                 - 创建流
GET    /api/v1/streams/{id}            - 获取流详情
GET    /api/v1/streams                 - 列出直播流
POST   /api/v1/streams/{id}/join       - 加入流
POST   /api/v1/streams/{id}/leave      - 离开流
POST   /api/v1/streams/{id}/comments   - 发送评论
GET    /api/v1/streams/{id}/comments   - 获取评论
GET    /api/v1/streams/{id}/analytics  - 获取分析
```

**内部事件**：
```
stream.started    - 流开始直播
stream.ended      - 流结束
viewer.joined     - 观众加入
viewer.left       - 观众离开
comment.posted    - 评论发布
```

## 通信协议

### HTTP/JSON (当前)
用于同步请求/响应。

**请求格式**：
```json
{
  "request_id": "uuid-xxx",
  "source_service": "user-service",
  "target_service": "streaming-service",
  "command": { /* 具体命令 */ },
  "timestamp": "2025-10-28T00:00:00Z"
}
```

**响应格式**：
```json
{
  "request_id": "uuid-xxx",
  "success": true,
  "data": { /* 响应数据 */ },
  "error": null,
  "timestamp": "2025-10-28T00:00:00Z"
}
```

### Kafka 事件 (异步)
用于事件发布和订阅。

**主题**：
- `streaming.events` - 所有流媒体事件
- `analytics.events` - 分析事件
- `notifications.events` - 通知事件

## 迁移路径

### Phase 3.1: nova-common 基础设施 ✅
- ✅ 创建 nova-common 库
- ✅ 定义统一错误类型
- ✅ 定义通信模型
- ✅ 实现 HTTP 客户端
- ⏳ 在 user-service 中集成

### Phase 3.2: 服务边界提取
- 为 streaming-service 创建抽象边界
- 定义清晰的 API 合约
- 实现内部服务调用

### Phase 3.3: 依赖隔离
- 将 streaming 依赖与 user-service 分离
- 创建 streaming-service 独立 Cargo 包

### Phase 3.4: 部署准备
- 为 streaming-service 创建独立 Dockerfile
- 配置服务发现 (Kubernetes)
- 实现健康检查端点

## 未来的微服务

根据功能域，可以进一步分离：

1. **内容服务** (Content Service)
   - 帖子管理
   - 评论管理
   - 点赞管理
   - 内容推荐

2. **媒体服务** (Media Service)
   - 视频上传/转码
   - 图像处理
   - 媒体转换

3. **分析服务** (Analytics Service)
   - 用户分析
   - 内容分析
   - 流媒体分析

4. **通知服务** (Notification Service)
   - 推送通知
   - 邮件通知
   - 短信通知

5. **搜索服务** (Search Service)
   - 用户搜索
   - 内容搜索
   - 流媒体搜索

## 代码统计

### nova-common 库

| 文件 | 行数 | 目的 |
|------|------|------|
| error.rs | 95 | 统一错误处理 |
| models.rs | 245 | 共享数据模型 |
| http_client.rs | 105 | 服务间 HTTP 通信 |
| grpc_proto.rs | 15 | gRPC 定义（占位符） |
| lib.rs + Cargo.toml | 40 | 模块导出和配置 |
| **总计** | **500** | **微服务通信基础** |

## 测试策略

### 单元测试
```rust
#[test]
fn test_command_request_creation() {
    let req = CommandRequest::new(
        "service-a",
        "service-b",
        SomeCommand {},
    );
    assert_eq!(req.source_service, "service-a");
    assert!(!req.request_id.is_empty());
}
```

### 集成测试
```rust
#[tokio::test]
async fn test_service_http_call() {
    let client = ServiceClient::new("test", "http://localhost:8080");
    let result = client.call(
        "other-service",
        "endpoint",
        TestCommand {},
    ).await;
    // 验证请求/响应流程
}
```

## 向后兼容性

✅ **完全兼容**：
- nova-common 是独立库，不影响现有代码
- user-service 可以逐步采用
- 现有 API 保持不变

## 成功标准

- ✅ nova-common 库完整且可编译
- ✅ 错误处理统一且文档完善
- ✅ 服务通信模型清晰定义
- ✅ HTTP 客户端可用且有测试
- ✅ 流媒体服务边界明确
- ✅ 迁移路径清晰

## 下一步行动

1. ✅ 创建 nova-common 库框架
2. ⏳ 在 user-service 中集成 nova-common
3. ⏳ 为 streaming-service 创建 Handler 适配器
4. ⏳ 实现服务健康检查端点
5. ⏳ 部署自动化和配置

## 总结

Phase 3 建立了微服务架构的基础设施，定义了清晰的服务边界，为未来的服务分离和独立部署做好准备。nova-common 库提供了统一的通信协议和错误处理，使得服务间通信变得简洁、可靠和可维护。

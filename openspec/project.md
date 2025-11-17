# Project Context

## Purpose

Nova Social Platform 是一个 Instagram 风格的全功能社交媒体应用，结合了：
- **Rust 微服务后端** - 8 个独立服务的分布式架构
- **iOS SwiftUI 前端** - 原生应用体验，使用 FFI 集成 Rust 核心库
- **实时通讯** - WebSocket 支持私信、直播、推送通知
- **内容管理** - 图片、视频、限时动态、短视频（Reels）
- **推荐引擎** - 基于 Rust 的个性化推荐算法
- **生产就绪** - 支持 Kubernetes 部署，多环境策略（本地、Staging、生产）

**关键目标**：
- 微服务架构（非协商项）- 每个服务独立可部署
- 跨平台共享 Rust 核心库
- 高可观测性（Prometheus + Grafana）
- 安全与隐私优先（GDPR 合规）
- 低延迟（<200ms API 响应，60fps UI）

## Tech Stack

### Backend (Rust)
- **Web 框架**: Actix-web 4.5（HTTP）、Axum（某些服务）
- **运行时**: Tokio 1.36（异步）、Actix-rt 2.9（并发演员模型）
- **数据库**:
  - PostgreSQL 14+（主存储，单一 nova_content 数据库）
  - Redis 7.0+（会话、缓存、实时）
  - ClickHouse 0.12（分析、时间序列数据）
  - MongoDB/Cassandra（可选，特定工作负载）
  - Neo4j（图数据库，社交网络关系）
- **消息队列**: Kafka（事件驱动）、RabbitMQ（可选）
- **gRPC**: Tonic 0.10（服务间通讯）
- **序列化**: Serde 1.0（JSON/MessagePack）
- **日志**: Tracing 0.1（结构化日志）
- **安全**: Jsonwebtoken 9.2、Argon2 0.5、RSA、AES-GCM
- **验证**: Validator 0.18（输入验证）
- **邮件**: Lettre 0.11（Email）
- **限流**: Governor 0.6
- **指标**: Prometheus 0.13（监控）
- **AWS**: S3（文件存储）
- **API 文档**: Utoipa 4.2（OpenAPI 自动生成）
- **测试**: Testcontainers 0.17（集成测试）

### Frontend (iOS)
- **UI 框架**: SwiftUI + UIKit 混合开发
- **网络**: URLSession with retry 逻辑
- **状态管理**: Clean Architecture + Repository 模式
- **Rust 集成**: FFI（外函数接口）for 核心算法

### Infrastructure
- **容器编排**: Kubernetes（EKS/本地 minikube）
- **CI/CD**: GitHub Actions
- **容器化**: Docker + Docker-compose
- **云平台**: AWS（S3、ECS、ECR）
- **监控**: Prometheus + Grafana
- **部署**: Kustomize（K8s 配置管理）

## Project Conventions

### Code Style

#### Rust
- **Formatting**: 遵循 `cargo fmt`（自动化）
- **Linting**: Clippy with `-D warnings`（致命警告级别）
- **版本**: Rust 2021 edition，MSRV 1.75
- **命名**:
  - 模块：`snake_case`
  - 函数/变量：`snake_case`
  - 类型/结构体：`PascalCase`
  - 常量：`SCREAMING_SNAKE_CASE`

#### 异步编程规则
- **运行时**: Tokio（多线程默认）
- **禁止在异步上下文中阻塞** - 使用 `tokio::task::block_in_place` 如果必须
- **避免不必要的 clone** - 使用引用和所有权转移
- **Async trait**: 使用 `async-trait` crate

#### 结构化日志
```rust
use tracing::{info, warn, error, debug};
info!(user_id = %user.id, action = "login_success", "User logged in");
warn!(retry_count = 3, "Request failed, retrying...");
error!(error = %err, "Database connection failed");
```

#### 特性标志（Feature Flags）
- 按交易所命名：`collector-binance`、`collector-okx` 等
- 按功能模块：`auth-oauth`、`content-video` 等
- 在 `Cargo.toml` 的 `[features]` 中定义
- 使用 `#[cfg(feature = "...")]` 条件编译

### Architecture Patterns

#### 微服务架构（核心）
当前 V2 核心服务（legacy `user-/streaming-service` 已合并）：
1. **identity-service**（原 auth-service）- 身份验证、JWT、OAuth
2. **content-service** - 帖子、媒体上传与 CDC
3. **feed-service** - 推荐、时间线、排序策略
4. **media-service** - 媒体处理、转码、CDN（整合 video/streaming/cdn）
5. **social-service** - Likes/Comments/Shares + 计数器、Outbox
6. **realtime-chat-service** - 私信、WebSocket、实时推送
7. **search-service** - 全文搜索、索引（ElasticSearch/ClickHouse）
8. **notification-service** - 推播、Email、SMS、通知偏好

**关键原则**：
- 每个服务拥有自己的表（部分共享用户表以维护外键）
- 通过 gRPC 进行服务间通讯
- 共享库：`error-handling`、`db-pool`、`redis-utils` 等
- 事件驱动（Kafka + Outbox Pattern）用于异步通讯

#### 分层架构（每个服务内部）
```
routes/ → handlers（HTTP 入口）
  ↓
services/ → 业务逻辑
  ↓
models/ → 数据结构、数据库模型
  ↓
db/ → 数据库访问层（sqlx）
  ↓
middleware/ → 跨切面（认证、限流、日志）
```

#### 中间件栈
```
Logger → CORS → Auth → RateLimit → Error Handling → Handler
```

#### 错误处理
- 使用 `thiserror` 定义错误类型
- 统一 HTTP 响应格式（在 `error-types` lib 中）
- 适当的 HTTP 状态码（401、403、429、500 等）
- 结构化错误响应，包含 error code 供客户端解析

### Testing Strategy

#### TDD（测试驱动开发）严格执行
- **红-绿-重构** 周期强制
- **目标覆盖率**: 80% 整体，关键路径 100%
- 每个提交必须：所有测试通过、零编译警告

#### 测试层级
1. **单元测试** - 函数/模块级别（`#[cfg(test)]`）
2. **集成测试** - 跨服务通讯（`tests/` 目录，使用 Testcontainers）
3. **端到端测试** - Staging 环境（可选，GitHub Actions）
4. **性能基准** - 关键路径（`benches/` 或集成测试中）

#### 测试命名约定
```rust
#[test]
fn test_user_login_with_valid_credentials_returns_jwt() { }

#[test]
fn test_rate_limit_blocks_after_threshold() { }
```

#### Testcontainers 集成
- PostgreSQL 容器用于数据库测试
- Redis 容器用于缓存测试
- Kafka 容器用于事件测试

### Git Workflow

#### 分支策略
- **主分支**: `main`（生产就绪代码）
- **开发分支**: `develop`（集成分支）
- **特性分支**: `feature/<feature-name>`
- **修复分支**: `fix/<issue-name>`
- **架构重构**: `refactor/<area>`
- **发布**: `release/v<version>`

#### 提交纪律
- **原子提交**: 一个逻辑单元 = 一个提交
- **清晰的提交信息**:
  ```
  <type>(<scope>): <description>

  <body>

  Fixes #<issue-number>
  ```
  - 类型: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
  - 示例: `feat(auth): add OAuth2 support for GitHub`

#### 代码审查规则
- 最少 1 个审查者（关键路径需要 2 个）
- 所有 CI 检查必须通过
- 不允许 force-push 到 `main`
- Squash and merge（保持历史清晰）

### Shared Libraries

所有共享库位于 `backend/libs/`：
- **actix-middleware** - 通用 HTTP 中间件（日志、CORS、速率限制）
- **db-pool** - 数据库连接池管理
- **error-handling** - 统一错误处理和转换
- **error-types** - 共享错误类型定义
- **event-schema** - Kafka 事件 schema（Avro/Protobuf）
- **crypto-core** - 加密原语（JWT、加密、哈希）
- **redis-utils** - Redis 客户端包装
- **video-core** - 视频处理核心库
- **nova-apns-shared** - Apple Push Notifications
- **nova-fcm-shared** - Firebase Cloud Messaging

## Domain Context

### 核心业务流程

#### 用户认证与授权
- JWT 令牌（短期访问令牌 + 刷新令牌）
- OAuth2 集成（Google、Apple、GitHub）
- 两因素认证（邮件 OTP）
- 会话管理（Redis）

#### 内容创建与分发
- 图片上传 → S3 → CDN（CloudFront）
- 视频上传 → 转码（FFmpeg）→ 存储 → CDN
- 限时动态（Stories）→ 24h 过期 → 自动删除
- 短视频（Reels）→ 推荐算法排序

#### 实时通讯
- WebSocket 连接（使用 Actix-web-actors）
- 私信队列（Redis）
- 直播流（RTMP → 转码 → HLS）
- 推送通知（APNS、FCM）

#### 推荐系统
- 协同过滤（用户-内容矩阵）
- 内容基过滤（标签、特征）
- 热度算法（评分、参与度）
- 黑名单（屏蔽用户、敏感内容）

#### 社交图谱
- 关注关系（Neo4j 或 PostgreSQL with ltree）
- 互动（点赞、评论、分享）
- 社群发现（推荐相似用户）
- 阻止与举报

### 关键性能指标（KPI）
- **API 响应时间**: <200ms（p95）
- **UI 帧率**: 60fps（iOS）
- **可用性**: 99.9%（SLA）
- **消息延迟**: <1s（实时通讯）
- **推荐刷新**: 每分钟（流式更新）

## Important Constraints

### 技术约束
1. **Rust 版本**: 严格 MSRV 1.75（向后兼容性）
2. **依赖**: 避免重型依赖，优先选择轻量级库
3. **异步**: 所有 I/O 操作必须异步，禁止阻塞
4. **数据库**: PostgreSQL 主库，Redis 缓存（no MongoDB by default）
5. **内存**: 每个服务 <500MB 限制（Kubernetes pod）

### 业务约束
1. **数据隐私**: GDPR 合规（数据导出、删除、遗忘权）
2. **App Store**: Apple 隐私政策合规（App Privacy）
3. **内容审核**: 自动化 + 人工审核流程
4. **用户配额**: 免费用户 50GB、付费用户 1TB（存储）
5. **速率限制**:
   - 认证端点: 5 requests/min
   - API 端点: 100 requests/min（免费）、1000 requests/min（付费）
   - 上传: 5 concurrent uploads

### 合规与安全
1. **TLS 1.3+** - 所有通讯加密
2. **输入验证** - 所有客户端输入都经过验证
3. **SQL 注入防护** - 仅使用参数化查询（sqlx）
4. **CORS 政策** - 白名单型（明确允许的域）
5. **密钥管理** - AWS Secrets Manager，不在代码中硬编码

## External Dependencies

### Cloud Services
- **AWS S3** - 文件存储（图片、视频）
- **AWS ECS/ECR** - 容器注册表与编排
- **CloudFront** - CDN（全球分发）

### 第三方集成
- **Auth0/Okta** - OAuth2 提供商（可选）
- **Sendgrid** - 邮件发送
- **Firebase** - 推送通知（FCM）
- **Apple Push** - iOS 推送（APNS）
- **Stripe** - 支付处理（如果启用付费）

### 监控与日志
- **Prometheus** - 指标收集
- **Grafana** - 指标可视化
- **Datadog/ELK** - 集中日志（可选）
- **Jaeger** - 分布式追踪（可选）

### 开发工具
- **GitHub** - 源代码管理 + Actions
- **Docker Hub** - 容器镜像
- **Cargo** - Rust 包管理器

### 协议与标准
- **OpenAPI 3.0** - API 文档（由 Utoipa 自动生成）
- **gRPC 1.0** - 服务间通讯
- **WebSocket** - 实时通讯
- **Protobuf 3** - 消息序列化

# 架构决策记录 (ADR)

> Nova Social Platform 的关键架构和设计决策

**维护者**: Claude Code
**最后更新**: 2025-10-22
**状态**: 活跃，持续更新

---

## 概述

本文档记录了 Nova 项目的重要架构决策，以及做出这些决策的上下文、考虑因素和长期影响。

---

## ADR-001: 微服务架构 (Microservices)

**状态**: ✅ **已实现** (Phase 7B)
**决策日期**: Phase 0
**优先级**: ⭐⭐⭐ **必须**

### 背景

Nova 需要处理多个独立的业务域：用户认证、内容管理、推荐、通知、流媒体等。单体架构难以满足以下要求：
- 独立扩展不同服务
- 不同团队独立部署
- 技术栈选择灵活性

### 决策

采用微服务架构，将系统分解为独立的、可部署的服务：
- **User Service**: 认证、用户管理、Feed 排名
- **Notification Service**: 推送通知 (FCM/APNs)
- **Video Service**: 视频处理、转码、流媒体
- **Messaging Service**: 实时消息 (WebSocket)
- **Streaming Service**: 直播服务 (RTMP/HLS/DASH)

### 实现

```rust
// 每个服务独立的 Cargo 模块
backend/user-service/
├── src/
│   ├── services/
│   │   ├── notifications/     # 通知服务
│   │   ├── messaging/         # 消息服务
│   │   ├── video_service.rs   # 视频服务
│   │   ├── recommendation_v2/ # 推荐引擎
│   │   └── ...
│   ├── db/                    # 数据层
│   └── config/                # 配置管理
```

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ 独立扩展 | ❌ 运维复杂性增加 |
| ✅ 技术灵活 | ❌ 分布式事务困难 |
| ✅ 故障隔离 | ❌ 跨服务调试困难 |
| ✅ 团队独立性 | ❌ 网络延迟 |

### 长期影响

- 通过服务隔离实现高可用性
- 支持独立的 CI/CD 流程
- 可随时添加新服务或替换现有服务

---

## ADR-002: 务实主义优先 (Pragmatism Over Perfection)

**状态**: ✅ **已实现** (Phase 7B)
**决策日期**: Phase 7B
**优先级**: ⭐⭐⭐ **必须**

### 背景

Phase 7B 中发现 4 个模块不完整：
- `messaging` 模块: 12+ 编译错误
- `neo4j_client`: 文件缺失
- `redis_social_cache`: 文件缺失
- `streaming` 工作区: 15 个编译错误

团队面临选择：
- 选项 A: 强行集成，延迟 Phase 7B 发布
- 选项 B: 禁用不完整模块，推迟到 Phase 7C

### 决策

**选择选项 B** - 禁用不完整模块，标记为 Phase 7C TODO

### 实现

```rust
// src/services/mod.rs
pub mod notifications;  // ✅ Phase 7B
pub mod video_service;  // ✅ Phase 7B
pub mod recommendation_v2; // ✅ Phase 7B

// pub mod messaging;        // TODO: Phase 7C - 12+ compilation errors
// pub mod neo4j_client;     // TODO: Phase 7C - File not found
// pub mod redis_social_cache; // TODO: Phase 7C - Not implemented
```

### 哲学基础

这项决策基于 Linus Torvalds 的 Linux 内核维护哲学：

> "不要解决虚拟问题。"
> "数据结构，而不是算法。"
> "永不破坏用户空间。"

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ Phase 7B 按时发布 | ❌ 功能延迟到 Phase 7C |
| ✅ 核心功能稳定 | ❌ 消息功能暂不可用 |
| ✅ 清晰的依赖图 | ❌ 需要更多规划 |
| ✅ 易于维护 | ❌ 社交图功能延迟 |

### 长期影响

- 建立了"生产就绪"的定义：0 个编译错误，明确的功能边界
- 为 Phase 7C 创建了清晰的集成点
- 改进了项目规划和里程碑管理

---

## ADR-003: 分阶段集成模式 (Phase-Based Integration)

**状态**: ✅ **已实现** (Phase 7B)
**决策日期**: Phase 7B
**优先级**: ⭐⭐⭐ **必须**

### 背景

大型系统集成经常因为复杂性而失败。需要一种可持续的、可验证的集成策略。

### 决策

采用分阶段集成模式：

```
Phase 7A: 基础设施      (通知系统基础、WebSocket 基础)
    ↓
Phase 7B: 核心服务      (推荐、视频、CDN 等)
    ↓
Phase 7C: 模块集成      (messaging、neo4j、redis、streaming)
    ↓
Phase 8:  优化和扩展    (性能、可扩展性)
```

### 实现

**每个 Phase 的定义**:
```
Definition of Done:
- ✅ 所有目标代码编译成功
- ✅ 核心功能的单元测试通过
- ✅ 清晰的 Git 历史和文档
- ✅ 推迟的工作明确标记 (TODO, ADR 参考)
```

**Phase 边界**:
- 每个 Phase 是一个独立的、可交付的单元
- 不完整的工作被明确推迟到下一个 Phase
- 每个 Phase 可单独部署（如需要）

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ 可验证的进度 | ❌ 需要更多规划 |
| ✅ 风险降低 | ❌ 迭代时间较长 |
| ✅ 清晰的里程碑 | ❌ 等待其他 Phase |
| ✅ 易于沟通 | ❌ 功能完成延迟 |

### 长期影响

- 建立了可预测的项目时间表
- 改进了跨团队协调
- 支持渐进式的功能发布

---

## ADR-004: 数据结构优先设计 (Data-Structure First Design)

**状态**: ✅ **已实现** (整个项目)
**决策日期**: Phase 0
**优先级**: ⭐⭐⭐ **必须**

### 背景

系统的可维护性和性能主要取决于数据结构的设计，而不是算法的复杂性。

### 决策

在设计 API 或服务时，始终首先定义数据结构：

```rust
// 第一步：定义数据结构
#[derive(Serialize, Deserialize, Clone)]
pub struct VideoProcessingConfig {
    pub ffmpeg_path: String,
    pub max_parallel_jobs: usize,
    pub target_bitrates: HashMap<String, u32>,
    pub s3_processed_bucket: String,
    pub s3_processed_prefix: String,
    pub extract_thumbnails: bool,
    pub thumbnail_dimensions: (u32, u32),
}

// 第二步：基于数据结构实现算法
impl VideoProcessingConfig {
    pub fn process_video(&self, video_path: &str) -> Result<()> {
        // 实现基于上述结构
    }
}
```

### 影响示例

**问题**: `transcoding_optimizer.rs` 的测试缺少字段
```rust
// ❌ 错误：字段不完整
VideoProcessingConfig {
    ffmpeg_path: "/usr/bin/ffmpeg".to_string(),
    max_parallel_jobs: 4,
    job_timeout_seconds: 7200,
    target_bitrates,
    thumbnail_dimensions: (320, 180),
}

// ✅ 正确：所有字段都包括
VideoProcessingConfig {
    ffmpeg_path: "/usr/bin/ffmpeg".to_string(),
    max_parallel_jobs: 4,
    job_timeout_seconds: 7200,
    target_bitrates,
    s3_processed_bucket: "nova-videos".to_string(),
    s3_processed_prefix: "processed/".to_string(),
    extract_thumbnails: true,
    thumbnail_dimensions: (320, 180),
}
```

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ 编译时错误检测 | ❌ 前期投入更多 |
| ✅ 类型安全 | ❌ Rust 学习曲线 |
| ✅ 重构变得容易 | ❌ 初期开发较慢 |
| ✅ 文档自驱动 | ❌ 模式不够灵活 |

### 长期影响

- Rust 的强类型系统防止了大量潜在的运行时错误
- 数据结构变化的传播能立即被编译器捕捉
- 代码自文档化，结构定义即文档

---

## ADR-005: 配置集中化 (Configuration Centralization)

**状态**: ✅ **已实现** (Phase 2+)
**决策日期**: Phase 2
**优先级**: ⭐⭐ **重要**

### 背景

多个服务需要共享和独立的配置。环境差异（开发、测试、生产）需要灵活处理。

### 决策

集中化配置管理：

```
backend/user-service/src/config/
├── mod.rs              # 配置导出
├── server_config.rs    # 服务器配置
├── database_config.rs  # 数据库配置
├── video_config.rs     # 视频处理配置
└── ...
```

**配置来源优先级**:
1. 环境变量 (最高)
2. `.env` 文件
3. 代码中的默认值 (最低)

### 实现

```rust
// 配置从环境变量读取
pub fn from_env() -> Self {
    Self {
        ffmpeg_path: env::var("FFMPEG_PATH")
            .unwrap_or_else(|_| "ffmpeg".to_string()),
        max_parallel_jobs: env::var("VIDEO_MAX_PARALLEL_JOBS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(4),
        // ...
    }
}
```

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ 环境差异隔离 | ❌ 增加复杂性 |
| ✅ 易于部署 | ❌ 需要文档 |
| ✅ 安全性 (密钥) | ❌ 参数数量增加 |
| ✅ 运维友好 | ❌ 初期配置工作 |

### 长期影响

- 支持 Docker 和 Kubernetes 部署
- 支持 CI/CD 流程中的环境差异
- 支持 12-factor 应用原则

---

## ADR-006: 异步优先架构 (Async-First Architecture)

**状态**: ✅ **已实现** (整个项目)
**决策日期**: Phase 0
**优先级**: ⭐⭐⭐ **必须**

### 背景

Nova 处理大量 I/O 操作：数据库查询、外部 API 调用、文件上传等。同步架构会导致资源浪费。

### 决策

全系统使用异步编程模型：

```rust
// 异步 HTTP 路由
#[post("/upload")]
async fn upload_video(req: HttpRequest, payload: Multipart) -> Result<HttpResponse> {
    // 异步处理
}

// 异步数据库查询
async fn get_user_feed(user_id: Uuid) -> Result<Vec<Post>> {
    sqlx::query_as::<_, Post>(...)
        .fetch_all(&pool)
        .await?
}

// 异步消息生产
async fn publish_event(event: Event) -> Result<()> {
    kafka_producer.send(event).await?
}
```

### 使用的异步运行时

- **Tokio**: 主要运行时
- **Actix-rt**: Web 框架集成
- **async-trait**: 异步特征

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ 高并发能力 | ❌ 代码复杂性增加 |
| ✅ 资源高效 | ❌ 调试困难 |
| ✅ 响应快速 | ❌ 学习曲线陡峭 |
| ✅ 可扩展性强 | ❌ 运行时开销 |

### 长期影响

- 支持数万并发连接
- 支持低延迟操作（直播、实时通知）
- 支持高吞吐量（批量处理）

---

## ADR-007: 模块清晰边界 (Clear Module Boundaries)

**状态**: ✅ **已实现** (Phase 7B)
**决策日期**: Phase 7B
**优先级**: ⭐⭐ **重要**

### 背景

随着系统增长，模块间的耦合会导致：
- 复杂的依赖图
- 难以测试的代码
- 难以维护的系统

### 决策

明确每个模块的责任和边界：

```
Database Layer (db/)
├── user_repo            # 用户数据操作
├── post_repo            # 内容数据操作
├── messaging_repo       # 消息数据操作 (Phase 7C)
└── oauth_repo           # OAuth 数据操作

Service Layer (services/)
├── notifications/       # 推送通知逻辑
├── video_service        # 视频处理逻辑
├── recommendation_v2/   # 推荐算法逻辑
├── messaging/           # 消息逻辑 (Phase 7C)
└── ...

API Layer (routes/handlers)
├── auth                 # 认证端点
├── video                # 视频端点
├── feed                 # Feed 端点
└── ...
```

### 边界规则

1. **数据库层**: 只负责数据操作，不包含业务逻辑
2. **服务层**: 包含业务逻辑，依赖数据库层，被 API 层使用
3. **API 层**: 处理 HTTP 请求/响应，调用服务层

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ 易于理解 | ❌ 层数增加 |
| ✅ 易于测试 | ❌ 请求处理开销 |
| ✅ 易于维护 | ❌ 初期设计成本 |
| ✅ 易于扩展 | ❌ 跨层 API 变更困难 |

### 长期影响

- 支持多个 API 端点（REST、GraphQL、gRPC）
- 支持单元测试和集成测试
- 支持模块独立演进

---

## ADR-008: 版本控制和标签策略 (Git Versioning Strategy)

**状态**: ✅ **已实现** (Phase 7B)
**决策日期**: Phase 7B
**优先级**: ⭐⭐ **重要**

### 背景

需要清晰的版本历史和里程碑标记。

### 决策

采用以下 Git 策略：

**分支策略**:
```
main                    # 生产就绪代码
├─ develop/phase-7a    # Phase 7A 功能分支
├─ develop/phase-7b    # Phase 7B 功能分支 ← 当前
└─ develop/phase-7c    # Phase 7C 功能分支 (规划中)
```

**标签策略**:
```
phase-7b-s4-complete   # Phase 7B Stage 4 完成
phase-7b-complete      # Phase 7B 全部完成
v0.1.0                 # 正式版本 (待发布)
```

### 提交信息格式

```
type(scope): subject

body (optional)

Relates to: ISSUE_NUMBER
```

**类型**:
- `feat`: 新特性
- `fix`: bug 修复
- `docs`: 文档
- `style`: 代码格式
- `refactor`: 重构
- `perf`: 性能
- `test`: 测试
- `build`: 构建
- `ci`: CI/CD
- `chore`: 其他

### 权衡

| 优势 | 劣势 |
|------|------|
| ✅ 清晰的历史 | ❌ 需要纪律 |
| ✅ 易于回滚 | ❌ 提交信息冗长 |
| ✅ 追踪能力强 | ❌ 学习成本 |
| ✅ 自动化友好 | ❌ 初期设置复杂 |

---

## 总结表格

| ADR | 决策 | 状态 | 优先级 | Phase |
|-----|------|------|--------|-------|
| 001 | 微服务架构 | ✅ | ⭐⭐⭐ | 0 |
| 002 | 务实主义优先 | ✅ | ⭐⭐⭐ | 7B |
| 003 | 分阶段集成 | ✅ | ⭐⭐⭐ | 7B |
| 004 | 数据结构优先 | ✅ | ⭐⭐⭐ | 0 |
| 005 | 配置集中化 | ✅ | ⭐⭐ | 2 |
| 006 | 异步优先架构 | ✅ | ⭐⭐⭐ | 0 |
| 007 | 模块清晰边界 | ✅ | ⭐⭐ | 7B |
| 008 | Git 版本策略 | ✅ | ⭐⭐ | 7B |

---

## 未来决策 (Phase 7C+)

计划中的 ADR 主题：
- [ ] ADR-009: 缓存策略 (Redis 集成)
- [ ] ADR-010: 向量数据库集成 (Milvus)
- [ ] ADR-011: 分布式事务处理
- [ ] ADR-012: 性能监控和告警
- [ ] ADR-013: 安全性和认证

---

**维护**: 每个新的重大决策应添加一个新的 ADR
**贡献**: 通过 PR 提议新的 ADR
**讨论**: ADR 相关讨论通过 GitHub Issues


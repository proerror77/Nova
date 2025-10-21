# Phase 7C - 模块集成规划

**状态**: 📋 规划中
**预计开始**: 即时 (2025-10-22 之后)
**预计完成**: 2025-11-05
**总工作量**: 11 个工作日

---

## 📋 执行概览

Phase 7C 将完成 Phase 7B 中推迟的 4 个模块的集成，使系统达到功能完整。

| 模块 | 优先级 | 复杂度 | 时间 | 状态 |
|------|--------|--------|------|------|
| Messaging | 1 | 🔴 高 | 3天 | 📋 规划中 |
| Neo4j 社交图 | 2 | 🟡 中 | 2天 | 📋 规划中 |
| Redis 缓存 | 3 | 🟢 低 | 1天 | 📋 规划中 |
| Streaming | 4 | 🔴 高 | 5天 | 📋 规划中 |

---

## 🎯 Phase 7C 目标

### 主要目标

1. ✅ 完成所有 4 个推迟的模块
2. ✅ 0 个编译错误
3. ✅ 100% 功能覆盖
4. ✅ 生产就绪质量

### 次要目标

- 改进测试覆盖率
- 性能优化
- 文档完整化
- 为 Phase 8 生产部署做准备

---

## 🚀 四个优先模块详解

### 优先级 1️⃣: Messaging 服务 (消息系统)

**位置**: `backend/user-service/src/services/messaging/`
**工作量**: 3 天
**复杂度**: 高 🔴
**关键路径**: 是 (用户可见功能)

#### 当前状态
```
❌ 12+ 编译错误
❌ 数据库层未实现
❌ WebSocket 处理不完整
❌ Kafka 集成缺失
```

#### 任务分解

**Task 1.1: 修复数据库层 (1 天)**
```rust
// db/messaging_repo.rs - 实现消息数据操作
pub struct MessageRepository { ... }

impl MessageRepository {
    pub async fn create_message(&self, msg: Message) -> Result<Uuid> { ... }
    pub async fn get_conversation(&self, user1: Uuid, user2: Uuid) -> Result<Vec<Message>> { ... }
    pub async fn mark_as_read(&self, message_id: Uuid) -> Result<()> { ... }
    pub async fn get_unread_count(&self, user_id: Uuid) -> Result<usize> { ... }
}
```

**Task 1.2: 完成 WebSocket 消息处理 (1 天)**
```rust
// services/messaging/websocket_handler.rs - WebSocket 路由和处理
pub struct MessagingWebSocketHandler { ... }

impl MessagingWebSocketHandler {
    pub async fn handle_connect(&self, user_id: Uuid, ws: WebSocket) { ... }
    pub async fn handle_message(&self, sender: Uuid, content: String) { ... }
    pub async fn handle_disconnect(&self, user_id: Uuid) { ... }
}
```

**Task 1.3: 集成 Kafka 事件队列 (1 天)**
```rust
// services/messaging/message_service.rs - 业务逻辑
pub struct MessageService { ... }

impl MessageService {
    pub async fn send_message(&self, from: Uuid, to: Uuid, content: String) -> Result<Message> {
        // 1. 保存到数据库
        // 2. 发送 Kafka 事件
        // 3. 通知接收者
    }
}
```

#### 验收标准
- [ ] 编译无错误
- [ ] 单元测试通过
- [ ] WebSocket 连接测试通过
- [ ] Kafka 事件路由验证
- [ ] 用户对用户消息端到端测试

#### 依赖
- Phase 7B core (✓ 已完成)
- WebSocket 基础设施 (✓ Phase 7A)
- Kafka 系统 (✓ Phase 7B)

---

### 优先级 2️⃣: Neo4j 社交图 (社交关系)

**位置**: `backend/user-service/src/services/neo4j_client.rs`
**工作量**: 2 天
**复杂度**: 中 🟡
**关键路径**: 是 (推荐系统依赖)

#### 当前状态
```
❌ 文件缺失
❌ Neo4j 客户端未实现
❌ 关系查询接口不存在
```

#### 任务分解

**Task 2.1: 实现 Neo4j 客户端 (1 天)**
```rust
// services/neo4j_client.rs - Neo4j 集成
pub struct Neo4jClient {
    uri: String,
    auth: Auth,
    driver: Driver,
}

impl Neo4jClient {
    pub async fn new(uri: &str) -> Result<Self> { ... }

    pub async fn create_user(&self, user_id: Uuid, props: UserProps) -> Result<()> { ... }
    pub async fn create_relationship(&self, user1: Uuid, user2: Uuid, rel_type: &str) -> Result<()> { ... }
    pub async fn get_followers(&self, user_id: Uuid) -> Result<Vec<Uuid>> { ... }
    pub async fn get_followings(&self, user_id: Uuid) -> Result<Vec<Uuid>> { ... }
    pub async fn get_mutual_follows(&self, user1: Uuid, user2: Uuid) -> Result<Vec<Uuid>> { ... }
}
```

**Task 2.2: 创建社交图 API (1 天)**
```rust
// services/social_graph_service.rs - 业务逻辑
pub struct SocialGraphService { ... }

impl SocialGraphService {
    pub async fn follow_user(&self, follower: Uuid, following: Uuid) -> Result<()> { ... }
    pub async fn unfollow_user(&self, follower: Uuid, following: Uuid) -> Result<()> { ... }
    pub async fn get_recommendations(&self, user_id: Uuid, limit: usize) -> Result<Vec<UserProfile>> { ... }
}
```

#### 验收标准
- [ ] 编译无错误
- [ ] Neo4j 连接验证
- [ ] 关系创建测试通过
- [ ] 查询性能基准测试
- [ ] 图遍历算法验证

#### 依赖
- Phase 7B core (✓)
- Messaging 服务 (✓ Task 1 完成后)

---

### 优先级 3️⃣: Redis 社交缓存 (缓存层)

**位置**: `backend/user-service/src/services/redis_social_cache.rs`
**工作量**: 1 天
**复杂度**: 低 🟢
**关键路径**: 否 (性能优化)

#### 当前状态
```
❌ 文件缺失
❌ 缓存策略未定义
❌ 失效机制不存在
```

#### 任务分解

**Task 3.1: 实现缓存层 (1 天)**
```rust
// services/redis_social_cache.rs - Redis 缓存
pub struct RedisSocialCache {
    redis: RedisClient,
}

impl RedisSocialCache {
    pub async fn get_followers(&self, user_id: Uuid) -> Result<Option<Vec<Uuid>>> { ... }
    pub async fn set_followers(&self, user_id: Uuid, followers: Vec<Uuid>) -> Result<()> { ... }
    pub async fn invalidate_user(&self, user_id: Uuid) -> Result<()> { ... }
    pub async fn invalidate_relationship(&self, user1: Uuid, user2: Uuid) -> Result<()> { ... }
}
```

#### 缓存策略

```
Key Pattern: social:followers:{user_id}
TTL: 24 小时
Invalidation:
  - 新增粉丝时立即失效
  - 用户信息更新时失效
  - 定时失效（24小时）
```

#### 验收标准
- [ ] 编译无错误
- [ ] 缓存命中率 > 80%
- [ ] 失效机制测试通过
- [ ] 分布式缓存协调验证

#### 依赖
- Neo4j 社交图 (✓ Task 2 完成后)
- Redis 系统 (✓ Phase 7B)

---

### 优先级 4️⃣: Streaming 工作区 (直播系统)

**位置**: `streaming/`
**工作量**: 5 天
**复杂度**: 高 🔴
**关键路径**: 是 (核心功能)

#### 当前状态
```
❌ 15 个编译错误
❌ RTMP 处理器不完整
❌ 会话管理有缺陷
❌ HLS/DASH 清单生成问题
```

#### 任务分解

**Task 4.1: 修复 RTMP 处理器 (2 天)**
```rust
// streaming/crates/streaming-ingest/src/rtmp_handler.rs
pub struct RtmpHandler { ... }

impl RtmpHandler {
    pub async fn handle_connect(&self, client_info: ClientInfo) -> Result<()> { ... }
    pub async fn handle_publish(&self, stream_key: String) -> Result<StreamSession> { ... }
    pub async fn handle_data(&self, session: &StreamSession, data: &[u8]) -> Result<()> { ... }
    pub async fn handle_disconnect(&self, session_id: Uuid) -> Result<()> { ... }
}
```

**Task 4.2: 修复会话管理 (1 天)**
```rust
// streaming/crates/streaming-core/src/session_manager.rs
pub struct SessionManager { ... }

impl SessionManager {
    pub async fn create_session(&self, stream_key: String) -> Result<StreamSession> { ... }
    pub async fn get_session(&self, session_id: Uuid) -> Result<Option<StreamSession>> { ... }
    pub async fn close_session(&self, session_id: Uuid) -> Result<()> { ... }
}
```

**Task 4.3: 集成到主 Cargo.toml (1 天)**
```toml
# 将 streaming workspace 集成到主工作区
[workspace]
members = [
    "backend/user-service",
    "streaming/crates/streaming-core",
    "streaming/crates/streaming-ingest",
    "streaming/crates/streaming-delivery",
    "streaming/crates/streaming-api",
]
```

**Task 4.4: 端到端测试 (1 天)**
- RTMP 连接测试
- 直播流质量测试
- HLS/DASH 清单验证
- 故障转移测试

#### 验收标准
- [ ] 编译无错误
- [ ] RTMP 直播流可以发送
- [ ] HLS/DASH 清单生成正确
- [ ] 低延迟测试 (<3秒)
- [ ] 1000+ 并发连接测试

#### 依赖
- 所有上述模块 (Tasks 1-3 完成后)

---

## 📅 执行时间表

### Week 1 (Days 1-3): Messaging + Neo4j

```
Day 1: Messaging 数据库层 + 启动 Neo4j 客户端
Day 2: Messaging WebSocket + Neo4j API
Day 3: Messaging Kafka 集成 + Neo4j 优化
```

### Week 2 (Days 4-7): Redis + Streaming 前期

```
Day 4: Redis 缓存实现 + Streaming RTMP 修复启动
Day 5: Streaming 会话管理
Day 6: Streaming 集成开始
Day 7: 集成和测试
```

### Week 3 (Days 8-11): Streaming 完成 + 验证

```
Day 8-9: Streaming 工作区完全集成
Day 10: 端到端测试和优化
Day 11: 最终验证和文档
```

---

## 🧪 测试策略

### 单元测试
```
Target: 80%+ 代码覆盖率
Tools: cargo test, tarpaulin
Tests: 每个模块 20+ 测试
```

### 集成测试
```
Messaging: WebSocket 连接、消息发送、Kafka 事件
Neo4j: 关系创建、查询、图遍历
Redis: 缓存命中、失效、分布式一致
Streaming: RTMP 连接、HLS/DASH 生成、故障转移
```

### 性能测试
```
Messaging: <100ms 消息延迟
Neo4j: <50ms 关系查询
Redis: <10ms 缓存查询
Streaming: <3秒 流启动延迟
```

---

## 📊 成功标准

### 构建标准
- [x] 0 编译错误
- [ ] <100 编译警告 (来自最多 Phase 7B 的 77)
- [ ] 所有 Clippy 建议处理

### 功能标准
- [ ] 所有 4 个模块完全实现
- [ ] 所有特性通过集成测试
- [ ] 无运行时 panic

### 性能标准
- [ ] Messaging: <100ms 延迟
- [ ] Neo4j 查询: <50ms
- [ ] Redis 查询: <10ms
- [ ] Streaming: <3s 启动

### 文档标准
- [ ] 每个模块有 API 文档
- [ ] 集成指南完成
- [ ] 性能指标文档
- [ ] 故障排除指南

---

## 🔄 依赖关系图

```
Phase 7B Core ✓
    │
    ├─→ Messaging (Task 1.1-1.3)
    │        │
    │        └─→ Neo4j (Task 2.1-2.2)
    │                 │
    │                 └─→ Redis (Task 3.1)
    │                       │
    └─→ Streaming (Task 4.1-4.4) ←─┘
         (可并行)
```

---

## 📈 进度跟踪

### Burndown Chart (计划)

```
Day 1:  11 tasks → 9 remaining
Day 2:  9 tasks  → 7 remaining
Day 3:  7 tasks  → 5 remaining
Day 4:  5 tasks  → 3 remaining
Day 5:  3 tasks  → 2 remaining
Day 6:  2 tasks  → 1 remaining
Day 7:  1 task   → 0 remaining ✓
```

---

## ⚠️ 风险和缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| Streaming 编译错误 | 高 | 高 | 每日编译检查 |
| 性能不达标 | 中 | 高 | 早期性能测试 |
| 依赖冲突 | 中 | 中 | 增量集成 |
| 测试覆盖不足 | 低 | 中 | TDD 方法 |

---

## 📝 完成清单

**Phase 7C 启动前**:
- [ ] develop/phase-7c 分支创建
- [ ] 开发环境准备
- [ ] 依赖验证
- [ ] 数据库迁移脚本准备

**每日**:
- [ ] 编译检查
- [ ] 测试运行
- [ ] 性能基准
- [ ] 进度更新

**每个 Task 完成后**:
- [ ] 代码审查
- [ ] 测试验证
- [ ] 文档更新
- [ ] Git 提交

**Phase 7C 完成时**:
- [ ] 所有模块集成
- [ ] 完整文档
- [ ] 性能验证
- [ ] 发布标签

---

## 📞 支持和协调

- **技术问题**: GitHub Issues
- **代码审查**: Pull Requests
- **进度同步**: 日常 standup
- **文档**: docs/ 目录
- **决策**: Architectural Decisions (ADR-009 onwards)

---

**计划创建人**: Claude Code
**计划完成时间**: 2025-10-22
**状态**: 📋 准备启动
**下一步**: 创建 develop/phase-7c 分支并开始 Task 1.1


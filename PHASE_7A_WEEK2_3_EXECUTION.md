# Phase 7A Week 2-3 执行计划
**状态**: 🚀 就绪 | **开始日期**: 2025-10-22 (周三) | **完成日期**: 2025-11-07 (周五)

## 📋 任务概览

### Week 2 (Oct 22-26): 实时通知系统 - 40 小时
| 天 | 任务 | 时间 | 目标 | 状态 |
|------|------|------|------|------|
| 周三-周四 | T201: Kafka消费者 + 批处理 | 16小时 | 30+ 测试 | 待启动 |
| 周五-周一 | T202: FCM/APNs 集成 | 16小时 | 25+ 测试 | 待启动 |
| 周二 | T203: WebSocket 处理器 | 8小时 | 20+ 测试 | 待启动 |

### Week 3 (Oct 27-31): 社交图优化 - 40 小时
| 天 | 任务 | 时间 | 目标 | 状态 |
|------|------|------|------|------|
| 周三 | T206.1: 集成测试 | 8小时 | 完整覆盖 | 待启动 |
| 周四-周一 | T234-T236: 核心实现 | 25小时 | 50+ 测试 | 待启动 |
| 周二 | T206.2 + 最终测试 | 6小时 | 全绿 | 待启动 |

---

## 🔧 Week 2 详细执行计划

### T201: Kafka消费者 + 批处理 (16小时)

**目标**: 实现高效的通知批处理引擎

**关键组件**:
```rust
// 1. KafkaNotificationConsumer (8小时)
pub struct KafkaNotificationConsumer {
    broker: String,
    topic: String,
    batch_size: usize,
    flush_interval: Duration,
}

impl KafkaNotificationConsumer {
    pub async fn start(&mut self) -> Result<()> {
        // 持续消费消息
        // 累积到批次大小
        // 定期刷新批次
    }
}

// 2. NotificationBatch (4小时)
pub struct NotificationBatch {
    notifications: Vec<Notification>,
    created_at: DateTime<Utc>,
}

impl NotificationBatch {
    pub async fn flush(&self) -> Result<usize> {
        // 批量插入数据库
        // 返回成功数量
    }
}

// 3. 错误处理和重试 (4小时)
pub struct RetryPolicy {
    max_retries: u32,
    backoff: Duration,
}
```

**测试覆盖** (30+ 测试):
- 单个消息处理 (5)
- 批处理逻辑 (6)
- 错误恢复 (5)
- 性能基准 (8)
- 端到端流 (6)

**验收标准**:
- ✅ P95延迟 < 500ms
- ✅ 吞吐量 ≥ 10k msg/sec
- ✅ 成功率 > 99%
- ✅ 测试覆盖 > 85%

---

### T202: FCM/APNs 集成 (16小时)

**目标**: 连接Firebase Cloud Messaging和Apple Push Notification

**关键组件**:
```rust
// 1. FCMClient (6小时)
pub struct FCMClient {
    project_id: String,
    credentials: ServiceAccountKey,
}

impl FCMClient {
    pub async fn send(&self, notification: &Notification) -> Result<String> {
        // 格式化FCM请求
        // 发送到Google API
        // 处理响应和错误
    }
}

// 2. APNsClient (6小时)
pub struct APNsClient {
    certificate_path: String,
    key_path: String,
}

impl APNsClient {
    pub async fn send(&self, notification: &Notification) -> Result<String> {
        // 建立与Apple服务器连接
        // 发送推送通知
        // 处理反馈
    }
}

// 3. 多平台路由 (4小时)
pub async fn route_notification(
    notification: &Notification,
    user_device: &UserDevice,
) -> Result<SendResult> {
    match user_device.platform {
        Platform::Android => fcm_client.send(notification).await,
        Platform::iOS => apns_client.send(notification).await,
    }
}
```

**测试覆盖** (25+ 测试):
- FCM单元测试 (8)
- APNs单元测试 (8)
- 路由逻辑 (5)
- 错误处理 (4)

**验收标准**:
- ✅ 发送成功率 > 99%
- ✅ 故障自动降级
- ✅ 完整审计日志
- ✅ 所有测试通过

---

### T203: WebSocket处理器 (8小时)

**目标**: 实现实时推送通知的WebSocket服务

**关键组件**:
```rust
// 1. WebSocketHandler (4小时)
pub struct WebSocketHandler {
    connected_clients: Arc<DashMap<UserId, Sender<Message>>>,
}

impl WebSocketHandler {
    pub async fn handle_connection(&self, user_id: UserId, ws: WebSocket) {
        // 建立连接
        // 维持活动心跳
        // 处理断开连接
    }
}

// 2. 通知广播 (3小时)
pub async fn broadcast_notification(
    handler: &WebSocketHandler,
    notification: &Notification,
) -> Result<BroadcastResult> {
    // 查找用户连接
    // 发送WebSocket消息
    // 记录传递状态
}

// 3. 连接管理 (1小时)
pub struct ConnectionPool {
    max_connections: usize,
    timeout: Duration,
}
```

**测试覆盖** (20+ 测试):
- 连接建立 (4)
- 消息传递 (5)
- 断开连接 (3)
- 并发连接 (5)
- 性能测试 (3)

**验收标准**:
- ✅ 连接延迟 < 100ms
- ✅ 消息延迟 P95 < 200ms
- ✅ 支持10k+ 并发连接
- ✅ 自动重连

---

## 🔧 Week 3 详细执行计划

### T206.1 + T234-T236: 社交图优化 (39小时)

**目标**: 实现高性能社交图查询和推荐算法

**核心指标**:
- 关系查询延迟: < 50ms (P95)
- 推荐生成: < 500ms
- 图遍历效率: 处理 1M+ 节点

**主要组件**:
```rust
// 1. 图存储接口 (8小时)
pub trait SocialGraphStore {
    async fn add_follow(&self, follower: UserId, following: UserId) -> Result<()>;
    async fn remove_follow(&self, follower: UserId, following: UserId) -> Result<()>;
    async fn get_followers(&self, user_id: UserId, limit: usize) -> Result<Vec<UserId>>;
    async fn get_following(&self, user_id: UserId, limit: usize) -> Result<Vec<UserId>>;
    async fn get_mutual_follows(&self, user_id1: UserId, user_id2: UserId) -> Result<Vec<UserId>>;
}

// 2. Neo4j实现 (10小时)
pub struct Neo4jGraphStore {
    driver: Driver,
}

impl SocialGraphStore for Neo4jGraphStore {
    async fn get_followers(&self, user_id: UserId, limit: usize) -> Result<Vec<UserId>> {
        // Cypher查询: MATCH (u:User)-[:FOLLOWS]->(target:User {id: $user_id})
        // 返回结果
    }
}

// 3. 推荐算法 (12小时)
pub struct RecommendationEngine {
    graph_store: Arc<dyn SocialGraphStore>,
}

impl RecommendationEngine {
    pub async fn recommend_users(
        &self,
        user_id: UserId,
        limit: usize,
    ) -> Result<Vec<(UserId, f32)>> {
        // 1. 获取用户的关注者
        // 2. 计算相似度 (基于共同关注)
        // 3. 按分数排序
        // 4. 返回Top-N
    }
}

// 4. 缓存层 (7小时)
pub struct GraphCache {
    redis: Arc<redis::Client>,
    ttl: Duration,
}
```

**测试覆盖** (50+ 测试):
- 图操作单元测试 (15)
- 推荐算法单元测试 (12)
- 集成测试 (15)
- 性能基准 (8)

**验收标准**:
- ✅ 所有查询 < 50ms
- ✅ 推荐准确率 > 85%
- ✅ 缓存命中率 > 80%
- ✅ 支持 1M+ 用户

---

## 📊 成功标准

### 代码质量
- ✅ 零编译错误
- ✅ 零 clippy 警告
- ✅ 测试覆盖 > 85% 每个模块
- ✅ 所有代码已审查

### 性能
- ✅ 通知P95延迟 < 500ms
- ✅ 社交图查询 < 50ms
- ✅ 吞吐量满足SLA
- ✅ 内存使用 < 1GB

### 测试
- ✅ 215+ 测试全部通过
- ✅ 端到端验证通过
- ✅ 负载测试通过
- ✅ 灾难恢复验证通过

### 文档
- ✅ API文档完整
- ✅ 部署指南完整
- ✅ 故障排查指南完整
- ✅ 性能调优指南完整

---

## 🚀 启动清单

**启动前验证** (待完成):
- [ ] 所有工程师确认分配
- [ ] 开发环境验证就绪
- [ ] Docker Compose 验证成功
- [ ] 数据库迁移验证
- [ ] 文档已全部阅读
- [ ] 第一次站会定于周三 10:00 AM

**分支策略**:
- Feature分支: `feature/t201-kafka-consumer`, `feature/t202-fcm-apns`, 等
- 每个任务独立分支
- 每日 PR 审查
- 周五合并到主分支

**每日检查点**:
- 10:00 AM: 团队站会 (15分钟)
- 12:00 PM: 进度检查 (必要时)
- 4:00 PM: 代码审查
- 5:00 PM: 每日提交

---

## ⚠️ 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| Kafka连接问题 | T201延迟 | 预先验证Docker配置 |
| FCM配额限制 | T202阻塞 | 准备降级策略 |
| Neo4j性能 | T234延迟 | 准备缓存策略 |
| 团队协作 | 延迟交付 | 每日站会同步 |

---

## 📞 关键联系方式

- **技术主管**: [TBD]
- **通知系统负责人**: [TBD]
- **社交图负责人**: [TBD]
- **QA主管**: [TBD]
- **Slack频道**: #phase-7a-week2-3

---

**最后更新**: 2025-10-21 | **下一次审查**: 周三启动后

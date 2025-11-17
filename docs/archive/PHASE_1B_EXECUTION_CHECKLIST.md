# Phase 1B 执行清单 - 周期计划和交付物

**生成日期**: 2025-11-06
**分支**: feature/phase1-grpc-migration
**状态**: 准备启动

---

## 📅 Week 1: 基础架构 (Outbox + Events)

### 日期: 2025-11-10 ~ 2025-11-16

#### Task 1.1: Outbox 模式库 (16h)

**成员**: 1 名资深工程师 + Serena

**交付物**:
- [ ] `backend/libs/event-schema/src/outbox.rs` (已提供框架)
- [ ] `backend/libs/event-schema/src/events.rs` (已提供框架)
- [ ] 数据库迁移文件 (已提供 SQL)
- [ ] 单元测试 (100% 覆盖率)
- [ ] 文档: 事件协议说明

**验收标准**:
- ✅ 编译无警告
- ✅ 所有单元测试通过
- ✅ 支持 15+ 事件类型
- ✅ 序列化/反序列化正确

**里程碑**:
- 周一-周二: 代码实现 (8h)
- 周三: 单元测试和文档 (4h)
- 周四: Code review 和修复 (4h)

---

#### Task 1.2: events-service 核心 (32h)

**成员**: 2 名工程师 (1 名 gRPC, 1 名数据库)

**分工**:
- **工程师 A** (gRPC 和 Kafka):
  - [ ] PublishEvent RPC 实现
  - [ ] SubscribeToEvents RPC (Kafka 流)
  - [ ] GetEventSchema RPC
  - [ ] RPC 单元测试 (16h)

- **工程师 B** (Outbox 和后台任务):
  - [ ] Outbox 发布器实现
  - [ ] 后台任务集成
  - [ ] 数据库操作和索引优化
  - [ ] 性能测试 (16h)

**交付物**:
- [ ] `backend/events-service/src/services/outbox.rs` (已提供框架)
- [ ] `backend/events-service/src/grpc/mod.rs` (更新)
- [ ] `backend/events-service/src/db/migrations.sql` (已提供)
- [ ] 集成测试 (5 个测试用例)
- [ ] 性能基准报告

**验收标准**:
- ✅ PublishEvent 延迟 < 100ms (P95)
- ✅ Outbox 发布成功率 > 99.99%
- ✅ 支持 1000 events/sec
- ✅ Kafka 消息无遗漏
- ✅ 集成测试全部通过

**里程碑**:
- 周一-周二: RPC 框架 (8h)
- 周三: Outbox 实现 (8h)
- 周四-周五: 测试和优化 (16h)

**Kafka 配置** (需要提前准备):
```yaml
bootstrap.servers: kafka:9092
num.partitions: 10
replication.factor: 2
retention.ms: 7 days
```

---

#### Task 1.3: messaging-service user_id 提取 (8h)

**成员**: 1 名工程师

**交付物**:
- [ ] `backend/messaging-service/src/grpc/mod.rs` (更新第 292 行)
  - [ ] 添加 `extract_user_id()` 函数
  - [ ] 在所有 RPC 中应用
- [ ] 单元测试 (3 个测试用例)
- [ ] 文档: gRPC metadata 规范

**验收标准**:
- ✅ 所有 RPC 正确提取 user_id
- ✅ 缺少 x-user-id 返回 401
- ✅ 无额外延迟 (< 1ms)

**里程碑**:
- 周一: 代码实现 (4h)
- 周二-周三: 测试和集成 (4h)

---

### Week 1 同步节点

**周三 11:00 (晨会)**:
- 进度汇报 (Outbox 库 + events-service gRPC)
- 阻塞点讨论
- 验收标准确认

**周五 17:00 (周末评审)**:
- 代码审查 (所有 Task 1.x)
- 集成测试运行
- 下周计划确认

---

## 📅 Week 2: 通知和搜索系统

### 日期: 2025-11-17 ~ 2025-11-23

#### Task 2.1: notification-service (24h)

**成员**: 2 名工程师

**分工**:
- **工程师 A** (gRPC CRUD):
  - [ ] CreateNotification / GetNotification
  - [ ] ListNotifications / MarkAsRead
  - [ ] RegisterPushToken / UnregisterPushToken
  - [ ] RPC 单元测试 (12h)

- **工程师 B** (Kafka 和推送):
  - [ ] Kafka consumer 实现
  - [ ] 批处理逻辑 (100 条缓冲，5s 刷新)
  - [ ] FCM/APNs 集成
  - [ ] 错误处理和重试 (12h)

**交付物**:
- [ ] `backend/notification-service/src/grpc.rs` (更新)
- [ ] `backend/notification-service/src/services/kafka_consumer.rs` (完成第 101-107 行)
- [ ] `backend/notification-service/src/services/push_sender.rs` (新增)
- [ ] 数据库 schema (3 个表)
- [ ] 集成测试

**验收标准**:
- ✅ Kafka 消费延迟 < 10 秒
- ✅ 推送发送成功率 > 99%
- ✅ 批处理吞吐量 > 1000 通知/秒
- ✅ 无重复通知

**关键依赖**:
- ✅ events-service 正常运行
- ✅ Kafka topics 已创建
- ✅ FCM/APNs 配置已设置

---

#### Task 2.2: search-service (20h)

**成员**: 2 名工程师

**分工**:
- **工程师 A** (Elasticsearch):
  - [ ] Elasticsearch 集成
  - [ ] FullTextSearch RPC
  - [ ] SearchPosts / SearchUsers RPC
  - [ ] 索引管理和同步 (10h)

- **工程师 B** (建议和热搜):
  - [ ] GetSearchSuggestions RPC
  - [ ] GetTrendingSearches RPC
  - [ ] ClickHouse 集成
  - [ ] 缓存和优化 (10h)

**交付物**:
- [ ] `backend/search-service/src/grpc.rs` (完成第 25-88 行)
- [ ] `backend/search-service/src/services/elasticsearch.rs` (新增)
- [ ] `backend/search-service/src/services/clickhouse.rs` (新增)
- [ ] Elasticsearch 索引定义
- [ ] ClickHouse 表定义
- [ ] 集成测试

**验收标准**:
- ✅ 搜索延迟 < 500ms (P95)
- ✅ 索引同步 < 5 秒
- ✅ 搜索精度 > 95%
- ✅ 建议响应 < 200ms

---

### Week 2 同步节点

**周四 15:00 (进度检查)**:
- notification-service 70% 进度
- search-service 50% 进度
- 阻塞点讨论

**周五 17:00 (周末评审)**:
- 代码审查
- 集成测试
- 性能基准报告

---

## 📅 Week 3: 推荐和直播

### 日期: 2025-11-24 ~ 2025-11-30

#### Task 3.1: feed-service 推荐算法 (24h)

**成员**: 2 名工程师 (1 名算法，1 名工程)

**交付物**:
- [ ] `backend/feed-service/src/services/recommendation_v2/collaborative_filtering.rs` (完成第 83 行)
- [ ] `backend/feed-service/src/services/recommendation_v2/content_based.rs` (完成第 49, 67 行)
- [ ] `backend/feed-service/src/services/recommendation_v2/onnx_serving.rs` (完成第 81 行)
- [ ] `backend/feed-service/src/services/recommendation_v2/ab_testing.rs` (完成第 76, 135, 149, 157 行)
- [ ] `backend/feed-service/src/services/recommendation_v2/hybrid_ranker.rs` (完成第 192, 279 行)
- [ ] ClickHouse 集成
- [ ] 单元测试和集成测试

**验收标准**:
- ✅ 推荐延迟 < 200ms (P95)
- ✅ 缓存命中率 > 90%
- ✅ ONNX 吞吐量 > 10k/sec
- ✅ A/B 测试统计显著 (p < 0.05)

---

#### Task 3.2: streaming-service (20h)

**成员**: 2 名工程师

**交付物**:
- [ ] `backend/streaming-service/src/main.rs` (更新第 200 行 HTTP 路由)
- [ ] `backend/streaming-service/src/grpc.rs` (完成第 54-183 行)
- [ ] `backend/streaming-service/src/services/streaming/repository.rs` (完成第 350 行)
- [ ] `backend/streaming-service/src/services/streaming/redis_counter.rs` (完成第 223-247 行)

**验收标准**:
- ✅ 支持 10k+ 并发观众
- ✅ 消息延迟 < 1 秒
- ✅ 播放启动 < 3 秒
- ✅ HLS 转码正常

---

### Week 3 同步节点

**周四 15:00**:
- feed-service 推荐 50% 进度
- streaming-service 框架完成

**周五 17:00**:
- 全面代码审查
- 集成测试
- Week 4 计划

---

## 📅 Week 4: CDN 和集成测试

### 日期: 2025-12-01 ~ 2025-12-07

#### Task 3.3: cdn-service (12h)

**成员**: 1 名工程师

**交付物**:
- [ ] `backend/cdn-service/src/grpc.rs` (完成第 25-104 行)
- [ ] `backend/cdn-service/src/services/cdn_provider.rs` (新增)
- [ ] `backend/cdn-service/src/services/image_processor.rs` (新增)

**验收标准**:
- ✅ URL 生成 < 50ms
- ✅ CDN 缓存命中率 > 95%
- ✅ 图像处理 < 1 秒

---

#### Task 4.1: 跨服务集成测试 (16h)

**成员**: 2 名 QA 工程师

**测试场景**:
1. [ ] messaging + notification (发消息 → 收通知)
2. [ ] content + search (发布内容 → 可搜索)
3. [ ] search + ranking (搜索结果 → feed 推荐)
4. [ ] streaming + messages (直播 → 实时聊天)
5. [ ] events + 所有服务 (端到端事件流)

**交付物**:
- [ ] 集成测试脚本 (5 个场景)
- [ ] 性能基准报告
- [ ] 故障恢复验证

**验收标准**:
- ✅ 所有场景通过
- ✅ 端到端延迟 < 500ms (P95)
- ✅ 网络分区自动恢复
- ✅ 无数据遗漏

---

### Week 4 最终评审

**周五 17:00 (Phase 1B 完成评审)**:
- 所有任务完成度确认 (目标 100%)
- 性能基准对标
- 生产部署前检查清单
- 文档和知识库更新

---

## 🔄 跨周期依赖

```
Week 1: Outbox + events-service
  ├─ Task 1.1 (Outbox) ✓
  └─ Task 1.2 (events-service) ✓
      └─ 阻塞 Week 2: notification + search

Week 2: notification-service + search-service
  ├─ Task 2.1 (notification) ✓
  │   └─ 依赖: events-service 正常
  └─ Task 2.2 (search) ✓
      └─ 依赖: events-service + Elasticsearch

Week 3: feed-service 推荐 + streaming-service
  ├─ Task 3.1 (feed) ✓
  │   └─ 依赖: ONNX 模型 + Redis + ClickHouse
  └─ Task 3.2 (streaming) ✓
      └─ 依赖: Nginx RTMP + Kafka

Week 4: cdn-service + 集成测试
  ├─ Task 3.3 (cdn) ✓
  │   └─ 依赖: S3 + CloudFront
  └─ Task 4.1 (集成测试) ✓
      └─ 依赖: 所有服务 > 80% 完成
```

---

## 📊 周度成果指标

### Week 1 成果
```
代码行数: ~2500 lines
功能点: 15+ 事件类型定义 + Outbox 发布器
测试: 25+ 单元测试
覆盖率: 85%+
```

### Week 2 成果
```
代码行数: ~3000 lines
功能点: notification CRUD + Kafka + search 全文
测试: 30+ 集成测试
吞吐量: > 5000 req/sec
```

### Week 3 成果
```
代码行数: ~2800 lines
功能点: 推荐算法 + 直播核心
测试: 20+ 端到端测试
模型精度: > 95%
```

### Week 4 成果
```
代码行数: ~1200 lines
功能点: CDN + 完整集成
测试: 全场景覆盖
准备度: 100% 生产就绪
```

---

## 🎯 关键里程碑和 go/no-go 决策

### Go/No-Go 1: Week 1 末 (2025-11-16)

**必须达成**:
- ✅ Outbox 表无警告创建
- ✅ events-service 启动正常
- ✅ Kafka 消费可用
- ✅ 集成测试通过

**如果不达成**: 延迟 Week 2 启动

---

### Go/No-Go 2: Week 2 末 (2025-11-23)

**必须达成**:
- ✅ notification-service CRUD 完成
- ✅ search-service 基础功能完成
- ✅ Kafka 消费延迟 < 10s
- ✅ 推送成功率 > 95%

**如果不达成**: 追加资源到 Week 3

---

### Go/No-Go 3: Week 4 末 (2025-12-07)

**必须达成**:
- ✅ 所有服务 > 90% 完成
- ✅ 集成测试全部通过
- ✅ 性能基准达标
- ✅ 零 P1 级别 bug

**如果达成**: 准备生产部署

---

## 📋 资源分配

### 工程师配置 (推荐)

```
总计: 5-6 名工程师

Week 1:
  ├─ 1 名资深 (Outbox + events)
  ├─ 1 名工程 (Outbox 库)
  └─ 1 名工程 (messaging user_id)

Week 2-3:
  ├─ 1 名工程 (notification RPC)
  ├─ 1 名工程 (notification Kafka)
  ├─ 1 名工程 (search Elasticsearch)
  ├─ 1 名工程 (search 建议)
  ├─ 1 名算法 (feed 推荐)
  └─ 1 名工程 (feed 工程)

Week 4:
  ├─ 1 名工程 (streaming)
  ├─ 1 名工程 (cdn)
  ├─ 2 名 QA (集成测试)
  └─ 1 名架构 (code review)
```

### 基础设施需求

```
✓ PostgreSQL 15+ (已有)
✓ Kafka 3.x (已部署)
✓ Elasticsearch 8.x (已有)
✓ ClickHouse (需要新建)
✓ Redis 7+ (已有)
✓ Nginx RTMP (需要新建)
✓ FCM 和 APNs 账户 (已配置)
```

---

## 📝 文档和交付清单

### 代码交付

- [x] IMPLEMENTATION_PLAN_PHASE_1B.md (详细规划)
- [x] QUICK_START_PHASE_1B.md (快速开始)
- [x] PHASE_1B_ARCHITECTURE_SUMMARY.md (架构设计)
- [x] CODE_SCAFFOLDS_PHASE_1B.md (代码框架)
- [x] PHASE_1B_EXECUTION_CHECKLIST.md (本文档)

### 代码和测试

- [ ] 所有 gRPC proto 文件更新
- [ ] 所有服务完成实现
- [ ] 500+ 单元和集成测试
- [ ] 性能基准报告
- [ ] API 文档更新

### 运维和部署

- [ ] Docker 镜像更新
- [ ] Kubernetes manifests 更新
- [ ] 数据库迁移脚本
- [ ] 监控和告警规则
- [ ] 灾难恢复文档

---

## 🚀 启动核清单

**立即执行 (今天)**:

- [ ] 分配 5 名工程师到 Task 1.1 和 1.2
- [ ] 准备 ClickHouse 集群
- [ ] 准备 Nginx RTMP 服务器
- [ ] 创建 Jira epic 和任务
- [ ] 第一次技术同步 (明天上午)

**Week 1 周一早上**:

- [ ] 工程师到位
- [ ] 开发环境验证
- [ ] 代码 review 工作流设置
- [ ] 日志和监控配置
- [ ] 第一次代码 push

---

**准备好启动 Phase 1B 了吗?** 🚀

所有文档已准备就绪。下一步: 分配工程师、启动 Week 1。

预计 4-6 周内完成全部实现。

# Nova Backend Phase 1 实现规划 - 执行摘要

**生成日期**: 2025-11-06  
**状态**: Phase 1 gRPC 迁移 66% 完成  
**总工作量**: 290-520 小时（取决于架构决策）

---

## 一页纸总结

| 维度 | 现状 | 目标 | 时间 |
|------|------|------|------|
| **已完成** | 3 个完整服务 (✅) | 7 个完整服务 | 4-6 周 |
| **关键路径** | content-service (75%) | feed-service (100%) | 200h 剩余 |
| **阻塞点** | events-service (10%) | 事件可靠性 (100%) | Week 1-2 (110h) |
| **最大风险** | 跨服务数据一致性 | CDC + Outbox 验证 | Week 3-4 |
| **性能目标** | Feed P95: 未知 | P95 < 800ms | Week 4-5 |

---

## 完成度地图

```
messaging-service     ███████████████████ 100% ✅
auth-service          ██████████████████░  95% ⏳
user-service          █████████████████░░  85% ⏳
content-service       ███████████████░░░░  75% ⏳
feed-service          ██████████████░░░░░  70% ⏳
streaming-service     ████████████░░░░░░░  65% ⏳
search-service        █░░░░░░░░░░░░░░░░░░   5% ❌
notification-service  ██░░░░░░░░░░░░░░░░░  15% ❌
events-service        █░░░░░░░░░░░░░░░░░░  10% ❌
cdn-service           █░░░░░░░░░░░░░░░░░░  10% ❌
```

---

## 优先级决策矩阵

### 🔴 关键路径服务 (必须做)

| 服务 | 工时 | 原因 | 阻塞 |
|------|------|------|------|
| **events-service** | 110h | 所有服务的事件基础 | 所有其他服务 |
| **notification-service** | 80h | 用户体验关键 | Feed, Streaming |
| **search-service** | 70h | Feed 推荐依赖 | Feed-service |
| **feed-service** | 100h | 核心产品 | 无（但依赖其他） |

**合计**: 360 小时 (关键路径)

### 🟡 优化与完善 (可延后)

| 服务 | 工时 | 延后策略 |
|------|------|---------|
| streaming-service | 65h | Phase 2 (非核心路径) |
| cdn-service | 50h | Phase 2 (媒体优化) |
| content-service 完善 | 45h | Phase 2 (已 75% 完成) |

**合计**: 160 小时 (可选)

---

## 关键发现（Linus 视角）

### ⚠️ 架构问题

**问题**: 7 个服务各自维护相同概念（reactions, likes, follows），导致：
- 数据不一致（reactions 在 messaging, content, feed 中定义不同）
- 查询分散（3 种不同的 SQL 模式获取同一个数据）
- 缓存冲突（4 种不同的 Redis TTL 策略）

**解决方案**: 建立统一的事件流
```
所有变化 → PostgreSQL (业务数据) + Outbox (事件)
        → Kafka (事件发布)
        → 各服务订阅事件 (独立消费)
```

### 💡 工作量现实调整

**原始估计**: 520 小时  
**现实估计**: 290 小时 + 40 小时架构  
**原因**: 
- 搜索不需要 70h (30h 足够 PostgreSQL FTS)
- Feed 排序不需要 100h (60h 足够基础实现)
- 测试不需要 30 个场景 (10 个关键场景足够)

### 🎯 实施策略

**两条路选择**:

**路线 A: 快速完成** (520h, 6 周)
- ❌ 大概率架构问题导致返工
- ❌ 最终花 800+ 小时

**路线 B: 设计先行** (330h, 4 周)
- ✅ 先花 40h 完善架构
- ✅ 然后 4 周高效执行
- ✅ 后续可自信优化

**建议**: 采用路线 B

---

## 具体执行计划

### Week 1: 架构基础 [40h]

```
Day 1-2: Outbox 模式设计
  ├─ PostgreSQL outbox 表设计
  ├─ Kafka 事件发送线程
  └─ 原子性验证

Day 3-4: 错误处理统一
  ├─ gRPC 错误码规范
  ├─ 所有服务集成 RequestGuard
  └─ 测试覆盖

Day 5: 性能基线
  ├─ 建立监控指标
  ├─ P95/P99 延迟基线
  └─ 告警规则配置
```

### Week 2: 事件系统 [80h]

```
关键路径: events-service (必须完成)
├─ PublishEvent (Kafka 实现)
├─ Event Schema (JSON 验证)
├─ CDC 消费验证
└─ 集成测试 (20+ 用例)

并行: content-service 完善 (30h)
├─ 评论系统分页
├─ 视频关联迁移
└─ 内容审核钩子
```

### Week 3: 消费者系统 [80h]

```
关键路径: notification-service (必须完成)
├─ PostgreSQL 通知表
├─ Redis 缓存 (unread count)
├─ Kafka 消费 (events → notifications)
├─ APNs/FCM 推送
└─ 集成测试 (15+ 用例)

并行: search-service 基础 (35h)
├─ PostgreSQL FTS 索引
├─ FullTextSearch RPC
├─ SearchUsers / SearchPosts
└─ Redis 缓存
```

### Week 4: Feed 推荐 [100h]

```
关键路径: feed-service 完整 (必须完成)
├─ Kafka 消费 (posts, users, follows)
├─ 混合排序算法 (协同 + 内容)
├─ Redis 缓存预热
├─ search-service 完成 (SearchSuggestions)
└─ 性能测试 (P95 < 800ms)
```

### Week 5+: 优化与完善 [160h]

```
Phase 2 (可延后):
├─ ONNX 模型集成 (30h)
├─ streaming-service 完成 (65h)
├─ cdn-service 完成 (50h)
└─ 性能优化与基准测试 (40h)
```

---

## 关键数字

### 时间分布

```
架构设计         40h  (12%)
事件基础设施     80h  (24%)
消费系统        80h  (24%)
Feed 推荐      100h  (30%)
优化完善       160h  (10%)
────────────────────
总计           460h
```

### 风险分布

```
事件系统设计缺陷    30% 概率 × 10 影响 = 300 分
跨服务数据不一致   20% 概率 × 9  影响 = 180 分
ONNX 模型性能      50% 概率 × 6  影响 = 300 分
缓存一致性问题    40% 概率 × 8  影响 = 320 分
Kafka 可靠性       10% 概率 × 9  影响 = 90 分
```

**最高风险**: 跨服务数据一致性  
**建议**: Week 1-2 额外 20h 进行架构评审

---

## 成功指标（周度检查）

| Week | 目标 | 检查点 |
|------|------|--------|
| 1 | 架构完善 | Outbox ✅, 错误处理 ✅ |
| 2 | 事件可靠 | events-svc ✅, 集成测试 > 10 |
| 3 | 消费就绪 | notif-svc ✅, search-svc ✅ |
| 4 | Feed 功能 | feed-svc ✅, P95 < 800ms |
| 5+ | 优化完成 | ONNX ✅, streaming ✅ |

---

## 前置条件检查清单

### 基础设施 (需要 Pre-Week 1)

- [x] PostgreSQL 14+ (66 migrations 已完成)
- [x] Redis 7+ (连接池就绪)
- [x] Kafka 3.0+ (集群已部署)
- [ ] Milvus 2.3+ (向量搜索) - **待部署**
- [ ] APNs 凭证 (iOS 推送) - **待配置**
- [ ] FCM 凭证 (Android 推送) - **待配置**
- [ ] CloudFront/Cloudflare API 密钥 - **待配置**

### 关键依赖库 (已完成)

- [x] grpc-metrics (RED 指标)
- [x] grpc-clients (统一客户端)
- [x] crypto-core (JWT/加密)
- [x] redis-utils (连接池)
- [x] error-handling (统一错误)

---

## 推荐路径

**推荐采用路线 B** (设计先行，4 周执行)：

1. **Week 0 (可选但强烈推荐)**
   - 团队评审架构设计 (2h)
   - 确认 Outbox 模式实现 (3h)
   - 确认事件协议规范 (2h)
   - 总计: 7h 的讨论 >> 100h 的返工

2. **Week 1-4**: 按计划执行关键路径

3. **Week 5+**: 根据市场反馈调整优化

---

## 下一步行动

1. **立即** (今天)
   - [ ] 团队评审本文档 (30min)
   - [ ] 确认资源分配 (1h)
   - [ ] 创建 Jira epic

2. **本周** (Week 0)
   - [ ] 架构设计评审会 (2h)
   - [ ] Outbox 模式代码设计 (4h)
   - [ ] 事件协议 proto 完善 (3h)

3. **下周** (Week 1)
   - [ ] PostgreSQL Outbox 迁移
   - [ ] Kafka 配置验证
   - [ ] 错误处理库集成

---

## 文档索引

| 文档 | 用途 | 读者 |
|------|------|------|
| **IMPLEMENTATION_PLAN.md** | 详细工作量估算 | 项目经理 |
| **LINUS_ARCHITECTURE_ANALYSIS.md** | 设计哲学与方法论 | 架构师 |
| **DEPENDENCY_MATRIX.txt** | 服务依赖关系 | 开发团队 |
| **IMPLEMENTATION_SUMMARY.md** | 本文档 - 执行摘要 | 所有人 |

---

## 联系与反馈

- **架构问题**: 联系架构师评审 LINUS_ARCHITECTURE_ANALYSIS.md
- **时间调整**: 基于实际进展调整 IMPLEMENTATION_PLAN.md
- **依赖问题**: 参考 DEPENDENCY_MATRIX.txt 中的依赖关系

---

**版本**: 1.0  
**状态**: 待团队确认  
**最后更新**: 2025-11-06

# Phase 7A Week 2-3 任务追踪 (Task Tracking)

**周期**: Week 2-3 (Oct 21 - Nov 4, 2025)
**状态**: 🚀 Ready for Execution
**总任务**: 6 个功能任务 + 测试任务

---

## 📋 快速概览

| 周次 | 功能 | 任务 ID | 分支名 | 工程师 | 状态 | 预计完成 |
|------|------|--------|-------|--------|------|---------|
| W2 | Notifications (Kafka) | T201 | `feature/T201-kafka-notifications` | [分配中] | 📋 准备中 | Wed 10/23 |
| W2 | FCM/APNs 集成 | T202 | `feature/T202-fcm-apns-integration` | [分配中] | 📋 准备中 | Thu 10/24 |
| W2 | WebSocket 处理 | T203 | `feature/T203-websocket-handler` | [分配中] | 📋 准备中 | Fri 10/25 |
| W3 | Neo4j 社交图 | T234 | `feature/T234-neo4j-social-graph` | [分配中] | 📋 准备中 | Wed 10/29 |
| W3 | Redis 缓存 | T235 | `feature/T235-redis-social-cache` | [分配中] | 📋 准备中 | Thu 10/30 |
| W3 | 测试套件 | T236 | `feature/T236-social-graph-tests` | [分配中] | 📋 准备中 | Fri 10/31 |

---

## 📝 详细任务说明

### Week 2: 实时通知系统 (Notifications)

#### T201: Kafka 消费者 & 批处理

**分支**: `feature/T201-kafka-notifications`

**说明**:
- 实现 Kafka 消费者初始化
- 批量聚合逻辑 (batch aggregation)
- 错误恢复机制

**关键文件**:
- `backend/services/notification-service/src/kafka_consumer.rs`
- `backend/services/notification-service/src/batch_aggregator.rs`
- `backend/services/notification-service/tests/`

**性能目标**:
- 批处理吞吐量: 10k msg/sec
- 延迟 (P95): <50ms
- 内存占用: <100MB

**测试需求**:
- Unit tests: 30+ (覆盖率 >90%)
- Integration tests: 10+ (模拟 Kafka)

**完成标准**:
- [ ] 代码通过 `cargo clippy`
- [ ] 所有测试通过
- [ ] 代码审查批准
- [ ] 性能基准达成

**时间**: 16 小时 (Mon 10/20 - Tue 10/21)

---

#### T202: FCM/APNs 集成

**分支**: `feature/T202-fcm-apns-integration`

**说明**:
- Firebase Cloud Messaging (FCM) 集成
- Apple Push Notification Service (APNs) 集成
- 重试机制 + 死信队列

**关键文件**:
- `backend/services/notification-service/src/fcm_handler.rs`
- `backend/services/notification-service/src/apns_handler.rs`
- `backend/services/notification-service/src/retry_policy.rs`

**性能目标**:
- 推送成功率: >99%
- 送达延迟 (P95): <500ms

**测试需求**:
- Unit tests: 25+ (覆盖率 >85%)
- Integration tests: 8+ (模拟 FCM/APNs API)

**完成标准**:
- [ ] FCM 和 APNs 均实现
- [ ] 错误处理完备
- [ ] 所有测试通过
- [ ] 代码审查批准

**时间**: 16 小时 (Wed 10/22 - Thu 10/23)

---

#### T203: WebSocket 处理器

**分支**: `feature/T203-websocket-handler`

**说明**:
- WebSocket 连接管理
- 实时消息广播
- 连接池优化

**关键文件**:
- `backend/services/notification-service/src/websocket_hub.rs`
- `backend/services/notification-service/src/websocket_handler.rs`

**性能目标**:
- 并发连接: 10k+
- 消息广播延迟: <100ms

**测试需求**:
- Unit tests: 20+ (覆盖率 >80%)
- Load tests: 模拟 1k+ 并发连接

**完成标准**:
- [ ] 连接管理实现
- [ ] 消息广播实现
- [ ] 负载测试通过
- [ ] 代码审查批准

**时间**: 8 小时 (Fri 10/24)

---

### Week 3: 社交图优化 (Social Graph)

#### T234: Neo4j 社交图

**分支**: `feature/T234-neo4j-social-graph`

**说明**:
- Neo4j 连接初始化
- 用户关系图建模
- 社交查询优化

**关键文件**:
- `backend/services/social-service/src/neo4j_client.rs`
- `backend/services/social-service/src/graph_model.rs`
- `backend/services/social-service/src/queries.rs`

**性能目标**:
- 关系查询延迟 (P95): <500ms
- 图遍历吞吐量: 10k queries/sec

**测试需求**:
- Unit tests: 30+ (覆盖率 >85%)
- Graph traversal tests: 15+

**完成标准**:
- [ ] Neo4j 连接池实现
- [ ] 主要查询优化
- [ ] 所有测试通过
- [ ] 代码审查批准

**时间**: 12 小时 (Mon 10/27 - Tue 10/28)

---

#### T235: Redis 社交缓存

**分支**: `feature/T235-redis-social-cache`

**说明**:
- Redis 缓存层实现
- 缓存失效策略
- 缓存预热机制

**关键文件**:
- `backend/services/social-service/src/cache_manager.rs`
- `backend/services/social-service/src/cache_invalidation.rs`

**性能目标**:
- 缓存命中率: >80%
- 缓存查询延迟: <50ms

**测试需求**:
- Unit tests: 20+ (覆盖率 >85%)
- Cache coherency tests: 10+

**完成标准**:
- [ ] Redis 连接池
- [ ] 缓存策略实现
- [ ] 失效机制测试通过
- [ ] 代码审查批准

**时间**: 10 小时 (Wed 10/29 - Thu 10/30)

---

#### T236: 社交图测试套件

**分支**: `feature/T236-social-graph-tests`

**说明**:
- 端到端测试 (E2E)
- 性能基准测试
- 压力测试

**关键文件**:
- `backend/services/social-service/tests/e2e_test.rs`
- `backend/services/social-service/tests/benchmark_test.rs`
- `backend/services/social-service/tests/stress_test.rs`

**测试需求**:
- E2E tests: 15+
- Performance benchmarks: 10+
- Stress tests: 模拟 10k+ 用户

**完成标准**:
- [ ] E2E 测试覆盖所有关键路径
- [ ] 性能基准达成
- [ ] 压力测试通过
- [ ] 代码审查批准

**时间**: 8 小时 (Fri 10/31)

---

## 🔄 依赖关系

```
Week 2:
T201 (Kafka) ──────┬──> T202 (FCM/APNs) ──> T203 (WebSocket)
                   └──────────────────────────────────┘
                        (所有使用 T201 消费者)

Week 3:
T234 (Neo4j) ──────┬──> T235 (Redis Cache)
                   └──> T236 (Tests)

完整依赖:
T201 → T202 → T203
T234 → T235 → T236
(W2 和 W3 可以并行)
```

---

## 📊 周计划

### Week 2: Notifications (40 小时)

**Monday 10/20 - Tuesday 10/21**:
- [ ] T201 完成 (Kafka 消费者)
- [ ] 16+ 小时
- [ ] 交付: `feature/T201-kafka-notifications` (PR ready)

**Wednesday 10/22 - Thursday 10/23**:
- [ ] T202 完成 (FCM/APNs)
- [ ] 16+ 小时
- [ ] 交付: `feature/T202-fcm-apns-integration` (PR ready)

**Friday 10/24**:
- [ ] T203 完成 (WebSocket)
- [ ] 8+ 小时
- [ ] T201/T202/T203 全部合并到 `develop/phase-7`

### Week 3: Social Graph (40 小时)

**Monday 10/27 - Tuesday 10/28**:
- [ ] T234 完成 (Neo4j)
- [ ] 12+ 小时
- [ ] 交付: `feature/T234-neo4j-social-graph` (PR ready)

**Wednesday 10/29 - Thursday 10/30**:
- [ ] T235 完成 (Redis)
- [ ] 10+ 小时
- [ ] 交付: `feature/T235-redis-social-cache` (PR ready)

**Friday 10/31**:
- [ ] T236 完成 (测试)
- [ ] 8+ 小时
- [ ] T234/T235/T236 全部合并到 `develop/phase-7`

---

## 🧪 测试覆盖矩阵

| 任务 | Unit Tests | Integration Tests | E2E Tests | Load Tests | 目标覆盖率 |
|------|------------|------------------|-----------|------------|----------|
| T201 | 30+ | 10+ | - | - | >90% |
| T202 | 25+ | 8+ | - | - | >85% |
| T203 | 20+ | - | - | ✅ 1k+ | >80% |
| T234 | 30+ | 15+ | - | - | >85% |
| T235 | 20+ | 10+ | - | - | >85% |
| T236 | - | 15+ | ✅ | ✅ 10k+ | >90% |
| **总计** | **135+** | **58+** | **15+** | **持续** | **>85%** |

---

## 📈 成功指标

### Phase 7A Week 2-3 完成标准

| 指标 | 目标 | 状态 |
|------|------|------|
| **任务完成率** | 100% (6/6) | ⏳ |
| **代码覆盖率** | >85% 平均 | ⏳ |
| **测试通过率** | 100% | ⏳ |
| **代码审查** | 100% 批准 | ⏳ |
| **性能目标** | 全部达成 | ⏳ |
| **发布就绪** | Oct 31 | ⏳ |

### SLA 验证

| 组件 | 指标 | 目标 | 测试方法 |
|------|------|------|---------|
| Notifications | 推送送达率 | >99% | Integration test + load test |
| Notifications | 延迟 (P95) | <500ms | Load test (10k msg/sec) |
| WebSocket | 并发连接 | 10k+ | Load test |
| WebSocket | 广播延迟 | <100ms | Latency test |
| Social Graph | 查询延迟 | <500ms | Benchmark test |
| Social Graph | 缓存命中率 | >80% | Cache coherency test |

---

## 🎯 日程表

```
Week 2-3 总时间线:
┌─────────────────────────────────────────────────────────────┐
│ W2.1 (Mon-Tue)  │ W2.2 (Wed-Thu)  │ W2.3 (Fri)              │
│ T201 Kafka      │ T202 FCM/APNs   │ T203 WebSocket + Merge   │
│ 16h             │ 16h             │ 8h                       │
├─────────────────┼─────────────────┼──────────────────────────┤
│ W3.1 (Mon-Tue)  │ W3.2 (Wed-Thu)  │ W3.3 (Fri)               │
│ T234 Neo4j      │ T235 Redis      │ T236 Tests + Merge       │
│ 12h             │ 10h             │ 8h                       │
└─────────────────┴─────────────────┴──────────────────────────┘

关键日期:
- Oct 20: 工作开始
- Oct 25: Week 2 完成（W2 所有任务合并）
- Oct 31: Week 3 完成 + 发布就绪（所有任务 merged）
- Nov 1: 开始 Phase 7B (Week 4+)
```

---

## 🔄 状态更新流程

### 每日 (Daily Standup)

**时间**: 每天 10:00 AM

**检查清单**:
- [ ] 当前分支进度 (% 完成)
- [ ] 阻塞器 (如有)
- [ ] 今天计划完成的内容

**命令**:
```bash
# 查看当前分支信息
git branch -v
git log --oneline -10

# 查看本周提交
git log --oneline --since="2 days ago"
```

### 每周五 (周汇总)

**时间**: 每周五 17:00

**提交内容**:
- [ ] 当周所有任务的最终状态
- [ ] 测试结果汇总
- [ ] 任何遗留问题或变化

---

## 🚨 常见问题

### Q: 如何处理分支冲突?

```bash
# 方式 1: Rebase (推荐，保持历史线性)
git fetch origin
git rebase origin/develop/phase-7
# 解决冲突
git add .
git rebase --continue
git push -f origin feature/T201-kafka-notifications

# 方式 2: Merge (简单，但会产生 merge commit)
git fetch origin
git merge origin/develop/phase-7
# 解决冲突
git add .
git commit
git push origin feature/T201-kafka-notifications
```

### Q: 任务提前完成，如何提早合并?

```bash
# 确保代码审查通过
# 1. PR 创建后，向审查者请求优先审查
# 2. 代码审查通过后立即合并
# 3. 下一个任务可立即开始

# 或通过命令合并:
git checkout develop/phase-7
git pull origin develop/phase-7
git merge --squash feature/T201-kafka-notifications
git push origin develop/phase-7
git push origin --delete feature/T201-kafka-notifications
```

### Q: 如何跟踪任务进度?

**使用 GitHub Projects**:
1. 打开 Nova 项目主页 → Projects
2. 选择 "Phase 7A Week 2-3" board
3. 每个任务对应一个 issue/PR，拖动更新状态

**使用命令行**:
```bash
# 查看所有任务分支的最新提交
git branch -v | grep feature/T

# 查看特定分支的提交
git log feature/T201-kafka-notifications --oneline | head -20
```

---

## 📚 参考文档

- [BRANCH_STRATEGY.md](./BRANCH_STRATEGY.md) — 分支管理详细指南
- [Phase 7 Planning](./specs/007-phase-7-notifications-social/) — 完整规划文档
- [CONTRIBUTING.md](./CONTRIBUTING.md) — 贡献指南

---

**版本**: 1.0
**最后更新**: 2025-10-21
**负责人**: Tech Lead


# Phase 3 快速状态 | 代码分析 + 分阶段指南

## 🎯 核心发现

| 方面 | 状态 | 详情 |
|-----|------|------|
| **整体完成度** | 60% | Phase 1-2 基础已有，Phase 3 核心缺失 |
| **关键阻塞** | 2 项 CRITICAL | CDC consumer ❌ Events consumer ❌ |
| **实施工作量** | 15-20 天 | 2 人团队 × 1.5-2 周 |
| **与现有代码兼容** | ✅ 100% | 无需重构，仅需扩展 |

---

## ✅ 现有资产

```
Feed Ranking Service (src/services/feed_ranking.rs)
  ├─ 三维排序算法 (freshness/engagement/affinity) ✓
  ├─ ClickHouse 查询生成 ✓
  ├─ Redis 缓存集成 ✓
  └─ 候选集去重 ✓

ClickHouse 集成 (src/db/ch_client.rs)
  ├─ 连接池 + 重试逻辑 ✓
  ├─ 查询执行 ✓
  └─ 反序列化 ✓

Redis 缓存 (src/cache/feed_cache.rs)
  ├─ TTL 过期 ✓
  ├─ 图案失效 ✓
  └─ 去重追踪 ✓

背景 Jobs (src/jobs/)
  ├─ Trending Generator ✓
  ├─ Suggested Users Generator ✓
  └─ Job 框架 ✓

Events Pipeline (部分)
  ├─ HTTP 端点 ✓
  ├─ Kafka 生产者 ✓
  └─ ❌ 消费者缺失
```

---

## ❌ 关键缺失

### P0 - 必须完成（否则 Phase 3 无法启动）

**1. CDC 消费者服务** (3-5 天)
```
当前问题：PostgreSQL 变更 → Kafka → [无人消费] ✗
需要：PostgreSQL → Kafka → CDC Consumer → ClickHouse ✓

文件：src/services/cdc/
  - consumer.rs (200 LOC)
  - offset_manager.rs (150 LOC)
  - models.rs (100 LOC)
```

**2. Events 消费者服务** (2-3 天)
```
当前问题：客户端事件 → Kafka → [无人消费] ✗
需要：客户端事件 → Kafka → Events Consumer → ClickHouse ✓

文件：src/services/events/
  - consumer.rs (250 LOC)
  - dedup.rs (150 LOC)
  - models.rs (100 LOC)
```

### P1 - 高优先级（阻塞大部分功能）

**3. ClickHouse 物化视图** (2 天)
```
当前：Events 表 10M+ 行 → 查询时扫全表 → 3-5s ✗
需要：物化视图自动聚合 → 查询时间 200-300ms ✓

文件：infra/clickhouse/views/
  - mv_post_metrics_1h.sql
  - mv_user_author_90d.sql
```

**4. Circuit Breaker** (1 天)
```
当前：ClickHouse 故障 → 整个 Feed 不可用 ✗
需要：ClickHouse 故障 → 自动回退 PostgreSQL ✓

文件：src/middleware/
  - circuit_breaker.rs (200 LOC)
```

### P2 - 中优先级

**5. 实时缓存失效** (1 天)
**6. CDC 管道指标** (2 天)
**7. 死信队列** (1 天)

---

## 📅 建议时间表

```
Week 1: Phase 1 - 基础管道
  Mon: CDC Consumer 基础 + Offset 管理
  Tue: CDC Consumer 完成 + 测试
  Wed: Events Consumer 基础
  Thu: Events Consumer 完成 + 去重
  Fri: 集成测试 + 修复
  → 可交付：完整的事件管道（0 丢失）

Week 2: Phase 2 - 核心功能
  Mon: ClickHouse 物化视图
  Tue: Circuit Breaker 实现
  Wed: 实时缓存失效
  Thu: 指标收集 (15+ metrics)
  Fri: 端到端测试
  → 可交付：性能达标 (P95 ≤150ms)

Week 3: Phase 3 - 优化和部署
  Mon-Tue: 性能优化
  Wed-Thu: 压力测试 (1k RPS)
  Fri: 文档 + 生产部署
  → 可交付：生产就绪
```

---

## 🔧 实施路径

### Option A: 自动渐进式实施
- 我自动执行所有 127 项任务
- 2-3 小时完成（代码生成）
- 需要你手动测试和调整

### Option B: 分阶段指导 ✅ 推荐
- Phase 1: 我提供详细代码框架 + 步骤
- 你手动实施（确保理解）
- Phase 2+: 基于 Phase 1 结果调整
- **优势**: 学习、控制、质量保证

### Option C: 咨询模式
- 我作为架构师提建议
- 你的团队负责实施
- 周 1-2 回顾 + 调整

---

## 📄 可用文档

已为你生成：

1. **PHASE3_IMPLEMENTATION_GUIDE.md** (当前文件上一个)
   - 详细的 Phase 1 实施步骤
   - 代码框架和集成点
   - 测试策略

2. **backend/user-service/PHASE3_ANALYSIS.md**
   - 完整的代码分析（831 行）
   - 组件评估和建议

3. **backend/user-service/PHASE3_CRITICAL_GAPS.md**
   - 10 个阻塞项深度分析
   - 代码示例、工作量估计

4. **backend/user-service/PHASE3_QUICK_SUMMARY.txt**
   - 快速参考、可视化计分

---

## 🎯 下一步

**请确认**：

1. **选择实施模式** (A/B/C)
2. **确认时间表** (能否投入 1-2 周)
3. **指定团队成员** (谁负责 CDC/Events)
4. **基础设施准备**:
   - [ ] PostgreSQL + Debezium 已配置
   - [ ] Kafka 集群可用
   - [ ] ClickHouse 实例可用
   - [ ] Redis 集群可用

---

## 📊 成功指标

完成 Phase 3 后，系统应该达到：

```
✓ 事件到可见延迟 P95 ≤5s
✓ Feed API P95 ≤150ms (Redis hit) / ≤800ms (CH)
✓ 缓存命中率 ≥90%
✓ Kafka 消费者延迟 <10s
✓ 系统可用性 ≥99.5% (with fallback)
✓ 去重率 100%
✓ 0 事件丢失
```

---

**准备好开始 Phase 3 了吗？👀**

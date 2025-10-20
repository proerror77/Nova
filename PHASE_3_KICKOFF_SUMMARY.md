# Phase 3 Kickoff: 完成基础设施模板生成

**执行时间**: October 17, 2024
**总代码行数**: 1,348 行 (模板化代码)
**文件数**: 6 个新文件 + 1 个更新
**架构**: TikTok 风格 OLTP + OLAP + Kafka CDC + Redis Cache

---

## 📊 生成的成果物 (Deliverables)

### 核心基础设施模板 (4 个)

```
┌─ backend/connectors/debezium-postgres-connector.json (37 行)
│  └─ PostgreSQL → Kafka CDC 连接器配置
│  └─ 支持快照模式 + 增量变更
│  └─ 自动主题转换 (cdc.posts, cdc.follows, ...)
│
├─ backend/clickhouse/schema.sql (341 行)
│  └─ 12 个表 (4 raw + 4 CDC + 4 聚合/缓存)
│  └─ 5 个物化视图 (自动更新聚合)
│  └─ 完整的排序与索引策略
│  └─ TTL 和分区配置
│
├─ backend/user-service/src/services/feed_service.rs (490 行)
│  └─ 3 候选源排序 (Follow + Trending + Affinity)
│  └─ 融合去重合并逻辑
│  └─ Redis 缓存路径 (150ms)
│  └─ ClickHouse 查询路径 (800ms P95)
│  └─ 包含 3 个单元测试
│
└─ backend/user-service/src/services/redis_job.rs (480 行)
   ├─ HotPostGenerator (60s 刷新 → hot:posts:1h)
   ├─ SuggestedUsersGenerator (协作过滤建议)
   └─ FeedCacheWarmer (预热活跃用户 Feed)
```

### 配置更新 (1 个)

```
└─ backend/user-service/src/services/mod.rs
   └─ 导出 feed_service 和 redis_job 模块
   └─ 更新模块文档
```

### 文档 (2 个)

```
├─ PHASE_3_INFRASTRUCTURE_SKELETON.md (600+ 行)
│  └─ 完整架构设计
│  └─ 所有 SQL 查询示例
│  └─ H1-H14 实现路线图
│  └─ 集成检查清单
│
└─ PHASE_3_TEMPLATES_GENERATED.md (400+ 行)
   └─ 快速参考指南
   └─ 部署说明
   └─ 性能 SLO
```

---

## 🎯 关键架构决策

### 三候选源排序算法

```
候选源 F1: Follow (最相关)
├─ 查询: 最近 72 小时内已关注用户的帖子
├─ 限制: 最多 500 个
└─ 排序: 按组合分数降序

候选源 F2: Trending (发现)
├─ 查询: 最近 24 小时高热度帖子
├─ 限制: 最多 200 个
└─ 排序: 按参与度 + 新鲜度降序

候选源 F3: Affinity (个性化)
├─ 查询: 高互动作者的帖子 (90 天历史)
├─ 限制: 最多 200 个
└─ 排序: 按亲和力分数降序

Merge: F1 优先 → F2 → F3 (去重)
Rank: 0.30×freshness + 0.40×engagement + 0.30×affinity
```

### 排序公式

```
Freshness Score:   exp(-0.10 * hours_ago)
                   ↓ 指数衰减，新帖优先

Engagement Score:  log1p((likes + 2×comments + 3×shares) / impressions)
                   ↓ 标准化参与度

Affinity Score:    log1p(90day_interaction_count)
                   ↓ 个性化推荐

Combined Score:    0.30×F + 0.40×E + 0.30×A
                   ↓ 权重组合
```

### 缓存层策略

```
Redis Keys:
├─ hot:posts:1h           → 最新热门 200 个 (TTL 120s)
├─ suggest:users:{id}     → 建议用户 20 个 (TTL 600s)
├─ feed:v1:{id}:{off}:{n} → 预生成 Feed (TTL 60s)
└─ seen:{id}:{post}       → 已看帖子去重 (TTL 604800s)

缓存命中率目标: ≥ 90%
冷启动延迟: Feed 预热器 (每 120s 刷新 top 100 活跃用户)
```

---

## ⚙️ 技术栈

### 数据层

```
PostgreSQL (OLTP)
├─ users, posts, comments, likes, follows
├─ 事务写入 (INSERT/UPDATE/DELETE)
└─ 软删除支持 (soft_delete 列)
     │
     ├─ Debezium CDC
     ├─ PostgreSQL 逻辑复制插件
     └─ 快照模式 + 增量
          │
          ▼
        Kafka (Streaming)
        ├─ cdc.posts, cdc.follows, cdc.comments, cdc.likes
        ├─ events (用户行为: impression, view, like, share)
        └─ 分区: 每个主题 3 分区 (吞吐量 1k+ EPS)
             │
             ▼
        ClickHouse (OLAP)
        ├─ posts_cdc, follows_cdc (ReplacingMergeTree)
        ├─ events_raw (MergeTree, 90天 TTL)
        ├─ post_metrics_1h (SummingMergeTree, 聚合)
        ├─ user_author_90d (亲和力表)
        ├─ Materialized Views (自动聚合)
        └─ 查询 P95 ≤ 500ms
             │
             ▼
        Redis Cache
        ├─ 热门帖子列表
        ├─ 建议用户
        ├─ 预热 Feed
        └─ 缓存命中率 ≥ 90%
             │
             ▼
        API 层
        ├─ GET /api/v1/feed (P95 ≤ 800ms)
        ├─ GET /api/v1/discover/suggested-users
        └─ POST /api/v1/events (事件上报)
```

### 应用层

```
FeedService (Rust, Tokio)
├─ 并行查询 3 个候选源
├─ Redis 缓存检查 (150ms hit)
├─ ClickHouse 排序 (500ms query)
└─ 融合 + 排序 (100ms)

Background Jobs
├─ HotPostGenerator (Tokio spawn, 60s interval)
├─ SuggestedUsersGenerator (300s interval)
└─ FeedCacheWarmer (120s interval)
```

---

## 📈 性能目标 (SLO)

| 指标 | 目标 | 备注 |
|------|------|------|
| Feed (缓存命中) | P95 ≤ 150ms | Redis 直接返回 |
| Feed (缓存缺失) | P95 ≤ 800ms | 3 并行 CH 查询 |
| ClickHouse 查询 | P95 ≤ 500ms | 单个候选源 |
| 热帖刷新 | 60s 一次 | 后台作业 |
| 建议用户 | P95 ≤ 300ms | CF 查询 |
| 事件可见延迟 | P95 ≤ 5s | CDC + 聚合 |
| 缓存命中率 | ≥ 90% | 60s TTL |

---

## 🚀 实现路线 (H1-H14)

### 第 1-2 小时: 基础设施部署
- [ ] 部署 ClickHouse (Docker 或托管)
- [ ] 创建 Kafka 主题
- [ ] 部署 Debezium 连接器
- [ ] 验证 CDC 流: PostgreSQL → Kafka → ClickHouse

### 第 3-4 小时: ClickHouse 架构
- [ ] 应用 schema.sql
- [ ] 创建所有表和物化视图
- [ ] 验证 Kafka Engine 消费
- [ ] 测试 CDC 数据流

### 第 5 小时: 数据验证
- [ ] 初始快照加载
- [ ] 验证 OLTP ↔ OLAP 一致性
- [ ] 检查 TTL 和分区

### 第 6-7 小时: 排序 & 热榜
- [ ] 集成 FeedService 到处理器
- [ ] 连接 ClickHouseClient
- [ ] 启动 HotPostGenerator
- [ ] 验证 hot:posts:1h 缓存

### 第 8 小时: Feed API
- [ ] 实现 GET /api/v1/feed 处理器
- [ ] 测试缓存 hit/miss
- [ ] 性能分析

### 第 9 小时: 推荐系统
- [ ] 实现 GET /api/v1/discover/suggested-users
- [ ] 启动 SuggestedUsersGenerator
- [ ] 协作过滤测试

### 第 10 小时: 事件流
- [ ] 创建 Events API (POST /events)
- [ ] Kafka 生产者配置
- [ ] 批量事件发布

### 第 11-12 小时: 可观测性 & 测试
- [ ] Grafana 仪表板
- [ ] ClickHouse 查询性能监控
- [ ] E2E 测试: Like → Feed 更新 ≤ 5s

### 第 13-14 小时: 调优 & 文档
- [ ] 权重调整 (0.30/0.40/0.30 比例)
- [ ] 操作手册
- [ ] 金丝雀部署 (10% 用户)

---

## ✅ 集成清单

### Cargo.toml 依赖 (TODO)
```toml
[dependencies]
clickhouse-rs = "0.11"      # ClickHouse 客户端
clickhouse = "0.11"
redis = "0.24"              # Redis 客户端
rdkafka = "0.35"            # Kafka 生产者
tokio = { version = "1.35", features = ["full"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1.0", features = ["serde", "v4"] }
```

### main.rs 集成 (TODO)
```rust
// 初始化客户端
let ch_client = Arc::new(ClickHouseClient::new(...));
let redis_client = Arc::new(RedisClient::new(...));

// 启动后台作业
let hot_post_job = HotPostGenerator::new(...).start();
let suggestions_job = SuggestedUsersGenerator::new(...).start();
let feed_warmer_job = FeedCacheWarmer::new(...).start();

// 初始化 FeedService
let feed_service = Arc::new(FeedService::new(...));
```

### 处理器集成 (TODO)
```rust
pub async fn get_feed(
    user_id: Uuid,
    offset: u32,
    limit: u32,
    feed_service: web::Data<Arc<FeedService>>,
) -> Result<HttpResponse> {
    let feed = feed_service
        .get_personalized_feed(user_id, offset, limit)
        .await?;
    Ok(HttpResponse::Ok().json(feed))
}
```

---

## 📁 文件布局

```
nova/
├── backend/
│   ├── migrations/
│   │   └── 004_social_graph_schema.sql          ✅ (已创建)
│   ├── connectors/                              ✅ (新目录)
│   │   └── debezium-postgres-connector.json     ✅ 1,348 行总计
│   ├── clickhouse/                              ✅ (新目录)
│   │   └── schema.sql                           ✅ 12 表 + 5 视图
│   └── user-service/src/services/
│       ├── mod.rs                               ✅ (已更新)
│       ├── feed_service.rs                      ✅ 490 行
│       └── redis_job.rs                         ✅ 480 行
│
└── docs/
    ├── PHASE_3_INFRASTRUCTURE_SKELETON.md       ✅ (完整设计)
    ├── PHASE_3_TEMPLATES_GENERATED.md           ✅ (快速参考)
    └── PHASE_3_KICKOFF_SUMMARY.md              ✅ (本文档)
```

---

## 🎯 成功标准 (Definition of Done)

### 基础设施层 ✅
- [x] 4 个模板文件创建完成
- [x] 1,348 行代码生成
- [x] 完整的架构文档
- [ ] ClickHouse 部署验证 (H1-H2)
- [ ] Kafka 主题创建验证 (H1-H2)
- [ ] Debezium CDC 验证 (H1-H2)

### 应用层 (TODO)
- [ ] FeedService 集成到主应用
- [ ] ClickHouseClient 实现
- [ ] RedisClient 实现
- [ ] 3 个后台作业启动

### API 层 (TODO)
- [ ] GET /api/v1/feed 端点实现
- [ ] GET /api/v1/discover/suggested-users 实现
- [ ] POST /api/v1/events 实现
- [ ] 所有端点测试通过

### 测试 (TODO)
- [ ] 50+ 个社交功能测试
- [ ] E2E: Like → Feed 更新 ≤ 5s
- [ ] 150+ 总测试通过

---

## 💡 关键设计原则

### 为什么选择 ClickHouse?
1. **列式存储** - 高效的聚合查询
2. **物化视图** - 无需 ETL 的自动聚合
3. **快速排序** - < 500ms 复杂评分查询
4. **实时流** - Kafka Engine 直接消费
5. **成本低** - 比 PostgreSQL 更高效的 OLAP

### 为什么分离 OLTP + OLAP?
1. **写入隔离** - PostgreSQL 处理事务写入
2. **读取隔离** - ClickHouse 处理分析读取
3. **独立扩展** - 每层独立伸缩
4. **性能优化** - 针对用例的数据结构

### 为什么 3 个候选源?
1. **Follow (相关性)** - 用户想看已关注账号
2. **Trending (发现)** - 病毒式传播内容
3. **Affinity (个性化)** - 基于历史互动

---

## 🔮 未来改进方向

### 短期 (Week 2-3)
- [ ] GraphQL 订阅 Feed 更新 (实时推送)
- [ ] A/B 测试框架 (权重调优)
- [ ] 用户指标收集 (参与度追踪)

### 中期 (Month 2)
- [ ] 多模态 ranking (图文视频权重)
- [ ] 话题模型 (LDA/BERTopic)
- [ ] 跨域推荐 (通知、DM、发现)

### 长期 (Quarter 2+)
- [ ] 强化学习排序 (策略优化)
- [ ] 实时 embedding 相似度 (向量搜索)
- [ ] 多目标优化 (参与度 vs 留存)

---

## 📞 支持

### 问题排查
- **ClickHouse 连接**: 检查 `DATABASE_URL` 环境变量
- **Kafka 消费**: 检查 consumer lag: `kafka-consumer-groups --describe`
- **缓存失效**: Redis `flushdb` 清空所有缓存
- **查询性能**: 使用 ClickHouse Web UI 分析 `system.query_log`

### 监控
- ClickHouse: `system.query_log`, `system.metric_log`
- Kafka: Consumer lag, topic partition lag
- Redis: Memory usage, key count, evictions
- Application: Feed API P95 latency, cache hit rate

---

## 📋 总结

✅ **Phase 3 基础设施骨架完成**

- **生成代码**: 1,348 行
- **文件数**: 6 个新文件 + 1 个更新
- **设计文档**: 1,000+ 行
- **架构**: TikTok 风格 OLTP + OLAP + CDC + Cache
- **SLO**: Feed P95 ≤ 800ms, Cache hit ≥ 90%
- **路线图**: H1-H14 完整 14 小时实现计划

### 下一步
🚀 **H1-H2**: 基础设施部署 (ClickHouse + Kafka + Debezium)


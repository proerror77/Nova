# Phase 7C 启动指南（Kickoff Guide）

**状态**: Ready for Execution
**开始日期**: 2025-10-23（预计 Week 13）
**基础分支**: `develop/phase-7c`（from main bc494a7b）

---

## 📋 Phase 7C 目标

基于 Phase 7B 完成的消息系统，实现以下功能：

| US | 用户故事 | 优先级 | 依赖 | 状态 |
|----|---------|--------|------|------|
| US3 | Message Search (全文搜索) | P1 | Messaging 完成 | ⏳ 开发就绪 |
| US4 | Stories API (故事系统) | P1 | Stories Model 完成 | ⏳ 开发就绪 |
| US5 | Advanced Features (@mentions) | P2 | US1-US4 | ⏳ 队列中 |
| US6 | Analytics Dashboard | P2 | US3 + US4 | ⏳ 队列中 |

---

## 🏗️ 当前基础

**Phase 7B 已交付（在 main 分支）**:

```rust
✅ WebSocket 实时通信
   - 双向消息多路复用
   - Typing indicators
   - 跨实例 Redis pub/sub 广播
   - 连接跟踪 + 离线检测

✅ E2E 加密
   - libsodium NaCl (secretbox)
   - Nonce 生成
   - 密钥管理

✅ REST API
   - POST /conversations
   - POST /messages + GET /messages
   - GET /conversations (with optimization)
   - Permission checks (RBAC)

✅ 持久化 + 缓存
   - PostgreSQL 消息存储
   - Redis 消息队列 + pub/sub
   - Idempotency key 去重

✅ TDD 集成测试
   - WebSocket 授权测试
   - 消息排序验证
   - Typing indicator 实时性
   - 非成员权限检查
```

---

## 🚀 开发流程

### 1. 检查出 develop/phase-7c

```bash
git fetch --all --prune
git checkout develop/phase-7c
git pull origin develop/phase-7c
```

### 2. 为 US3 创建特性分支

```bash
# US3: Message Search
git checkout -b feature/phase-7c-search-service

# 或 US4: Stories API
git checkout -b feature/phase-7c-stories-api
```

### 3. 开发流程（TDD）

对每个任务遵循 Red-Green-Refactor：

```
1. 红色（Red）：写失败的测试
   tests/integration/test_search_latency.rs

2. 绿色（Green）：实现最少代码通过测试
   src/services/search_service.rs

3. 重构（Refactor）：消除重复，改进设计
   - 提取公共函数
   - 优化查询
   - 添加注释
```

### 4. 提交和代码审查

```bash
# 提交单个逻辑单元
git add src/services/search_service.rs tests/
git commit -m "feat(search): implement basic message search with Elasticsearch"

# 推送到 GitHub
git push origin feature/phase-7c-search-service

# 创建 PR: feature/phase-7c-search-service → develop/phase-7c
# 等待代码审查 → merge
```

### 5. 定期同步到 main

```bash
# 当 Phase 7C 完成时
git checkout develop/phase-7c
git pull origin develop/phase-7c

git checkout main
git pull origin main
git merge develop/phase-7c
git push origin main
```

---

## 📊 US3 - Message Search 技术设计

**Acceptance Criteria:**
- [ ] Full-text search via Elasticsearch
- [ ] 支持按 sender、conversation、date range 过滤
- [ ] P95 延迟 <200ms（1000+ 结果）
- [ ] 30+ 集成测试
- [ ] 100% 代码覆盖

**实现步骤:**

```
Phase 1: Elasticsearch 集成
├─ Setup Elasticsearch container (docker-compose.yml)
├─ Create message_index mapping
├─ Implement ES client connection pool
└─ Test basic connectivity

Phase 2: CDC 实现（数据同步）
├─ PostgreSQL → Kafka CDC
├─ Kafka consumer → Elasticsearch indexer
├─ Message persistence → Index within 5s
└─ Test index freshness

Phase 3: Search API
├─ POST /messages/search endpoint
├─ Query parser + filter builder
├─ Result ranking + pagination
└─ Integration tests (30+)

Phase 4: 性能优化
├─ Query latency profiling
├─ Index optimization
├─ Result caching
└─ Load testing (50k concurrent)
```

**文件位置（预计）:**

```
backend/
├─ search-service/
│  ├─ src/main.rs
│  ├─ src/services/search_service.rs
│  ├─ src/elastic/client.rs
│  └─ src/kafka/consumer.rs
├─ messaging-service/
│  └─ src/kafka/producer.rs (已有，扩展)
└─ migrations/
   └─ 020_elasticsearch_schema.sql (mapping definition)
```

---

## 📊 US4 - Stories API 技术设计

**Acceptance Criteria:**
- [ ] POST /stories/feed (with privacy filtering)
- [ ] POST /stories/{id}/views (view tracking)
- [ ] Story reactions (reuse T5 logic)
- [ ] 25+ 集成测试
- [ ] Story feed P95 <100ms

**实现步骤:**

```
Phase 1: 数据模型
├─ Story entity + repository
├─ StoryView tracking
├─ Privacy filter logic (3-tier)
└─ 24h expiration Tokio task

Phase 2: REST API
├─ GET /stories/feed endpoint
├─ Privacy filtering (public/followers/close-friends)
├─ View counting (Redis cache)
└─ Test authorization

Phase 3: Real-time
├─ WebSocket story updates
├─ View count broadcast
├─ Reaction propagation
└─ Integration tests

Phase 4: Performance
├─ Feed query optimization
├─ View counter accuracy
├─ Expiration job reliability
└─ Load testing (10k stories)
```

**文件位置（预计）:**

```
backend/
├─ story-service/
│  ├─ src/main.rs
│  ├─ src/services/story_service.rs
│  ├─ src/db/story_repo.rs
│  └─ src/tasks/expiration.rs
└─ migrations/
   └─ 019_stories_schema.sql
```

---

## 🛠️ 开发环境设置

### 启动依赖服务

```bash
# 启动 PostgreSQL, Redis, Elasticsearch
docker-compose up -d

# 验证服务健康
curl http://localhost:9200          # Elasticsearch
redis-cli PING                       # Redis
psql -h localhost -U postgres        # PostgreSQL
```

### 运行测试

```bash
# 单个测试
cargo test test_message_search_latency --test-threads=1

# 所有集成测试
cargo test --test '*' -- --test-threads=1

# 代码覆盖（需要 tarpaulin）
cargo tarpaulin --out Html --output-dir coverage/
```

### 性能验证

```bash
# 启动服务
cargo run --bin messaging-service

# 运行负载测试
cargo test --release load_test_50k_concurrent -- --nocapture --test-threads=1

# 查看 Prometheus 指标
curl http://localhost:9090
```

---

## 📚 关键参考文档

**Phase 7B 规范（已完成，供参考）:**
- `specs/002-messaging-stories-system/spec.md` - 功能规范
- `specs/002-messaging-stories-system/plan.md` - 实现计划
- `specs/002-messaging-stories-system/data-model.md` - 数据模型

**代码参考（Phase 7B 实现）:**
- `backend/messaging-service/src/websocket/handlers.rs` - WebSocket 实现
- `backend/messaging-service/src/services/message_service.rs` - 服务层模式
- `backend/libs/crypto-core/src/lib.rs` - 加密库使用

---

## ⚠️ 潜在风险和缓解

| 风险 | 影响 | 概率 | 缓解 |
|------|------|------|------|
| Elasticsearch 延迟 | Search SLA miss | 中等 | 早期负载测试，调整 shard 数 |
| CDC 同步延迟 | 搜索不新鲜 | 低 | Kafka 监控告警，<5s SLA 验证 |
| Privacy 逻辑复杂 | 权限绕过 | 低 | 早期审查，30+ 边界情况测试 |
| 故事过期竞态 | 数据不一致 | 很低 | 分布式锁（Redis），定期一致性检查 |

---

## 🎯 成功指标

### Week 13-14（US3 Search）
- [ ] Elasticsearch 集成完成
- [ ] CDC pipeline 运行
- [ ] Search API <200ms P95
- [ ] 30+ 测试通过
- [ ] 代码审查批准

### Week 15-16（US4 Stories）
- [ ] Story model + repository
- [ ] Privacy filtering 实现
- [ ] Stories API 完成
- [ ] 视图计数准确
- [ ] Story feed <100ms P95

### Week 17（Advanced）
- [ ] @mentions 实现
- [ ] Analytics API
- [ ] 所有 SLA 验证

---

## 📞 沟通渠道

**Daily Standup**:
- 时间: 09:00 UTC
- 持续时间: 15 分钟
- 频道: Slack #phase-7c-development

**Weekly Sync**:
- Tuesday 10:00 UTC: 性能评审 + 计划
- Friday 14:00 UTC: 代码质量 + 测试评审

**异步通信**:
- GitHub PRs for code review
- Slack #phase-7c-development for blockers

---

## ✅ 预启动清单

在开始 Phase 7C 开发前，验证以下事项：

- [ ] 阅读本文档
- [ ] 检查 `develop/phase-7c` 分支（已存在，指向 main bc494a7b）
- [ ] 运行 `docker-compose up -d` 启动依赖
- [ ] 运行 Phase 7B 测试验证环境: `cargo test --test '*'`
- [ ] 创建 feature 分支: `git checkout -b feature/phase-7c-{your-feature}`
- [ ] 编写首个失败测试（Red）
- [ ] 每日 09:00 UTC 参加 standup

---

**创建日期**: 2025-10-23
**分支**: `develop/phase-7c`
**预计开始**: Week 13（约 2025-10-27）
**预期完成**: Week 17（约 2025-11-24）

May the Force be with you. 🚀

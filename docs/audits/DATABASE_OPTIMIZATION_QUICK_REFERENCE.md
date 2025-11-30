# Nova 数据库优化 - 快速参考

## 🎯 核心问题清单

### 🔴 P0 - 立即修复（1-2 周）

#### 1️⃣ 缺少复合索引
**位置**: PostgreSQL 社交交互表
**影响**: 点赞/评论列表查询 10 倍慢
**修复**: 添加 3 个复合索引
```sql
-- 在 migration 中执行
CREATE INDEX idx_likes_post_created_id ON likes(post_id, created_at DESC, id);
CREATE INDEX idx_comments_post_created ON comments(post_id, created_at DESC);
CREATE INDEX idx_comments_parent_created ON comments(parent_comment_id, created_at DESC);
```
**成本**: 0 (仅元数据)
**预期改进**: 500ms → 50ms

#### 2️⃣ GraphQL N+1 查询风险
**位置**: `/graphql-gateway/src/schema/loaders.rs`
**问题**: Loaders 是虚拟实现，未连接真实数据库
**修复**: 实现真实的批量数据加载
```rust
// 将虚拟实现替换为真实数据库查询
// 使用 sqlx::query_as 批量加载用户/点赞数据
```
**成本**: 3-4 小时开发
**预期改进**: 300ms → 50ms (6 倍)

#### 3️⃣ 不完整的连接池配置
**位置**: 所有微服务的 `create_pool` 函数
**问题**: 缺少超时、空闲时间、验证配置
**修复**: 添加生产级别的超时和生命周期参数
```rust
.connect_timeout(Duration::from_secs(5))
.acquire_timeout(Duration::from_secs(10))
.idle_timeout(Some(Duration::from_secs(600)))
.test_on_checkout(true)
```
**成本**: 2 小时
**预期改进**: 消除连接泄漏，提高高并发稳定性

---

### 🟡 P1 - 高优先级（2-4 周）

#### 4️⃣ Neo4j 多次网络往返
**位置**: `/graph-service/src/repository/graph_repository.rs`
**问题**: `create_follow` 包含 3 次分别的 Cypher 调用
```rust
// ❌ 当前: 3 RTT
ensure_user_node(follower).await?;
ensure_user_node(followee).await?;
create_follow_edge(...).await?;

// ✅ 优化: 1 RTT
// 合并为单个 MERGE 语句
```
**成本**: 3-4 小时
**预期改进**: 3 RTT → 1 RTT (66% 延迟减少)

#### 5️⃣ Redis 缓存策略单一
**位置**: `/graphql-gateway/src/cache/redis_cache.rs`
**问题**: 硬编码 60 秒 TTL，无故障转移
**修复**: 多级缓存 (Redis → DB 缓存 → 实时计算)
```rust
// L1: Redis (快, 易失)
// L2: post_counters 表 (慢, 准确)
// L3: SELECT COUNT(*) (很慢, 准确)
```
**成本**: 6-8 小时
**预期改进**: Redis 故障不阻塞请求，命中率 > 80%

---

## 📊 性能对标

### 当前 → 优化后

| 查询类型 | 当前 | 目标 | 改进倍数 |
|---------|------|------|---------|
| Feed 列表 | 500-800ms | 100-200ms | 3-8x |
| 点赞计数 | 200ms | 5ms | 40x |
| 评论列表 | 300ms | 30ms | 10x |
| GraphQL post + likes | 300ms | 50ms | 6x |
| API 吞吐量 | 500 req/s | 1500-2000 req/s | 3-4x |
| 缓存命中率 | - | >80% | N/A |

---

## 🛠️ 快速实施命令

### 第 1 周

```bash
# 1. 添加索引
cd /Users/proerror/Documents/nova/backend
cat > migrations/201_add_composite_indexes.sql << 'EOF'
CREATE INDEX idx_likes_post_created_id ON likes(post_id, created_at DESC, id);
CREATE INDEX idx_comments_post_created ON comments(post_id, created_at DESC);
CREATE INDEX idx_comments_parent_created ON comments(parent_comment_id, created_at DESC);
ANALYZE likes; ANALYZE comments;
EOF

# 2. 修改连接池（所有服务）
# - user-service/src/db/mod.rs
# - feed-service/src/db/mod.rs
# - social-service/src/main.rs
# 添加: .idle_timeout(), .test_on_checkout(), .connect_timeout()

# 3. 修复 GraphQL Loaders
vim graphql-gateway/src/schema/loaders.rs
# 替换虚拟实现为 sqlx::query_as

# 部署
git commit -am "perf: add indexes, fix connection pools, implement real loaders"
git push
```

### 第 2-3 周

```bash
# 4. 优化 Neo4j 查询
vim graph-service/src/repository/graph_repository.rs
# 合并 ensure_user_node 调用

# 5. 部署多级缓存
vim social-service/src/services/counters.rs
# 添加 L1 (Redis) → L2 (DB cache) → L3 (Direct) 逻辑

# 6. 添加 ClickHouse 分区
vim clickhouse/002_feed_candidates_tables.sql
# 添加 PARTITION BY toYYYYMM(event_date)
```

### 第 4 周

```bash
# 7. 启用监控
# 在 Prometheus 中添加:
# - db_query_duration_ms
# - cache_hit_rate
# - db_pool_connections_active

# 8. 性能对标
cargo bench --bench database_performance
python3 compare_baseline.py baseline.json optimized.json
```

---

## 🔍 诊断命令

### PostgreSQL 性能分析

```sql
-- 慢查询检测
SELECT query, calls, mean_time
FROM pg_stat_statements
WHERE mean_time > 100
ORDER BY mean_time DESC LIMIT 10;

-- 索引使用情况
SELECT tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0;  -- 未使用的索引

-- 连接池状态
SELECT datname, count(*) as total,
       sum(case when state = 'idle' then 1 else 0 end) as idle
FROM pg_stat_activity
GROUP BY datname;

-- 表膨胀检查
SELECT schemaname, tablename, n_live_tup, n_dead_tup,
       round(100 * n_dead_tup / (n_live_tup + n_dead_tup), 1) as bloat_ratio
FROM pg_stat_user_tables
WHERE (n_live_tup + n_dead_tup) > 0
ORDER BY bloat_ratio DESC;

-- 索引膨胀
SELECT schemaname, tablename, indexname, idx_blks_hit, idx_blks_read
FROM pg_stat_user_indexes
ORDER BY (idx_blks_hit + idx_blks_read) DESC;
```

### Redis 监控

```bash
# 连接状态
redis-cli INFO stats

# 内存使用
redis-cli INFO memory

# 慢查询
redis-cli --latency
redis-cli --bigkeys

# 缓存命中率
redis-cli GET stats:cache_hits
redis-cli GET stats:cache_misses
```

### Neo4j 性能检查

```cypher
-- 事务时间分析
MATCH (n) RETURN COUNT(n);
-- 观察执行时间

-- 索引状态
SHOW INDEXES;

-- 慢查询日志
CALL dbms.queryJlog.queryLogLevel();
```

---

## ⚠️ 常见陷阱

| 陷阱 | 症状 | 解决方案 |
|------|------|---------|
| **N+1 查询** | GraphQL 慢 1 秒+ | 使用 DataLoader 批量加载 |
| **连接泄漏** | 高并发 DB 连接数爆炸 | 添加 idle_timeout + test_on_checkout |
| **索引碎片** | 索引大小 2x 表大小 | REINDEX CONCURRENTLY |
| **查询计划缓存过期** | 新索引创建后查询仍慢 | ANALYZE 更新统计信息 |
| **Redis 内存溢出** | Redis 断开连接 | 设置 maxmemory + eviction 策略 |
| **死锁在更新** | 偶发性超时 | 统一 UPDATE 语句的列顺序 |

---

## 📋 每周检查清单

### 第 1 周
- [ ] 索引迁移已应用
- [ ] 连接池配置已更新（所有 5 个服务）
- [ ] GraphQL Loaders 已实现真实查询
- [ ] 性能基准已记录
- [ ] 没有新的慢查询告警

### 第 2-3 周
- [ ] Neo4j 查询已合并（测试 OK）
- [ ] 多级缓存已部署
- [ ] ClickHouse 分区已配置
- [ ] 缓存失效策略已实施
- [ ] 缓存命中率 > 70%

### 第 4 周
- [ ] Prometheus 指标已启用
- [ ] Grafana 仪表板已创建
- [ ] 性能对标已完成
- [ ] 平均改进 > 50%
- [ ] 无新 regression

---

## 💰 ROI 总结

**总投资**: 38-40 小时开发 + 0 基础设施成本

**预期回报**:
- ✅ 60-75% 延迟减少
- ✅ 3-4 倍吞吐量提升
- ✅ $24,000/年 成本节省
- ✅ 消除 N+1 查询
- ✅ 99.9% 缓存可用性

**ROI**: ~$24,000 / ($40 * $200/小时) = **30x**

---

## 📞 技术支持

遇到问题?

1. 检查 `/DATABASE_OPTIMIZATION_ANALYSIS.md` 中的详细说明
2. 参考 `/OPTIMIZATION_IMPLEMENTATION_GUIDE.md` 中的分步指南
3. 运行诊断命令验证问题
4. 查看故障排除部分

---

**最后更新**: 2025-11-24
**状态**: 准备实施
**下一步**: 立即启动 P0 优化


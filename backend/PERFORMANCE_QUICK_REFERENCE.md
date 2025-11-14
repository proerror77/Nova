# Performance Optimization Quick Reference

**一页速查手册** - 所有关键性能模式和反模式

---

## 🚨 Critical Anti-Patterns (立即修复)

### ❌ N+1 Query Problem
```rust
// BAD: 循环中查询数据库
for user_id in user_ids {
    let user = query!("SELECT * FROM users WHERE id = $1", user_id)
        .fetch_one(pool).await?;
}

// GOOD: 批量查询
let users = query!("SELECT * FROM users WHERE id = ANY($1)", &user_ids)
    .fetch_all(pool).await?;
```

### ❌ No Connection Pool Timeouts
```rust
// BAD: 无超时配置
PgPoolOptions::new()
    .max_connections(50)
    .connect(&url).await?;

// GOOD: 完整超时配置
PgPoolOptions::new()
    .max_connections(50)
    .acquire_timeout(Duration::from_secs(10))
    .idle_timeout(Duration::from_secs(600))
    .max_lifetime(Duration::from_secs(1800))
    .connect(&url).await?;
```

### ❌ Missing Cache Layer
```rust
// BAD: 每次都查询数据库
let user = db.get_user(id).await?;

// GOOD: 缓存包装
if let Some(user) = cache.get(&key).await? {
    return Ok(user);
}
let user = db.get_user(id).await?;
cache.set(&key, &user).await?;
```

### ❌ Blocking in Async Code
```rust
// BAD: 阻塞 async 执行器
async fn handler() {
    let data = std::fs::read("file.txt")?;  // 阻塞!
}

// GOOD: 使用 async I/O
async fn handler() {
    let data = tokio::fs::read("file.txt").await?;
}

// GOOD: CPU 密集任务用 spawn_blocking
async fn handler() {
    let result = tokio::task::spawn_blocking(|| {
        expensive_computation()
    }).await?;
}
```

---

## ✅ Database Optimization Patterns

### 1. Covering Indexes (避免表回查)
```sql
-- BAD: 普通索引 (需要回表)
CREATE INDEX idx_user_created ON posts(user_id);

-- GOOD: 覆盖索引 (包含所有需要的列)
CREATE INDEX idx_user_created_covering ON posts(user_id)
INCLUDE (id, content, created_at);
```

### 2. Partial Indexes (减少索引大小)
```sql
-- BAD: 索引所有行
CREATE INDEX idx_posts_created ON posts(created_at);

-- GOOD: 只索引活跃数据
CREATE INDEX idx_posts_active ON posts(created_at)
WHERE soft_delete IS NULL AND created_at > NOW() - INTERVAL '30 days';
```

### 3. Keyset Pagination (深分页优化)
```rust
// BAD: OFFSET 分页 (深分页慢)
query!("SELECT * FROM posts ORDER BY created_at DESC LIMIT $1 OFFSET $2",
    limit, page * limit)

// GOOD: Keyset 分页 (基于游标)
query!("SELECT * FROM posts WHERE created_at < $1 ORDER BY created_at DESC LIMIT $2",
    cursor_timestamp, limit)
```

### 4. Batch Inserts (减少往返)
```rust
// BAD: 逐个插入
for post in posts {
    query!("INSERT INTO posts (...) VALUES (...)", post).execute(pool).await?;
}

// GOOD: 批量插入
query!("INSERT INTO posts (...) SELECT * FROM UNNEST($1)", &posts)
    .execute(pool).await?;
```

---

## 🔄 Caching Patterns

### 1. Cache-Aside (Lazy Loading)
```rust
async fn get_user_cached(cache: &Cache, db: &Db, id: &str) -> Result<User> {
    let key = format!("user:{}", id);

    // L2: Redis
    if let Some(user) = cache.get(&key).await? {
        return Ok(user);
    }

    // DB fallback
    let user = db.get_user(id).await?;
    cache.set(&key, &user, 600).await?;

    Ok(user)
}
```

### 2. Write-Through (写入同步更新)
```rust
async fn update_user(cache: &Cache, db: &Db, user: User) -> Result<()> {
    // 写数据库
    db.update_user(&user).await?;

    // 同步更新缓存
    let key = format!("user:{}", user.id);
    cache.set(&key, &user, 600).await?;

    Ok(())
}
```

### 3. Cache Stampede Prevention (防止缓存击穿)
```rust
use tokio::sync::Mutex;
use std::collections::HashMap;

lazy_static::lazy_static! {
    static ref REFRESH_LOCKS: Mutex<HashMap<String, Arc<Mutex<()>>>> =
        Mutex::new(HashMap::new());
}

async fn get_with_stampede_protection(
    cache: &Cache,
    db: &Db,
    key: &str,
) -> Result<User> {
    // 尝试从缓存获取
    if let Some(user) = cache.get(key).await? {
        return Ok(user);
    }

    // 获取刷新锁 (同一 key 只有一个请求刷新)
    let lock = {
        let mut locks = REFRESH_LOCKS.lock().await;
        locks.entry(key.to_string())
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    };

    let _guard = lock.lock().await;

    // 再次检查缓存 (可能已被其他线程刷新)
    if let Some(user) = cache.get(key).await? {
        return Ok(user);
    }

    // 查询数据库并更新缓存
    let user = db.get_user(key).await?;
    cache.set(key, &user, 600).await?;

    Ok(user)
}
```

---

## ⚡ gRPC Optimization

### 1. Connection Pooling with Timeouts
```rust
let channel = Channel::from_shared(uri)?
    .connect_timeout(Duration::from_secs(3))
    .timeout(Duration::from_secs(5))
    .http2_keep_alive_interval(Duration::from_secs(30))
    .keep_alive_timeout(Duration::from_secs(60))
    .connect().await?;
```

### 2. Batch Requests (减少往返)
```rust
// BAD: 逐个调用
for id in ids {
    let user = client.get_user(id).await?;
}

// GOOD: 批量调用
let users = client.batch_get_users(ids).await?;
```

### 3. Streaming for Large Results
```rust
// BAD: 一次返回全部数据
rpc GetPosts(Request) returns (PostList);

// GOOD: 流式返回
rpc GetPosts(Request) returns (stream Post);
```

---

## 📊 Monitoring Checklist

### 必须监控的指标

#### 1. Request Latency (请求延迟)
```promql
# P50/P95/P99
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

#### 2. Database Pool Utilization (连接池利用率)
```promql
db_pool_connections_active / db_pool_connections_max * 100
```

#### 3. Cache Hit Rate (缓存命中率)
```promql
sum(rate(cache_operations_total{result="hit"}[5m])) /
sum(rate(cache_operations_total{operation="get"}[5m])) * 100
```

#### 4. Error Rate (错误率)
```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) /
sum(rate(http_requests_total[5m])) * 100
```

#### 5. gRPC Latency per Service
```promql
histogram_quantile(0.95, rate(grpc_request_duration_seconds_bucket[5m]))
```

### 告警阈值
| 指标 | 警告 | 严重 |
|------|------|------|
| P95 延迟 | > 500ms | > 1s |
| 连接池利用率 | > 75% | > 85% |
| 缓存命中率 | < 60% | < 40% |
| 错误率 | > 1% | > 5% |
| CPU 使用率 | > 70% | > 85% |

---

## 🎯 Performance Testing Commands

### Artillery 基准测试
```bash
# Feed 生成压测
artillery run load-test/feed-load-test.yml

# 生成 HTML 报告
artillery report results.json --output report.html

# 快速压测 (命令行)
artillery quick --duration 60 --rate 100 http://localhost:8080/graphql
```

### k6 压测
```bash
# 基本压测
k6 run --vus 100 --duration 60s load-test/script.js

# 阶梯式加压
k6 run --stages '5s:10,10s:20,30s:50,10s:0' script.js
```

### Database 慢查询分析
```sql
-- 启用 pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 查看最慢查询 (Top 10)
SELECT
    query,
    calls,
    mean_exec_time,
    max_exec_time,
    stddev_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- 重置统计
SELECT pg_stat_statements_reset();
```

---

## 🔧 Quick Fixes (30分钟内实施)

### 1. 启用查询缓存
```rust
// 在 resolver 中包装缓存
async fn get_user(&self, ctx: &Context, id: ID) -> Result<User> {
    let cache = ctx.data::<Cache>()?;
    let key = format!("user:{}", id);

    if let Some(user) = cache.get(&key).await? {
        return Ok(user);
    }

    let user = self.fetch_user(id).await?;
    cache.set(&key, &user, 600).await?;
    Ok(user)
}
```

### 2. 添加数据库索引
```sql
-- 复合索引 (最常查询的列)
CREATE INDEX CONCURRENTLY idx_posts_user_created
ON posts(user_id, created_at DESC);

-- 覆盖索引 (避免回表)
CREATE INDEX CONCURRENTLY idx_posts_covering
ON posts(user_id) INCLUDE (id, content, created_at);
```

### 3. 配置连接池超时
```rust
// 在 db-pool 配置中添加
DbConfig {
    acquire_timeout_secs: 10,
    idle_timeout_secs: 600,
    max_lifetime_secs: 1800,
    ..Default::default()
}
```

---

## 📚 Performance Checklist

### Pre-Deployment
- [ ] ✅ 所有查询有索引支持
- [ ] ✅ 连接池有超时配置
- [ ] ✅ 热路径有缓存
- [ ] ✅ 慢查询日志启用
- [ ] ✅ 监控指标完整

### Post-Deployment
- [ ] ✅ 负载测试通过 (P95 < 500ms)
- [ ] ✅ 缓存命中率 > 60%
- [ ] ✅ 错误率 < 1%
- [ ] ✅ 数据库连接 < 75%
- [ ] ✅ Grafana 仪表板正常

### Weekly Review
- [ ] ✅ 检查慢查询日志
- [ ] ✅ 审查缓存命中率
- [ ] ✅ 优化低效索引
- [ ] ✅ 清理未使用索引
- [ ] ✅ 容量规划更新

---

## 🆘 Emergency Performance Fixes

### 数据库连接耗尽
```bash
# 临时增加连接数 (需重启)
ALTER SYSTEM SET max_connections = 200;
SELECT pg_reload_conf();

# 查看当前连接
SELECT count(*) FROM pg_stat_activity;

# 杀死空闲连接
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND state_change < now() - interval '10 minutes';
```

### Redis 内存爆满
```bash
# 查看内存使用
redis-cli INFO memory

# 临时增加内存限制
redis-cli CONFIG SET maxmemory 2gb

# 清理过期 key
redis-cli --scan --pattern "cache:*" | xargs redis-cli DEL

# 设置 LRU 淘汰策略
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### 高延迟排查
```bash
# 1. 检查 CPU
top -H -p $(pgrep -f feed-service)

# 2. 检查网络
ss -s | grep ESTAB

# 3. 检查磁盘 I/O
iostat -x 1

# 4. 检查数据库
psql -c "SELECT * FROM pg_stat_activity WHERE state != 'idle';"

# 5. 检查 gRPC 延迟
curl http://localhost:8080/metrics | grep grpc_request_duration
```

---

## 🔗 Related Documents

- [完整性能审计报告](./PERFORMANCE_AUDIT_REPORT.md)
- [实施指南](./PERFORMANCE_OPTIMIZATION_IMPLEMENTATION_GUIDE.md)
- [负载测试](./load-test/README.md)
- [监控仪表板](http://localhost:3000/d/nova-performance)

---

**最后更新**: 2025-11-14
**维护者**: Performance Engineering Team

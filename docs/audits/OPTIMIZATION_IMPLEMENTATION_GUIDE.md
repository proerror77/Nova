# Nova 数据库优化实施指南

**目标**: 按优先级实施数据库性能优化
**时间线**: 4 周
**起始时间**: 第1周

---

## 周计划表

### 第 1 周：索引和连接池优化

#### 任务 1.1: 添加复合索引 (2-3 小时)

**目标**: 改进 likes/comments 分页查询性能

**步骤**:

1. **创建迁移文件**
```bash
cd /Users/proerror/Documents/nova/backend
touch migrations/201_add_composite_indexes.sql
```

2. **填充迁移内容**
```sql
-- 复合索引用于点赞分页
CREATE INDEX IF NOT EXISTS idx_likes_post_created_id
  ON likes(post_id, created_at DESC, id)
  WHERE deleted_at IS NULL;

-- 复合索引用于评论分页
CREATE INDEX IF NOT EXISTS idx_comments_post_created
  ON comments(post_id, created_at DESC)
  WHERE is_deleted = FALSE;

-- 评论回复导航
CREATE INDEX IF NOT EXISTS idx_comments_parent_created
  ON comments(parent_comment_id, created_at DESC)
  WHERE parent_comment_id IS NOT NULL AND is_deleted = FALSE;

-- 用户活动时间线
CREATE INDEX IF NOT EXISTS idx_messages_sender_created
  ON messages(sender_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- 更新统计信息
ANALYZE likes;
ANALYZE comments;
ANALYZE messages;
```

3. **在本地测试**
```bash
# 使用 Docker 启动本地 PostgreSQL
docker run -d --name pg_test \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  postgres:15

# 创建测试数据库
psql -h localhost -U postgres -d postgres \
  -c "CREATE DATABASE nova_test;"

# 应用迁移
sqlx migrate run --database-url "postgres://postgres:password@localhost/nova_test"

# 验证索引创建
psql -h localhost -U postgres -d nova_test \
  -c "SELECT indexname FROM pg_indexes WHERE indexname LIKE 'idx_likes%';"
```

4. **验证查询性能**
```bash
# 检查查询计划
psql -h localhost -U postgres -d nova_test << 'EOF'
-- 验证索引使用
EXPLAIN ANALYZE
SELECT id, user_id, post_id, created_at
FROM likes
WHERE post_id = 'some-uuid'
ORDER BY created_at DESC
LIMIT 20;

-- 应该看到 "Index Scan using idx_likes_post_created_id"
EOF
```

5. **部署到开发环境**
```bash
# 推送迁移文件
git add migrations/201_add_composite_indexes.sql
git commit -m "feat(db): add composite indexes for likes/comments pagination"

# 在 CI/CD 中自动应用
# (由 sqlx migrate run 处理)
```

**预期结果**:
- ✅ 点赞列表查询: 500ms → 50ms
- ✅ 评论列表查询: 300ms → 30ms
- ✅ 索引大小: ~200MB 额外存储

---

#### 任务 1.2: 优化连接池配置 (2 小时)

**目标**: 配置生产级别的连接池参数

**步骤**:

1. **修改 social-service 连接池** (`/social-service/src/main.rs`)

找到这段代码:
```rust
let db_pool = match create_pool(&config.database.url, config.database.max_connections).await {
```

修改 `create_pool` 函数:
```rust
use std::time::Duration;
use sqlx::postgres::PgPoolOptions;

pub async fn create_pool(url: &str, max_connections: u32) -> Result<PgPool> {
    let pool = PgPoolOptions::new()
        // 连接限制
        .max_connections(max_connections)
        .min_connections(std::cmp::max(max_connections / 2, 10))

        // 超时配置
        .connect_timeout(Duration::from_secs(5))
        .acquire_timeout(Duration::from_secs(10))

        // 连接生命周期
        .idle_timeout(Some(Duration::from_secs(600)))      // 10分钟
        .max_lifetime(Some(Duration::from_secs(1800)))     // 30分钟

        // 连接验证
        .test_on_checkout(true)

        .connect(url)
        .await
        .context("Failed to connect to database")?;

    Ok(pool)
}
```

2. **为所有微服务应用相同更改**
```bash
# 检查所有服务的 create_pool 函数
grep -r "create_pool" /Users/proerror/Documents/nova/backend --include="*.rs"

# 受影响的服务:
# - feed-service/src/main.rs
# - user-service/src/main.rs
# - content-service/src/main.rs
# - notification-service/src/main.rs
# - media-service/src/main.rs
```

3. **配置环境变量**
```bash
# 在 .env 或 K8s ConfigMap 中设置:

# social-service (高写入)
DATABASE_MAX_CONNECTIONS=50

# feed-service (高读取)
DATABASE_MAX_CONNECTIONS=40

# graphql-gateway (混合 + 网关)
DATABASE_MAX_CONNECTIONS=80

# notification-service (低流量)
DATABASE_MAX_CONNECTIONS=20
```

4. **测试连接池**
```rust
// 添加测试用例 tests/connection_pool_test.rs
#[tokio::test]
async fn test_pool_exhaustion_handling() {
    let pool = create_pool(&test_db_url, 5).await.unwrap();

    // 尝试获取超过最大连接数的连接
    let mut handles = vec![];
    for _ in 0..10 {
        let p = pool.clone();
        handles.push(tokio::spawn(async move {
            p.acquire().await
        }));
    }

    // 最后的连接应该在 10 秒后超时（acquire_timeout）
    let results = futures::future::join_all(handles).await;
    assert!(results.into_iter().any(|r| r.is_err()));
}
```

5. **验证空闲连接清理**
```bash
# 监控连接使用
psql -h localhost -U postgres -d nova_test << 'EOF'
SELECT datname, count(*) as total,
       sum(case when state = 'idle' then 1 else 0 end) as idle
FROM pg_stat_activity
GROUP BY datname;
EOF

# 应该在 10 分钟后看到闲置连接数减少
```

**预期结果**:
- ✅ 避免连接泄漏
- ✅ 自动回收僵尸连接
- ✅ 改善高并发场景的连接获取延迟

---

#### 任务 1.3: 修复 GraphQL N+1 Loaders (3-4 小时)

**目标**: 实现真实的批量数据加载

**步骤**:

1. **分析当前 Loaders** (`/graphql-gateway/src/schema/loaders.rs`)

当前问题:
```rust
// ❌ 虚拟实现，不查询数据库
impl Loader<String> for UserIdLoader {
    async fn load(&self, keys: &[String]) -> Result<HashMap<String, Self::Value>, Self::Error> {
        let users: HashMap<String, String> = keys
            .iter()
            .map(|id| (id.clone(), format!("User {}", id)))  // ← 虚假数据！
            .collect();
        Ok(users)
    }
}
```

2. **创建真实的 Loader 实现**

新建文件 `/graphql-gateway/src/schema/real_loaders.rs`:
```rust
use async_graphql::dataloader::Loader;
use std::collections::HashMap;
use sqlx::PgPool;
use uuid::Uuid;
use user_service::models::User;

/// 真实的用户 Loader，从数据库批量加载
#[derive(Clone)]
pub struct RealUserLoader {
    db_pool: PgPool,
}

impl RealUserLoader {
    pub fn new(db_pool: PgPool) -> Self {
        Self { db_pool }
    }
}

#[async_trait::async_trait]
impl Loader<Uuid> for RealUserLoader {
    type Value = User;
    type Error = String;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Self::Value>, Self::Error> {
        // ✅ 真实的数据库查询：1 个查询替代 N 个查询
        let users: Vec<User> = sqlx::query_as!(
            User,
            "SELECT id, username, email, avatar_url, created_at, updated_at
             FROM users
             WHERE id = ANY($1::uuid[]) AND is_active = true",
            &keys
        )
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| format!("Failed to load users: {}", e))?;

        // 返回映射
        Ok(users.into_iter().map(|u| (u.id, u)).collect())
    }
}

/// 真实的点赞计数 Loader
#[derive(Clone)]
pub struct RealLikeCountLoader {
    db_pool: PgPool,
}

impl RealLikeCountLoader {
    pub fn new(db_pool: PgPool) -> Self {
        Self { db_pool }
    }
}

#[async_trait::async_trait]
impl Loader<Uuid> for RealLikeCountLoader {
    type Value = i64;
    type Error = String;

    async fn load(&self, post_ids: &[Uuid]) -> Result<HashMap<Uuid, i64>, Self::Error> {
        // ✅ 批量计数查询
        #[derive(sqlx::FromRow)]
        struct LikeCount {
            post_id: Uuid,
            count: i64,
        }

        let counts: Vec<LikeCount> = sqlx::query_as!(
            r#"
            SELECT post_id, COUNT(*) as count
            FROM likes
            WHERE post_id = ANY($1::uuid[])
            GROUP BY post_id
            "#,
            &post_ids
        )
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| format!("Failed to load like counts: {}", e))?;

        // 确保所有 post_id 都有结果（即使是 0 个赞）
        let mut result: HashMap<Uuid, i64> = post_ids.iter().map(|id| (*id, 0)).collect();
        for count in counts {
            result.insert(count.post_id, count.count);
        }

        Ok(result)
    }
}
```

3. **在 GraphQL Context 中注册 Loaders**

修改 `src/main.rs`:
```rust
use async_graphql::{dataloader::DataLoader, Schema, EmptyMutation, EmptySubscription};
use crate::schema::real_loaders::{RealUserLoader, RealLikeCountLoader};

#[actix_web::main]
async fn main() -> io::Result<()> {
    // ... 初始化代码 ...

    let db_pool = create_pool(&config.database_url).await?;

    // 创建 DataLoader 实例
    let user_loader = DataLoader::new(
        RealUserLoader::new(db_pool.clone()),
        tokio::task::spawn
    );

    let like_count_loader = DataLoader::new(
        RealLikeCountLoader::new(db_pool.clone()),
        tokio::task::spawn
    );

    // 构建 Schema，传入 loaders
    let schema = Schema::build(Query, EmptyMutation, EmptySubscription)
        .data(user_loader)
        .data(like_count_loader)
        .finish();

    // ... 启动服务器 ...
    Ok(())
}
```

4. **在 GraphQL 解析器中使用 Loaders**

修改 GraphQL 查询:
```rust
// 在 async_graphql 中使用 DataLoader
pub struct Post {
    pub id: Uuid,
    pub creator_id: Uuid,
    // ...
}

#[Object]
impl Post {
    async fn creator(&self, ctx: &Context<'_>) -> Result<User> {
        let loader = ctx.data::<DataLoader<RealUserLoader>>()
            .map_err(|_| "User loader not found")?;

        // ✅ DataLoader 自动批处理
        loader.load_one(self.creator_id)
            .await
            .map_err(|e| e.into())
    }

    async fn like_count(&self, ctx: &Context<'_>) -> Result<i64> {
        let loader = ctx.data::<DataLoader<RealLikeCountLoader>>()
            .map_err(|_| "Like count loader not found")?;

        loader.load_one(self.id)
            .await
            .map_err(|e| e.into())
    }
}
```

5. **测试 Loaders**

新建测试文件 `tests/graphql_loaders_test.rs`:
```rust
#[tokio::test]
async fn test_user_loader_batching() {
    let db_pool = create_test_pool().await;
    let user_loader = RealUserLoader::new(db_pool);
    let data_loader = DataLoader::new(user_loader, tokio::task::spawn);

    // 模拟 GraphQL 请求加载多个用户
    let user_ids = vec![uuid_1, uuid_2, uuid_3];
    let users = futures::future::join_all(
        user_ids.iter().map(|id| data_loader.load_one(*id))
    ).await;

    // 验证所有用户加载成功
    assert_eq!(users.len(), 3);
    for user in users {
        assert!(user.is_ok());
    }

    // 验证只发生了 1 次数据库查询（batch）
    let query_count = db_pool.query_count();
    assert_eq!(query_count, 1, "Expected 1 batched query, got {}", query_count);
}

#[tokio::test]
async fn test_like_count_loader_missing_data() {
    let db_pool = create_test_pool().await;
    let like_count_loader = RealLikeCountLoader::new(db_pool);
    let data_loader = DataLoader::new(like_count_loader, tokio::task::spawn);

    let post_ids = vec![post_1, post_2, post_3];  // post_3 可能没有赞

    let counts = futures::future::join_all(
        post_ids.iter().map(|id| data_loader.load_one(*id))
    ).await;

    // 验证 post_3 返回 0（而不是错误）
    assert_eq!(counts[2].unwrap(), 0);
}
```

6. **运行测试**
```bash
cd /Users/proerror/Documents/nova/backend/graphql-gateway

# 单元测试
cargo test --lib schema::loaders

# 集成测试
cargo test --test graphql_loaders_test

# 实际性能测试
cargo test --test performance_benchmark -- --nocapture
```

**预期结果**:
- ✅ GraphQL 查询 N+1 消除
- ✅ 从 300ms 减少到 50ms（6倍改进）
- ✅ 数据库查询从 10+ 减少到 2-3

**性能验证**:
```bash
# 使用 GraphQL 工具验证
curl -X POST http://localhost:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{ posts(limit: 10) { id creator { id username } likeCount } }"
  }' \
  | jq .
```

---

### 第 2-3 周：高级优化

#### 任务 2.1: Neo4j 查询合并 (3-4 小时)

**步骤**:

1. **分析当前 Neo4j 实现**

文件: `/graph-service/src/repository/graph_repository.rs`

2. **创建优化版本**

```rust
// 优化前（3 次网络往返）
pub async fn create_follow_old(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
    self.ensure_user_node(follower_id).await?;  // RTT 1
    self.ensure_user_node(followee_id).await?;  // RTT 2
    self.create_follow_edge(...).await?;        // RTT 3
}

// 优化后（1 次网络往返）
pub async fn create_follow_optimized(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
    let cypher = r#"
        MERGE (a:User {id: $follower})
        ON CREATE SET a.created_at = timestamp()
        MERGE (b:User {id: $followee})
        ON CREATE SET b.created_at = timestamp()
        MERGE (a)-[r:FOLLOWS]->(b)
        ON CREATE SET r.created_at = timestamp()
        RETURN r.created_at
    "#;

    let mut result = self
        .graph
        .execute(
            query(cypher)
                .param("follower", follower_id.to_string())
                .param("followee", followee_id.to_string()),
        )
        .await
        .context("Failed to create follow")?;

    while result.next().await?.is_some() {}

    debug!("Created FOLLOWS: {} -> {}", follower_id, followee_id);
    Ok(())
}
```

3. **添加 Neo4j 索引**

新建迁移: `/graph-service/migrations/create_neo4j_indexes.cypher`

```cypher
// 用户节点标签索引
CREATE INDEX idx_user_id IF NOT EXISTS FOR (u:User) ON (u.id);

// FOLLOWS 关系索引
CREATE INDEX idx_follows_created IF NOT EXISTS
  FOR ()-[r:FOLLOWS]-() ON (r.created_at DESC);

// 反向查询优化（获取粉丝）
CREATE INDEX idx_follows_follower IF NOT EXISTS
  FOR (a:User)-[r:FOLLOWS]->(b:User) ON (a.id, b.id);

// MUTES 关系
CREATE INDEX idx_mutes_mutee IF NOT EXISTS
  FOR ()-[r:MUTES]->(u:User) ON (u.id);
```

执行:
```bash
# 连接 Neo4j
neo4j-shell -u neo4j -p password

# 执行索引创建脚本
:source /path/to/create_neo4j_indexes.cypher

# 验证索引
SHOW INDEXES;
```

#### 任务 2.2: 多级缓存架构 (6-8 小时)

**步骤**:

1. **设计缓存层**

```rust
// /backend/libs/cache-service/src/lib.rs
use redis::aio::ConnectionManager;
use sqlx::PgPool;
use std::sync::Arc;

#[derive(Clone)]
pub struct MultiLevelCache {
    l1_redis: ConnectionManager,      // 热缓存（易失）
    l2_db: PgPool,                    // 持久缓存（准确）
}

impl MultiLevelCache {
    pub async fn get_like_count(&self, post_id: Uuid) -> Result<i64> {
        // L1: Redis
        let redis_key = format!("likes:count:{}", post_id);
        if let Ok(Some(count)) = self.get_from_redis(&redis_key).await {
            metrics::counter!("cache_hits", "level" => "l1");
            return Ok(count);
        }

        // L2: Database cache table
        if let Ok(Some(count)) = self.get_from_db_cache(post_id).await {
            metrics::counter!("cache_hits", "level" => "l2");
            // 异步回写 L1
            self.write_to_redis_async(&redis_key, count).await;
            return Ok(count);
        }

        // L3: Real-time count
        let count = self.compute_like_count(post_id).await?;
        metrics::counter!("cache_misses");

        // 填充所有缓存层
        self.write_to_redis_async(&redis_key, count).await;
        self.write_to_db_cache(post_id, count).await.ok();

        Ok(count)
    }

    async fn get_from_redis(&self, key: &str) -> Result<Option<i64>> {
        redis::cmd("GET")
            .arg(key)
            .query_async(&mut self.l1_redis.clone())
            .await
            .map_err(|e| anyhow::anyhow!(e))
    }

    async fn write_to_redis_async(&self, key: &str, value: i64) {
        let redis = self.l1_redis.clone();
        let key = key.to_string();
        tokio::spawn(async move {
            let _ = redis::cmd("SETEX")
                .arg(&key)
                .arg(3600)  // 1 小时 TTL
                .arg(value)
                .query_async::<_, ()>(&mut redis.clone())
                .await;
        });
    }

    async fn get_from_db_cache(&self, post_id: Uuid) -> Result<Option<i64>> {
        sqlx::query_scalar::<_, i64>(
            "SELECT like_count FROM post_counters WHERE post_id = $1"
        )
        .bind(post_id)
        .fetch_optional(&self.l2_db)
        .await
        .map_err(|e| anyhow::anyhow!(e))
    }

    async fn compute_like_count(&self, post_id: Uuid) -> Result<i64> {
        sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM likes WHERE post_id = $1"
        )
        .bind(post_id)
        .fetch_one(&self.l2_db)
        .await
        .map_err(|e| anyhow::anyhow!(e))
    }
}
```

2. **集成到 social-service**

修改 `/social-service/src/services/counters.rs`:

```rust
use cache_service::MultiLevelCache;

pub struct CounterService {
    cache: MultiLevelCache,
}

impl CounterService {
    pub async fn get_like_count(&self, post_id: Uuid) -> Result<i64> {
        self.cache.get_like_count(post_id).await
    }
}
```

3. **测试多级缓存**

```rust
#[tokio::test]
async fn test_multilevel_cache_fallback() {
    let cache = create_test_cache().await;

    // 清空所有缓存
    cache.clear_redis().await.unwrap();
    cache.clear_db_cache().await.unwrap();

    // 第一次访问 → L3（直接查询）
    let count = cache.get_like_count(post_id).await.unwrap();
    assert_eq!(count, 5);

    // 等待异步回写完成
    tokio::time::sleep(Duration::from_millis(100)).await;

    // 第二次访问 → L1（Redis）
    let count = cache.get_like_count(post_id).await.unwrap();
    assert_eq!(count, 5);

    // 验证命中率
    assert!(cache.metrics().cache_hit_rate > 0.5);
}
```

---

### 第 4 周：监控和验证

#### 任务 4.1: 设置性能监控 (2-3 小时)

1. **添加 Prometheus 指标**

```rust
// /backend/libs/metrics/src/lib.rs
use prometheus::{Counter, Histogram, Gauge, Registry};
use lazy_static::lazy_static;

lazy_static! {
    pub static ref DB_QUERY_DURATION: Histogram =
        Histogram::new("db_query_duration_ms", "Database query duration in ms")
            .unwrap();

    pub static ref CACHE_HIT_RATE: Gauge =
        Gauge::new("cache_hit_rate", "Cache hit rate").unwrap();

    pub static ref POOL_CONNECTIONS_ACTIVE: Gauge =
        Gauge::new("db_pool_connections_active", "Active connections").unwrap();

    pub static ref N_PLUS_ONE_DETECTED: Counter =
        Counter::new("graphql_n_plus_one_queries", "N+1 queries detected").unwrap();
}

pub fn record_query_duration(duration_ms: f64, table: &str) {
    DB_QUERY_DURATION
        .with_label_values(&[table])
        .observe(duration_ms);
}
```

2. **Grafana 仪表板**

创建仪表板配置文件:
```json
{
  "dashboard": {
    "title": "Nova Database Performance",
    "panels": [
      {
        "title": "Query Duration by Table",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, db_query_duration_ms)"
          }
        ]
      },
      {
        "title": "Cache Hit Rate",
        "targets": [
          {
            "expr": "cache_hit_rate"
          }
        ]
      },
      {
        "title": "Active DB Connections",
        "targets": [
          {
            "expr": "db_pool_connections_active"
          }
        ]
      }
    ]
  }
}
```

3. **慢查询监控**

```sql
-- 在 PostgreSQL 中启用日志
ALTER SYSTEM SET log_min_duration_statement = 100;  -- 记录 > 100ms 的查询
ALTER SYSTEM SET log_statement = 'all';

-- 重启 PostgreSQL
SELECT pg_reload_conf();

-- 监视慢查询
SELECT query, calls, mean_time
FROM pg_stat_statements
WHERE mean_time > 100
ORDER BY mean_time DESC
LIMIT 10;
```

#### 任务 4.2: 性能验证和对标 (2-3 小时)

1. **建立性能基准**

```bash
# 运行基准测试
cd /Users/proerror/Documents/nova/backend
cargo bench --bench performance

# 记录基准数据
cat > /tmp/baseline.json << 'EOF'
{
  "feed_query_p95": 500,          // ms
  "like_count_query": 200,        // ms
  "comment_list_query": 300,      // ms
  "graphql_post_query": 300,      // ms
  "api_throughput": 500           // req/s
}
EOF
```

2. **优化后对比**

```bash
# 验证性能改进
cargo bench --bench performance 2>&1 | tee /tmp/optimized.json

# 使用脚本对比
python3 << 'EOF'
import json

with open('/tmp/baseline.json') as f:
    baseline = json.load(f)

with open('/tmp/optimized.json') as f:
    optimized = json.load(f)

improvements = {}
for key in baseline:
    before = baseline[key]
    after = optimized.get(key, before)
    improvement = ((before - after) / before) * 100
    improvements[key] = improvement
    print(f"{key}: {before} → {after} ({improvement:.1f}% 改进)")

avg_improvement = sum(improvements.values()) / len(improvements)
print(f"\n平均改进: {avg_improvement:.1f}%")
EOF
```

3. **端到端测试**

```bash
# 启动应用
docker-compose up -d

# 运行负载测试
k6 run performance-test.js

# 收集指标
curl http://localhost:9090/api/v1/query \
  -G --data-urlencode 'query=histogram_quantile(0.95, db_query_duration_ms)'
```

---

## 部署检查表

### 前置检查
- [ ] 备份生产数据库
- [ ] 在测试环境验证所有更改
- [ ] 获取性能基准数据
- [ ] 准备回滚计划
- [ ] 通知运维和产品团队

### 第 1 周部署
- [ ] 创建并应用索引迁移
- [ ] 更新所有服务的连接池配置
- [ ] 部署 GraphQL Loader 修复
- [ ] 监控性能指标

### 第 2-3 周部署
- [ ] 优化 Neo4j 查询
- [ ] 部署多级缓存
- [ ] 添加 ClickHouse 分区
- [ ] 实施缓存失效策略

### 第 4 周部署
- [ ] 启用性能监控
- [ ] 收集对标数据
- [ ] 文档化优化成果
- [ ] 制定持续改进计划

---

## 成功指标

| 指标 | 目标 | 验证方法 |
|------|------|---------|
| Feed 查询延迟 | <200ms (P95) | `SELECT query_time FROM metrics WHERE endpoint = '/feed'` |
| 点赞计数查询 | <10ms | `EXPLAIN ANALYZE SELECT COUNT(*) FROM likes WHERE post_id = $1` |
| API 吞吐量 | >2000 req/s | K6 负载测试 |
| 缓存命中率 | >80% | Prometheus 指标 `cache_hit_rate` |
| N+1 查询 | 0 检测到 | GraphQL DataLoader 指标 |
| 数据库连接泄漏 | 0 | `SELECT count(*) FROM pg_stat_activity` |

---

## 故障排除

### 问题 1: 索引创建超时

```bash
# 使用 CONCURRENTLY 在后台创建
DROP INDEX idx_likes_post_created_id;
CREATE INDEX CONCURRENTLY idx_likes_post_created_id
  ON likes(post_id, created_at DESC, id);

# 监控进度
SELECT * FROM pg_stat_progress_create_index;
```

### 问题 2: 连接池耗尽

```bash
# 检查活跃连接
SELECT count(*) FROM pg_stat_activity;

# 增加最大连接数（临时）
ALTER SYSTEM SET max_connections = 200;
SELECT pg_reload_conf();

# 分析连接泄漏
SELECT pid, usename, application_name, wait_event
FROM pg_stat_activity
WHERE state != 'active'
ORDER BY query_start DESC LIMIT 10;
```

### 问题 3: Redis 内存溢出

```bash
# 检查内存使用
redis-cli INFO memory

# 设置驱逐策略
redis-cli CONFIG SET maxmemory-policy allkeys-lru

# 清理过期 key
redis-cli --scan --pattern "*" | redis-cli -x DEL
```

---

## 后续维护

### 每周任务
- 检查慢查询日志
- 验证缓存命中率
- 监控索引碎片

### 每月任务
- 更新表统计信息 (`ANALYZE`)
- 重建膨胀的索引 (`REINDEX`)
- 审查数据库成长率

### 每季度任务
- 性能对标测试
- 识别新的优化机会
- 更新容量规划预测


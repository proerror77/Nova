# Performance Optimization Implementation Guide

**目标**: 3-10x 吞吐量提升, 80%+ 延迟降低
**时间线**: 4 周完整实施
**风险等级**: 低 (向后兼容)

---

## Week 1: Critical P0 Fixes (Quick Wins)

### 1. 修复 feed-service N+1 查询 [P0-BLOCKER]

**问题位置**: `backend/feed-service/src/services/recommendation_v2/mod.rs:L185`

#### 当前实现 (❌ BAD)
```rust
// ❌ 每个关注用户单独查询 posts
async fn fetch_posts_from_follows(
    pool: &PgPool,
    following_ids: &[Uuid],
) -> Result<Vec<PostId>> {
    let mut all_posts = Vec::new();

    for user_id in following_ids {
        let posts = sqlx::query_as!(
            PostRecord,
            "SELECT id FROM posts
             WHERE user_id = $1 AND soft_delete IS NULL
             ORDER BY created_at DESC LIMIT $2",
            user_id,
            20
        )
        .fetch_all(pool)
        .await?;

        all_posts.extend(posts.into_iter().map(|p| p.id));
    }

    Ok(all_posts)
}
```

**问题**: 100个关注 = 100次数据库查询 = 500ms+ 延迟

#### 优化方案 1: 批量查询 (✅ GOOD - 临时方案)
```rust
// ✅ GOOD: 单次批量查询
async fn fetch_posts_from_follows_batch(
    pool: &PgPool,
    following_ids: &[Uuid],
    limit_per_user: i32,
) -> Result<Vec<PostId>> {
    // 使用 LATERAL JOIN 为每个用户限制 post 数量
    let posts = sqlx::query_as!(
        PostRecord,
        r#"
        SELECT DISTINCT ON (user_id, id) id
        FROM (
            SELECT p.id, p.user_id, p.created_at
            FROM posts p
            WHERE p.user_id = ANY($1)
              AND p.soft_delete IS NULL
            ORDER BY p.user_id, p.created_at DESC
        ) sub
        ORDER BY user_id, created_at DESC
        LIMIT $2
        "#,
        following_ids,
        (following_ids.len() as i32) * limit_per_user
    )
    .fetch_all(pool)
    .await?;

    Ok(posts.into_iter().map(|p| p.id).collect())
}
```

**性能提升**: 100次查询 → 1次查询 = -98% 数据库往返

#### 优化方案 2: ClickHouse 预计算 (✅ BEST - 最终方案)
```rust
// ✅ BEST: 从 ClickHouse 读取预计算的 feed 候选
async fn fetch_feed_candidates_from_clickhouse(
    ch_client: &ClickHouseClient,
    user_id: &Uuid,
    limit: usize,
) -> Result<Vec<FeedCandidate>> {
    let query = r#"
        SELECT
            post_id,
            score,
            created_at,
            author_id
        FROM feed_candidates
        WHERE user_id = ?
          AND created_at > now() - INTERVAL 7 DAY
          AND is_deleted = 0
        ORDER BY score DESC
        LIMIT ?
    "#;

    let candidates = ch_client
        .query(query)
        .bind(user_id)
        .bind(limit)
        .fetch_all::<FeedCandidate>()
        .await?;

    Ok(candidates)
}

// 后台作业: 每5分钟更新 feed 候选
async fn refresh_feed_candidates_job(
    ch_client: Arc<ClickHouseClient>,
    pg_pool: PgPool,
) {
    let mut interval = tokio::time::interval(Duration::from_secs(300)); // 5分钟

    loop {
        interval.tick().await;

        match compute_and_store_feed_candidates(&ch_client, &pg_pool).await {
            Ok(count) => tracing::info!("Refreshed {} feed candidates", count),
            Err(e) => tracing::error!("Feed refresh failed: {}", e),
        }
    }
}
```

**性能提升**:
- 延迟: 500ms → 50ms (-90%)
- 数据库负载: -95%
- 可扩展性: 支持百万级用户

#### 实施步骤
```bash
# Step 1: 添加 ClickHouse 表结构
clickhouse-client --query "
CREATE TABLE IF NOT EXISTS feed_candidates (
    user_id UUID,
    post_id UUID,
    author_id UUID,
    score Float32,
    created_at DateTime,
    is_deleted UInt8,
    INDEX idx_user_score (user_id, score) TYPE minmax GRANULARITY 1
) ENGINE = MergeTree()
ORDER BY (user_id, score DESC)
PARTITION BY toYYYYMM(created_at)
SETTINGS index_granularity = 8192;
"

# Step 2: 数据迁移 (一次性)
cargo run --bin feed-candidate-migrator

# Step 3: 启动后台刷新作业
# 在 feed-service main.rs 添加:
tokio::spawn(refresh_feed_candidates_job(ch_client, db_pool));

# Step 4: 切换流量 (Feature Flag)
export FEED_SOURCE=clickhouse  # 或 postgres (回滚)
```

**回滚方案**:
```rust
let feed_source = std::env::var("FEED_SOURCE").unwrap_or("postgres".into());

let posts = match feed_source.as_str() {
    "clickhouse" => fetch_feed_candidates_from_clickhouse(/*...*/).await?,
    _ => fetch_posts_from_follows_batch(/*...*/).await?,
};
```

---

### 2. 启用 GraphQL Redis 缓存 [P0]

**问题位置**: `backend/graphql-gateway/src/schema/user.rs`

#### 当前实现 (❌ BAD)
```rust
#[Object]
impl UserQuery {
    async fn user(&self, ctx: &Context<'_>, id: ID) -> Result<User> {
        let clients = ctx.data::<ServiceClients>()?;

        // ❌ 每次都调用 gRPC
        let user = clients
            .user_client()
            .get_user(id.to_string())
            .await?;

        Ok(user.into())
    }
}
```

**问题**: 每次 GraphQL 查询都击穿到 user-service

#### 优化实现 (✅ GOOD)
```rust
use crate::cache::{CacheClient, CacheKeyBuilder};

#[Object]
impl UserQuery {
    async fn user(&self, ctx: &Context<'_>, id: ID) -> Result<User> {
        let clients = ctx.data::<ServiceClients>()?;
        let cache = ctx.data::<Arc<CacheClient>>()?;

        let cache_key = CacheKeyBuilder::user_profile(&id);

        // ✅ L2: Redis 缓存检查
        if let Some(user) = cache.get::<User>(&cache_key).await? {
            tracing::debug!("Cache hit: user {}", id);
            return Ok(user);
        }

        // Cache miss - 查询后端
        tracing::debug!("Cache miss: user {}", id);
        let user = clients
            .user_client()
            .get_user(id.to_string())
            .await?
            .into();

        // 回写缓存 (TTL: 10分钟)
        cache.set_with_ttl(&cache_key, &user, 600).await?;

        Ok(user)
    }
}
```

#### 缓存失效处理
```rust
// 在 user update mutation 中失效缓存
#[Object]
impl UserMutation {
    async fn update_user(
        &self,
        ctx: &Context<'_>,
        input: UpdateUserInput,
    ) -> Result<User> {
        let clients = ctx.data::<ServiceClients>()?;
        let cache = ctx.data::<Arc<CacheClient>>()?;

        // 更新用户
        let user = clients
            .user_client()
            .update_user(input)
            .await?
            .into();

        // ✅ 失效相关缓存
        let invalidator = CacheInvalidator::new(cache.clone());
        invalidator.on_user_update(&user.id).await?;

        Ok(user)
    }
}
```

#### 批量查询优化 (DataLoader 模式)
```rust
use async_graphql::dataloader::{DataLoader, Loader};
use std::collections::HashMap;

pub struct UserLoader {
    clients: Arc<ServiceClients>,
    cache: Arc<CacheClient>,
}

#[async_trait::async_trait]
impl Loader<String> for UserLoader {
    type Value = User;
    type Error = Arc<anyhow::Error>;

    async fn load(&self, keys: &[String]) -> Result<HashMap<String, User>, Self::Error> {
        // ✅ Step 1: 批量检查缓存
        let mut result = HashMap::new();
        let mut cache_misses = Vec::new();

        for key in keys {
            let cache_key = CacheKeyBuilder::user_profile(key);
            if let Some(user) = self.cache.get::<User>(&cache_key).await? {
                result.insert(key.clone(), user);
            } else {
                cache_misses.push(key.clone());
            }
        }

        // ✅ Step 2: 批量查询未命中的用户
        if !cache_misses.is_empty() {
            let users = self
                .clients
                .user_client()
                .batch_get_users(cache_misses.clone())
                .await?;

            // ✅ Step 3: 回写缓存并返回结果
            for user in users {
                let cache_key = CacheKeyBuilder::user_profile(&user.id);
                self.cache.set_with_ttl(&cache_key, &user, 600).await?;
                result.insert(user.id.clone(), user);
            }
        }

        Ok(result)
    }
}

// 使用 DataLoader
#[Object]
impl PostQuery {
    async fn posts(&self, ctx: &Context<'_>, limit: i32) -> Result<Vec<Post>> {
        let user_loader = ctx.data::<DataLoader<UserLoader>>()?;

        let posts = fetch_posts(limit).await?;

        // ✅ 批量加载作者信息 (自动去重 + 缓存)
        for post in &mut posts {
            post.author = user_loader.load_one(post.author_id.clone()).await?;
        }

        Ok(posts)
    }
}
```

**性能提升**:
- 缓存命中率 60-80%
- 延迟降低: 200ms → 40ms (-80%)
- 数据库查询: -60%

---

### 3. 添加 gRPC 超时和重试配置 [P1]

**问题位置**: `backend/libs/grpc-clients/src/pool.rs`

#### 当前实现 (⚠️ 缺少超时)
```rust
let channel = Channel::from_shared(uri)?
    .connect()
    .await?;
```

#### 优化实现 (✅ GOOD)
```rust
use tonic::transport::{Channel, ClientTlsConfig};
use std::time::Duration;

pub async fn create_grpc_channel(
    uri: String,
    tls_config: Option<ClientTlsConfig>,
) -> Result<Channel> {
    let mut builder = Channel::from_shared(uri)?
        // ✅ 连接超时 (3秒)
        .connect_timeout(Duration::from_secs(3))
        // ✅ 请求超时 (5秒)
        .timeout(Duration::from_secs(5))
        // ✅ HTTP/2 Keep-alive (30秒发送 PING)
        .http2_keep_alive_interval(Duration::from_secs(30))
        // ✅ Keep-alive 超时 (60秒无响应断开)
        .keep_alive_timeout(Duration::from_secs(60))
        // ✅ Keep-alive 即使空闲也发送
        .keep_alive_while_idle(true)
        // ✅ 初始连接窗口大小 (减少 HOL blocking)
        .initial_connection_window_size(1024 * 1024) // 1MB
        .initial_stream_window_size(1024 * 1024);   // 1MB

    if let Some(tls) = tls_config {
        builder = builder.tls_config(tls)?;
    }

    builder.connect().await
}
```

#### 添加重试逻辑 (Exponential Backoff)
```rust
use resilience::retry::{RetryPolicy, ExponentialBackoff};

pub async fn call_with_retry<F, T, E>(
    operation: F,
    max_retries: u32,
) -> Result<T, E>
where
    F: Fn() -> std::pin::Pin<Box<dyn Future<Output = Result<T, E>>>>,
    E: std::fmt::Display,
{
    let policy = ExponentialBackoff::new(
        Duration::from_millis(100), // 初始延迟
        2.0,                         // 指数因子
        Duration::from_secs(5),      // 最大延迟
    );

    for attempt in 0..=max_retries {
        match operation().await {
            Ok(result) => return Ok(result),
            Err(e) if attempt == max_retries => {
                tracing::error!("Operation failed after {} retries: {}", max_retries, e);
                return Err(e);
            }
            Err(e) => {
                let delay = policy.delay(attempt);
                tracing::warn!(
                    "Operation failed (attempt {}/{}): {}. Retrying in {:?}",
                    attempt + 1,
                    max_retries,
                    e,
                    delay
                );
                tokio::time::sleep(delay).await;
            }
        }
    }

    unreachable!()
}

// 使用示例
let user = call_with_retry(
    || Box::pin(client.get_user(user_id.clone())),
    3,
).await?;
```

---

## Week 2: Database Optimization

### 4. 添加复合索引和覆盖索引 [P2]

#### Migration: `126_performance_indexes_week2.sql`
```sql
-- ============================================================================
-- Week 2 Performance Indexes
-- ============================================================================

-- Feed 生成查询优化 (covering index)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_follows_feed_covering
ON follows(follower_id, created_at DESC)
INCLUDE (following_id, unfollowed_at)
WHERE unfollowed_at IS NULL;

COMMENT ON INDEX idx_follows_feed_covering IS
'Covering index for feed generation: avoids table lookup';

-- 消息分页查询优化 (partial index + covering)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_conversation_paging
ON messages(conversation_id, created_at DESC)
INCLUDE (content, sender_id, message_type)
WHERE deleted_at IS NULL;

-- Story 可见性查询 (表达式索引)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_stories_active_visibility
ON stories(owner_id, expires_at)
WHERE expires_at > NOW() AND deleted_at IS NULL;

-- Post 搜索优化 (GIN 全文索引)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_posts_content_search
ON posts USING GIN (to_tsvector('english', content));

-- 热门内容查询 (部分索引 + 函数索引)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_posts_trending_score
ON posts(
    (engagement_count::float / EXTRACT(EPOCH FROM (NOW() - created_at))::float) DESC,
    created_at DESC
)
WHERE created_at > NOW() - INTERVAL '7 days'
  AND soft_delete IS NULL;

-- 用户活跃度统计 (聚合查询优化)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_actions_aggregation
ON user_actions(user_id, action_type, created_at)
WHERE created_at > NOW() - INTERVAL '30 days';

-- ============================================================================
-- Index Monitoring Queries
-- ============================================================================

-- 查询索引使用情况
CREATE OR REPLACE VIEW v_index_usage_stats AS
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC;

-- 查询未使用的索引 (候选删除)
CREATE OR REPLACE VIEW v_unused_indexes AS
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE 'pg_toast%'
ORDER BY pg_relation_size(indexrelid) DESC;

-- 查询重复索引
CREATE OR REPLACE VIEW v_duplicate_indexes AS
SELECT
    pg_size_pretty(SUM(pg_relation_size(idx))::BIGINT) AS size,
    (array_agg(idx))[1] AS idx1,
    (array_agg(idx))[2] AS idx2,
    (array_agg(idx))[3] AS idx3,
    (array_agg(idx))[4] AS idx4
FROM (
    SELECT
        indexrelid::regclass AS idx,
        (indrelid::text ||E'\n'|| indclass::text ||E'\n'||
         indkey::text ||E'\n'|| COALESCE(indexprs::text,'')||E'\n' ||
         COALESCE(indpred::text,'')) AS key
    FROM pg_index
) sub
GROUP BY key
HAVING COUNT(*) > 1
ORDER BY SUM(pg_relation_size(idx)) DESC;

-- ============================================================================
-- Performance Tips
-- ============================================================================

-- CONCURRENTLY 注意事项:
-- 1. 创建索引时不阻塞写入 (但会更慢)
-- 2. 适合生产环境在线操作
-- 3. 失败需要手动清理: DROP INDEX CONCURRENTLY idx_name;

-- VACUUM ANALYZE 推荐:
VACUUM ANALYZE posts, follows, messages, stories;

-- 查询计划缓存刷新:
DISCARD PLANS;
```

#### 验证索引效果
```sql
-- 验证 feed 查询计划
EXPLAIN (ANALYZE, BUFFERS)
SELECT following_id
FROM follows
WHERE follower_id = 'user-uuid-here'
  AND unfollowed_at IS NULL
ORDER BY created_at DESC
LIMIT 100;

-- 预期结果: Index Only Scan (不访问表)
-- Execution Time: < 5ms
```

---

### 5. 查询优化最佳实践 [P2]

#### 避免 SELECT * (减少网络传输)
```rust
// ❌ BAD: 查询所有列
let posts = sqlx::query_as!(
    Post,
    "SELECT * FROM posts WHERE user_id = $1",
    user_id
)
.fetch_all(pool)
.await?;

// ✅ GOOD: 只查询需要的列
let posts = sqlx::query_as!(
    PostSummary,
    "SELECT id, user_id, created_at, content_preview
     FROM posts WHERE user_id = $1",
    user_id
)
.fetch_all(pool)
.await?;
```

#### 使用 Prepared Statements (查询缓存)
```rust
// ✅ GOOD: sqlx 自动使用 prepared statements
let stmt = sqlx::query_as!(
    User,
    "SELECT id, username, email FROM users WHERE id = $1",
    user_id
);

// 多次执行不会重复解析 SQL
for id in user_ids {
    let user = stmt.bind(id).fetch_one(pool).await?;
}
```

#### 分页查询优化 (Keyset Pagination)
```rust
// ❌ BAD: OFFSET 分页 (深分页性能差)
let posts = sqlx::query_as!(
    Post,
    "SELECT * FROM posts
     ORDER BY created_at DESC
     LIMIT $1 OFFSET $2",
    limit,
    page * limit  // 1000页 = 扫描10万行
)
.fetch_all(pool)
.await?;

// ✅ GOOD: Keyset 分页 (基于游标)
let posts = sqlx::query_as!(
    Post,
    "SELECT * FROM posts
     WHERE created_at < $1  -- 上一页最后的时间戳
     ORDER BY created_at DESC
     LIMIT $2",
    cursor_timestamp,
    limit
)
.fetch_all(pool)
.await?;
```

---

## Week 3-4: Monitoring & Observability

### 6. Prometheus 指标完善 [P1]

#### gRPC 请求延迟指标
```rust
// backend/libs/grpc-metrics/src/lib.rs

use prometheus::{
    register_histogram_vec, register_int_counter_vec,
    HistogramVec, IntCounterVec,
};
use std::time::Instant;
use tonic::Code;

lazy_static::lazy_static! {
    // gRPC 请求延迟分布
    pub static ref GRPC_REQUEST_DURATION: HistogramVec = register_histogram_vec!(
        "grpc_request_duration_seconds",
        "gRPC request latency distribution",
        &["service", "method", "status"],
        vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
    ).unwrap();

    // gRPC 请求计数
    pub static ref GRPC_REQUEST_COUNT: IntCounterVec = register_int_counter_vec!(
        "grpc_requests_total",
        "Total number of gRPC requests",
        &["service", "method", "status"]
    ).unwrap();
}

/// 记录 gRPC 请求指标
pub fn observe_grpc_request(
    service: &str,
    method: &str,
    status: Code,
    duration: std::time::Duration,
) {
    let status_str = match status {
        Code::Ok => "ok",
        Code::Cancelled => "cancelled",
        Code::Unknown => "unknown",
        Code::InvalidArgument => "invalid_argument",
        Code::DeadlineExceeded => "deadline_exceeded",
        Code::NotFound => "not_found",
        Code::AlreadyExists => "already_exists",
        Code::PermissionDenied => "permission_denied",
        Code::ResourceExhausted => "resource_exhausted",
        Code::FailedPrecondition => "failed_precondition",
        Code::Aborted => "aborted",
        Code::OutOfRange => "out_of_range",
        Code::Unimplemented => "unimplemented",
        Code::Internal => "internal",
        Code::Unavailable => "unavailable",
        Code::DataLoss => "data_loss",
        Code::Unauthenticated => "unauthenticated",
    };

    GRPC_REQUEST_DURATION
        .with_label_values(&[service, method, status_str])
        .observe(duration.as_secs_f64());

    GRPC_REQUEST_COUNT
        .with_label_values(&[service, method, status_str])
        .inc();
}

/// gRPC 调用包装器 (自动记录指标)
pub async fn call_with_metrics<F, T>(
    service: &str,
    method: &str,
    operation: F,
) -> Result<T, tonic::Status>
where
    F: std::future::Future<Output = Result<T, tonic::Status>>,
{
    let start = Instant::now();

    let result = operation.await;

    let duration = start.elapsed();
    let status = match &result {
        Ok(_) => Code::Ok,
        Err(e) => e.code(),
    };

    observe_grpc_request(service, method, status, duration);

    result
}
```

#### 缓存命中率指标
```rust
// backend/graphql-gateway/src/cache/metrics.rs

use prometheus::{register_int_counter_vec, IntCounterVec};

lazy_static::lazy_static! {
    pub static ref CACHE_OPERATIONS: IntCounterVec = register_int_counter_vec!(
        "cache_operations_total",
        "Cache operation counts",
        &["operation", "cache_key", "result"]
    ).unwrap();
}

impl CacheClient {
    pub async fn get_with_metrics<T>(&self, key: &str) -> Result<Option<T>>
    where
        T: for<'de> Deserialize<'de>,
    {
        match self.get::<T>(key).await {
            Ok(Some(value)) => {
                CACHE_OPERATIONS
                    .with_label_values(&["get", key, "hit"])
                    .inc();
                Ok(Some(value))
            }
            Ok(None) => {
                CACHE_OPERATIONS
                    .with_label_values(&["get", key, "miss"])
                    .inc();
                Ok(None)
            }
            Err(e) => {
                CACHE_OPERATIONS
                    .with_label_values(&["get", key, "error"])
                    .inc();
                Err(e)
            }
        }
    }
}
```

#### Grafana 仪表板配置
```yaml
# grafana-dashboard-nova-performance.json
{
  "dashboard": {
    "title": "Nova Platform Performance",
    "panels": [
      {
        "title": "gRPC Request Latency (P50/P95/P99)",
        "targets": [
          {
            "expr": "histogram_quantile(0.50, sum(rate(grpc_request_duration_seconds_bucket[5m])) by (service, le))",
            "legendFormat": "{{service}} P50"
          },
          {
            "expr": "histogram_quantile(0.95, sum(rate(grpc_request_duration_seconds_bucket[5m])) by (service, le))",
            "legendFormat": "{{service}} P95"
          },
          {
            "expr": "histogram_quantile(0.99, sum(rate(grpc_request_duration_seconds_bucket[5m])) by (service, le))",
            "legendFormat": "{{service}} P99"
          }
        ]
      },
      {
        "title": "Cache Hit Rate",
        "targets": [
          {
            "expr": "sum(rate(cache_operations_total{result=\"hit\"}[5m])) / sum(rate(cache_operations_total{operation=\"get\"}[5m])) * 100",
            "legendFormat": "Hit Rate %"
          }
        ]
      },
      {
        "title": "Database Connection Pool Utilization",
        "targets": [
          {
            "expr": "db_pool_connections_active / db_pool_connections_max * 100",
            "legendFormat": "{{service}} Pool %"
          }
        ]
      },
      {
        "title": "Query Duration (Slow Queries > 100ms)",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, sum(rate(sqlx_query_duration_seconds_bucket[5m])) by (query, le))",
            "legendFormat": "{{query}} P99"
          }
        ]
      }
    ],
    "alerts": [
      {
        "name": "High Database Pool Utilization",
        "condition": "avg(db_pool_connections_active / db_pool_connections_max) > 0.85",
        "for": "5m",
        "annotations": {
          "summary": "Database pool >85% utilized - risk of exhaustion"
        }
      },
      {
        "name": "Low Cache Hit Rate",
        "condition": "avg(cache_hit_rate) < 50",
        "for": "10m",
        "annotations": {
          "summary": "Cache hit rate <50% - check cache config"
        }
      },
      {
        "name": "High gRPC Latency",
        "condition": "histogram_quantile(0.95, grpc_request_duration_seconds) > 0.5",
        "for": "5m",
        "annotations": {
          "summary": "gRPC P95 latency >500ms"
        }
      }
    ]
  }
}
```

---

## 性能测试脚本

### 负载测试配置
```yaml
# load-test/feed-generation.yml
config:
  target: "http://localhost:8080"
  phases:
    - duration: 60
      arrivalRate: 10
      name: "Warm-up"
    - duration: 300
      arrivalRate: 100
      name: "Sustained load"
    - duration: 60
      arrivalRate: 200
      name: "Spike test"

scenarios:
  - name: "Feed Generation"
    flow:
      - post:
          url: "/graphql"
          json:
            query: |
              query GetFeed($limit: Int!) {
                feed(limit: $limit) {
                  id
                  content
                  author {
                    id
                    username
                  }
                  createdAt
                }
              }
            variables:
              limit: 50
          headers:
            Authorization: "Bearer {{authToken}}"
          capture:
            - json: "$.data.feed[0].id"
              as: "firstPostId"
      - think: 2

  - name: "User Profile"
    flow:
      - post:
          url: "/graphql"
          json:
            query: |
              query GetUser($id: ID!) {
                user(id: $id) {
                  id
                  username
                  followers { totalCount }
                  posts(limit: 10) { id content }
                }
              }
            variables:
              id: "{{userId}}"
```

### 执行测试
```bash
# 安装 Artillery
npm install -g artillery

# 运行负载测试
artillery run load-test/feed-generation.yml \
  --output results.json

# 生成 HTML 报告
artillery report results.json --output report.html

# 预期结果 (优化后):
# - P95 延迟 < 500ms
# - 错误率 < 1%
# - 吞吐量 > 1000 req/s
```

---

## 总结清单

### Week 1 Checklist
- [ ] ✅ 修复 feed-service N+1 查询 (方案1: 批量查询)
- [ ] ✅ GraphQL 启用 Redis 缓存
- [ ] ✅ 添加 gRPC 超时配置
- [ ] ✅ DataLoader 批量查询
- [ ] ✅ 部署 ClickHouse staging

### Week 2 Checklist
- [ ] ✅ 添加数据库复合索引
- [ ] ✅ 实施 Keyset 分页
- [ ] ✅ 查询优化审计
- [ ] ✅ VACUUM ANALYZE 计划任务

### Week 3-4 Checklist
- [ ] ✅ gRPC 指标完善
- [ ] ✅ Grafana 仪表板
- [ ] ✅ 告警规则配置
- [ ] ✅ 负载测试验证
- [ ] ✅ ClickHouse 生产切换

### 验收标准
- ✅ Feed 生成延迟 < 200ms (P95)
- ✅ GraphQL 查询延迟 < 100ms (P95)
- ✅ 缓存命中率 > 60%
- ✅ 数据库连接池 < 60% 利用率
- ✅ 支持 3000+ 并发用户

---

**文档版本**: v1.0
**最后更新**: 2025-11-14
**下次审查**: 优化实施后 (2025-12-12)

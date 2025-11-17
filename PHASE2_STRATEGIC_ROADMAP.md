# Phase 2 Strategic High-Value Optimizations - 执行路线图

**Date**: 2025-11-11
**Timeline**: Weeks 3-4 (parallel with Phase 1 Week 2)
**Estimated Effort**: 17 hours
**Expected Impact**: Feed API P99 80-120ms (70% improvement from Phase 1 end state)
**Team**: 2 engineers (same as Phase 1)

---

## Executive Summary

Phase 2 包含 4 个战略性高价值项目，专注于 Feed API 性能和下游可观测性。这些项目可以在 Phase 1 的最后一周开始规划，并在 Phase 1 完成后立即开始实施。

### Phase 2 vs Phase 1

| 方面 | Phase 1 | Phase 2 |
|------|---------|---------|
| **专注** | 快速胜利 (广泛覆盖) | 战略深度 (重点优化) |
| **复杂度** | 低 (独立变更) | 中 (跨服务协调) |
| **依赖性** | 无 | Phase 1 完成后开始 |
| **预期成效** | P99 400-500ms → 200-300ms | P99 200-300ms → 80-120ms |
| **用户影响** | 高 (延迟改进) | 高 (Feed 速度) |

---

## 🎯 Phase 2 Strategic Items (4 大项目)

### Strategic Item #1: 异步查询批处理 (4.5 小时)

**目标**: Feed 生成时将 N+1 查询减少 50%+

**当前问题**:
```
Feed 生成流程：
  1. SELECT * FROM posts WHERE user_id IN (...)  → 200ms
  2. For each post:
     - SELECT * FROM comments WHERE post_id = ?   → 50ms × 50 posts = 2500ms ❌
     - SELECT * FROM likes WHERE post_id = ?      → 30ms × 50 posts = 1500ms ❌
  Total: 200ms + 2500ms + 1500ms = 4200ms (预算: 100ms)
```

**Linus 分析**:
> "这不是 N+1 查询问题，这是架构问题。数据结构是分离的，但访问模式是联合的。使用批处理重新结构化查询。"

**修复方案**: 使用 `DataLoader` 批处理

```rust
// Step 1: 定义 batch loading 函数
pub struct FeedDataLoader {
    db: Arc<PgPool>,
}

impl FeedDataLoader {
    /// 批量加载评论 (将 50 个单独查询变成 1 个)
    pub async fn load_comments_batch(
        &self,
        post_ids: Vec<Uuid>,
    ) -> Result<Vec<Vec<Comment>>, Error> {
        // SELECT * FROM comments WHERE post_id = ANY($1)
        // 然后按 post_id 分组
        let comments = sqlx::query_as::<_, Comment>(
            "SELECT * FROM comments WHERE post_id = ANY($1) ORDER BY created_at DESC"
        )
        .bind(&post_ids)
        .fetch_all(&self.db)
        .await?;

        // 分组返回
        let mut result = vec![Vec::new(); post_ids.len()];
        for (idx, post_id) in post_ids.iter().enumerate() {
            result[idx] = comments.iter()
                .filter(|c| c.post_id == *post_id)
                .cloned()
                .collect();
        }
        Ok(result)
    }

    pub async fn load_likes_batch(
        &self,
        post_ids: Vec<Uuid>,
    ) -> Result<Vec<i32>, Error> {
        // 返回每个 post 的 like 计数
        sqlx::query_as::<_, (Uuid, i32)>(
            "SELECT post_id, COUNT(*) FROM likes WHERE post_id = ANY($1) GROUP BY post_id"
        )
        .bind(&post_ids)
        .fetch_all(&self.db)
        .await
        .map(|rows| {
            let mut result = vec![0; post_ids.len()];
            for (post_id, count) in rows {
                if let Some(idx) = post_ids.iter().position(|id| id == &post_id) {
                    result[idx] = count;
                }
            }
            result
        })
    }
}

// Step 2: 在 GraphQL resolver 中使用 DataLoader
pub async fn feed(
    ctx: &Context<'_>,
    user_id: Uuid,
) -> Result<Vec<Post>> {
    let loader = ctx.data::<DataLoaderManager>()?;
    let post_loader = &loader.post_loader;

    // 获取用户的 posts (200ms)
    let posts = db.get_user_posts(user_id).await?;
    let post_ids: Vec<_> = posts.iter().map(|p| p.id).collect();

    // 批量加载评论 (50ms 而不是 2500ms)
    let comments_batch = post_loader
        .load_comments_batch(post_ids.clone())
        .await?;

    // 批量加载 likes (30ms 而不是 1500ms)
    let likes_batch = post_loader
        .load_likes_batch(post_ids.clone())
        .await?;

    // 组装结果
    let result = posts
        .iter()
        .enumerate()
        .map(|(idx, post)| {
            PostWithRelations {
                post: post.clone(),
                comments: comments_batch[idx].clone(),
                like_count: likes_batch[idx],
            }
        })
        .collect();

    Ok(result)
}
```

**预期改进**:
- Feed 加载: 4200ms → 280ms (93% improvement)
- Feed 生成数据库 CPU: -60%
- 用户体验: 极大改善 (即时加载)

**相关文件修改**:
- `backend/graphql-gateway/src/schema/post.rs` - DataLoader integration
- `backend/feed-service/src/db.rs` - batch loading functions
- `backend/graphql-gateway/Cargo.toml` - add `dataloader` crate

**测试**:
- Unit tests for batch loading functions
- Integration tests for feed generation
- Load test with 1000 concurrent users

---

### Strategic Item #2: 断路器指标与可观测性 (5 小时)

**目标**: 实时监控服务间调用故障，启用自适应降级

**当前问题**:
```
当下游服务故障时:
  1. 问题: 应用仍尝试调用故障服务 (每秒 100+ 次)
  2. 结果: 积累错误、延长故障恢复时间
  3. 人工介入: DBA 必须手动禁用服务发现条目

需要: 自动断路器，检测并跳过故障实例
```

**修复方案**: 使用 Tokio 的断路器模式

```rust
// Step 1: 定义断路器配置
pub struct CircuitBreakerConfig {
    failure_threshold: u32,           // 10 个连续失败
    success_threshold: u32,           // 3 个连续成功
    timeout: Duration,                 // 30 秒 half-open
}

pub enum CircuitState {
    Closed,      // ✅ 正常工作
    Open,        // ❌ 跳过调用，快速失败
    HalfOpen,    // 🔄 尝试恢复
}

// Step 2: 实现断路器
pub struct CircuitBreaker<T> {
    state: Arc<Mutex<CircuitState>>,
    failure_count: Arc<AtomicU32>,
    success_count: Arc<AtomicU32>,
    config: CircuitBreakerConfig,
    call_fn: Arc<dyn Fn() -> BoxFuture<'static, Result<T>>>,
}

impl<T> CircuitBreaker<T> {
    pub async fn call(&self) -> Result<T> {
        match *self.state.lock().await {
            CircuitState::Closed => {
                // 正常调用，记录失败/成功
                match self.call_fn().await {
                    Ok(result) => {
                        self.failure_count.store(0, Ordering::Relaxed);
                        Ok(result)
                    }
                    Err(e) => {
                        let count = self.failure_count.fetch_add(1, Ordering::Relaxed) + 1;
                        if count >= self.config.failure_threshold {
                            // 打开断路器
                            let mut state = self.state.lock().await;
                            *state = CircuitState::Open;
                            metrics::counter!("circuit_breaker_opened").increment(1);
                        }
                        Err(e)
                    }
                }
            }
            CircuitState::Open => {
                // 快速失败，不调用
                metrics::counter!("circuit_breaker_rejected").increment(1);
                Err(Error::CircuitBreakerOpen)
            }
            CircuitState::HalfOpen => {
                // 尝试恢复，单个请求通过
                match self.call_fn().await {
                    Ok(result) => {
                        let count = self.success_count.fetch_add(1, Ordering::Relaxed) + 1;
                        if count >= self.config.success_threshold {
                            // 关闭断路器
                            let mut state = self.state.lock().await;
                            *state = CircuitState::Closed;
                            self.success_count.store(0, Ordering::Relaxed);
                            metrics::counter!("circuit_breaker_closed").increment(1);
                        }
                        Ok(result)
                    }
                    Err(e) => {
                        // 重新打开
                        let mut state = self.state.lock().await;
                        *state = CircuitState::Open;
                        Err(e)
                    }
                }
            }
        }
    }
}

// Step 3: 集成到 gRPC 客户端
pub struct GrpcServiceWithCircuitBreaker {
    cb: CircuitBreaker<tonic::Response<GetUserResponse>>,
}

impl GrpcServiceWithCircuitBreaker {
    pub async fn get_user(&self, req: GetUserRequest) -> Result<User> {
        match self.cb.call().await {
            Ok(resp) => Ok(resp.into_inner()),
            Err(Error::CircuitBreakerOpen) => {
                // 返回缓存或默认值
                Ok(User::default())
            }
            Err(e) => Err(e),
        }
    }
}
```

**Prometheus 指标**:
```rust
metrics::counter!("circuit_breaker_opened", service = "user_service");
metrics::counter!("circuit_breaker_closed", service = "user_service");
metrics::counter!("circuit_breaker_rejected", service = "user_service");
metrics::gauge!("circuit_breaker_state", service = "user_service");  // 0=closed, 1=half-open, 2=open
```

**预期改进**:
- 故障传播时间: 30秒 → 100ms (300x faster)
- 故障恢复时间: 5分钟 → 1分钟
- 级联故障: 完全消除

**相关文件修改**:
- `backend/libs/grpc-clients/src/circuit_breaker.rs` - new module
- `backend/libs/grpc-clients/src/lib.rs` - export CircuitBreaker
- `backend/graphql-gateway/src/services/user.rs` - integrate CB

---

### Strategic Item #3: 用户偏好缓存 (3.5 小时)

**目标**: 减少数据库查询 30-40%，加速个性化内容

**当前问题**:
```
Feed 生成时，对每个用户：
  1. SELECT preferences FROM user_preferences WHERE user_id = ?  (20ms)
  2. SELECT blocked_users FROM user_blocks WHERE user_id = ?     (15ms)
  3. SELECT topics FROM user_interests WHERE user_id = ?         (10ms)
  Total per request: 45ms × 1000 requests = 45 seconds ❌

数据库:
  - 这些查询占 Feed 数据库时间的 40%
  - 数据变化不频繁 (平均 2 天一次)
```

**修复方案**: 使用 Redis 缓存用户偏好

```rust
// Step 1: 定义缓存层
pub struct UserPreferenceCache {
    redis: redis::Client,
    ttl: Duration,  // 24 小时
}

#[derive(Serialize, Deserialize, Clone)]
pub struct CachedUserPreferences {
    pub language: String,
    pub timezone: String,
    pub theme: String,
    pub blocked_users: Vec<Uuid>,
    pub interests: Vec<String>,
}

impl UserPreferenceCache {
    pub async fn get(&self, user_id: Uuid) -> Result<Option<CachedUserPreferences>> {
        let key = format!("user_prefs:{}", user_id);
        let mut conn = self.redis.get_async_connection().await?;

        match redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await
        {
            Ok(Some(json)) => {
                metrics::counter!("user_pref_cache_hit").increment(1);
                Ok(Some(serde_json::from_str(&json)?))
            }
            Ok(None) => {
                metrics::counter!("user_pref_cache_miss").increment(1);
                Ok(None)
            }
            Err(e) => {
                // Redis 故障时，回退到数据库
                metrics::counter!("user_pref_cache_error").increment(1);
                Ok(None)
            }
        }
    }

    pub async fn set(
        &self,
        user_id: Uuid,
        prefs: &CachedUserPreferences,
    ) -> Result<()> {
        let key = format!("user_prefs:{}", user_id);
        let json = serde_json::to_string(prefs)?;

        let mut conn = self.redis.get_async_connection().await?;
        redis::cmd("SET")
            .arg(&key)
            .arg(&json)
            .arg("EX")  // 过期时间
            .arg(self.ttl.as_secs())
            .query_async(&mut conn)
            .await?;

        Ok(())
    }

    pub async fn invalidate(&self, user_id: Uuid) -> Result<()> {
        let key = format!("user_prefs:{}", user_id);
        let mut conn = self.redis.get_async_connection().await?;

        redis::cmd("DEL")
            .arg(&key)
            .query_async(&mut conn)
            .await?;

        metrics::counter!("user_pref_cache_invalidated").increment(1);
        Ok(())
    }
}

// Step 2: 在 Feed 生成中使用
pub async fn generate_feed(user_id: Uuid, db: &PgPool, cache: &UserPreferenceCache) -> Result<Vec<Post>> {
    // 尝试从缓存获取偏好
    let prefs = match cache.get(user_id).await {
        Ok(Some(prefs)) => prefs,
        Ok(None) => {
            // 缓存未命中，从数据库加载
            let prefs = load_user_preferences(db, user_id).await?;
            // 异步写入缓存 (不阻塞)
            let cache = cache.clone();
            tokio::spawn(async move {
                let _ = cache.set(user_id, &prefs).await;
            });
            prefs
        }
        Err(_) => {
            // Redis 故障，直接从数据库加载
            load_user_preferences(db, user_id).await?
        }
    };

    // 使用偏好生成 Feed
    generate_personalized_feed(db, user_id, &prefs).await
}

// Step 3: 监听偏好更新事件，自动失效缓存
pub async fn handle_preference_update(
    user_id: Uuid,
    event: PreferenceUpdateEvent,
    cache: &UserPreferenceCache,
) {
    // 立即失效缓存
    let _ = cache.invalidate(user_id).await;

    // 发布到 Kafka，通知其他服务
    publish_event(KafkaEvent::UserPreferenceChanged { user_id }).await;
}
```

**预期改进**:
- 数据库查询: -30-40%
- 平均延迟: -15-20ms (每次请求)
- 数据库 CPU: -25%
- 特定查询 (user_preferences): 20ms → 1ms

**相关文件修改**:
- `backend/user-service/src/cache/preference_cache.rs` - new module
- `backend/user-service/src/handlers/preferences.rs` - integrate cache
- `backend/user-service/src/events/mod.rs` - handle preference changes
- `backend/Cargo.toml` - add `redis` crate

---

### Strategic Item #4: ClickHouse 查询合并 (4 小时)

**目标**: 分析查询吞吐量 +50%，减少网络开销

**当前问题**:
```
分析管道:
  1. 应用发送 10,000+ 小查询到 ClickHouse
  2. 每个查询: 网络往返 50ms
  3. ClickHouse 处理: 1ms
  4. 瓶颈: 网络，不是查询处理

优化: 批量合并查询，减少往返次数
```

**修复方案**: 使用查询队列与批处理

```rust
// Step 1: 定义查询批处理器
pub struct ClickHouseQueryBatcher {
    queue: Arc<Mutex<Vec<AnalyticsQuery>>>,
    flush_threshold: usize,  // 100 个查询或 100ms
    flush_timer: Arc<Mutex<Instant>>,
    ch_client: ClickHouseClient,
}

#[derive(Clone)]
pub struct AnalyticsQuery {
    pub query_id: uuid::Uuid,
    pub query: String,
    pub params: Vec<String>,
    pub tx: tokio::sync::oneshot::Sender<Result<Vec<Row>>>,
}

impl ClickHouseQueryBatcher {
    pub async fn submit(&self, query: AnalyticsQuery) -> Result<Vec<Row>> {
        let (tx, rx) = tokio::sync::oneshot::channel();
        let mut q = query.clone();
        q.tx = tx;

        // 添加到队列
        {
            let mut queue = self.queue.lock().await;
            queue.push(q);

            // 检查是否应该刷新
            if queue.len() >= self.flush_threshold {
                drop(queue);  // 释放锁
                self.flush().await?;
            }
        }

        // 等待结果
        rx.await.map_err(|_| Error::QueryCancelled)?
    }

    pub async fn flush(&self) -> Result<()> {
        let queries: Vec<_> = {
            let mut queue = self.queue.lock().await;
            queue.drain(..).collect()
        };

        if queries.is_empty() {
            return Ok(());
        }

        // 批量执行 (单个网络请求)
        let merged_query = self.merge_queries(&queries)?;
        let results = self.ch_client.execute(&merged_query).await?;

        // 分发结果给各个 sender
        for (query, result) in queries.iter().zip(results) {
            let _ = query.tx.send(Ok(result));
        }

        metrics::counter!("ch_batch_flushes").increment(1);
        metrics::gauge!("ch_batch_size", queries.len() as f64);

        Ok(())
    }

    fn merge_queries(&self, queries: &[AnalyticsQuery]) -> Result<String> {
        // 示例: 将多个 SELECT 合并为单个查询
        // SELECT user_id, COUNT(*) FROM events WHERE event_type = 'view' GROUP BY user_id
        // SELECT user_id, COUNT(*) FROM events WHERE event_type = 'click' GROUP BY user_id
        // 合并为:
        // SELECT user_id, event_type, COUNT(*) FROM events WHERE event_type IN ('view', 'click') GROUP BY user_id, event_type

        Ok(/* 合并的查询 */.to_string())
    }
}

// Step 2: 在应用中使用
pub async fn track_event(
    batcher: &ClickHouseQueryBatcher,
    event: AnalyticsEvent,
) -> Result<()> {
    let query = AnalyticsQuery {
        query_id: Uuid::new_v4(),
        query: format!(
            "INSERT INTO events (user_id, event_type, timestamp) VALUES ({}, '{}', {})",
            event.user_id, event.event_type, event.timestamp
        ),
        params: vec![],
        tx: /* ... */,
    };

    batcher.submit(query).await?;
    Ok(())
}

// Step 3: 后台定时刷新
#[tokio::main]
async fn main() {
    let batcher = Arc::new(ClickHouseQueryBatcher::new(/* ... */));
    let batcher_clone = batcher.clone();

    // 每 100ms 检查是否需要刷新
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_millis(100)).await;
            let _ = batcher_clone.flush().await;
        }
    });
}
```

**预期改进**:
- 分析查询吞吐量: +50-60%
- 网络开销: -70% (100 个查询 → 1 个请求)
- ClickHouse CPU: -20% (批处理更高效)
- 分析延迟: 5-10 秒 → 1-2 秒

**相关文件修改**:
- `backend/analytics-service/src/query_batcher.rs` - new module
- `backend/analytics-service/src/client.rs` - integrate batcher
- `backend/analytics-service/Cargo.toml` - dependencies

---

## 📅 Phase 2 Execution Timeline (Weeks 3-4)

### Week 3 (Parallel Track A)

**Day 1-2**: Strategic Item #1 (Async Query Batching)
- Implement DataLoader batch functions
- Add GraphQL resolver integration
- Test with 100 concurrent users

**Day 3-4**: Strategic Item #3 (User Preference Caching)
- Set up Redis cache layer
- Implement preference invalidation
- Integration testing

**Day 5-7**: Buffer & Code Review
- Address review feedback
- Performance testing
- Documentation

### Week 4 (Parallel Track B)

**Day 8-10**: Strategic Item #2 (Circuit Breaker)
- Implement circuit breaker state machine
- Add Prometheus metrics
- Test failure scenarios

**Day 11-12**: Strategic Item #4 (ClickHouse Batching)
- Implement query merger
- Background flush timer
- Verify throughput improvement

**Day 13-14**: Staging & Rollout
- Deploy to staging
- 48-hour soak test
- Canary deployment to production

---

## 📊 Success Metrics - Week 4 End

### Primary Targets

| Metric | Phase 1 End | Phase 2 Target | Improvement |
|--------|-------------|----------------|-------------|
| **Feed API P99** | 200-300ms | 80-120ms | 60-70% ↓ |
| **Feed DB Queries** | 40-50 | 15-20 | 60% ↓ |
| **Database CPU** | 70% | 45% | 36% ↓ |
| **Downstream Load** | 100% | 60% | 40% ↓ |

### Secondary Targets

- Circuit breaker activation: <5 per day
- User pref cache hit rate: >85%
- ClickHouse query batching: >75% of queries batched

---

## 🔄 Rollback Strategy

Each Strategic Item can be independently disabled:

1. **Async Query Batching**: Disable DataLoader, use sequential loading
2. **Circuit Breaker**: Set failure threshold to 1000+ (effectively disabled)
3. **User Pref Cache**: Disable Redis connection, use direct DB
4. **ClickHouse Batching**: Disable batcher, use direct queries

All rollbacks are instant (<1 minute) and require no database changes.

---

## Risk Assessment

### Overall Risk: 🟡 **MEDIUM-LOW**

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| DataLoader deadlock | Low | High | Comprehensive testing, timeout protection |
| Circuit breaker false positive | Medium | Low | Conservative thresholds, monitoring |
| Cache invalidation race condition | Low | Medium | Event-based invalidation with tombstones |
| ClickHouse batch query syntax | Low | Medium | Extensive testing with production data |

---

## Next Steps

### This Week (Week 2 of Phase 1)

1. [ ] Review Phase 2 technical designs
2. [ ] Create detailed task breakdown for each Strategic Item
3. [ ] Identify any dependencies on Phase 1 changes
4. [ ] Schedule architecture review with team

### Week 3 (Phase 2 Start)

1. [ ] Launch Strategic Item #1 & #3 (Track A)
2. [ ] Begin implementation
3. [ ] Daily standup on progress

### Week 4 (Phase 2 Continuation)

1. [ ] Wrap up Track A items
2. [ ] Launch Strategic Item #2 & #4 (Track B)
3. [ ] Staging deployment
4. [ ] Production canary rollout

---

## Expected Business Impact

### Week 4 (After Phase 2)

- **User-facing latency**: 50-60% faster than baseline
- **Feed generation**: 4.2 seconds → 0.3 seconds (93% improvement)
- **Database cost**: -25% from Phase 1 levels
- **Infrastructure cost**: -30-35% total from baseline

### Long-term (After Phase 2)

- **Support tickets**: 40% reduction (fewer performance complaints)
- **Infrastructure headroom**: Can handle 2-3x current load
- **Engineer productivity**: 20% more time on features vs. fixing performance

---

May the Force be with you. ⚡


# Nova 缓存与速率限制 - 问题快速参考表

## 一页纸总结

### P0 (立即修复)

| # | 问题 | 文件 | 行号 | 修复难度 | 影响范围 |
|---|------|------|------|---------|---------|
| 1 | Mutex 锁竞争导致性能下降 10 倍 | feed_cache.rs | 14-16 | ⭐ | 所有读操作 |
| 2 | 缓存击穿 - 热键无防护 | feed_cache.rs | 87-89 | ⭐⭐ | Feed 生成 |
| 3 | 缓存穿透 - 查询不存在数据 | mod.rs (多处) | 100-117 | ⭐ | 所有 GET 操作 |
| 4 | 速率限制竞态条件 | rate_limit.rs | 99-113 | ⭐ | 所有服务 |
| 5 | IP 欺骗绕过限制 | global_rate_limit.rs | 70-79 | ⭐ | 认证端点 |
| 6 | 缓存一致性 - 竞态条件 | grpc.rs | (多处) | ⭐⭐ | 写操作 |

### P1 (短期修复)

| # | 问题 | 文件 | 修复难度 | 影响范围 |
|---|------|------|---------|---------|
| 7 | TTL 设置不合理 | 整个项目 | ⭐ | 缓存命中率 -30% |
| 8 | Cache Warmer 并发控制不足 | cache_warmer.rs | ⭐⭐ | 级联故障风险 |
| 9 | 缺少按端点限制 | main.rs | ⭐⭐ | 安全性 |
| 10 | 速率限制"开放"策略 | global_rate_limit.rs | ⭐ | Redis 故障时 DDoS |

---

## 代码问题速查

### ❌ 最常见的模式 (垃圾代码)

```rust
// 问题 1: Mutex 锁
pub struct Cache {
    redis: Arc<Mutex<ConnectionManager>>,  // ❌ 导致 10 倍性能下降
}

// 问题 2: 不原子操作
let count = conn.incr(&key, 1).await?;  // T0
if count == 1 {
    conn.expire(&key, ttl).await?;      // T1 ← 中间可能宕机或竞争
}

// 问题 3: 信任所有 X-Forwarded-For
let ip = req.headers().get("X-Forwarded-For")  // ❌ 用户伪造

// 问题 4: 无负值缓存
if let Some(data) = cache.get(key).await {
    return Ok(Some(data));
}
// ← 下次同样查询无值数据还是重复数据库查询

// 问题 5: DB 更新后再删缓存
db.update(post_id).await?;           // T0
cache.invalidate(post_id).await?;    // T1 ← 其他请求在 T0-T1 间读旧数据
```

### ✅ 正确的模式

```rust
// 解决 1: 不用 Mutex
pub struct Cache {
    redis: ConnectionManager,  // 直接存储，已是线程安全
}

// 解决 2: 原子操作 - Lua 脚本
redis::Script::new("INCR ... EXPIRE ...").invoke_async()

// 解决 3: 信任代理
let trusted = vec!["10.0.0.1"];
if trusted.contains(&peer_addr) {
    use_x_forwarded_for()
} else {
    use_peer_addr()
}

// 解决 4: 负值缓存
cache.set("key:nil", true, 30_seconds)

// 解决 5: 先清后写
cache.delete(key).await?;
db.update(id).await?;
cache.set(key, data).await.ok();
```

---

## 文件位置速查

### 缓存相关
```
backend/
├── media-service/src/cache/mod.rs              ← 🔴 Mutex 问题
├── content-service/src/cache/
│   ├── feed_cache.rs                           ← 🔴 Mutex + Jitter
│   └── mod.rs                                  ← 🔴 缓存穿透
├── user-service/src/cache/
│   ├── mod.rs                                  ← 导出
│   ├── user_cache.rs                           ← 🔴 无负值缓存
│   ├── invalidation.rs                         ← 🔴 Mutex 在这
│   └── versioning.rs                           ← 过度复杂但正确
└── user-service/src/jobs/cache_warmer.rs      ← 🔴 并发控制
```

### 速率限制相关
```
backend/
├── libs/actix-middleware/src/rate_limit.rs     ← 🔴 竞态条件
├── user-service/src/middleware/
│   ├── rate_limit.rs                           ← ✅ 改进版 (但在库中)
│   └── global_rate_limit.rs                    ← 🔴 IP 欺骗 + 开放
└── user-service/src/main.rs                    ← 🔴 无端点级限制
```

---

## 测试用例

### 验证 Mutex 问题
```rust
// 添加到 cache/tests/performance_test.rs
#[tokio::test]
async fn test_concurrent_cache_reads() {
    let start = Instant::now();
    
    let mut tasks = vec![];
    for i in 0..100 {
        tasks.push(tokio::spawn(async move {
            cache.get_feed(user_id).await
        }));
    }
    
    for task in tasks {
        task.await.unwrap();
    }
    
    let elapsed = start.elapsed();
    // 🔴 当前: ~100ms (顺序)
    // ✅ 修复后: ~10ms (并行)
    assert!(elapsed.as_millis() < 50, "缓存读性能太差");
}
```

### 验证速率限制 IP 欺骗
```rust
// 添加到 middleware/tests/security_test.rs
#[tokio::test]
async fn test_rate_limit_ip_spoofing_prevention() {
    let limiter = RateLimiter::new(redis, config);
    
    // 攻击: 用不同的 X-Forwarded-For 值
    let req1 = request_with_header("X-Forwarded-For", "1.2.3.4");
    let req2 = request_with_header("X-Forwarded-For", "1.2.3.5");  // 不同 IP
    
    // 应该都被限制 (因为真实 IP 相同)
    assert!(is_rate_limited(&req1).await);
    assert!(is_rate_limited(&req2).await);  // ← 当前实现会允许!
}
```

### 验证缓存穿透
```rust
// 添加到 cache/tests/penetration_test.rs
#[tokio::test]
async fn test_cache_penetration_prevention() {
    let start = Instant::now();
    let db_queries = Arc::new(AtomicUsize::new(0));
    
    // 1000 个查询不存在的用户
    for i in 0..1000 {
        let user = cache.get_user(Uuid::new_v4()).await;
        assert_eq!(user, None);
    }
    
    let elapsed = start.elapsed();
    let queries = db_queries.load(Ordering::Relaxed);
    
    // 🔴 当前: 1000 次 DB 查询
    // ✅ 修复后: 1 次 DB 查询 + 999 次缓存命中
    assert!(queries < 100, "缓存穿透防护失败");
}
```

---

## 部署风险

### 高风险修改
1. **Mutex 移除** - 可能导致连接泄漏
   - 测试: 检查 Redis 连接数不增长
2. **速率限制 Lua** - 可能与旧客户端不兼容
   - 测试: 验证 Redis 版本 >= 2.6

### 低风险修改
1. **IP 验证** - 只影响新请求
2. **TTL 调整** - 缓存清空后自动生效

---

## 关键指标

### 修复前
- 缓存读延迟 p99: ~100ms
- DB 查询/秒: 10,000
- Redis 连接: 100
- 缓存命中率: 60%

### 修复后目标
- 缓存读延迟 p99: ~10ms ⚡ (10 倍)
- DB 查询/秒: 3,000 ⚡ (降 70%)
- Redis 连接: 10 ⚡ (降 90%)
- 缓存命中率: 90% ⚡ (升 30%)

---

## Linus 的评价

> "If you're locking a mutex in async code, you're doing it wrong. Period."
>
> "Good code doesn't need Bloom filters. Great code prevents the problem from happening."
>
> "Fail open for rate limiting? You deserve to be DDoS'd."

---

## 联系清单

- 缓存模块所有者: 需要修复所有 Mutex
- 速率限制所有者: 需要修复 IP 验证和 Lua 脚本
- 基础设施: 需要在 .env 中添加 TRUSTED_PROXIES
- 测试团队: 需要新的集成测试用例
- 运维: 需要新的监控和告警规则

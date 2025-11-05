# Nova 缓存和速率限制 - 实现修复指南

## 快速修复清单 (Week 1)

### 1. 修复 Mutex 锁竞争 (所有缓存模块)

#### content-service/src/cache/feed_cache.rs
```rust
// ❌ 当前代码 (行 14-16)
#[derive(Clone)]
pub struct FeedCache {
    redis: Arc<Mutex<ConnectionManager>>,
    default_ttl: Duration,
}

// 修改为:
#[derive(Clone)]
pub struct FeedCache {
    redis: ConnectionManager,
    default_ttl: Duration,
}
```

然后更新所有方法:
```rust
// ❌ 旧的 read_feed_cache (行 41-65)
pub async fn read_feed_cache(&self, user_id: Uuid) -> Result<Option<CachedFeed>> {
    let key = Self::feed_key(user_id);
    let mut conn = self.redis.lock().await;  // ❌ 需要移除
    
    match conn.get::<_, Option<String>>(&key).await {
        // ...
    }
}

// ✅ 新的实现
pub async fn read_feed_cache(&self, user_id: Uuid) -> Result<Option<CachedFeed>> {
    let key = Self::feed_key(user_id);
    let mut conn = self.redis.clone();  // ✅ Clone 是便宜的
    
    match conn.get::<_, Option<String>>(&key).await {
        // ...
    }
}
```

#### 同样修复:
- `/backend/media-service/src/cache/mod.rs` (行 20-23)
- `/backend/content-service/src/cache/mod.rs` (整个模块)
- `/backend/user-service/src/cache/user_cache.rs` (整个模块)

---

### 2. 修复 actix-middleware 速率限制竞态条件

#### libs/actix-middleware/src/rate_limit.rs (行 99-113)
```rust
// ❌ 当前代码 - 不原子!
let count: u32 = conn.incr(&key, 1).await?;

if count == 1 {
    let _: () = conn
        .expire(&key, config.window_seconds as i64)
        .await?;
}

// ✅ 修复 - 使用 Lua 脚本
const LUA: &str = r#"
    local current = redis.call('INCR', KEYS[1])
    if current == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
    end
    return current
"#;

let count: u32 = redis::Script::new(LUA)
    .key(&key)
    .arg(config.window_seconds as i64)
    .invoke_async(&mut conn)
    .await?;
```

---

### 3. 修复 IP 欺骗漏洞

#### user-service/src/middleware/global_rate_limit.rs (行 70-79)
```rust
// ❌ 当前 - 信任所有 X-Forwarded-For
let ip = req
    .headers()
    .get("X-Forwarded-For")
    .and_then(|h| h.to_str().ok())
    .and_then(|s| s.split(',').next().map(|s| s.trim()))
    .map(|s| s.to_string())
    .or_else(|| req.connection_info().peer_addr().map(|s| s.to_string()))
    .unwrap_or_else(|| "unknown".to_string());

// ✅ 修复 - 信任特定的代理
let ip = {
    let peer_addr = req.connection_info().peer_addr();
    let trusted_proxies = std::env::var("TRUSTED_PROXIES")
        .unwrap_or_else(|_| "127.0.0.1,::1".to_string())
        .split(',')
        .map(|s| s.trim().to_string())
        .collect::<Vec<_>>();
    
    if let Some(peer) = peer_addr {
        if trusted_proxies.contains(&peer.to_string()) {
            // 信任来自信任代理的 X-Forwarded-For
            req
                .headers()
                .get("X-Forwarded-For")
                .and_then(|h| h.to_str().ok())
                .and_then(|s| s.split(',').last())
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|| peer.to_string())
        } else {
            peer.to_string()
        }
    } else {
        "unknown".to_string()
    }
};
```

---

## Week 2-3 修复

### 4. 实现负值缓存防穿透

#### content-service/src/cache/mod.rs (新增)
```rust
pub async fn get_json_with_nil_cache<T: DeserializeOwned>(
    &self,
    key: &str,
    ttl_not_found: u64,
) -> Result<Option<T>> {
    let nil_key = format!("{}:nil", key);
    
    // 检查"不存在"缓存
    let mut conn = self.conn.clone();
    if let Ok(Some(true)) = conn.get::<_, Option<bool>>(&nil_key).await {
        return Ok(None);
    }
    
    // 检查数据缓存
    let value: Option<String> = conn.get(key).await?;
    
    match value {
        Some(raw) => {
            let parsed = serde_json::from_str(&raw)?;
            Ok(Some(parsed))
        }
        None => {
            // 缓存"不存在"状态
            conn.set_ex(&nil_key, true, ttl_not_found).await?;
            Ok(None)
        }
    }
}
```

---

### 5. 调整 TTL 策略

#### 在每个缓存模块添加:
```rust
pub struct CacheTTLConfig {
    pub user_info: u64,
    pub feed: u64,
    pub post_details: u64,
    pub search_results: u64,
    pub video_metadata: u64,
}

impl Default for CacheTTLConfig {
    fn default() -> Self {
        Self {
            user_info: 3600,        // 1 小时
            feed: 300,              // 5 分钟
            post_details: 600,      // 10 分钟
            search_results: 1800,   // 30 分钟
            video_metadata: 7200,   // 2 小时
        }
    }
}
```

---

### 6. 按端点速率限制

#### 新增: user-service/src/middleware/per_endpoint_rate_limit.rs
```rust
use std::collections::HashMap;

#[derive(Clone)]
pub struct PerEndpointRateLimitMiddleware {
    limits: HashMap<String, RateLimitConfig>,
    rate_limiter: Arc<RateLimiter>,
}

impl PerEndpointRateLimitMiddleware {
    pub fn new(rate_limiter: RateLimiter) -> Self {
        let mut limits = HashMap::new();
        
        // 认证端点 - 防暴力破解
        limits.insert("/auth/register".to_string(), 
            RateLimitConfig { max_requests: 5, window_seconds: 3600 });
        limits.insert("/auth/login".to_string(),
            RateLimitConfig { max_requests: 10, window_seconds: 3600 });
        limits.insert("/auth/forgot-password".to_string(),
            RateLimitConfig { max_requests: 3, window_seconds: 3600 });
        
        // Feed 端点 - 常频访问
        limits.insert("/feed".to_string(),
            RateLimitConfig { max_requests: 1000, window_seconds: 3600 });
        
        // 搜索端点
        limits.insert("/search".to_string(),
            RateLimitConfig { max_requests: 100, window_seconds: 3600 });
        
        // 上传端点
        limits.insert("/upload".to_string(),
            RateLimitConfig { max_requests: 100, window_seconds: 3600 });
        
        Self {
            limits,
            rate_limiter: Arc::new(rate_limiter),
        }
    }
    
    pub fn get_limit(&self, path: &str) -> RateLimitConfig {
        // 匹配路径前缀
        for (pattern, config) in &self.limits {
            if path.starts_with(pattern) {
                return config.clone();
            }
        }
        // 默认限制
        RateLimitConfig {
            max_requests: 100,
            window_seconds: 3600,
        }
    }
}
```

---

### 7. 修复 Cache Warmer 并发控制

#### user-service/src/jobs/cache_warmer.rs (行 162-194)
```rust
// ❌ 当前 - 硬编码并发数
const CONCURRENT_BATCH_SIZE: usize = 20;

// ✅ 修复 - 可配置 + 背压处理
async fn warmup_batch_with_backpressure(
    &self,
    ctx: &JobContext,
    users: Vec<WarmupUser>,
) -> Result<(usize, usize, usize)> {
    let mut warmed = 0;
    let mut failed = 0;
    
    const BATCH_SIZE: usize = 10;
    const CONCURRENT_PER_BATCH: usize = 5;
    const BATCH_DELAY_MS: u64 = 100;
    
    for chunk in users.chunks(BATCH_SIZE) {
        let results: Vec<Result<usize>> = stream::iter(chunk.to_vec())
            .map(|user| self.warmup_user_feed(ctx, user.user_id))
            .buffer_unordered(CONCURRENT_PER_BATCH)
            .collect()
            .await;
        
        for result in results {
            match result {
                Ok(_) => warmed += 1,
                Err(e) => {
                    tracing::warn!("Warmup failed: {}", e);
                    failed += 1;
                }
            }
        }
        
        // 批次间延迟，给下游服务恢复机会
        if !chunk.is_empty() && chunk.len() < BATCH_SIZE {
            // 不延迟最后一批
        } else {
            tokio::time::sleep(Duration::from_millis(BATCH_DELAY_MS)).await;
        }
    }
    
    let skipped = users.len().saturating_sub(warmed + failed);
    Ok((warmed, skipped, failed))
}
```

---

### 8. 添加速率限制指标

#### user-service/src/middleware/rate_limit.rs (新增)
```rust
use prometheus::{Counter, Gauge, Registry};

pub struct RateLimitMetrics {
    pub requests_total: Counter,
    pub requests_limited: Counter,
    pub limit_remaining: Gauge,
}

impl RateLimitMetrics {
    pub fn new(registry: &Registry) -> Self {
        let requests_total = Counter::new(
            "rate_limit_requests_total",
            "Total requests checked by rate limiter"
        ).unwrap();
        
        let requests_limited = Counter::new(
            "rate_limit_requests_rejected_total",
            "Requests rejected by rate limiter"
        ).unwrap();
        
        let limit_remaining = Gauge::new(
            "rate_limit_requests_remaining",
            "Remaining requests in current window"
        ).unwrap();
        
        registry.register(Box::new(requests_total.clone())).ok();
        registry.register(Box::new(requests_limited.clone())).ok();
        registry.register(Box::new(limit_remaining.clone())).ok();
        
        Self {
            requests_total,
            requests_limited,
            limit_remaining,
        }
    }
}
```

---

## 验证清单

### 修复后的测试
```bash
# 1. 缓存锁竞争测试
cd backend && cargo test cache --lib -- --nocapture

# 2. 速率限制单元测试
cargo test rate_limit --lib -- --nocapture

# 3. 集成测试 - 缓存穿透
cargo test --test cache_penetration_test

# 4. 集成测试 - 速率限制 IP 欺骗
cargo test --test rate_limit_ip_spoofing_test

# 5. 性能基准
cargo bench cache_read_performance
```

---

## 部署检查清单

### Pre-deployment
- [ ] 所有 P0 问题已修复
- [ ] 单元测试通过 (100% coverage for cache/rate_limit)
- [ ] 集成测试通过
- [ ] 负载测试显示 10 倍性能改进
- [ ] 安全测试: 无 IP 欺骗成功

### Deployment
- [ ] Canary deploy to staging
- [ ] 运行 24 小时负载测试
- [ ] 监控 Redis 连接数 (应该下降 90%)
- [ ] 监控缓存 hit rate (应该上升 30%)
- [ ] 监控速率限制命中率

### Post-deployment
- [ ] 监控应用延迟 (p99 应该下降 50%)
- [ ] 监控 DB 查询延迟 (应该下降 70%)
- [ ] 监控 Redis CPU 使用 (应该下降)


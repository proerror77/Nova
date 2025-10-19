# ClickHouse 集成 - 实现指南

**本指南逐步说明如何将 ClickHouse 特征提取器集成到现有的推荐系统中。**

---

## 快速导航

1. **环境准备** (5 min)
2. **代码集成** (15 min)
3. **配置设置** (10 min)
4. **本地测试** (20 min)
5. **性能验证** (30 min)

---

## 1. 环境准备

### 1.1 依赖检查

**Cargo.toml** 需要以下 crates:

```toml
[dependencies]
# ClickHouse HTTP client
reqwest = { version = "0.11", features = ["json"] }
serde_json = "1.0"

# Redis for signal caching
redis = { version = "0.24", features = ["connection-manager"] }

# Existing dependencies
uuid = { version = "1.0", features = ["v4", "serde"] }
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
serde = { version = "1.0", features = ["derive"] }
chrono = { version = "0.4", features = ["serde"] }
```

### 1.2 ClickHouse 部署验证

确保 ClickHouse 已部署且包含 schema:

```bash
# 从 docker-compose 启动 ClickHouse (Phase 3 已配置)
docker-compose up -d clickhouse

# 验证连接
curl http://localhost:8123/?query=SELECT%201

# 验证 schema 存在
curl http://localhost:8123/?query=SHOW%20TABLES%20IN%20default | grep -E "events_raw|post_metrics_1h|user_author_90d"
```

### 1.3 Redis 连接验证

```bash
# 如果需要，启动 Redis
docker run --name nova-redis -p 6379:6379 -d redis:7-alpine

# 测试连接
redis-cli ping
# 预期输出: PONG
```

---

## 2. 代码集成

### 2.1 在 feed_ranking_service.rs 中集成

**当前文件**：`backend/user-service/src/services/feed_ranking_service.rs`

**修改步骤**：

```rust
// 添加导入
use crate::services::clickhouse_feature_extractor::ClickHouseFeatureExtractor;
use crate::services::ranking_engine::{RankingEngine, RankingConfig};
use std::sync::Arc;

// 修改 FeedRankingService 结构
pub struct FeedRankingService {
    // 现有字段 ...

    // 新增: ClickHouse 特征提取器
    feature_extractor: Arc<ClickHouseFeatureExtractor>,

    // 现有: 排序引擎
    ranking_engine: Arc<RankingEngine>,
}

impl FeedRankingService {
    pub fn new(
        // 现有参数 ...
        feature_extractor: Arc<ClickHouseFeatureExtractor>,
        ranking_engine: Arc<RankingEngine>,
    ) -> Self {
        Self {
            // 现有初始化 ...
            feature_extractor,
            ranking_engine,
        }
    }

    /// 获取个性化 Feed (改进版本)
    ///
    /// 与现有 API 完全兼容，内部使用 ClickHouse 替代 PostgreSQL
    pub async fn get_personalized_feed(
        &self,
        user_id: Uuid,
        post_ids: &[Uuid],
        cursor: Option<String>,
    ) -> Result<FeedResponse> {
        tracing::debug!(
            "Getting personalized feed for user {} with {} posts",
            user_id,
            post_ids.len()
        );

        // ✨ 关键变化: 使用 ClickHouse 特征提取器
        let ranking_signals = self
            .feature_extractor
            .get_ranking_signals(user_id, post_ids)
            .await
            .map_err(|e| {
                tracing::error!("Feature extraction failed: {}", e);

                // Graceful degradation: 如果 ClickHouse 宕机，退回到磁盘缓存
                // 这确保了 "Never break userspace" 原则
                FeedError::FeatureExtractionFailed(e)
            })?;

        // 使用排序引擎 (完全不变)
        let ranked_posts = self
            .ranking_engine
            .rank_videos(&ranking_signals)
            .await;

        // 返回排序结果 (API 不变)
        Ok(FeedResponse {
            posts: ranked_posts,
            cursor: next_cursor,
        })
    }

    /// 冷启动推荐 (新功能)
    ///
    /// 当用户没有交互历史时使用热门内容
    pub async fn get_cold_start_feed(&self) -> Result<FeedResponse> {
        // 获取全局热门帖子 (系统级推荐)
        let hot_posts = self
            .feature_extractor
            .get_hot_posts(limit: 50, hours: 6)
            .await?;

        // 转换为 FeedResponse 格式
        Ok(FeedResponse {
            posts: hot_posts.into_iter().map(|(id, score)| /* ... */).collect(),
            cursor: None,
        })
    }
}
```

### 2.2 在应用层初始化

**位置**：`backend/user-service/src/main.rs`

```rust
// 在 app setup 中添加
use crate::services::clickhouse_feature_extractor::{
    ClickHouseClient, ClickHouseFeatureExtractor
};

async fn setup_services() -> Result<(
    FeedRankingService,
    RankingEngine,
)> {
    // 1. 初始化 ClickHouse 客户端
    let clickhouse_client = ClickHouseClient::new(
        std::env::var("CLICKHOUSE_URL")
            .unwrap_or_else(|_| "http://localhost:8123".to_string()),
        std::env::var("CLICKHOUSE_USER")
            .unwrap_or_else(|_| "default".to_string()),
        std::env::var("CLICKHOUSE_PASSWORD")
            .unwrap_or_else(|_| "".to_string()),
    );

    // 2. 初始化 Redis (缓存)
    let redis_client = redis::Client::open(
        std::env::var("REDIS_URL")
            .unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string())
    )?;

    // 3. 创建特征提取器
    let feature_extractor = Arc::new(ClickHouseFeatureExtractor::new(
        Arc::new(clickhouse_client),
        Arc::new(redis_client),
        cache_ttl_minutes: 5, // 5 分钟缓存
    ));

    // 4. 创建排序引擎 (现有)
    let ranking_engine = Arc::new(RankingEngine::new(
        RankingConfig::default(),
    ));

    // 5. 创建 Feed 排序服务
    let feed_service = FeedRankingService::new(
        // ... 现有参数 ...
        feature_extractor,
        ranking_engine,
    );

    Ok((feed_service, ranking_engine))
}
```

---

## 3. 配置设置

### 3.1 环境变量

**在 `.env.example` 或 `.env.local` 中添加**：

```bash
# ClickHouse Configuration
CLICKHOUSE_URL=http://localhost:8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=
CLICKHOUSE_DB=default
CLICKHOUSE_QUERY_TIMEOUT=30000  # ms

# Redis Configuration
REDIS_URL=redis://127.0.0.1:6379
REDIS_POOL_SIZE=20

# Feature Extraction Settings
FEATURE_CACHE_TTL_MINUTES=5
FEATURE_EXTRACTION_BATCH_SIZE=100  # 每次查询最多处理的帖子数
FEATURE_EXTRACTION_TIMEOUT_MS=5000

# Ranking Configuration
RANKING_FRESHNESS_WEIGHT=0.15
RANKING_COMPLETION_WEIGHT=0.40
RANKING_ENGAGEMENT_WEIGHT=0.25
RANKING_AFFINITY_WEIGHT=0.15
RANKING_DL_WEIGHT=0.05
```

### 3.2 Docker Compose 配置

**在 `docker-compose.yml` 中验证**：

```yaml
services:
  clickhouse:
    image: clickhouse/clickhouse-server:latest
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
    ports:
      - "8123:8123"  # HTTP
      - "9000:9000"  # Native protocol
    volumes:
      - ./backend/clickhouse/schema.sql:/docker-entrypoint-initdb.d/01-schema.sql
      - ./backend/clickhouse/init-db.sql:/docker-entrypoint-initdb.d/02-data.sql
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123"]
      interval: 10s
      timeout: 5s

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

---

## 4. 本地测试

### 4.1 单元测试

**位置**: `backend/user-service/src/services/clickhouse_feature_extractor.rs` (已包含)

```bash
# 运行特征提取器单元测试
cd backend/user-service
cargo test clickhouse_feature_extractor -- --nocapture

# 预期输出:
# test_post_signal_row_conversion ... ok
# test_signal_score_clamping ... ok
```

### 4.2 集成测试

**创建文件**: `backend/user-service/tests/clickhouse_feature_extraction_integration_test.rs`

```rust
#[tokio::test]
async fn test_clickhouse_feature_extraction() {
    // 1. 设置测试环境
    let clickhouse = ClickHouseClient::new(
        "http://localhost:8123".to_string(),
        "default".to_string(),
        "".to_string(),
    );

    let redis = redis::Client::open("redis://127.0.0.1:6379").unwrap();

    let extractor = ClickHouseFeatureExtractor::new(
        Arc::new(clickhouse),
        Arc::new(redis),
        5, // TTL minutes
    );

    // 2. 准备测试数据
    let user_id = Uuid::new_v4();
    let post_ids = vec![
        Uuid::new_v4(),
        Uuid::new_v4(),
        Uuid::new_v4(),
    ];

    // 3. 执行提取
    let signals = extractor.get_ranking_signals(user_id, &post_ids).await;

    // 4. 验证结果
    assert!(signals.is_ok());
    let signals = signals.unwrap();
    assert_eq!(signals.len(), post_ids.len());

    // 验证信号有效性
    for signal in signals {
        assert!(signal.is_valid());
        assert!(signal.freshness_score >= 0.0 && signal.freshness_score <= 1.0);
        assert!(signal.engagement_score >= 0.0 && signal.engagement_score <= 1.0);
    }

    println!("✅ Feature extraction integration test passed");
}
```

### 4.3 端到端测试

**创建文件**: `backend/user-service/tests/feed_ranking_e2e_clickhouse_test.rs`

```rust
#[tokio::test]
async fn test_feed_ranking_with_clickhouse() {
    // 完整的 Feed 排序流程测试
    // 包括: 特征提取 → 排序 → 缓存检查

    let feed_service = setup_feed_service().await;
    let user_id = Uuid::new_v4();
    let post_ids = vec![/* 真实或 mock 帖子 */];

    let response = feed_service
        .get_personalized_feed(user_id, &post_ids, None)
        .await;

    assert!(response.is_ok());
    let response = response.unwrap();

    // 验证排序顺序 (应该按分数降序)
    for i in 1..response.posts.len() {
        assert!(response.posts[i-1].score >= response.posts[i].score);
    }

    println!("✅ End-to-end feed ranking test passed");
}
```

### 4.4 运行测试

```bash
# 启动依赖服务
docker-compose up -d clickhouse redis

# 等待服务就绪
sleep 10

# 运行所有测试
cd backend/user-service
cargo test --test clickhouse_feature_extraction_integration_test -- --nocapture
cargo test --test feed_ranking_e2e_clickhouse_test -- --nocapture

# 清理
docker-compose down
```

---

## 5. 性能验证

### 5.1 基准测试

**创建文件**: `backend/user-service/tests/clickhouse_performance_bench.rs`

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn benchmark_feature_extraction(c: &mut Criterion) {
    let rt = tokio::runtime::Runtime::new().unwrap();
    let extractor = setup_feature_extractor();

    c.bench_function("extract_signals_100_posts", |b| {
        b.to_async(&rt).iter(|| async {
            let user_id = black_box(Uuid::new_v4());
            let post_ids: Vec<_> = (0..100)
                .map(|_| black_box(Uuid::new_v4()))
                .collect();

            extractor.get_ranking_signals(user_id, &post_ids).await
        })
    });

    c.bench_function("extract_signals_1000_posts", |b| {
        b.to_async(&rt).iter(|| async {
            let user_id = black_box(Uuid::new_v4());
            let post_ids: Vec<_> = (0..1000)
                .map(|_| black_box(Uuid::new_v4()))
                .collect();

            extractor.get_ranking_signals(user_id, &post_ids).await
        })
    });
}

criterion_group!(benches, benchmark_feature_extraction);
criterion_main!(benches);
```

运行基准测试：

```bash
cargo bench --bench clickhouse_performance_bench
```

### 5.2 性能指标检查

```bash
# 查看 ClickHouse 查询日志
curl 'http://localhost:8123/?query=SELECT+query_duration_ms,+query FROM system.query_log ORDER BY event_time DESC LIMIT 10 FORMAT Pretty'

# 监控 Redis 缓存命中率
redis-cli INFO stats | grep keyspace_hits_percentage

# 监控 ClickHouse 性能
curl 'http://localhost:8123/?query=SELECT+database,+table,+count(*) FROM system.parts GROUP BY database,table FORMAT Pretty'
```

### 5.3 预期指标

✅ **目标性能**:
- 单次提取 (100 posts): **< 100ms**
- 单次提取 (1000 posts): **< 500ms**
- 缓存命中时间: **< 5ms**
- 缓存命中率: **> 80%** (假设 5min TTL, 实际使用)

---

## 6. 故障排除

### 问题 1: ClickHouse 连接超时

```
Error: ClickHouse request failed: Connection timeout
```

**解决方案**:
```bash
# 1. 检查 ClickHouse 是否运行
docker ps | grep clickhouse

# 2. 检查连接
curl http://localhost:8123

# 3. 增加超时
CLICKHOUSE_QUERY_TIMEOUT_MS=60000  # 60s
```

### 问题 2: Redis 缓存未命中

```
All signals served from cache → 但实际没有加速
```

**解决方案**:
```bash
# 检查 Redis 连接
redis-cli PING

# 检查缓存键
redis-cli KEYS "ranking_signals:*"

# 如果为空, 检查 Redis 配置
echo $REDIS_URL
```

### 问题 3: 查询返回空结果

```
Successfully extracted 0 ranking signals from ClickHouse
```

**解决方案**:
```bash
# 验证 ClickHouse 中有数据
curl 'http://localhost:8123/?query=SELECT COUNT(*) FROM events_raw'

# 如果为 0, 需要导入数据 (见 schema.sql)
curl 'http://localhost:8123/?query=SHOW TABLES FORMAT JSONEachRow'
```

---

## 7. 监控和告警

### 7.1 Prometheus 指标

**在应用启动时导出**:

```rust
lazy_static::lazy_static! {
    static ref CH_QUERY_LATENCY: Histogram = Histogram::new(
        "clickhouse_query_latency_ms",
        "ClickHouse query latency in milliseconds"
    ).unwrap();

    static ref CH_CACHE_HITS: Counter = Counter::new(
        "clickhouse_cache_hits_total",
        "Total ClickHouse cache hits"
    ).unwrap();
}

// 在 feature_extractor 中使用
CH_QUERY_LATENCY.observe(query_duration_ms as f64);
if cache_hit {
    CH_CACHE_HITS.inc();
}
```

### 7.2 告警规则 (Prometheus AlertManager)

```yaml
groups:
  - name: clickhouse_ranking
    rules:
      - alert: ClickHouseQueryLatencyHigh
        expr: histogram_quantile(0.95, clickhouse_query_latency_ms) > 500
        for: 5m
        annotations:
          summary: "ClickHouse query latency above 500ms"

      - alert: ClickHouseCacheMissRate
        expr: |
          (rate(clickhouse_cache_misses_total[5m]) /
           rate(clickhouse_queries_total[5m])) > 0.5
        for: 10m
        annotations:
          summary: "ClickHouse cache miss rate above 50%"
```

---

## 8. 回滚计划

如果需要快速回滚到 PostgreSQL:

```rust
// 在 feed_ranking_service.rs 中
pub async fn get_personalized_feed(
    &self,
    user_id: Uuid,
    post_ids: &[Uuid],
) -> Result<FeedResponse> {
    // 尝试 ClickHouse
    match self.feature_extractor.get_ranking_signals(user_id, post_ids).await {
        Ok(signals) => {
            // 成功，使用 ClickHouse 信号
            self.ranking_engine.rank_videos(&signals).await
        }
        Err(e) => {
            // 失败，降级到 PostgreSQL (旧逻辑)
            tracing::warn!("ClickHouse failed, falling back to PostgreSQL: {}", e);
            self.legacy_get_feed_from_postgres(user_id, post_ids).await
        }
    }
}
```

---

## 9. 下一步

✅ **完成本指南后**:

1. [ ] 代码集成到 `feed_ranking_service.rs`
2. [ ] 环境变量配置完成
3. [ ] 本地测试全部通过
4. [ ] 性能基准达到目标
5. [ ] 创建 Pull Request 进行审查
6. [ ] A/B 测试部署到预发布环境
7. [ ] 灰度部署到生产 (10% → 50% → 100%)

---

**文件总结**

| 文件 | 作用 |
|------|------|
| `clickhouse_feature_extractor.rs` | 核心特征提取实现 |
| `feed_ranking_service.rs` (修改) | 集成特征提取器 |
| `main.rs` (修改) | 初始化 ClickHouse 和 Redis |
| `.env` | 环境配置 |
| `docker-compose.yml` | 依赖服务 |
| `tests/*_test.rs` | 集成和端到端测试 |
| `docs/CLICKHOUSE_INTEGRATION_ARCHITECTURE.md` | 架构设计文档 |

---

**支持与反馈**

- 问题?: 查看 `TROUBLESHOOTING.md`
- 性能?: 参考 `PERFORMANCE_TUNING.md`
- 架构?: 查看 `CLICKHOUSE_INTEGRATION_ARCHITECTURE.md`

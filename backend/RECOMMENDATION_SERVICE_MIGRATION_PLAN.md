# Recommendation Service v2 迁移计划

**Status**: 🚀 即将开始 - Phase 3
**Date**: October 30, 2025
**Target Completion**: November 13, 2025

---

## 目标

将 `user-service` 中的 `recommendation_v2` 模块 (66KB, 6 files) 完全迁移到独立的 `recommendation-service` 微服务。

**结果**:
- ✅ user-service 从 ~600KB 减少到 ~500KB
- ✅ 推荐算法与认证/授权解耦
- ✅ 支持推荐服务独立扩展和版本管理
- ✅ 为 Milvus 向量搜索和实时个性化铺路

---

## 源代码分析

### 文件结构 (6 modules, 66 KB)

```
backend/user-service/src/services/recommendation_v2/
├── mod.rs                   (15.7 KB) - 主服务,协调层
├── ab_testing.rs           (10.5 KB) - A/B测试框架
├── collaborative_filtering.rs (10.3 KB) - 协作过滤算法
├── content_based.rs        (8.5 KB) - 基于内容的过滤
├── hybrid_ranker.rs        (10.9 KB) - 混合排序 + MMR多样性
└── onnx_serving.rs         (10.4 KB) - ONNX模型推理
```

### 核心数据流

```
用户请求
    ↓
[A/B Framework] → 确定用户试验分组
    ↓
[Candidate Collection]
    ├→ 协作过滤: 基于用户历史推荐
    ├→ 趋势算法: 热门贴文
    └→ 最新贴文: 时间序列
    ↓
[Hybrid Ranker]
    ├→ 协作过滤评分 (0.4)
    ├→ 内容过滤评分 (0.3)
    └→ v1.0回退评分 (0.3)
    ↓
[MMR多样性优化] → 平衡相关性和多样性
    ↓
排序结果 → 缓存到Redis → 返回给客户端
```

### 关键类和方法

#### RecommendationServiceV2 (主服务)

```rust
pub struct RecommendationServiceV2 {
    pub cf_model: CollaborativeFilteringModel,       // 协作过滤
    pub cb_model: ContentBasedModel,                 // 内容过滤
    pub hybrid_ranker: HybridRanker,                 // 混合排序
    pub ab_framework: ABTestingFramework,            // A/B测试
    pub onnx_server: ONNXModelServer,                // ONNX推理
    db_pool: PgPool,                                  // PostgreSQL连接
    config: RecommendationConfig,
}
```

**关键方法**:
- `new(config, db_pool)` - 初始化(加载所有模型)
- `get_recommendations(user_id, limit)` → Vec<Uuid> - 核心API
- `rank_with_context(user_id, context, candidates, limit)` - 测试用
- `reload_models()` - 热重载
- `get_model_info()` → ModelInfo - 模型版本信息

**内部方法**:
- `build_user_context()` - 收集用户历史(喜欢/评论/自己的贴文)
- `collect_candidates()` - 收集候选集合
- `fetch_trending_posts()` - 获取趋势贴文
- `fetch_recent_posts()` - 获取最新贴文

#### 其他模块

| 模块 | 主要类 | 功能 |
|------|---------|------|
| ab_testing | ABTestingFramework | 一致性哈希、用户分桶、实验跟踪 |
| collaborative_filtering | CollaborativeFilteringModel | kNN、相似度矩阵、item-based推荐 |
| content_based | ContentBasedModel | TF-IDF特征、用户档案、相似度计算 |
| hybrid_ranker | HybridRanker | 权重组合、MMR多样性、排序策略 |
| onnx_serving | ONNXModelServer | 模型加载、版本管理、推理包装 |

---

## 依赖分析

### 内部依赖 (在迁移范围内)

```
user-service 中的依赖:
- crate::error::{AppError, Result}    → 共享错误处理库
- crate::services::recommendation_v2::* → 推荐模块
- sqlx::{PgPool, Row, ...}             → 数据库查询
- serde_json                            → JSON序列化
- chrono::{DateTime, Utc}              → 时间戳
- uuid::Uuid                            → UUID处理
- std::collections::*                   → 标准库
- tracing::{info, warn, error}         → 日志

数据库查询:
- SELECT post_id FROM likes WHERE user_id
- SELECT post_id FROM comments WHERE user_id
- SELECT id FROM posts WHERE user_id (own posts)
- Trending: JOIN post_metadata ORDER BY engagement
- Recent: ORDER BY created_at DESC
```

### 外部依赖

必须在 recommendation-service Cargo.toml 中添加:

```toml
# 已有的关键依赖
tract-onnx = "0.20"        # ONNX模型推理
ndarray = "0.15"           # 数值计算
rdkafka = "0.36"           # Kafka消费
neo4rs = "0.7"             # Neo4j图数据库
sqlx = { version = "0.7", features = ["postgres", "uuid", "chrono"] }
tonic = "0.10"             # gRPC框架
```

---

## 迁移步骤

### Phase 3.1: 代码迁移 (2-3天)

#### 步骤1: 创建数据库模型

**Location**: `backend/recommendation-service/src/models/`

创建表结构支持:
- `recommendation_models` - 模型元数据版本
- `experiment_assignments` - 用户试验分配缓存
- `recommendation_logs` - 推荐事件日志

```sql
-- 模型元数据
CREATE TABLE IF NOT EXISTS recommendation_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL,
    version VARCHAR NOT NULL,
    model_type VARCHAR NOT NULL, -- collaborative, content_based, onnx
    model_path VARCHAR NOT NULL,
    deployed_at TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR DEFAULT 'active', -- active, deprecated, testing
    config JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 用户试验分配(缓存)
CREATE TABLE IF NOT EXISTS experiment_assignments (
    user_id UUID NOT NULL,
    experiment_id UINT NOT NULL,
    variant_name VARCHAR NOT NULL,
    assigned_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, experiment_id)
);
```

#### 步骤2: 迁移推荐模块

复制 6 个文件到 recommendation-service:

```bash
# 目标路径
backend/recommendation-service/src/services/recommendation_v2/
├── mod.rs
├── ab_testing.rs
├── collaborative_filtering.rs
├── content_based.rs
├── hybrid_ranker.rs
└── onnx_serving.rs
```

**修改点** (最小化):

1. 导入路径调整:
   - `crate::error` → `crate::error` (共享库)
   - `crate::services::recommendation_v2` → `crate::services::recommendation_v2`

2. 数据库查询去重:
   - 如果有必要,新建 `src/db/recommendation.rs` 处理复杂查询

3. 配置加载:
   - 从环境变量读取模型路径
   - 推荐 config.rs 中统一处理

#### 步骤3: 更新模块导出

**File**: `backend/recommendation-service/src/services/mod.rs`

```rust
pub mod recommendation_v2;

pub use recommendation_v2::{
    RecommendationServiceV2,
    RecommendationConfig,
    UserContext,
    HybridRanker,
    HybridWeights,
    ABTestingFramework,
    ModelInfo,
};
```

### Phase 3.2: HTTP API实现 (1-2天)

**Location**: `backend/recommendation-service/src/handlers/recommendations.rs`

实现以下HTTP端点:

#### 1. 获取推荐

```rust
#[get("/api/v1/recommendations")]
async fn get_recommendations(
    user_id: web::Path<Uuid>,
    limit: web::Query<u32>,
    service: web::Data<Arc<RecommendationServiceV2>>,
) -> Result<Json<RecommendationResponse>> {
    let recommendations = service.get_recommendations(*user_id, limit.into_inner() as usize).await?;
    Ok(Json(RecommendationResponse {
        user_id: *user_id,
        post_ids: recommendations,
        timestamp: Utc::now(),
    }))
}

#[derive(Serialize)]
struct RecommendationResponse {
    user_id: Uuid,
    post_ids: Vec<Uuid>,
    timestamp: DateTime<Utc>,
}
```

#### 2. 获取模型信息

```rust
#[get("/api/v1/recommendations/model-info")]
async fn get_model_info(
    service: web::Data<Arc<RecommendationServiceV2>>,
) -> Result<Json<ModelInfo>> {
    let info = service.get_model_info().await;
    Ok(Json(info))
}
```

#### 3. 排序排行 (内部API)

```rust
#[post("/api/v1/recommendations/rank")]
async fn rank_candidates(
    user_id: web::Path<Uuid>,
    req: web::Json<RankingRequest>,
    service: web::Data<Arc<RecommendationServiceV2>>,
) -> Result<Json<Vec<Uuid>>> {
    let context = UserContext {
        recent_posts: req.recent_posts.clone(),
        seen_posts: req.seen_posts.clone(),
        user_profile: req.user_profile.clone(),
    };

    let result = service.rank_with_context(
        *user_id,
        context,
        req.candidates.clone(),
        req.limit as usize,
    ).await?;

    Ok(Json(result))
}

#[derive(Deserialize)]
struct RankingRequest {
    candidates: Vec<Uuid>,
    limit: u32,
    recent_posts: Vec<Uuid>,
    seen_posts: Vec<Uuid>,
    user_profile: Option<Vec<f32>>,
}
```

### Phase 3.3: gRPC服务实现 (1-2天)

**Location**: `backend/protos/recommendation.proto` (新增)

```protobuf
service RecommendationService {
    rpc GetRecommendations(GetRecommendationsRequest) returns (GetRecommendationsResponse);
    rpc RankCandidates(RankCandidatesRequest) returns (RankCandidatesResponse);
    rpc GetModelInfo(Empty) returns (ModelInfoResponse);
}

message GetRecommendationsRequest {
    string user_id = 1;
    uint32 limit = 2;
}

message GetRecommendationsResponse {
    repeated string post_ids = 1;
    string timestamp = 2;
}

message RankCandidatesRequest {
    string user_id = 1;
    repeated string candidates = 2;
    uint32 limit = 3;
    repeated string recent_posts = 4;
    repeated string seen_posts = 5;
    repeated float user_profile = 6;
}

message RankCandidatesResponse {
    repeated string ranked_post_ids = 1;
}
```

### Phase 3.4: Kafka消费者 (1-2天)

**Location**: `backend/recommendation-service/src/services/recommendation_events.rs`

监听推荐相关事件:

```rust
pub struct RecommendationEventsConsumer {
    consumer: StreamConsumer,
    service: Arc<RecommendationServiceV2>,
    db_pool: PgPool,
}

impl RecommendationEventsConsumer {
    /// 监听topics:
    /// - recommendations.model_updates - 模型更新事件
    /// - recommendations.feedback - 用户反馈(点击/点赞/驻留时间)
    /// - experiments.config - 试验配置更新

    pub async fn process_model_update(&self, event: ModelUpdateEvent) -> Result<()> {
        // 热重载模型
        self.service.reload_models().await?;
        Ok(())
    }

    pub async fn process_feedback(&self, event: UserFeedbackEvent) -> Result<()> {
        // 记录用户反馈到数据库
        // 用于模型训练的ClickHouse
        sqlx::query(
            "INSERT INTO recommendation_feedback (user_id, post_id, action, timestamp) VALUES ($1, $2, $3, $4)"
        )
        .bind(event.user_id)
        .bind(event.post_id)
        .bind(event.action)
        .bind(Utc::now())
        .execute(&self.db_pool)
        .await?;

        Ok(())
    }
}
```

### Phase 3.5: 集成到main.rs (1天)

**Location**: `backend/recommendation-service/src/main.rs`

```rust
#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 加载配置
    let config = RecommendationConfig::from_env()?;

    // 创建数据库连接池
    let db_pool = PgPoolOptions::new()
        .max_connections(32)
        .connect(&config.database_url)
        .await?;

    // 初始化推荐服务(加载所有模型)
    let recommendation_service = Arc::new(
        RecommendationServiceV2::new(config.clone(), db_pool.clone()).await?
    );

    // 创建Kafka消费者
    let consumer = RecommendationEventsConsumer::new(
        &config.kafka,
        recommendation_service.clone(),
        db_pool.clone(),
    ).await?;

    // 启动消费者后台任务
    let _consumer_handle = Arc::new(consumer).start();

    // 启动HTTP服务器
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(recommendation_service.clone()))
            .app_data(web::Data::new(db_pool.clone()))
            .route("/health", web::get().to(health_check))
            .route("/api/v1/recommendations", web::get().to(handlers::get_recommendations))
            .route("/api/v1/recommendations/model-info", web::get().to(handlers::get_model_info))
            .route("/api/v1/recommendations/rank", web::post().to(handlers::rank_candidates))
    })
    .bind("0.0.0.0:3003")?
    .run()
    .await
}
```

### Phase 3.6: API网关配置 (1天)

**Location**: `backend/nginx/nginx.conf`

更新上游和路由:

```nginx
upstream recommendation_service {
    server recommendation-service:3003;
}

# 在 /api/v1/ 作用域中添加
location /api/v1/recommendations {
    proxy_pass http://recommendation_service;
    proxy_set_header Authorization $http_authorization;

    # 缓存个性化推荐(用户级缓存)
    proxy_cache recommendations_cache;
    proxy_cache_key "$scheme$request_method$host$request_uri$http_authorization";
    proxy_cache_valid 200 5m;  # 5分钟有效期
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
}
```

### Phase 3.7: 文档和测试 (1-2天)

创建:
1. `RECOMMENDATION_SERVICE_API.md` - API文档
2. `recommendation_service_test.rs` - 集成测试
3. Docker Compose配置
4. CI/CD pipeline (GitHub Actions)

---

## 部署策略

### 1. 先决条件

✅ 所有模块代码迁移完成
✅ 数据库migration执行
✅ HTTP API测试通过
✅ gRPC服务正常工作

### 2. 蓝绿部署

```
Week 1 (Nov 1-5):
- 并行运行 user-service (旧) 和 recommendation-service (新)
- 0% 流量路由到 recommendation-service (备用)

Week 2 (Nov 8-12):
- 逐步增加: 10% → 25% → 50% 流量
- 监控延迟、错误率、缓存命中率

Week 3+ (Nov 15+):
- 100% 流量到 recommendation-service
- 从 user-service 中移除推荐代码
```

### 3. 回滚计划

如果出现问题 (P99延迟 > 500ms或错误率 > 1%):

```bash
# 快速回滚
- 从nginx重新路由到 user-service
- 保留所有recommendation-service日志用于分析
- 发送告警通知
```

---

## 验证清单

### 代码迁移

- [ ] 6个模块代码复制到 recommendation-service
- [ ] 导入路径修复无编译错误
- [ ] 所有单元测试通过 (`cargo test --lib`)
- [ ] Clippy检查通过 (`cargo clippy`)

### 功能验证

- [ ] 获取推荐API返回正确结果
- [ ] 模型热重载工作正常
- [ ] A/B测试框架正确分配用户
- [ ] 多样性(MMR)正常工作
- [ ] Kafka消费者启动并处理事件

### 性能验证

- [ ] P95延迟 < 200ms (之前: ~165ms)
- [ ] 吞吐量 > 1000 req/sec
- [ ] 模型加载时间 < 5秒
- [ ] 缓存命中率 > 85%

### 部署验证

- [ ] Docker镜像构建成功
- [ ] 健康检查端点响应正常
- [ ] gRPC服务可访问
- [ ] Kafka连接成功

---

## 文件变更总结

### 新增文件

```
backend/recommendation-service/
├── src/
│   ├── handlers/
│   │   └── recommendations.rs (NEW - HTTP handlers)
│   ├── services/
│   │   ├── mod.rs (MODIFIED - export recommendation_v2)
│   │   └── recommendation_v2/ (NEW - 6 modules)
│   │       ├── mod.rs
│   │       ├── ab_testing.rs
│   │       ├── collaborative_filtering.rs
│   │       ├── content_based.rs
│   │       ├── hybrid_ranker.rs
│   │       └── onnx_serving.rs
│   ├── services/
│   │   └── recommendation_events.rs (NEW - Kafka consumer)
│   ├── db/
│   │   └── models.rs (NEW - 数据库表定义)
│   └── main.rs (MODIFIED - 集成推荐服务)
├── migrations/
│   └── 001_create_recommendation_tables.sql (NEW)
├── Dockerfile (NEW)
└── docker-compose.override.yml (MODIFIED)

backend/nginx/
└── nginx.conf (MODIFIED - 添加推荐服务路由)

backend/protos/
└── recommendation.proto (NEW - gRPC定义)

backend/
├── RECOMMENDATION_SERVICE_API.md (NEW)
└── RECOMMENDATION_SERVICE_MIGRATION_PLAN.md (THIS FILE)
```

### 修改的文件

```
backend/user-service/
├── src/
│   ├── handlers/discover.rs (MODIFIED - 改用gRPC调用recommendation-service)
│   ├── services/mod.rs (MODIFIED - 移除recommendation_v2模块)
│   └── main.rs (MODIFIED - 移除推荐服务初始化)
├── Cargo.toml (MODIFIED - 移除部分依赖)
└── build.rs (MODIFIED - 更新依赖)

backend/recommendation-service/
└── Cargo.toml (MODIFIED - 添加recommendation_v2依赖)
```

### 删除的文件

```
backend/user-service/src/services/recommendation_v2/
├── mod.rs (MOVED)
├── ab_testing.rs (MOVED)
├── collaborative_filtering.rs (MOVED)
├── content_based.rs (MOVED)
├── hybrid_ranker.rs (MOVED)
└── onnx_serving.rs (MOVED)
```

---

## 性能影响

### user-service 优化

| 指标 | 前 | 后 | 改进 |
|------|----|----|------|
| 代码大小 | ~600KB | ~500KB | -17% |
| 初始化时间 | ~8s | ~6s | -25% |
| 内存使用 | ~512MB | ~384MB | -25% |
| 编译时间 | ~120s | ~95s | -21% |

### recommendation-service 新增

| 指标 | 目标 |
|------|------|
| P95延迟 | < 200ms |
| P99延迟 | < 500ms |
| 吞吐量 | > 1000 req/sec |
| 错误率 | < 0.1% |
| 缓存命中率 | > 85% |

---

## 成功标准

✅ **代码质量**
- 零编译警告
- Clippy评分 ≥ 95%
- 代码覆盖率 ≥ 80%

✅ **功能完整**
- 所有推荐算法按期望工作
- A/B测试框架可用
- Kafka消费者处理事件

✅ **性能目标**
- P95延迟 < 200ms
- 缓存命中率 > 85%
- 99.9% 可用性

✅ **部署顺利**
- 蓝绿部署成功
- 零宕机时间
- 可快速回滚

---

## 后续优化 (Phase 4+)

1. **Milvus向量搜索** - 实时推荐搜索
2. **分布式缓存** - Redis集群支持
3. **实时特征计算** - 流处理管道
4. **在线学习** - 模型持续改进
5. **跨域推荐** - 支持多个内容类型

---

**Author**: Nova Engineering Team
**Last Updated**: October 30, 2025
**Next Review**: November 13, 2025

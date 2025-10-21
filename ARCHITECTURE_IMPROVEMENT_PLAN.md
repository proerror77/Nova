# Nova 项目架构改进详细计划

**文档版本**: 1.0
**创建日期**: 2025-10-21
**优先级**: 🔴 立即执行

---

## 目录
1. [问题分析](#问题分析)
2. [第1优先级：架构诚实化（本周）](#第1优先级)
3. [第2优先级：质量提升（2周内）](#第2优先级)
4. [第3优先级：生产就绪（1个月内）](#第3优先级)
5. [执行检查清单](#执行检查清单)

---

## 问题分析

### 问题1：虚假微服务架构 🔴

**当前状态**:
```
backend/
└── user-service/
    ├── src/handlers/
    │   ├── auth.rs           ← 认证
    │   ├── feed.rs           ← Feed推荐
    │   ├── messaging.rs      ← 私信系统
    │   ├── oauth.rs          ← OAuth登录
    │   ├── posts.rs          ← 帖子管理
    │   ├── streaming_websocket.rs  ← 直播
    │   └── events.rs         ← 事件处理
    ├── src/services/
    │   ├── feed_ranking.rs
    │   ├── feed_cache.rs
    │   ├── feed_service.rs
    │   ├── cdc/
    │   ├── events/
    │   ├── messaging/
    │   ├── streaming/
    │   └── ... (64个service文件！)
    └── docker-compose.yml    ← 只有这一个应用镜像
```

**问题**:
- 声称是微服务，实际是单体
- 所有功能共享一个二进制、一个数据库、一个部署单元
- 修改消息系统 → 重新部署整个应用 → Feed、认证全部重启
- 无法独立扩展某个功能

**为什么现在是问题**:
- 64个service模块堆在一起，代码找不到
- 每次编译时间超过13分钟（所有功能都要重新编译）
- 难以理解数据流（哪个模块依赖哪个?)
- 将来无法独立扩展Feed而不影响消息系统

---

### 问题2：Phase 5 过度设计 🔴

**当前 docker-compose.yml 配置**:
```yaml
services:
  # 核心应用
  user-service:
    build: ./backend

  # 核心基础设施
  postgres:
  redis:
  kafka:
  zookeeper:

  # 过度设计（Phase 5）
  neo4j:              # 图数据库 - 不必要
  elasticsearch:      # 搜索引擎 - 100K用户不需要
  ray-head:          # 分布式ML - 推荐系统还很简单
  redis-cluster:     # 集群模式 - 单节点12GB就够
  nginx-rtmp:        # RTMP服务器 - 直播需求不明确
```

**内存占用**:
```
现在: zookeeper(512M) + kafka(1G) + neo4j(2G) + es(2G) +
      ray(2G) + redis-cluster(1G) + postgres(2G) + redis(512M) = 11G+

应该: kafka(1G) + redis(512M) + postgres(1G) + zk(512M) = 3G
```

**为什么是问题**:
- 新开发者无法在笔记本上运行完整环境
- 每次启动要等15分钟所有服务就绪
- 维护额外11个服务的配置和依赖
- 这些技术现在完全用不到

---

### 问题3：iOS 项目重复 🔴

**当前状态**:
```
ios/
├── NovaSocial/                    ← 项目A
│   ├── NovaSocial.xcodeproj
│   ├── Network/
│   │   ├── Core/APIClient.swift
│   │   ├── Models/APIModels.swift
│   │   └── Repositories/PostRepository.swift
│   └── ...
│
└── NovaSocialApp/                 ← 项目B（相似）
    ├── NovaSocialApp.xcodeproj
    ├── Network/
    │   ├── Core/APIClient.swift        ← 重复代码!
    │   ├── Models/APIModels.swift      ← 重复代码!
    │   ├── Repositories/PostRepository.swift  ← 重复代码!
    │   └── Utils/AppConfig.swift
    └── ...
```

**实际修改证明重复问题**:
```bash
git log --oneline | grep ios
# ... 多个commit都是改A又改B的相同代码
```

**为什么是问题**:
- 维护两份相似代码 = bug修一个漏一个
- 新功能需要加两遍
- 占用磁盘和CI时间
- 开发者困惑（应该用哪个?)
- Pod依赖可能不一致

---

## 第1优先级：架构诚实化（本周）

### Step 1.1: 决策 - 单体 vs 微服务

#### 选项A：优化单体（推荐短期）

**时间**: 1-2周
**复杂度**: 低
**收益**: 立即可执行

**做法**:
```
1. 重命名 user-service → nova-backend (或 nova-api)
   - 诚实命名，不再假装微服务

2. 保持代码结构，但明确标记模块边界
   - src/modules/auth/       ← 认证模块
   - src/modules/feed/       ← Feed模块
   - src/modules/messaging/  ← 消息模块
   - src/modules/streaming/  ← 流媒体模块

3. 更新 Constitution.md
   改为: "Monolithic Architecture (Phase 1-2)"
   添加: "Planned Microservices Migration (Phase 3+)"

4. 优化单体的编译时间
   - 使用增量编译缓存
   - 将大模块分离为独立库 (lib)

5. 规划未来拆分（6个月后）
```

**优缺点**:
```
✅ 优点:
   - 快速改进（1周完成）
   - 零风险（不改代码逻辑）
   - 清晰路线图（何时拆分微服务）
   - 团队易于理解

❌ 缺点:
   - 仍然是单点故障
   - 水平扩展有限制
   - 长期需要拆分
```

---

#### 选项B：立即拆分微服务（不推荐现在做）

**时间**: 3-6个月
**复杂度**: 高
**收益**: 长期架构改善

**如果要做拆分**:

**Phase B1 (第1个月) - 认证服务独立**:
```
auth-service/
├── Cargo.toml
├── src/
│   ├── main.rs
│   ├── models/      (User, Session, Token)
│   ├── handlers/    (register, login, verify_token)
│   └── db/          (auth_db - 独立PostgreSQL)
└── Dockerfile

# 修改 user-service 的依赖：
user-service 通过 HTTP/gRPC 调用 auth-service
所有认证逻辑移出 user-service
```

**问题**: 现在不建议做这个，因为：
- 需要重写所有JWT验证中间件
- 服务间通信增加延迟和复杂性
- 现有用户量不需要这种扩展
- 会打乱当前迭代周期

---

### 建议：**选择选项A（优化单体）**

**原因**:
1. **快速改进** - 1周内见效
2. **低风险** - 代码逻辑不变
3. **清晰路线** - 明确何时拆分
4. **支撑增长** - 能应付100K用户
5. **保持迭代** - 不打乱功能开发

---

### Step 1.2: 删除 Phase 5 过度设计

**这一步最立竿见影！**

#### 识别要删除的服务

```yaml
# 当前 docker-compose.yml
services:
  neo4j:            # ❌ 删除 - PostgreSQL递归查询够用
  elasticsearch:    # ❌ 删除 - 100K用户无全文搜索需求
  ray-head:         # ❌ 删除 - 推荐还不复杂
  redis-cluster:    # ❌ 删除 - 单节点12GB就够
  nginx-rtmp:       # ⚠️ 评估 - 直播真的需要吗?

  # 保留这些
  postgres:         # ✅ 核心
  redis:            # ✅ 缓存
  kafka:            # ✅ CDC需要
  zookeeper:        # ✅ Kafka依赖
  prometheus:       # ✅ 监控
  grafana:          # ✅ 可视化
```

#### 执行步骤

**Step 1: 备份当前状态**
```bash
cd /Users/proerror/Documents/nova
git checkout -b archive/phase5-full  # 备份分支
git push origin archive/phase5-full
```

**Step 2: 清理 docker-compose.yml**
```yaml
# 删除这些块:
  neo4j:
    image: neo4j:5.15
    ...

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.10.0
    ...

  ray-head:
    image: rayproject/ray:latest
    ...

  redis-cluster:
    image: redis:7-alpine
    ...
```

**Step 3: 检查代码中的依赖**
```bash
# 搜索Neo4j相关代码
grep -r "neo4j" backend/user-service/src/
grep -r "elasticsearch" backend/user-service/src/
grep -r "ray" backend/user-service/src/
```

**Step 4: 删除未使用的依赖**
```bash
# 在 backend/user-service/Cargo.toml 中删除:
neo4j = ...
elasticsearch = ...
ray = ...
```

**Step 5: 保存特性开关**
```rust
// 创建 src/config/feature_flags.rs
pub struct FeatureFlags {
    pub enable_recommendations: bool,  // 现在: false, 未来: true
    pub enable_graph_search: bool,     // 现在: false, 未来: true
    pub enable_full_text_search: bool, // 现在: false, 未来: true
}

impl FeatureFlags {
    pub fn from_env() -> Self {
        Self {
            enable_recommendations: std::env::var("ENABLE_RECOMMENDATIONS")
                .unwrap_or_else(|_| "false".to_string()) == "true",
            // ...
        }
    }
}
```

这样，如果将来需要重新启用这些功能，只需要：
1. 重新添加docker-compose配置
2. 启用特性开关
3. 实现相关处理代码

---

#### 验证删除是否完整

```bash
# 确保没有遗留配置
grep -r "neo4j\|elasticsearch\|ray" docker-compose*.yml
grep -r "neo4j\|elasticsearch\|ray" backend/

# 确保能启动最小配置
docker-compose down
docker-compose up -d postgres redis kafka zookeeper

# 检查内存使用
docker stats --no-stream
# 应该从11G+ 降到3-4G
```

---

### Step 1.3: 统一 iOS 项目

#### 决策：保留哪个项目？

**分析现有两个项目**:
```bash
# 项目A的状态
ls ios/NovaSocial/
NovaSocial.xcodeproj  # 文件数量?
NovaSocial/           # 源代码量?

# 项目B的状态
ls ios/NovaSocialApp/
NovaSocialApp.xcodeproj
NovaSocialApp/

# 比较哪个更完整
find ios/NovaSocial -name "*.swift" | wc -l
find ios/NovaSocialApp -name "*.swift" | wc -l
```

**建议**:
1. 保留文件数更多、更新更频繁的那个
2. 按惯例，保留名称带"App"的（NovaSocialApp）

#### 执行合并

**Step 1: 提取两个项目的差异**
```bash
# 生成差异报告
diff -r ios/NovaSocial/ ios/NovaSocialApp/ > /tmp/ios_diff.txt

# 手动审查关键差异
grep -A 3 "diff --git" /tmp/ios_diff.txt | head -50
```

**Step 2: 合并有价值的代码**

如果项目A有项目B没有的功能：
```bash
# 比如项目A有某个工具类
ls ios/NovaSocial/Network/Utils/
# 如果B没有，复制过去
cp ios/NovaSocial/Network/Utils/*.swift ios/NovaSocialApp/Network/Utils/
```

**Step 3: 删除重复项目**
```bash
# 备份
git mv ios/NovaSocial ios/NovaSocial.backup

# 验证编译
cd ios/NovaSocialApp
xcodebuild build -scheme NovaSocialApp -destination generic/platform=iOS

# 如果编译成功
rm -rf ios/NovaSocial.backup
```

**Step 4: 更新项目配置**
```swift
// ios/NovaSocialApp/Shared/Constants.swift
struct AppConstants {
    static let appName = "Nova Social"
    static let appVersion = "1.0.0"
    static let apiBaseURL = "https://api.nova.app"
}

// 确保只在一个地方定义
```

**Step 5: Commit**
```bash
git add ios/
git commit -m "chore(ios): consolidate duplicated projects into NovaSocialApp

- Removed redundant NovaSocial project
- Merged unique components from NovaSocial into NovaSocialApp
- Verified build and functionality
- Single source of truth for iOS codebase"
```

---

### Step 1.4: 清理 95个 TODO/FIXME

```bash
# 统计TODO
grep -r "TODO\|FIXME" backend/user-service/src/ | wc -l
# 输出: 95

# 分类TODO
grep -r "TODO" backend/ | cut -d':' -f2 | sort | uniq -c | sort -rn
```

**处理方案**:

**方案1：转移到GitHub Issues**
```bash
# 对每个TODO创建issue
# 示例:
github issue create --title "Phase 2: Implement VideoService" \
  --body "TODO from handlers/mod.rs line 42"
```

**方案2：删除低优先级的注释**
```rust
// ❌ 删除这种
// TODO: Phase 2 - needs VideoService implementation
// pub mod discover;
// pub mod reels;

// ✅ 改为GitHub Issue + 代码注释
// Feature branches commented out. See issue #42
```

**方案3：标记优先级**
```rust
// TODO: CRITICAL - Phase 1 blocker
// - Implement message encryption key rotation

// TODO: HIGH - Phase 2
// - Add video transcoding optimization

// TODO: LOW - Phase 3+
// - Implement AI-based content moderation
```

---

## 第2优先级：质量提升（2周内）

### Step 2.1: 建立 CI/CD 管线

#### 创建 GitHub Actions 工作流

**文件**: `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

env:
  RUST_BACKTRACE: 1
  CARGO_TERM_COLOR: always

jobs:
  # ============================================================
  # 步骤1: 代码质量检查
  # ============================================================
  quality:
    name: Code Quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy

      # 格式检查
      - name: Check formatting
        run: cargo fmt -p user-service -- --check

      # Clippy 静态分析
      - name: Run Clippy
        run: cargo clippy -p user-service --all-targets -- -D warnings

      # 文档检查
      - name: Check documentation
        run: cargo doc -p user-service --no-deps

  # ============================================================
  # 步骤2: 单元测试
  # ============================================================
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable

      - name: Cache cargo registry
        uses: actions/cache@v3
        with:
          path: ~/.cargo/registry
          key: ${{ runner.os }}-cargo-registry-${{ hashFiles('**/Cargo.lock') }}

      - name: Cache cargo index
        uses: actions/cache@v3
        with:
          path: ~/.cargo/git
          key: ${{ runner.os }}-cargo-git-${{ hashFiles('**/Cargo.lock') }}

      - name: Cache cargo build
        uses: actions/cache@v3
        with:
          path: target
          key: ${{ runner.os }}-cargo-build-target-${{ hashFiles('**/Cargo.lock') }}

      - name: Run unit tests
        run: cargo test --lib -p user-service --verbose

  # ============================================================
  # 步骤3: 集成测试
  # ============================================================
  integration-tests:
    name: Integration Tests
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15-alpine
        env:
          POSTGRES_USER: nova
          POSTGRES_PASSWORD: password
          POSTGRES_DB: nova_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable

      - name: Set up database
        env:
          DATABASE_URL: postgres://nova:password@localhost:5432/nova_test
        run: |
          sqlx-cli database create
          sqlx-cli migrate run -D backend/migrations

      - name: Run integration tests
        env:
          DATABASE_URL: postgres://nova:password@localhost:5432/nova_test
          REDIS_URL: redis://localhost:6379
        run: cargo test --test '*_integration_test' -p user-service --verbose

  # ============================================================
  # 步骤4: 代码覆盖率
  # ============================================================
  coverage:
    name: Code Coverage
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable

      - name: Install tarpaulin
        run: cargo install cargo-tarpaulin

      - name: Generate coverage
        run: cargo tarpaulin -p user-service --out Xml --exclude-files tests/*

      - name: Check coverage threshold
        run: |
          COVERAGE=$(cat cobertura.xml | grep -oP 'line-rate="\K[^"]*')
          echo "Code coverage: ${COVERAGE}%"
          if (( $(echo "$COVERAGE < 0.80" | bc -l) )); then
            echo "❌ Coverage below 80% threshold!"
            exit 1
          fi

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./cobertura.xml
          flags: unittests
          name: codecov-umbrella

  # ============================================================
  # 步骤5: 安全检查
  # ============================================================
  security:
    name: Security Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rustsec/audit-check-action@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

  # ============================================================
  # 步骤6: 构建 Docker 镜像
  # ============================================================
  build:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: [quality, unit-tests, integration-tests, coverage, security]
    if: success() && github.event_name == 'push'

    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./backend
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/nova-api:${{ github.sha }}
            ghcr.io/${{ github.repository }}/nova-api:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ============================================================
  # 步骤7: iOS 构建
  # ============================================================
  ios-build:
    name: iOS Build
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode version
        run: sudo xcode-select --switch /Applications/Xcode_15.1.app

      - name: Build iOS app
        run: |
          cd ios/NovaSocialApp
          xcodebuild build \
            -scheme NovaSocialApp \
            -destination generic/platform=iOS \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO

      - name: Run iOS tests
        run: |
          cd ios/NovaSocialApp
          xcodebuild test \
            -scheme NovaSocialApp \
            -destination 'platform=iOS Simulator,name=iPhone 15'

  # ============================================================
  # 最终步骤：总结
  # ============================================================
  all-checks:
    name: All Checks Passed ✅
    runs-on: ubuntu-latest
    needs: [quality, unit-tests, integration-tests, coverage, security, build, ios-build]
    if: always()
    steps:
      - name: Check job status
        run: |
          if [[ "${{ needs.quality.result }}" != "success" || \
                "${{ needs.unit-tests.result }}" != "success" || \
                "${{ needs.integration-tests.result }}" != "success" || \
                "${{ needs.coverage.result }}" != "success" || \
                "${{ needs.security.result }}" != "success" ]]; then
            echo "❌ Some checks failed!"
            exit 1
          fi
          echo "✅ All checks passed!"
```

#### 在 main.rs 中添加健康检查端点

```rust
// src/handlers/health.rs
use actix_web::{web, HttpResponse};
use serde_json::json;

pub async fn health_check() -> HttpResponse {
    HttpResponse::Ok().json(json!({
        "status": "healthy",
        "service": "nova-api",
        "version": env!("CARGO_PKG_VERSION"),
    }))
}

pub async fn readiness_check(
    db: web::Data<PgPool>,
    redis: web::Data<redis::aio::ConnectionManager>,
) -> HttpResponse {
    // 检查数据库连接
    match db.acquire().await {
        Ok(_) => {},
        Err(_) => return HttpResponse::ServiceUnavailable().json(json!({"ready": false}))
    }

    // 检查Redis连接
    match redis.get_connection().await {
        Ok(_) => {},
        Err(_) => return HttpResponse::ServiceUnavailable().json(json!({"ready": false}))
    }

    HttpResponse::Ok().json(json!({"ready": true}))
}

pub async fn liveness_check() -> HttpResponse {
    HttpResponse::Ok().json(json!({"alive": true}))
}
```

#### 在 main.rs 中注册路由

```rust
// src/main.rs
app.route("/health", web::get().to(handlers::health_check))
   .route("/health/ready", web::get().to(handlers::readiness_check))
   .route("/health/live", web::get().to(handlers::liveness_check))
```

---

### Step 2.2: 添加分布式追踪 (Jaeger)

#### 安装依赖

```toml
# Cargo.toml
[dependencies]
opentelemetry = "0.20"
opentelemetry-jaeger = "0.19"
tracing = "0.1"
tracing-opentelemetry = "0.21"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
```

#### 添加追踪初始化

```rust
// src/telemetry/mod.rs
use opentelemetry::global;
use opentelemetry_jaeger::new_agent_pipeline;
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

pub fn init_tracing() -> Result<(), Box<dyn std::error::Error>> {
    // 创建Jaeger导出器
    let tracer = new_agent_pipeline()
        .with_service_name("nova-api")
        .with_endpoint("http://localhost:14268/api/traces")
        .install_simple()?;

    // 创建OpenTelemetry层
    let telemetry = OpenTelemetryLayer::new(tracer);

    // 初始化subscriber
    tracing_subscriber::registry()
        .with(telemetry)
        .with(tracing_subscriber::fmt::layer())
        .with(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    Ok(())
}
```

#### 在 main.rs 中初始化

```rust
// src/main.rs
mod telemetry;

#[actix_web::main]
async fn main() -> io::Result<()> {
    // 初始化追踪
    telemetry::init_tracing()
        .expect("Failed to initialize tracing");

    // ... rest of setup
}
```

#### 在 docker-compose.yml 中添加 Jaeger

```yaml
jaeger:
  image: jaegertracing/all-in-one:latest
  ports:
    - "6831:6831/udp"      # Jaeger agent 接收追踪
    - "14268:14268"        # 直接HTTP接收
    - "16686:16686"        # UI
  environment:
    COLLECTOR_ZIPKIN_HOST_PORT: ":9411"
```

#### 访问追踪界面

```
http://localhost:16686
```

选择 "nova-api" 服务，即可看到所有请求的完整追踪链路。

---

### Step 2.3: 统一配置管理

#### 问题：当前130+环境变量

```bash
# .env.example 太混乱
DATABASE_URL=postgres://...
REDIS_URL=redis://...
JWT_SECRET=...
JWT_PRIVATE_KEY_PEM=...  # 整个PEM文件 Base64编码?!
# ... 还有130行
```

#### 解决方案：分层配置

**创建配置文件结构**:

```
backend/config/
├── default.toml          # 默认配置
├── development.toml      # 开发环境覆盖
├── staging.toml          # 预发环境
├── production.toml       # 生产环境
└── local.toml           # 本地(git ignore)
```

**文件内容**:

```toml
# backend/config/default.toml
[server]
host = "127.0.0.1"
port = 8080
workers = 4

[database]
url = "postgres://localhost/nova"
max_connections = 20
ssl_mode = "disable"

[redis]
url = "redis://localhost:6379"
db = 0

[jwt]
algorithm = "RS256"
expiry_hours = 24

[logging]
level = "info"
format = "json"

[features]
enable_e2e_messaging = true
enable_live_streaming = false
```

```toml
# backend/config/development.toml
[logging]
level = "debug"

[features]
enable_e2e_messaging = true
enable_live_streaming = false
```

```toml
# backend/config/production.toml
[database]
ssl_mode = "require"
max_connections = 50

[logging]
level = "warn"

# 密钥从Kubernetes Secret读取，不在文件中
```

#### 代码实现

```rust
// src/config.rs
use config::{Config, ConfigError, Environment, File};
use serde::Deserialize;
use std::env;

#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub jwt: JwtConfig,
    pub logging: LoggingConfig,
    pub features: FeaturesConfig,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub workers: usize,
}

// ... 其他config结构体

impl AppConfig {
    pub fn from_env() -> Result<Self, ConfigError> {
        let env = env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());

        let config = Config::builder()
            // 默认配置
            .add_source(File::with_name("config/default"))
            // 环境特定配置
            .add_source(File::with_name(&format!("config/{}", env)).required(false))
            // 本地覆盖 (git ignored)
            .add_source(File::with_name("config/local").required(false))
            // 环境变量覆盖
            .add_source(Environment::with_prefix("APP"))
            .build()?;

        config.try_deserialize()
    }
}
```

#### 密钥管理

```rust
// src/config/secrets.rs
use std::fs;

pub struct Secrets {
    pub jwt_private_key: Vec<u8>,
    pub jwt_public_key: Vec<u8>,
}

impl Secrets {
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        let app_env = std::env::var("APP_ENV").unwrap_or_else(|_| "development".to_string());

        match app_env.as_str() {
            "production" => {
                // 生产环境从文件系统读取（Kubernetes Secret挂载）
                let private_key = fs::read("/etc/secrets/jwt_private.pem")?;
                let public_key = fs::read("/etc/secrets/jwt_public.pem")?;

                Ok(Self {
                    jwt_private_key: private_key,
                    jwt_public_key: public_key,
                })
            }
            _ => {
                // 开发环境从环境变量读取
                let private_key = std::env::var("JWT_PRIVATE_KEY")?
                    .into_bytes();
                let public_key = std::env::var("JWT_PUBLIC_KEY")?
                    .into_bytes();

                Ok(Self {
                    jwt_private_key: private_key,
                    jwt_public_key: public_key,
                })
            }
        }
    }
}
```

#### 更新 .gitignore

```bash
# .gitignore
config/local.toml
.env.local
/secrets/
```

---

## 第3优先级：生产就绪（1个月内）

### Step 3.1: 负载测试

#### 安装压测工具

```bash
# 安装 Apache Bench
brew install httpd

# 或者 wrk
brew install wrk

# 或者 k6
brew install k6
```

#### 创建测试脚本

```javascript
// tests/load_test.js (使用k6)
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 100 },   // 2分钟内逐步增加到100个用户
    { duration: '5m', target: 100 },   // 保持100个用户5分钟
    { duration: '2m', target: 200 },   // 逐步增加到200个用户
    { duration: '5m', target: 200 },   // 保持200个用户5分钟
    { duration: '2m', target: 0 },     // 逐步降到0（冷却）
  ],
};

export default function () {
  // 测试认证
  const registerRes = http.post('http://localhost:8080/api/v1/auth/register', {
    email: `user_${__VU}_${__ITER}@test.com`,
    password: 'Test@123456',
  });
  check(registerRes, {
    'register status is 201': (r) => r.status === 201,
  });

  // 测试Feed获取
  const feedRes = http.get('http://localhost:8080/api/v1/feed');
  check(feedRes, {
    'feed status is 200': (r) => r.status === 200,
  });

  sleep(1);
}
```

#### 运行测试

```bash
# 启动应用
docker-compose up -d

# 等待应用就绪
sleep 10

# 运行负载测试
k6 run tests/load_test.js

# 查看结果
# 输出应该显示：
# - 响应时间（p95, p99等)
# - 错误率
# - 吞吐量(RPS)
```

#### 性能指标目标

```
✅ 目标:
- P95 响应时间 < 200ms
- P99 响应时间 < 500ms
- 错误率 < 0.1%
- 吞吐量 > 500 RPS
- 200并发用户下无崩溃
```

---

### Step 3.2: 数据库查询优化

#### 识别慢查询

```sql
-- 启用慢查询日志
ALTER SYSTEM SET log_min_duration_statement = 100;  -- 记录超过100ms的查询
SELECT pg_reload_conf();

-- 查看慢查询
SELECT query, calls, mean_exec_time, max_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

#### 常见优化

**问题1：N+1查询**

```rust
// ❌ 坏的做法
let posts = get_all_posts().await?;  // 1个查询
for post in posts {
    let author = get_user(post.user_id).await?;  // N个查询
    println!("{}: {}", author.name, post.title);
}

// ✅ 好的做法
let posts = get_all_posts().await?;
let user_ids: Vec<_> = posts.iter().map(|p| p.user_id).collect();
let authors = get_users_batch(&user_ids).await?;
let author_map: HashMap<_, _> = authors.into_iter()
    .map(|u| (u.id, u))
    .collect();

for post in posts {
    let author = &author_map[&post.user_id];
    println!("{}: {}", author.name, post.title);
}
```

**问题2：缺失索引**

```sql
-- 找出所有未使用的查询
EXPLAIN ANALYZE
SELECT p.* FROM posts p
WHERE p.user_id = $1
ORDER BY p.created_at DESC
LIMIT 20;

-- 如果看到 "Seq Scan"（全表扫描），说明需要索引
-- 创建索引
CREATE INDEX idx_posts_user_created ON posts(user_id, created_at DESC);
```

**问题3：大连接查询**

```sql
-- ❌ 低效
SELECT * FROM posts p
JOIN users u ON p.user_id = u.id
JOIN comments c ON p.id = c.post_id
WHERE p.created_at > now() - interval '7 days'

-- ✅ 优化：分离关注点
-- 步骤1: 获取近7天的帖子
SELECT id FROM posts WHERE created_at > now() - interval '7 days'

-- 步骤2: 批量获取这些帖子的详细数据和评论
SELECT * FROM posts WHERE id = ANY($1)
SELECT * FROM comments WHERE post_id = ANY($1)
```

---

### Step 3.3: 监控告警

#### 创建 Prometheus 告警规则

```yaml
# backend/monitoring/prometheus_rules.yml
groups:
  - name: nova_alerts
    interval: 15s
    rules:
      # 应用健康
      - alert: HighErrorRate
        expr: |
          (sum(rate(http_requests_total{status=~"5.."}[5m])) /
           sum(rate(http_requests_total[5m]))) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "高错误率告警"
          description: "过去5分钟内错误率> 5%"

      # 性能
      - alert: HighLatency
        expr: histogram_quantile(0.95, http_request_duration_seconds) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "高延迟告警"
          description: "P95响应时间 > 1s"

      # 资源
      - alert: HighMemoryUsage
        expr: process_resident_memory_bytes / 1024 / 1024 > 900
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "高内存使用告警"
          description: "内存使用 > 900MB"

      # 数据库
      - alert: DatabaseConnectionPoolExhausted
        expr: db_connection_pool_available_connections == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "数据库连接池耗尽"

      # Redis
      - alert: RedisHighMemory
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Redis内存使用> 90%"
```

#### 配置 AlertManager

```yaml
# backend/monitoring/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      continue: true

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5000/alerts'

  - name: 'critical'
    email_configs:
      - to: 'oncall@nova.app'
        from: 'alerts@nova.app'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alerts@nova.app'
        auth_password: '${GMAIL_PASSWORD}'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_URL}'
        channel: '#alerts-critical'
```

---

### Step 3.4: 灰度发布机制

#### 实现特性开关

```rust
// src/config/feature_flags.rs
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

#[derive(Clone)]
pub struct FeatureFlags {
    flags: Arc<RwLock<HashMap<String, bool>>>,
}

impl FeatureFlags {
    pub async fn new() -> Self {
        let mut flags = HashMap::new();

        // 从数据库或配置加载
        flags.insert("enable_e2e_messaging".to_string(), true);
        flags.insert("enable_live_streaming".to_string(), false);
        flags.insert("enable_new_feed_algorithm".to_string(), false);

        Self {
            flags: Arc::new(RwLock::new(flags)),
        }
    }

    pub async fn is_enabled(&self, flag: &str) -> bool {
        self.flags.read().await
            .get(flag)
            .copied()
            .unwrap_or(false)
    }

    pub async fn set_flag(&self, flag: &str, enabled: bool) {
        self.flags.write().await.insert(flag.to_string(), enabled);
    }
}
```

#### 在处理器中使用

```rust
// src/handlers/feed.rs
pub async fn get_feed(
    user: UserId,
    flags: web::Data<FeatureFlags>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
    let use_new_algorithm = flags.is_enabled("enable_new_feed_algorithm").await;

    let posts = if use_new_algorithm {
        // 新的推荐算法
        feed_ranking_v2::get_feed(&db, user.0).await?
    } else {
        // 旧的算法
        feed_ranking::get_feed(&db, user.0).await?
    };

    Ok(HttpResponse::Ok().json(posts))
}
```

#### 按用户百分比灰度

```rust
// src/config/feature_flags.rs (扩展)
pub struct FeatureFlag {
    pub name: String,
    pub enabled: bool,
    pub rollout_percentage: u32,  // 0-100
}

pub async fn should_enable_for_user(
    flag: &FeatureFlag,
    user_id: Uuid,
) -> bool {
    if !flag.enabled {
        return false;
    }

    // 使用用户ID哈希确保一致性
    let hash = calculate_hash(&user_id.to_string());
    let percentage = (hash % 100) as u32;

    percentage < flag.rollout_percentage
}
```

#### 在数据库中存储特性开关

```sql
-- 特性开关表
CREATE TABLE feature_flags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    rollout_percentage INT NOT NULL DEFAULT 100 CHECK (rollout_percentage >= 0 AND rollout_percentage <= 100),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- 创建索引
CREATE INDEX idx_feature_flags_name ON feature_flags(name);

-- 插入示例
INSERT INTO feature_flags (name, description, enabled, rollout_percentage) VALUES
('enable_e2e_messaging', 'E2E encrypted messaging', true, 100),
('enable_live_streaming', 'Live streaming feature', false, 0),
('enable_new_feed_algorithm', 'ML-based feed ranking', true, 30);  -- 30%用户
```

#### 创建管理API

```rust
// src/handlers/admin/feature_flags.rs
pub async fn list_flags(
    db: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
    let flags = sqlx::query_as!(
        FeatureFlag,
        "SELECT id, name, description, enabled, rollout_percentage, created_at FROM feature_flags"
    )
    .fetch_all(db.as_ref())
    .await?;

    Ok(HttpResponse::Ok().json(flags))
}

pub async fn update_flag(
    db: web::Data<PgPool>,
    flag_name: web::Path<String>,
    update: web::Json<FlagUpdateRequest>,
) -> Result<HttpResponse, AppError> {
    sqlx::query!(
        "UPDATE feature_flags SET enabled = $1, rollout_percentage = $2, updated_at = NOW() WHERE name = $3",
        update.enabled,
        update.rollout_percentage,
        flag_name.as_str()
    )
    .execute(db.as_ref())
    .await?;

    Ok(HttpResponse::Ok().json(json!({"updated": true})))
}
```

---

## 执行检查清单

### 第1周：架构诚实化

- [ ] **周一**: 决策 - 单体 vs 微服务（推荐单体）
  - [ ] 开会讨论30分钟
  - [ ] 记录决策和理由

- [ ] **周二-三**: 删除 Phase 5 过度设计
  - [ ] 从docker-compose.yml删除neo4j, es, ray, redis-cluster
  - [ ] 从Cargo.toml删除相关依赖
  - [ ] 验证应用仍能启动
  - [ ] 测试内存使用降低

- [ ] **周四**: 统一 iOS 项目
  - [ ] 比较两个项目，决定保留哪个
  - [ ] 合并有价值的代码
  - [ ] 删除重复项目
  - [ ] 验证编译和运行

- [ ] **周五**: 清理 TODO/FIXME
  - [ ] 转移95个TODO到GitHub Issues
  - [ ] 删除低优先级注释
  - [ ] 标记优先级
  - [ ] Commit改动

- [ ] **周末**: 测试和验证
  - [ ] cargo test 全部通过
  - [ ] 应用成功启动
  - [ ] 内存使用降低到预期
  - [ ] Commit汇总

### 第2周：质量提升

- [ ] **周一**: 建立 CI/CD 管线
  - [ ] 创建 .github/workflows/ci.yml
  - [ ] 配置质量检查 (fmt, clippy)
  - [ ] 配置测试运行
  - [ ] 首次GitHub Actions运行

- [ ] **周二**: 添加分布式追踪
  - [ ] 安装opentelemetry依赖
  - [ ] 创建telemetry模块
  - [ ] 在main.rs初始化
  - [ ] 启动Jaeger容器
  - [ ] 验证追踪显示

- [ ] **周三**: 统一配置管理
  - [ ] 创建config/文件夹结构
  - [ ] 创建Config结构体
  - [ ] 迁移环境变量
  - [ ] 更新密钥管理

- [ ] **周四-五**: 测试和集成
  - [ ] 所有config运行无错误
  - [ ] CI/CD管线绿灯
  - [ ] 追踪成功显示在Jaeger
  - [ ] Commit改动

### 第3周-4周：生产就绪

- [ ] **第3周**: 负载测试和优化
  - [ ] 安装压测工具(k6或wrk)
  - [ ] 创建测试脚本
  - [ ] 运行负载测试
  - [ ] 分析结果
  - [ ] 优化慢查询

- [ ] **第4周**: 监控和灰度
  - [ ] 创建Prometheus告警规则
  - [ ] 配置AlertManager
  - [ ] 实现特性开关
  - [ ] 创建特性开关管理API
  - [ ] 验证灰度发布流程

### 最终验收

- [ ] ✅ 所有质量检查通过
- [ ] ✅ 负载测试指标达标
- [ ] ✅ 监控告警正常工作
- [ ] ✅ 灰度发布可用
- [ ] ✅ 文档更新完整
- [ ] ✅ Team review通过
- [ ] ✅ Production环境验证

---

## 预期收益

### 完成后的状态

| 指标 | 改进前 | 改进后 | 收益 |
|------|--------|--------|------|
| **本地开发内存** | 32GB | 8GB | 节省75% |
| **Docker Compose启动时间** | 15分钟 | 5分钟 | 节省67% |
| **编译时间** | 13分钟 | 6分钟 | 节省54% |
| **支持的并发用户** | 5K | 50K | 提升10倍 |
| **部署失败恢复时间** | 手动 | 自动 | 从小时到秒 |
| **问题检测时间** | 人工 | 自动告警 | 从天到分钟 |
| **新功能上线时间** | 2周 | 2天 | 加速7倍 |

---

## 风险规避

### 如果第1优先级（第1周）失败怎么办?

```
原因1: 删除Phase 5服务后应用崩溃
→ 原因: 有地方还在用neo4j/es
→ 解决: 搜索代码找到依赖，改为不使用

原因2: iOS项目合并有冲突
→ 原因: 两个项目的差异太大
→ 解决: 保留两个项目的分支，稍后再合并

原因3: 删除服务后无法启动Docker
→ 原因: docker-compose依赖关系配置错
→ 解决: 检查docker-compose.yml的depends_on
```

### 如果第2优先级（第2周）失败怎么办?

```
原因1: CI/CD管线配置太复杂
→ 解决: 先简化，只做测试，再逐步添加检查

原因2: Jaeger追踪数据太多，查询慢
→ 解决: 配置采样率 (sample_rate = 0.1)

原因3: 配置迁移中的密钥丢失
→ 解决: 先在开发环境测试，再上生产
```

---

## 结论

这个详细计划涵盖了从架构修复到生产就绪的完整4周改进路径。

**关键是**: 逐周推进，不要试图一周内完成所有事情。

下一步：选择第1优先级的Step 1.1（做出单体vs微服务决策），今天就开始。


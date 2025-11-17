# Nova User Service - Backend

面向用户资料、社交关系与偏好管理的 Rust 微服务，基于 Actix-web + PostgreSQL + Redis 构建。

## 技术栈

- **Rust 1.76+** - 系统编程语言,内存安全和高性能
- **Actix-web 4.5** - 高性能异步 Web 框架
- **PostgreSQL 14** - 关系型数据库
- **Redis 7** - 内存缓存和会话存储
- **sqlx** - 编译时类型检查的 SQL 工具
- **Tokio** - 异步运行时
- **Docker & Docker Compose** - 容器化和本地开发环境

## 项目结构

```
backend/
├── Cargo.toml                 # Workspace 配置
├── Dockerfile                 # 多阶段生产构建
├── migrations/                # 数据库迁移文件
│   ├── 050_search_suggestions_and_history.sql
│   ├── 051_moderation_and_reports.sql
│   └── 052_user_core_tables.sql
└── user-service/
    ├── Cargo.toml            # 服务依赖配置
    └── src/
        ├── main.rs           # 应用程序入口
        ├── lib.rs            # 库入口
        ├── config.rs         # 配置管理
        ├── error.rs          # 错误处理
        ├── db/               # 数据库连接和迁移
        ├── handlers/         # HTTP 请求处理器
        │   ├── health.rs     # 健康检查端点
        │   ├── users.rs      # 用户资料
        │   ├── relationships.rs # 关注/粉丝
        │   ├── preferences.rs   # 偏好设置
        │   ├── moderation.rs    # 社群治理接口
        │   └── events.rs     # 事件回调
        ├── middleware/       # 中间件
        ├── models/           # 数据模型
        ├── services/         # 业务逻辑层
        └── utils/            # 工具函数
```

## 数据库 Schema

### 核心表结构

1. **users** - 用户账户信息
   - 字段: id, email, username, password_hash, email_verified, is_active, failed_login_attempts, locked_until, created_at, updated_at, last_login_at
   - 索引: email, username, is_active, created_at

2. **sessions** - 活跃用户会话
   - 字段: id, user_id, access_token_hash, expires_at, ip_address, user_agent, created_at
   - 索引: user_id, access_token_hash, expires_at

3. **refresh_tokens** - 长期刷新令牌
   - 字段: id, user_id, token_hash, expires_at, is_revoked, revoked_at, ip_address, user_agent, created_at
   - 索引: user_id, token_hash, expires_at, is_revoked

4. **email_verifications** - 邮箱验证令牌
   - 字段: id, user_id, email, token_hash, expires_at, is_used, used_at, created_at
   - 索引: user_id, token_hash, expires_at, is_used

5. **password_resets** - 密码重置令牌
   - 字段: id, user_id, token_hash, expires_at, is_used, used_at, ip_address, created_at
   - 索引: user_id, token_hash, expires_at, is_used

6. **auth_logs** - 认证审计日志
   - 字段: id, user_id, event_type, status, email, ip_address, user_agent, metadata(JSONB), created_at
   - 索引: user_id, event_type, status, created_at, ip_address, metadata(GIN)

## 快速开始

### 前置要求

- Rust 1.76+ (安装: https://rustup.rs/)
- Docker & Docker Compose
- PostgreSQL 14+ (仅本地开发)
- Redis 7+ (仅本地开发)

### 1. 克隆仓库并设置环境变量

```bash
# 克隆仓库
git clone <repository-url>
cd nova

# 复制环境变量示例文件
cp .env.example .env

# 编辑 .env 文件,修改必要的配置(特别是 JWT_SECRET)
nano .env
```

### 2. 使用 Docker Compose 启动服务(推荐)

```bash
# 启动所有服务(PostgreSQL + Redis + User Service)
docker-compose up -d

# 查看日志
docker-compose logs -f user-service

# 停止服务
docker-compose down

# 停止并删除卷(清空数据库)
docker-compose down -v
```

服务地址:
- **User Service**: http://localhost:8080
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379
- **MailHog Web UI**: http://localhost:8025 (邮件测试)

### 3. 本地开发(不使用 Docker)

```bash
# 启动 PostgreSQL 和 Redis
docker-compose up -d postgres redis

# 进入 backend 目录
cd backend

# 安装 sqlx-cli (用于数据库迁移)
cargo install sqlx-cli --no-default-features --features postgres

# 运行数据库迁移
sqlx migrate run --database-url postgresql://postgres:postgres@localhost:5432/nova_auth

# 构建项目
cargo build

# 运行开发服务器(带热重载)
cargo watch -x run

# 或者直接运行
cargo run
```

### 4. 验证服务运行

```bash
# 健康检查
curl http://localhost:8080/api/v1/health

# 预期响应
{
  "status": "ok",
  "version": "0.1.0",
  "database": "healthy"
}

# Readiness probe
curl http://localhost:8080/api/v1/health/ready

# Liveness probe
curl http://localhost:8080/api/v1/health/live
```

## API 端点

### 健康检查

- `GET /api/v1/health` - 综合健康检查(包含数据库状态)
- `GET /api/v1/health/ready` - Kubernetes readiness probe
- `GET /api/v1/health/live` - Kubernetes liveness probe

### 认证端点

认证能力已迁移至独立的 `auth-service`，请参见 `backend/auth-service/README.md` 和对应的 gRPC/HTTP 接口文档。

## 开发工具

### 常用 Cargo 命令

```bash
# 编译检查(无生成二进制)
cargo check

# 格式化代码
cargo fmt

# Lint 检查
cargo clippy

# 运行测试
cargo test

# 运行测试并显示输出
cargo test -- --nocapture

# 生成文档
cargo doc --open

# 构建生产版本
cargo build --release
```

## Centralized gRPC 客户端与 mTLS 配置

本仓库提供统一的 gRPC 客户端库 `backend/libs/grpc-clients`，集中管理连接、TLS/重试/超时与连接池。服务可通过 `GrpcConfig::from_env()` 与 `GrpcClientPool::new(&config).await` 初始化并注入使用。

环境变量（按服务 URL 与连接参数）：

- `GRPC_AUTH_SERVICE_URL`（默认 `http://auth-service:9080`）
- `GRPC_USER_SERVICE_URL`（默认 `http://user-service:9080`）
- `GRPC_MESSAGING_SERVICE_URL`（默认 `http://messaging-service:9080`）
- `GRPC_CONTENT_SERVICE_URL`（默认 `http://content-service:9080`）
- `GRPC_FEED_SERVICE_URL`（默认 `http://feed-service:9080`）
- `GRPC_SEARCH_SERVICE_URL`（默认 `http://search-service:9080`）
- `GRPC_MEDIA_SERVICE_URL`（默认 `http://media-service:9080`）
- `GRPC_NOTIFICATION_SERVICE_URL`（默认 `http://notification-service:9080`）
- `GRPC_STREAMING_SERVICE_URL`（默认 `http://streaming-service:9080`）
- `GRPC_CDN_SERVICE_URL`（默认 `http://cdn-service:9080`）
- `GRPC_EVENTS_SERVICE_URL`（默认 `http://events-service:9080`）
- `GRPC_VIDEO_SERVICE_URL`（默认 `http://video-service:9080`）

连接与 Keep-Alive：

- `GRPC_CONNECTION_TIMEOUT_SECS`（默认 10）
- `GRPC_REQUEST_TIMEOUT_SECS`（默认 30）
- `GRPC_MAX_CONCURRENT_STREAMS`（默认 1000）
- `GRPC_KEEPALIVE_INTERVAL_SECS`（默认 30）
- `GRPC_KEEPALIVE_TIMEOUT_SECS`（默认 10）
- `GRPC_ENABLE_CONNECTION_POOLING`（默认 true）
- `GRPC_CONNECTION_POOL_SIZE`（默认 10）

TLS/mTLS（可选，启用后将为所有客户端应用 TLS/mTLS）：

- `GRPC_TLS_ENABLED` = `true|1` 启用 TLS/mTLS（默认 false）
- `GRPC_TLS_DOMAIN_NAME` 覆盖 SNI/验证域名（可选）
- `GRPC_TLS_CA_CERT_PATH` CA 证书 PEM 路径（启用 TLS 建议设置）
- `GRPC_TLS_CLIENT_CERT_PATH` 客户端证书 PEM 路径（启用 mTLS 时必填）
- `GRPC_TLS_CLIENT_KEY_PATH` 客户端私钥 PEM 路径（启用 mTLS 时必填）

示例（本地开发 + mTLS）：

```bash
export GRPC_TLS_ENABLED=true
export GRPC_TLS_DOMAIN_NAME=internal.nova
export GRPC_TLS_CA_CERT_PATH=/etc/certs/ca.pem
export GRPC_TLS_CLIENT_CERT_PATH=/etc/certs/client.pem
export GRPC_TLS_CLIENT_KEY_PATH=/etc/certs/client.key
```

### 数据库管理

```bash
# 创建新迁移
sqlx migrate add <migration_name>

# 运行迁移
sqlx migrate run

# 回滚上一个迁移
sqlx migrate revert

# 查看迁移状态
sqlx migrate info
```

### Docker 命令

```bash
# 构建 Docker 镜像
docker build -t nova-user-service:latest ./backend

# 运行容器
docker run -p 8080:8080 --env-file .env nova-user-service:latest

# 查看容器日志
docker logs -f <container_id>

# 进入容器 shell
docker exec -it <container_id> /bin/bash
```

## 配置说明

所有配置通过环境变量管理,参考 `.env.example` 文件:

### 关键配置项

- **APP_ENV**: 运行环境 (development/production)
- **DATABASE_URL**: PostgreSQL 连接字符串
- **REDIS_URL**: Redis 连接字符串
- **JWT_SECRET**: JWT 签名密钥 (生产环境必须修改,至少 32 字符)
- **SMTP_***: SMTP 邮件服务器配置

### 生产环境配置

⚠️ **安全警告**: 生产环境必须修改以下配置:

```bash
# 使用强随机密钥(至少 32 字符)
JWT_SECRET=$(openssl rand -base64 32)

# 使用真实 SMTP 服务器
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password

# 设置合适的连接池大小
DATABASE_MAX_CONNECTIONS=10
REDIS_POOL_SIZE=20

# 生产环境日志级别
RUST_LOG=info,actix_web=info
```

## 性能优化

### Docker 构建优化

Dockerfile 使用多阶段构建和依赖缓存优化:

1. **Builder stage**: 单独缓存依赖层,仅源代码变更时重新编译
2. **Runtime stage**: 最小化镜像大小,仅包含运行时依赖
3. **非 root 用户**: 安全容器执行

### 数据库优化

- 所有外键和常用查询字段已建立索引
- 使用 PostgreSQL CHECK 约束确保数据完整性
- 触发器自动更新 `updated_at` 时间戳
- JSONB 字段使用 GIN 索引支持高效查询

### Redis 缓存策略

- 使用连接管理器复用连接
- LRU 淘汰策略(maxmemory-policy allkeys-lru)
- AOF 持久化保证数据安全

## 测试

```bash
# 运行所有测试
cargo test

# 运行特定测试
cargo test test_name

# 生成测试覆盖率报告
cargo tarpaulin --out Html

# 集成测试(需要数据库)
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/nova_auth_test cargo test
```

## CI/CD

GitHub Actions 工作流包含:

1. **Lint**: 代码格式化检查 + Clippy 静态分析
2. **Build & Test**: 编译 + 单元测试 + 集成测试
3. **Security Audit**: cargo-audit + cargo-deny 安全扫描
4. **Docker Build**: 多架构镜像构建和推送到 Docker Hub
5. **Deploy**: 部署到目标环境(待配置)

### 触发条件

- Push 到 `main` 或 `develop` 分支
- Pull Request 到 `main` 或 `develop` 分支

### 所需 Secrets

在 GitHub 仓库设置中添加:

- `DOCKER_USERNAME` - Docker Hub 用户名
- `DOCKER_PASSWORD` - Docker Hub 访问令牌

## 故障排查

### 数据库连接失败

```bash
# 检查 PostgreSQL 是否运行
docker-compose ps postgres

# 查看 PostgreSQL 日志
docker-compose logs postgres

# 手动连接测试
psql postgresql://postgres:postgres@localhost:5432/nova_auth
```

### Redis 连接失败

```bash
# 检查 Redis 是否运行
docker-compose ps redis

# 测试 Redis 连接
redis-cli -h localhost -p 6379 -a redis123 ping
```

### 编译错误

```bash
# 清理构建缓存
cargo clean

# 更新依赖
cargo update

# 重新构建
cargo build
```

## 下一步计划

Phase 0 已完成基础设施搭建,接下来将实现:

- **Phase 1**: 用户注册和邮箱验证
- **Phase 2**: 用户登录和 JWT 认证
- **Phase 3**: 密码重置和账户管理
- **Phase 4**: 会话管理和令牌刷新
- **Phase 5**: 速率限制和安全加固
- **Phase 6**: 审计日志和监控

## 许可证

MIT License

## 联系方式

- 团队: Nova Team
- Email: team@nova.dev

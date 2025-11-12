# Nova Backend - Deployment Guide

**Version:** 2.0
**Last Updated:** 2025-11-12
**Phase:** Production-Ready V2 Architecture

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Environment Configuration](#environment-configuration)
4. [Local Development Deployment](#local-development-deployment)
5. [Kubernetes Deployment](#kubernetes-deployment)
6. [Canary Release Strategy](#canary-release-strategy)
7. [Database Migrations](#database-migrations)
8. [Monitoring Setup](#monitoring-setup)
9. [Troubleshooting](#troubleshooting)
10. [Service Deployment Order](#service-deployment-order)

---

## Prerequisites

Nova Backend 需要以下工具和基础设施来部署和运行所有 15 个微服务。

### Required Tools

确保安装以下工具及版本：

- **Rust** 1.76+ (本地开发和构建)
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  rustup update
  rustc --version  # Should be 1.76 or higher
  ```

- **Docker** 24.0+ 和 **Docker Compose** 2.20+
  ```bash
  docker --version
  docker compose version
  ```

- **Kubernetes** 1.27+ (生产环境)
  - **kubectl** 1.27+
  - **Helm** 3.10+ (可选，用于 Prometheus/Grafana)
  - **kustomize** 5.0+ (内置于 kubectl)

- **PostgreSQL** 14+ client tools
  ```bash
  psql --version
  ```

- **sqlx-cli** 0.7+ (数据库迁移工具)
  ```bash
  cargo install sqlx-cli --no-default-features --features postgres
  sqlx --version
  ```

### Infrastructure Dependencies

Nova Backend 依赖以下基础设施组件：

| 组件 | 版本要求 | 用途 | 服务依赖 |
|------|---------|------|----------|
| **PostgreSQL** | 14+ | 主数据库 | 所有服务 |
| **Redis** | 7+ | 缓存、会话、Pub/Sub | 所有服务 |
| **Kafka** | 3.5+ | 事件流 | analytics-service, notification-service |
| **ClickHouse** | 23.11+ | 分析数据库 | analytics-service, ranking-service |
| **Neo4j** | 5.0+ | 图数据库 | graph-service, feed-service |
| **Elasticsearch** | 8.11+ | 全文搜索 | search-service |
| **AWS S3** | - | 对象存储 | media-service |

### Development Environment Setup

完整的本地开发环境设置：

```bash
# 1. 克隆仓库
git clone https://github.com/your-org/nova.git
cd nova/backend

# 2. 安装 Rust 工具链
rustup install 1.76
rustup default 1.76

# 3. 安装 protobuf 编译器 (gRPC 必需)
# macOS
brew install protobuf

# Ubuntu/Debian
sudo apt install protobuf-compiler

# 4. 安装 sqlx-cli
cargo install sqlx-cli --no-default-features --features postgres

# 5. 验证安装
cargo --version
protoc --version
sqlx --version
```

---

## Architecture Overview

Nova Backend 采用微服务架构，共 **15 个核心服务** + **1 个 API Gateway**。

### Services

| 服务名称 | HTTP Port | gRPC Port | 数据库 | 用途 |
|---------|-----------|-----------|-------|------|
| **identity-service** | 8010 | 9010 | PostgreSQL | 认证、授权、JWT、OAuth |
| **user-service** | 8011 | 9011 | PostgreSQL | 用户资料 |
| **content-service** | 8012 | 9012 | PostgreSQL | 帖子、评论 |
| **social-service** | 8013 | 9013 | PostgreSQL | 关注、点赞、动态流 |
| **media-service** | 8014 | 9014 | PostgreSQL + S3 | 媒体上传、视频转码、CDN、直播 |
| **notification-service** | 8015 | 9015 | PostgreSQL | 推送通知 (APNs, FCM) |
| **search-service** | 8016 | 9016 | Elasticsearch | 全文搜索、建议 |
| **analytics-service** | 8017 | 9017 | ClickHouse + Kafka | 事件总线、分析 |
| **graph-service** | 8018 | 9018 | Neo4j | 社交图谱 (关注/屏蔽/静音) |
| **feed-service** | 8019 | 9019 | Redis + PostgreSQL | 推荐算法、Feed 生成 |
| **feature-store** | 8020 | 9020 | Redis + ClickHouse | 特征存储 (ML) |
| **ranking-service** | 8021 | 9021 | ClickHouse | 排序服务 |
| **realtime-chat-service** | 8022 | 9022 | PostgreSQL | WebSocket、E2EE 消息 |
| **trust-safety-service** | 8023 | 9023 | PostgreSQL | 内容审核、信任安全 |
| **graphql-gateway** | 8000 | - | - | GraphQL API 网关 |

### Port Convention

**规则:** `gRPC_PORT = HTTP_PORT + 1000`

示例:
- `identity-service` HTTP: 8010 → gRPC: 9010
- `user-service` HTTP: 8011 → gRPC: 9011

### Service Dependencies Graph

```
┌────────────────────────────────────────────────────────────┐
│  Infrastructure Layer (External Dependencies)              │
│  ──────────────────────────────────────────               │
│  • PostgreSQL (14+ with pgBouncer connection pooling)      │
│  • Redis (7+ cluster mode, Pub/Sub for cache invalidation)│
│  • Kafka (3.5+ for event streaming)                        │
│  • ClickHouse (23.11+ for analytics)                       │
│  • Neo4j (5.0+ for graph relationships)                    │
│  • Elasticsearch (8.11+ for search)                        │
│  • AWS S3 (media storage)                                  │
│  • AWS Secrets Manager (secret management)                 │
└────────────────────────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────────┐
│  Core Services Layer (15 microservices)                    │
│  ──────────────────────────                                │
│  • identity-service (authentication, JWT validation)       │
│  • user-service (user profiles)                            │
│  • content-service (posts, comments)                       │
│  • social-service (follows, likes, feeds)                  │
│  • media-service (uploads, transcoding, CDN, streaming)    │
│  • notification-service (push notifications)               │
│  • search-service (full-text search)                       │
│  • analytics-service (event bus, analytics)                │
│  • graph-service (social graph via Neo4j)                  │
│  • feed-service (recommendation engine)                    │
│  • feature-store (ML feature serving)                      │
│  • ranking-service (content ranking)                       │
│  • realtime-chat-service (WebSocket, E2EE)                 │
│  • trust-safety-service (content moderation)               │
│  ──────────────────────────                                │
│  Communication:                                            │
│  • HTTP REST APIs (public endpoints)                       │
│  • gRPC APIs (inter-service communication)                 │
│  • Health checks (/api/v1/health)                          │
│  • Metrics (/metrics for Prometheus)                       │
└────────────────────────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────────┐
│  API Gateway Layer                                         │
│  ──────────────────────────────────────────               │
│  • graphql-gateway (unified GraphQL API, persisted queries)│
│  • Authentication middleware (JWT validation)              │
│  • Rate limiting (governor)                                │
│  • Request tracing (correlation IDs)                       │
└────────────────────────────────────────────────────────────┘
                          ↓
┌────────────────────────────────────────────────────────────┐
│  Client Applications                                       │
│  ──────────────────────────────────────────               │
│  • iOS App (Swift)                                         │
│  • Android App (Kotlin)                                    │
│  • Web App (React)                                         │
└────────────────────────────────────────────────────────────┘
```

### Shared Libraries

所有服务使用以下共享库：

- `libs/db-pool` - PostgreSQL 连接池
- `libs/resilience` - 超时、熔断器、重试
- `libs/grpc-clients` - gRPC 客户端池
- `libs/grpc-tls` - gRPC mTLS 配置
- `libs/grpc-health` - gRPC 健康检查
- `libs/aws-secrets` - AWS Secrets Manager 集成
- `libs/transactional-outbox` - 事务发件箱模式
- `libs/idempotent-consumer` - 幂等消费者
- `libs/cache-invalidation` - Redis Pub/Sub 缓存失效

---

## Environment Configuration

### 1. Copy Environment Template

```bash
cd backend
cp .env.example .env
```

### 2. Critical Configuration (Must Change)

#### JWT Keys (Production Only)

Generate RSA key pair for JWT signing:

```bash
# Generate private key
openssl genpkey -algorithm RSA -out jwt_private.pem -pkeyopt rsa_keygen_bits:2048

# Extract public key
openssl rsa -pubout -in jwt_private.pem -out jwt_public.pem

# Convert to single-line format for .env
JWT_PRIVATE_KEY_PEM=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' jwt_private.pem)
JWT_PUBLIC_KEY_PEM=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' jwt_public.pem)

# Add to .env
echo "JWT_PRIVATE_KEY_PEM=\"${JWT_PRIVATE_KEY_PEM}\"" >> .env
echo "JWT_PUBLIC_KEY_PEM=\"${JWT_PUBLIC_KEY_PEM}\"" >> .env
```

**Alternative:** Use file paths (recommended for production):

```bash
JWT_PRIVATE_KEY_PATH=/etc/secrets/jwt_private.pem
JWT_PUBLIC_KEY_PATH=/etc/secrets/jwt_public.pem
```

#### Database URL

```bash
# Development
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/nova

# Staging
DATABASE_URL=postgresql://nova_user:STRONG_PASSWORD@staging-db.internal:5432/nova

# Production
DATABASE_URL=postgresql://nova_user:STRONG_PASSWORD@prod-db-primary.internal:5432/nova
```

#### AWS S3 Configuration

```bash
AWS_S3_BUCKET=nova-media-prod
AWS_S3_REGION=us-east-1
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

#### SMTP Configuration

```bash
# Production (SendGrid example)
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=SG....
SMTP_FROM_EMAIL=noreply@nova.app

# Development (MailHog)
SMTP_HOST=localhost
SMTP_PORT=1025
```

### 3. Environment-Specific Overrides

#### Development (.env.dev)

```bash
APP_ENV=development
LOG_LEVEL=debug
DEBUG_SQL_QUERIES=true
DISABLE_AUTH=false  # Keep auth enabled even in dev

# Use local services
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/nova
REDIS_URL=redis://localhost:6379
CLICKHOUSE_URL=http://localhost:8123
KAFKA_BROKERS=localhost:9092
```

#### Staging (.env.staging)

```bash
APP_ENV=staging
LOG_LEVEL=info
DEBUG_SQL_QUERIES=false

# Use staging infrastructure
DATABASE_URL=postgresql://nova_user:STAGING_PASS@staging-db.internal:5432/nova
REDIS_URL=redis://staging-redis.internal:6379
CLICKHOUSE_URL=http://staging-clickhouse.internal:8123
KAFKA_BROKERS=staging-kafka-1.internal:9092,staging-kafka-2.internal:9092

# Staging S3 bucket
AWS_S3_BUCKET=nova-media-staging
```

#### Production (.env.prod)

```bash
APP_ENV=production
LOG_LEVEL=info
DEBUG_SQL_QUERIES=false

# Use production infrastructure (managed)
DATABASE_URL=postgresql://nova_user:PROD_PASS@prod-db-primary.internal:5432/nova
REDIS_URL=redis://prod-redis-cluster.internal:6379
CLICKHOUSE_URL=http://prod-clickhouse-cluster.internal:8123
KAFKA_BROKERS=prod-kafka-1.internal:9092,prod-kafka-2.internal:9092,prod-kafka-3.internal:9092

# Production S3 bucket
AWS_S3_BUCKET=nova-media-prod

# Enable connection pooling
DATABASE_MAX_CONNECTIONS=20
REDIS_POOL_SIZE=50
GRPC_CONNECTION_POOL_SIZE=20
```

---

## Local Development Deployment

本地开发部署流程分为 4 个步骤：启动基础设施、运行迁移、构建服务、验证部署。

### Step 1: 配置环境变量

```bash
cd /Users/proerror/Documents/nova/backend

# 复制环境变量模板
cp .env.example .env

# 编辑 .env，设置开发环境
# 关键配置：
# - ENVIRONMENT=development
# - DATABASE_URL=postgresql://postgres:postgres@localhost:5432/nova
# - REDIS_URL=redis://localhost:6379
# - LOG_LEVEL=debug
```

### Step 2: 启动基础设施服务

使用 Docker Compose 启动所有基础设施依赖：

```bash
# 启动核心基础设施 (PostgreSQL, Redis, Kafka, ClickHouse, Neo4j, Elasticsearch)
docker compose -f docker-compose.prod.yml up -d \
  postgres \
  redis \
  kafka \
  clickhouse \
  neo4j \
  elasticsearch

# 等待健康检查通过 (约 30-60 秒)
watch -n 5 'docker compose -f docker-compose.prod.yml ps'
```

预期输出（所有服务 STATUS 为 `Up (healthy)`）：

```
NAME                  STATUS             PORTS
nova-postgres         Up (healthy)       0.0.0.0:5432->5432/tcp
nova-redis            Up (healthy)       0.0.0.0:6379->6379/tcp
nova-kafka            Up (healthy)       0.0.0.0:9092->9092/tcp
nova-clickhouse       Up (healthy)       0.0.0.0:8123->8123/tcp, 0.0.0.0:9000->9000/tcp
nova-neo4j            Up (healthy)       0.0.0.0:7474->7474/tcp, 0.0.0.0:7687->7687/tcp
nova-elasticsearch    Up (healthy)       0.0.0.0:9200->9200/tcp
```

**验证基础设施连接：**

```bash
# PostgreSQL
psql postgresql://postgres:postgres@localhost:5432/nova -c "SELECT version();"

# Redis
redis-cli ping  # Should return "PONG"

# ClickHouse
curl http://localhost:8123/?query=SELECT%201

# Neo4j (Web UI)
open http://localhost:7474  # Default credentials: neo4j/password

# Elasticsearch
curl http://localhost:9200
```

### Step 3: 运行数据库迁移

```bash
# 创建数据库 (如果不存在)
sqlx database create --database-url postgresql://postgres:postgres@localhost:5432/nova

# 运行所有迁移
sqlx migrate run --database-url postgresql://postgres:postgres@localhost:5432/nova

# 验证迁移状态
sqlx migrate info --database-url postgresql://postgres:postgres@localhost:5432/nova
```

预期输出：

```
Applied migrations:
  20250101000000 create_users_table (applied)
  20250101000001 create_posts_table (applied)
  ... (显示所有已应用的迁移)
```

### Step 4: 构建并运行服务

**推荐方式 A: Docker Compose (所有 15 个服务)**

使用 Dockerfile.template 构建所有服务：

```bash
# 构建所有服务镜像
./scripts/build-all-services.sh

# 或手动构建单个服务
docker build \
  --build-arg SERVICE_NAME=identity-service \
  -f Dockerfile.template \
  -t nova-identity-service:dev \
  .

# 启动所有服务
docker compose -f docker-compose.prod.yml up -d
```

**方式 B: Cargo (单个服务开发调试)**

适用于开发单个服务时：

```bash
# 运行 identity-service (认证服务)
cd identity-service
cargo run

# 运行 user-service (用户服务)
cd user-service
cargo run

# 运行时指定环境变量
HTTP_PORT=8011 GRPC_PORT=9011 cargo run
```

**方式 C: 混合模式 (基础设施 + 选择性服务)**

在 Docker 中运行基础设施和部分服务，本地 Cargo 运行正在开发的服务：

```bash
# 启动基础设施 + 稳定服务
docker compose -f docker-compose.prod.yml up -d \
  postgres redis kafka clickhouse neo4j elasticsearch \
  identity-service user-service content-service

# 本地运行正在开发的服务
cd feed-service
cargo run
```

### Step 5: 验证部署

**健康检查所有服务：**

```bash
# 使用循环检查所有服务健康状态
for port in 8010 8011 8012 8013 8014 8015 8016 8017 8018 8019 8020 8021 8022 8023 8000; do
  service_name=$(curl -s http://localhost:$port/api/v1/health 2>/dev/null | jq -r '.service // "unknown"')
  status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/api/v1/health 2>/dev/null)

  if [ "$status" = "200" ]; then
    echo "✅ Port $port ($service_name): Healthy"
  else
    echo "❌ Port $port: Unhealthy (HTTP $status)"
  fi
done
```

**预期输出：**

```
✅ Port 8010 (identity-service): Healthy
✅ Port 8011 (user-service): Healthy
✅ Port 8012 (content-service): Healthy
✅ Port 8013 (social-service): Healthy
✅ Port 8014 (media-service): Healthy
✅ Port 8015 (notification-service): Healthy
✅ Port 8016 (search-service): Healthy
✅ Port 8017 (analytics-service): Healthy
✅ Port 8018 (graph-service): Healthy
✅ Port 8019 (feed-service): Healthy
✅ Port 8020 (feature-store): Healthy
✅ Port 8021 (ranking-service): Healthy
✅ Port 8022 (realtime-chat-service): Healthy
✅ Port 8023 (trust-safety-service): Healthy
✅ Port 8000 (graphql-gateway): Healthy
```

**测试 GraphQL Gateway：**

```bash
# GraphQL introspection query
curl -X POST http://localhost:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __schema { types { name } } }"}' | jq

# 测试用户注册 (通过 identity-service)
curl -X POST http://localhost:8010/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "SecurePass123!",
    "username": "testuser"
  }' | jq
```

**查看服务日志：**

```bash
# Docker Compose 日志
docker compose -f docker-compose.prod.yml logs -f identity-service

# Cargo 运行时日志 (自动输出到终端)
# 设置 RUST_LOG 环境变量调整日志级别
RUST_LOG=debug cargo run
```

---

## Kubernetes Deployment

Kubernetes 部署适用于 Staging 和 Production 环境，使用 Kustomize 管理不同环境的配置。

### Prerequisites

- Kubernetes 集群 1.27+
- kubectl 已配置正确的 context
- Container Registry 访问权限 (Docker Hub, AWS ECR, GCP GCR, etc.)
- Kustomize 5.0+ (kubectl 内置)

### Step 1: 构建 Docker 镜像

使用统一的 `Dockerfile.template` 构建所有 15 个服务：

```bash
cd /Users/proerror/Documents/nova/backend

# 设置容器镜像仓库和版本标签
export REGISTRY="your-registry.example.com"  # 替换为实际仓库地址
export VERSION="v2.0.0"  # 语义化版本号
export ENV="staging"  # staging 或 production

# 定义所有服务列表
SERVICES=(
  "identity-service"
  "user-service"
  "content-service"
  "social-service"
  "media-service"
  "notification-service"
  "search-service"
  "analytics-service"
  "graph-service"
  "feed-service"
  "feature-store"
  "ranking-service"
  "realtime-chat-service"
  "trust-safety-service"
  "graphql-gateway"
)

# 构建所有服务镜像
for service in "${SERVICES[@]}"; do
  echo "========================================="
  echo "Building $service:$VERSION..."
  echo "========================================="

  docker build \
    --build-arg SERVICE_NAME=$service \
    --platform linux/amd64 \
    -f Dockerfile.template \
    -t nova-$service:$VERSION \
    -t nova-$service:latest \
    -t $REGISTRY/nova-$service:$VERSION \
    -t $REGISTRY/nova-$service:$ENV \
    .

  if [ $? -ne 0 ]; then
    echo "❌ Failed to build $service"
    exit 1
  fi

  echo "✅ Successfully built $service"
done

echo ""
echo "========================================="
echo "All services built successfully!"
echo "========================================="
```

**验证构建的镜像：**

```bash
# 列出所有 Nova 镜像
docker images | grep nova-

# 检查镜像大小 (应该 <200MB)
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep nova-
```

### Step 2: 推送镜像到容器仓库

```bash
# 登录容器仓库
# Docker Hub
docker login

# AWS ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REGISTRY

# GCP GCR
gcloud auth configure-docker

# 推送所有镜像
for service in "${SERVICES[@]}"; do
  echo "Pushing $service:$VERSION..."

  docker push $REGISTRY/nova-$service:$VERSION
  docker push $REGISTRY/nova-$service:$ENV

  if [ $? -ne 0 ]; then
    echo "❌ Failed to push $service"
    exit 1
  fi

  echo "✅ Successfully pushed $service"
done

echo ""
echo "========================================="
echo "All images pushed to $REGISTRY"
echo "========================================="
```

### Step 3: 配置 Kubernetes Secrets

**重要：不要将 secrets 提交到 Git！**

```bash
# 切换到目标集群 context
kubectl config use-context staging-cluster  # 或 production-cluster

# 创建命名空间
kubectl create namespace nova-backend --dry-run=client -o yaml | kubectl apply -f -

# 从 .env 文件创建 Secret
kubectl create secret generic nova-backend-secrets \
  -n nova-backend \
  --from-env-file=.env.staging \
  --dry-run=client -o yaml | kubectl apply -f -

# 创建 AWS Secrets Manager credentials (如果使用 AWS)
kubectl create secret generic aws-secrets-manager \
  -n nova-backend \
  --from-literal=AWS_REGION=us-east-1 \
  --from-literal=AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  --from-literal=AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  --dry-run=client -o yaml | kubectl apply -f -

# 创建 Docker Registry pull secret
kubectl create secret docker-registry regcred \
  -n nova-backend \
  --docker-server=$REGISTRY \
  --docker-username=$DOCKER_USER \
  --docker-password=$DOCKER_PASS \
  --docker-email=$DOCKER_EMAIL \
  --dry-run=client -o yaml | kubectl apply -f -

# 验证 Secrets
kubectl get secrets -n nova-backend
```

### Step 4: 部署到 Kubernetes

使用 Kustomize 部署所有服务到 Staging 或 Production 环境：

```bash
# Staging 部署
kubectl apply -k k8s/infrastructure/overlays/staging/

# Production 部署 (谨慎操作！)
kubectl apply -k k8s/infrastructure/overlays/prod/

# 等待所有 Deployment rollout 完成
kubectl rollout status deployment -n nova-backend --timeout=10m
```

**监控部署进度：**

```bash
# 实时查看 Pod 状态
watch kubectl get pods -n nova-backend

# 查看所有 Deployment 状态
kubectl get deployments -n nova-backend -o wide

# 查看 Service 端点
kubectl get svc -n nova-backend

# 查看 Ingress (如果配置了)
kubectl get ingress -n nova-backend
```

### Step 5: 验证部署

**健康检查：**

```bash
# 使用 port-forward 测试服务健康检查
kubectl port-forward -n nova-backend svc/identity-service 8010:8010 &
curl http://localhost:8010/api/v1/health | jq

# 测试所有服务
for service in "${SERVICES[@]}"; do
  port=$(kubectl get svc -n nova-backend $service -o jsonpath='{.spec.ports[0].port}')
  kubectl port-forward -n nova-backend svc/$service $port:$port > /dev/null 2>&1 &
  PID=$!

  sleep 2
  status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/api/v1/health)

  if [ "$status" = "200" ]; then
    echo "✅ $service: Healthy"
  else
    echo "❌ $service: Unhealthy (HTTP $status)"
  fi

  kill $PID 2>/dev/null
done
```

**查看日志：**

```bash
# 查看特定服务日志
kubectl logs -n nova-backend -l app=identity-service --tail=100 -f

# 查看所有服务日志
kubectl logs -n nova-backend --all-containers=true --tail=50

# 查看 Pod 事件
kubectl describe pod -n nova-backend <pod-name>
```

**资源使用情况：**

```bash
# 查看 Pod CPU 和内存使用
kubectl top pods -n nova-backend

# 查看 Node 资源使用
kubectl top nodes
```

---

## Canary Release Strategy

生产环境部署使用金丝雀发布 (Canary Release) 策略，逐步推出新版本以最小化风险。

### Canary 发布原则

**目标：** 在保证服务可用性的前提下，逐步将流量切换到新版本。

**三阶段策略：**
1. **Phase 1 (5% 流量)** → 监控 15 分钟 → 无问题继续
2. **Phase 2 (50% 流量)** → 监控 30 分钟 → 无问题继续
3. **Phase 3 (100% 流量)** → 完全发布 → 删除旧版本

**自动回滚触发条件：**
- 错误率 > 1%
- P95 延迟 > 500ms
- 5xx 错误增加 > 10%
- Pod crash loop

### Prerequisites

在生产部署前，确保以下条件满足：

- ✅ 所有服务通过集成测试
- ✅ 数据库迁移在 Staging 环境验证通过
- ✅ Secrets 存储在安全保管库 (AWS Secrets Manager)
- ✅ 监控和告警已配置 (Prometheus + Grafana + AlertManager)
- ✅ 回滚计划已准备
- ✅ On-call 人员已通知
- ✅ 变更窗口已预约 (通常在低流量时段)

### Phase 1: Canary Deployment (5% Traffic)

**Step 1: 创建 Canary Deployment**

```bash
# 设置版本号
export NEW_VERSION="v2.0.1"
export OLD_VERSION="v2.0.0"

# 为每个服务创建 Canary Deployment (5% 副本数)
# 假设生产环境每个服务有 20 个副本，Canary 阶段启动 1 个新版本副本

for service in "${SERVICES[@]}"; do
  echo "Deploying canary for $service..."

  # 创建 Canary Deployment (1 replica = 5% of 20)
  kubectl create deployment ${service}-canary \
    -n nova-backend \
    --image=$REGISTRY/nova-$service:$NEW_VERSION \
    --replicas=1 \
    --dry-run=client -o yaml | kubectl apply -f -

  # 使用相同的 Service 选择器，让流量分流到新旧版本
  kubectl patch deployment ${service}-canary -n nova-backend -p '{
    "spec": {
      "template": {
        "metadata": {
          "labels": {
            "app": "'$service'",
            "version": "'$NEW_VERSION'",
            "canary": "true"
          }
        }
      }
    }
  }'

  echo "✅ Canary deployed for $service"
done
```

**Step 2: 监控 Canary 副本 (15 分钟)**

```bash
# 实时监控 Canary Pods
watch kubectl get pods -n nova-backend -l canary=true

# 查看 Canary 日志
kubectl logs -n nova-backend -l canary=true --tail=100 -f

# 检查 Prometheus 指标
# - Error rate: rate(http_requests_total{status=~"5.."}[5m])
# - Latency P95: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
# - Request count: sum(rate(http_requests_total[5m])) by (service)
```

**Step 3: 验证 Canary 健康状态**

```bash
# 检查 Canary Pods 是否全部 Running
CANARY_PODS=$(kubectl get pods -n nova-backend -l canary=true --no-headers | wc -l)
CANARY_READY=$(kubectl get pods -n nova-backend -l canary=true --field-selector=status.phase=Running --no-headers | wc -l)

if [ "$CANARY_PODS" -eq "$CANARY_READY" ]; then
  echo "✅ All canary pods are healthy"
else
  echo "❌ Some canary pods are unhealthy ($CANARY_READY/$CANARY_PODS ready)"
  exit 1
fi

# 测试 Canary 版本的健康检查
for service in "${SERVICES[@]}"; do
  canary_pod=$(kubectl get pods -n nova-backend -l app=$service,canary=true -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n nova-backend $canary_pod -- curl -f http://localhost:8080/api/v1/health || echo "❌ $service canary health check failed"
done
```

**决策点：**
- ✅ **继续 Phase 2** - 如果错误率 <1%，延迟正常，无崩溃
- ❌ **回滚** - 如果任何监控指标异常

### Phase 2: Scale to 50% Traffic

**Step 1: 扩展 Canary 副本到 50%**

```bash
# 每个服务从 1 个 Canary 副本扩展到 10 个 (50% of 20)
for service in "${SERVICES[@]}"; do
  echo "Scaling canary for $service to 50%..."

  kubectl scale deployment ${service}-canary -n nova-backend --replicas=10

  echo "✅ Scaled $service canary to 10 replicas"
done

# 等待所有 Canary Pods 就绪
kubectl wait --for=condition=available --timeout=5m -n nova-backend deployment -l canary=true
```

**Step 2: 监控 50% 流量 (30 分钟)**

```bash
# 监控流量分布
kubectl get pods -n nova-backend -l app=identity-service -o wide

# 查看 Prometheus 指标对比
# Old version: sum(rate(http_requests_total{version="v2.0.0"}[5m])) by (service)
# New version: sum(rate(http_requests_total{version="v2.0.1"}[5m])) by (service)
```

**Step 3: 性能对比分析**

```bash
# 使用 PromQL 查询比较新旧版本性能
# P95 latency comparison:
#   Old: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{version="v2.0.0"}[5m]))
#   New: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{version="v2.0.1"}[5m]))

# Error rate comparison:
#   Old: sum(rate(http_requests_total{version="v2.0.0",status=~"5.."}[5m])) / sum(rate(http_requests_total{version="v2.0.0"}[5m]))
#   New: sum(rate(http_requests_total{version="v2.0.1",status=~"5.."}[5m])) / sum(rate(http_requests_total{version="v2.0.1"}[5m]))
```

**决策点：**
- ✅ **继续 Phase 3** - 新版本性能 >= 旧版本
- ❌ **回滚** - 新版本性能下降或错误率上升

### Phase 3: Full Rollout (100% Traffic)

**Step 1: 更新主 Deployment 到新版本**

```bash
# 更新所有服务的主 Deployment 到新版本
for service in "${SERVICES[@]}"; do
  echo "Updating main deployment for $service to $NEW_VERSION..."

  kubectl set image deployment/$service \
    -n nova-backend \
    $service=$REGISTRY/nova-$service:$NEW_VERSION

  echo "✅ Updated $service main deployment"
done

# 等待 Rollout 完成
kubectl rollout status deployment -n nova-backend --timeout=10m
```

**Step 2: 删除 Canary Deployment**

```bash
# 删除所有 Canary Deployments
for service in "${SERVICES[@]}"; do
  kubectl delete deployment ${service}-canary -n nova-backend

  echo "✅ Deleted canary deployment for $service"
done
```

**Step 3: 验证生产部署**

```bash
# 检查所有 Pods 运行新版本
kubectl get pods -n nova-backend -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' | grep $NEW_VERSION

# 测试生产环境健康检查 (通过 LoadBalancer/Ingress)
curl https://api.nova.app/api/v1/health | jq

# 验证所有服务版本
for service in "${SERVICES[@]}"; do
  version=$(curl -s https://api.nova.app/api/v1/${service}/version | jq -r '.version')
  echo "$service: $version"
done
```

### Rollback Procedure (紧急回滚)

如果在任何阶段检测到问题，立即执行回滚：

```bash
# 快速回滚到上一个稳定版本
for service in "${SERVICES[@]}"; do
  echo "Rolling back $service to $OLD_VERSION..."

  # 回滚主 Deployment
  kubectl set image deployment/$service \
    -n nova-backend \
    $service=$REGISTRY/nova-$service:$OLD_VERSION

  # 删除 Canary Deployment (如果存在)
  kubectl delete deployment ${service}-canary -n nova-backend 2>/dev/null || true

  echo "✅ Rolled back $service"
done

# 等待回滚完成
kubectl rollout status deployment -n nova-backend --timeout=5m

# 验证回滚成功
kubectl get pods -n nova-backend -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' | grep $OLD_VERSION
```

**回滚后行动：**
1. 通知团队回滚已完成
2. 收集错误日志和指标
3. 进行根因分析 (Root Cause Analysis)
4. 修复问题后重新测试
5. 安排下次发布窗口

---

## Database Migrations

### Migration Strategy

**Rule:** All migrations must be **backward-compatible** (zero-downtime).

**Safe Patterns:**
- ✅ Add new columns (with default values)
- ✅ Add new tables
- ✅ Add new indexes (CONCURRENTLY in PostgreSQL)
- ❌ Rename columns (requires multi-step migration)
- ❌ Drop columns (requires multi-step migration)

### Running Migrations

**Development:**

```bash
sqlx migrate run --database-url $DATABASE_URL
```

**Staging/Production:**

```bash
# Dry-run (check what will run)
sqlx migrate info --database-url $DATABASE_URL

# Run migrations
sqlx migrate run --database-url $DATABASE_URL

# Verify
psql $DATABASE_URL -c "SELECT * FROM _sqlx_migrations ORDER BY version DESC LIMIT 5;"
```

### Migration Rollback

```bash
# Revert last migration
sqlx migrate revert --database-url $DATABASE_URL

# Revert specific version
sqlx migrate revert --database-url $DATABASE_URL --target-version 20250101000000
```

---

## Monitoring Setup

### Prometheus

**Deploy Prometheus:**

```bash
kubectl apply -f monitoring/prometheus/prometheus-config.yaml
kubectl apply -f monitoring/prometheus/prometheus-deployment.yaml
```

**Verify scraping:**

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets
```

### Grafana

**Deploy Grafana:**

```bash
kubectl apply -f monitoring/grafana/grafana-deployment.yaml
```

**Import Dashboard:**

1. Open Grafana: http://localhost:3000
2. Go to **Dashboards** → **Import**
3. Upload `monitoring/grafana/dashboards/nova-overview.json`

### Alerts

**Configure AlertManager:**

```bash
kubectl apply -f monitoring/prometheus/alertmanager-config.yaml
```

**Test Alert:**

```bash
# Trigger high latency alert (for testing)
kubectl exec -it -n nova-backend auth-service-xxx -- sh -c "sleep 10"
```

---

## Troubleshooting

常见部署和运行时问题的诊断和解决方案。

### 1. Service Won't Start (服务无法启动)

**症状：** Pod 处于 `CrashLoopBackOff` 或 `Error` 状态

**诊断步骤：**

```bash
# 1. 查看 Pod 状态
kubectl get pods -n nova-backend

# 2. 查看最近的日志 (包括崩溃前的日志)
kubectl logs -n nova-backend <pod-name> --previous

# 3. 查看 Pod 事件
kubectl describe pod -n nova-backend <pod-name>

# 4. 检查容器启动命令
kubectl get pod -n nova-backend <pod-name> -o jsonpath='{.spec.containers[0].command}'
```

**常见原因和解决方案：**

| 原因 | 解决方案 |
|------|---------|
| **缺少环境变量** | 检查 ConfigMap/Secret: `kubectl get secret -n nova-backend nova-backend-secrets -o yaml` |
| **数据库连接失败** | 验证 `DATABASE_URL` 格式和凭证，确保 PostgreSQL Pod 运行中 |
| **数据库迁移未运行** | 手动运行迁移: `sqlx migrate run` |
| **gRPC 端口冲突** | 检查 `HTTP_PORT` 和 `GRPC_PORT` 环境变量 |
| **二进制文件缺失** | 重新构建镜像，确保 `SERVICE_NAME` 构建参数正确 |
| **OOM (Out of Memory)** | 增加 Pod 内存限制: `kubectl edit deployment -n nova-backend <service>` |

**示例：检查 identity-service 启动失败**

```bash
# 查看崩溃日志
kubectl logs -n nova-backend identity-service-xxx --previous

# 常见错误信息：
# "Error: Environment variable DATABASE_URL not found"
#   → 解决: kubectl create secret ... --from-env-file=.env

# "Error: Failed to connect to database"
#   → 解决: 检查 PostgreSQL 服务是否运行, 验证凭证

# "Error: migration 20250101_xxx.sql failed"
#   → 解决: 手动运行迁移或回滚到之前的版本
```

### 2. High Latency (高延迟)

**症状：** P95 延迟 > 500ms，用户体验变慢

**诊断步骤：**

```bash
# 1. 检查 Prometheus 延迟指标
# PromQL: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# 2. 查看数据库连接池
psql $DATABASE_URL -c "
  SELECT count(*), state
  FROM pg_stat_activity
  WHERE datname = 'nova'
  GROUP BY state;
"

# 3. 检查 Redis 延迟
redis-cli --latency

# 4. 检查 ClickHouse 慢查询
curl "http://clickhouse:8123/?query=SELECT%20query%2C%20query_duration_ms%20FROM%20system.query_log%20WHERE%20query_duration_ms%20%3E%201000%20ORDER%20BY%20event_time%20DESC%20LIMIT%2010&default_format=PrettyCompact"

# 5. 查看服务间 gRPC 调用延迟
# PromQL: histogram_quantile(0.95, rate(grpc_client_duration_seconds_bucket[5m]))
```

**常见原因和解决方案：**

| 原因 | 解决方案 |
|------|---------|
| **数据库连接池耗尽** | 增加 `DATABASE_MAX_CONNECTIONS` (默认 20 → 50) |
| **慢 SQL 查询** | 添加索引，优化查询，使用 `EXPLAIN ANALYZE` |
| **Redis 网络延迟** | 检查 Redis 集群健康状态，考虑使用本地缓存 |
| **gRPC 超时** | 增加 `GRPC_REQUEST_TIMEOUT` (默认 10s → 30s) |
| **CPU throttling** | 增加 Pod CPU 限制: `kubectl set resources deployment ...` |
| **N+1 查询问题** | 使用 DataLoader 批量加载，减少数据库往返 |

### 3. gRPC Connection Refused (gRPC 连接拒绝)

**症状：** `grpc_client_errors` 指标增加，服务间调用失败

**诊断步骤：**

```bash
# 1. 验证 gRPC 端口是否开放
kubectl exec -n nova-backend user-service-xxx -- netstat -tuln | grep 9011

# 2. 测试 gRPC 健康检查
kubectl run grpcurl --rm -it --image=fullstorydev/grpcurl:latest -- \
  -plaintext user-service.nova-backend.svc.cluster.local:9011 \
  grpc.health.v1.Health/Check

# 3. 检查 Service 端点
kubectl get endpoints -n nova-backend user-service

# 4. 查看 gRPC 服务日志
kubectl logs -n nova-backend -l app=user-service --tail=100 | grep -i grpc
```

**常见原因和解决方案：**

| 原因 | 解决方案 |
|------|---------|
| **端口配置错误** | 确认 `GRPC_PORT = HTTP_PORT + 1000` |
| **Service 选择器错误** | 检查 k8s Service YAML 中的 `selector` 标签 |
| **Pod 未就绪** | 等待 Pod `Ready` 状态: `kubectl wait --for=condition=ready pod -l app=user-service` |
| **TLS 证书问题** | 如果启用 mTLS，检查证书有效期和 CN |
| **防火墙规则** | 确保 Kubernetes NetworkPolicy 允许服务间通信 |

### 4. Database Migration Failure (数据库迁移失败)

**症状：** 迁移在中途失败，部分表/列已修改

**诊断步骤：**

```bash
# 1. 检查迁移状态
sqlx migrate info --database-url $DATABASE_URL

# 2. 查看失败的迁移
psql $DATABASE_URL -c "SELECT * FROM _sqlx_migrations WHERE success = false;"

# 3. 查看 PostgreSQL 错误日志
kubectl logs -n nova-backend postgres-xxx --tail=100
```

**恢复步骤：**

```bash
# 场景 1: 迁移未开始 (最简单)
# 修复迁移脚本，重新运行
sqlx migrate run --database-url $DATABASE_URL

# 场景 2: 迁移部分完成 (需要手动修复)
# Step 1: 查看哪个迁移失败
sqlx migrate info --database-url $DATABASE_URL

# Step 2: 手动回滚部分应用的变更
psql $DATABASE_URL -f backend/migrations/XXXXX_rollback.sql

# Step 3: 修复迁移脚本
# 编辑 backend/migrations/XXXXX_fix.sql

# Step 4: 重新运行
sqlx migrate run --database-url $DATABASE_URL

# 场景 3: 紧急生产修复 (谨慎操作！)
# 如果迁移已手动应用，标记为已完成
psql $DATABASE_URL -c "
  INSERT INTO _sqlx_migrations (version, description, installed_on, success)
  VALUES (20250112000000, 'Manual emergency fix', NOW(), true);
"
```

**预防措施：**
- 所有迁移在 Staging 环境先测试
- 使用事务包裹迁移脚本 (`BEGIN; ... COMMIT;`)
- 遵循展开-收缩 (Expand-Contract) 模式
- 避免在高峰时段运行迁移

### 5. OOM Killed (内存溢出)

**症状：** Pod 频繁重启，日志显示 `OOMKilled`

**诊断步骤：**

```bash
# 1. 查看 Pod 重启原因
kubectl describe pod -n nova-backend <pod-name> | grep -A 5 "Last State"

# 2. 查看内存使用趋势
kubectl top pod -n nova-backend --sort-by=memory

# 3. 查看内存限制配置
kubectl get pod -n nova-backend <pod-name> -o jsonpath='{.spec.containers[0].resources}'
```

**解决方案：**

```bash
# 方案 1: 增加内存限制
kubectl set resources deployment -n nova-backend identity-service \
  --limits=memory=1Gi \
  --requests=memory=512Mi

# 方案 2: 优化代码 (查找内存泄漏)
# - 检查是否缓存过多数据
# - 使用 valgrind 或 Rust memory profiler
# - 减少并发连接数

# 方案 3: 启用水平扩展 (HPA)
kubectl autoscale deployment -n nova-backend identity-service \
  --cpu-percent=70 \
  --min=3 \
  --max=10
```

### 6. Kafka Consumer Lag (消费延迟)

**症状：** 事件处理延迟，消息积压

**诊断步骤：**

```bash
# 1. 查看 Consumer Group Lag
kafka-consumer-groups.sh --bootstrap-server kafka:9092 \
  --group nova-analytics-service \
  --describe

# 2. 检查 Consumer 日志
kubectl logs -n nova-backend analytics-service-xxx | grep -i kafka

# 3. 查看 Kafka Topic 分区
kafka-topics.sh --bootstrap-server kafka:9092 \
  --describe --topic events
```

**解决方案：**

| 问题 | 解决方案 |
|------|---------|
| **消费速度慢** | 增加 Consumer 副本数: `kubectl scale deployment analytics-service --replicas=5` |
| **分区数不足** | 增加 Kafka Topic 分区: `kafka-topics.sh --alter --partitions 10` |
| **消息处理失败** | 检查错误日志，修复业务逻辑，重启 Consumer |
| **Rebalance 频繁** | 调整 `session.timeout.ms` 和 `heartbeat.interval.ms` |

---

## Quick Reference

### Health Check Endpoints

- **Liveness:** `GET /api/v1/health/live` (returns 200 if process is alive)
- **Readiness:** `GET /api/v1/health/ready` (returns 200 if ready to serve traffic)
- **Detailed:** `GET /api/v1/health` (returns JSON with database status)

### Service Discovery (Kubernetes)

Internal DNS:
- `auth-service.nova-backend.svc.cluster.local:8083`
- `user-service.nova-backend.svc.cluster.local:8080`

Short form (within same namespace):
- `auth-service:8083`
- `user-service:8080`

### Common Commands

```bash
# Restart all services
kubectl rollout restart deployment -n nova-backend

# Scale service
kubectl scale deployment -n nova-backend auth-service --replicas=5

# View logs
kubectl logs -f -n nova-backend -l app=auth-service

# Port-forward for debugging
kubectl port-forward -n nova-backend svc/auth-service 8083:8083
```

---

## Service Deployment Order

服务之间存在依赖关系，必须按照正确的顺序部署以避免启动失败。

### Dependency Graph

```
┌─────────────────────────────────────────────────┐
│  Infrastructure (必须先启动)                    │
│  ──────────────────────────                     │
│  1. PostgreSQL (数据库)                          │
│  2. Redis (缓存)                                 │
│  3. Kafka (事件流)                               │
│  4. ClickHouse (分析数据库)                      │
│  5. Neo4j (图数据库)                             │
│  6. Elasticsearch (搜索)                         │
└─────────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────┐
│  Tier 1: 核心服务 (无外部服务依赖)              │
│  ──────────────────────────                     │
│  1. identity-service (认证服务)                  │
│     - 依赖: PostgreSQL, Redis                    │
│     - 端口: 8010 (HTTP), 9010 (gRPC)             │
│  2. user-service (用户服务)                      │
│     - 依赖: PostgreSQL, Redis                    │
│     - 端口: 8011 (HTTP), 9011 (gRPC)             │
└─────────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────┐
│  Tier 2: 业务服务 (依赖 Tier 1)                 │
│  ──────────────────────────                     │
│  3. content-service (内容服务)                   │
│     - 依赖: identity-service, user-service       │
│     - 端口: 8012 (HTTP), 9012 (gRPC)             │
│  4. social-service (社交服务)                    │
│     - 依赖: user-service, content-service        │
│     - 端口: 8013 (HTTP), 9013 (gRPC)             │
│  5. graph-service (图服务)                       │
│     - 依赖: Neo4j, user-service                  │
│     - 端口: 8018 (HTTP), 9018 (gRPC)             │
│  6. media-service (媒体服务)                     │
│     - 依赖: user-service, S3                     │
│     - 端口: 8014 (HTTP), 9014 (gRPC)             │
└─────────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────┐
│  Tier 3: 高级功能服务 (依赖 Tier 1 + 2)          │
│  ──────────────────────────                     │
│  7. analytics-service (分析服务)                 │
│     - 依赖: Kafka, ClickHouse                    │
│     - 端口: 8017 (HTTP), 9017 (gRPC)             │
│  8. search-service (搜索服务)                    │
│     - 依赖: Elasticsearch, content-service       │
│     - 端口: 8016 (HTTP), 9016 (gRPC)             │
│  9. feature-store (特征存储)                     │
│     - 依赖: Redis, ClickHouse                    │
│     - 端口: 8020 (HTTP), 9020 (gRPC)             │
│  10. ranking-service (排序服务)                  │
│      - 依赖: ClickHouse, feature-store           │
│      - 端口: 8021 (HTTP), 9021 (gRPC)            │
│  11. feed-service (Feed 服务)                    │
│      - 依赖: graph-service, ranking-service      │
│      - 端口: 8019 (HTTP), 9019 (gRPC)            │
└─────────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────┐
│  Tier 4: 辅助服务 (可独立启动)                   │
│  ──────────────────────────                     │
│  12. notification-service (通知服务)             │
│      - 依赖: user-service, Kafka                 │
│      - 端口: 8015 (HTTP), 9015 (gRPC)            │
│  13. realtime-chat-service (实时聊天)            │
│      - 依赖: identity-service, user-service      │
│      - 端口: 8022 (HTTP), 9022 (gRPC)            │
│  14. trust-safety-service (信任安全)             │
│      - 依赖: content-service, user-service       │
│      - 端口: 8023 (HTTP), 9023 (gRPC)            │
└─────────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────┐
│  Tier 5: API Gateway (最后启动)                  │
│  ──────────────────────────                     │
│  15. graphql-gateway (GraphQL 网关)              │
│      - 依赖: 所有上述服务                        │
│      - 端口: 8000 (HTTP)                         │
└─────────────────────────────────────────────────┘
```

### Recommended Deployment Sequence

**完整部署顺序脚本：**

```bash
#!/bin/bash
# deploy-all-services.sh
# 按照依赖顺序部署所有服务

set -e  # 遇到错误立即退出

NAMESPACE="nova-backend"
TIMEOUT="5m"

echo "=========================================="
echo "Nova Backend - Full Deployment Script"
echo "=========================================="
echo ""

# Function: 部署服务并等待就绪
deploy_service() {
  local service=$1
  echo "→ Deploying $service..."
  kubectl apply -f k8s/services/${service}.yaml -n $NAMESPACE
  kubectl rollout status deployment/$service -n $NAMESPACE --timeout=$TIMEOUT
  echo "✅ $service is ready"
  echo ""
}

# Function: 验证服务健康
verify_health() {
  local service=$1
  local port=$2
  echo "→ Verifying $service health..."
  kubectl run curl-test --rm -it --image=curlimages/curl:latest -- \
    curl -f http://${service}:${port}/api/v1/health || echo "⚠️ Health check failed for $service"
  echo ""
}

# Tier 1: 核心服务
echo "=========================================="
echo "Tier 1: Core Services"
echo "=========================================="
deploy_service "identity-service"
verify_health "identity-service" 8010

deploy_service "user-service"
verify_health "user-service" 8011

# Tier 2: 业务服务
echo "=========================================="
echo "Tier 2: Business Services"
echo "=========================================="
deploy_service "content-service"
verify_health "content-service" 8012

deploy_service "social-service"
verify_health "social-service" 8013

deploy_service "graph-service"
verify_health "graph-service" 8018

deploy_service "media-service"
verify_health "media-service" 8014

# Tier 3: 高级功能
echo "=========================================="
echo "Tier 3: Advanced Services"
echo "=========================================="
deploy_service "analytics-service"
verify_health "analytics-service" 8017

deploy_service "search-service"
verify_health "search-service" 8016

deploy_service "feature-store"
verify_health "feature-store" 8020

deploy_service "ranking-service"
verify_health "ranking-service" 8021

deploy_service "feed-service"
verify_health "feed-service" 8019

# Tier 4: 辅助服务
echo "=========================================="
echo "Tier 4: Auxiliary Services"
echo "=========================================="
deploy_service "notification-service"
verify_health "notification-service" 8015

deploy_service "realtime-chat-service"
verify_health "realtime-chat-service" 8022

deploy_service "trust-safety-service"
verify_health "trust-safety-service" 8023

# Tier 5: API Gateway
echo "=========================================="
echo "Tier 5: API Gateway"
echo "=========================================="
deploy_service "graphql-gateway"
verify_health "graphql-gateway" 8000

echo ""
echo "=========================================="
echo "✅ All services deployed successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Run smoke tests: ./scripts/smoke-test.sh"
echo "2. Monitor metrics: open http://grafana.nova.app"
echo "3. Check logs: kubectl logs -n $NAMESPACE -l app=graphql-gateway"
```

### Dependency Matrix

服务依赖关系矩阵（✅ = 直接依赖，➡️ = 间接依赖）：

| 服务 | identity | user | content | social | media | graph | analytics | search | feature-store | ranking | feed | notification | chat | trust-safety |
|------|----------|------|---------|--------|-------|-------|-----------|--------|---------------|---------|------|--------------|------|--------------|
| **identity-service** | - | | | | | | | | | | | | | |
| **user-service** | ✅ | - | | | | | | | | | | | | |
| **content-service** | ✅ | ✅ | - | | | | | | | | | | | |
| **social-service** | ✅ | ✅ | ✅ | - | | | | | | | | | | |
| **media-service** | ✅ | ✅ | | | - | | | | | | | | | |
| **graph-service** | | ✅ | | | | - | | | | | | | | |
| **analytics-service** | | | | | | | - | | | | | | | |
| **search-service** | | | ✅ | | | | | - | | | | | | |
| **feature-store** | | | | | | | | | - | | | | | |
| **ranking-service** | | | | | | | | | ✅ | - | | | | |
| **feed-service** | | | | | | ✅ | | | | ✅ | - | | | |
| **notification-service** | ✅ | ✅ | | | | | | | | | | - | | |
| **realtime-chat-service** | ✅ | ✅ | | | | | | | | | | | - | |
| **trust-safety-service** | | ✅ | ✅ | | | | | | | | | | | - |
| **graphql-gateway** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Next Steps

部署完成后，执行以下验证步骤：

### 1. 运行烟雾测试

```bash
# 使用 Postman Collection 或自定义脚本
./scripts/smoke-test.sh

# 测试关键流程
# - 用户注册和登录
# - 发布帖子
# - 关注用户
# - Feed 生成
# - 搜索功能
```

### 2. 配置监控仪表板

- **Prometheus**: http://prometheus.nova.app
- **Grafana**: http://grafana.nova.app
  - 导入 Dashboard: `monitoring/grafana/dashboards/nova-overview.json`
  - 配置 AlertManager 规则

### 3. 设置告警

```bash
# 应用 AlertManager 配置
kubectl apply -f monitoring/prometheus/alertmanager-config.yaml

# 验证告警规则
curl http://prometheus.nova.app/api/v1/rules | jq
```

### 4. 检查清单

使用部署前检查清单：

- [ ] 所有服务 Pod 状态为 `Running`
- [ ] 健康检查全部通过
- [ ] 数据库迁移完成
- [ ] Secrets 配置正确
- [ ] 监控和告警正常工作
- [ ] 日志聚合已配置 (ELK Stack)
- [ ] 备份策略已实施

---

## Support & Documentation

**团队支持：**
- Slack: `#nova-backend-ops`
- On-call: PagerDuty rotation
- Wiki: https://wiki.nova.app/backend

**相关文档：**
- [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md) - 部署前检查清单
- [ROLLBACK_PROCEDURE.md](./ROLLBACK_PROCEDURE.md) - 回滚程序
- [MONITORING_GUIDE.md](./MONITORING_GUIDE.md) - 监控配置指南
- [DATABASE_MIGRATION_GUIDE.md](./DATABASE_MIGRATION_GUIDE.md) - 数据库迁移详细指南

**紧急联系：**
- 生产事故: PagerDuty (24/7)
- 安全问题: security@nova.app
- Infrastructure 问题: devops@nova.app

---

**文档版本**: 2.0
**最后更新**: 2025-11-12
**维护者**: Nova DevOps Team

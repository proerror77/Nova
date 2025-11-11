# 服务边界迁移执行计划 (Service Boundary Migration Execution Plan)

**Version**: 1.0.0
**Created**: 2025-11-11
**Owner**: System Architecture Team
**Risk Level**: High
**Estimated Duration**: 8 days

---

## 迁移原则 (Migration Principles)

遵循 Linus Torvalds 的核心原则：
1. **"Never break userspace"** - 保持向后兼容
2. **实用主义** - 解决实际问题，不过度设计
3. **简洁性** - 消除特殊情况，简化数据结构

---

## Pre-Migration Checklist

### 环境准备
- [ ] 生产数据备份完成
- [ ] Kafka 集群部署就绪
- [ ] 监控系统配置完成
- [ ] 回滚计划验证
- [ ] 团队培训完成

### 技术准备
- [ ] 所有服务 Docker 镜像构建
- [ ] Kubernetes manifests 更新
- [ ] 数据库迁移脚本测试
- [ ] gRPC 客户端库发布
- [ ] 事件 Schema 注册

---

## Phase 0: 基础设施准备 (Day 0)

### 0.1 部署事件基础设施

```bash
# 1. 部署 Kafka 集群
kubectl apply -f k8s/kafka/namespace.yaml
kubectl apply -f k8s/kafka/zookeeper.yaml
kubectl apply -f k8s/kafka/kafka-cluster.yaml

# 2. 部署 Schema Registry
kubectl apply -f k8s/kafka/schema-registry.yaml

# 3. 创建 Topics
./scripts/create-kafka-topics.sh

# 4. 验证
kubectl get pods -n kafka
kafka-topics --list --bootstrap-server kafka:9092
```

### 0.2 数据库准备

```sql
-- 1. 创建备份
pg_dump -h localhost -U postgres -d nova > nova_backup_$(date +%Y%m%d).sql

-- 2. 创建 outbox 表结构
CREATE TABLE IF NOT EXISTS outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published BOOLEAN DEFAULT FALSE,
    published_at TIMESTAMP WITH TIME ZONE,
    INDEX idx_unpublished (published, created_at) WHERE published = FALSE
);

-- 3. 为每个服务创建 outbox
CREATE TABLE users_outbox AS TABLE outbox_events WITH NO DATA;
CREATE TABLE content_outbox AS TABLE outbox_events WITH NO DATA;
-- ... 其他服务
```

### 0.3 监控配置

```yaml
# prometheus/rules/boundaries.yml
groups:
  - name: migration_monitoring
    interval: 30s
    rules:
      - alert: MigrationPhaseActive
        expr: migration_phase_active == 1
        annotations:
          summary: "Migration phase {{ $labels.phase }} is active"

      - alert: ServiceDependencyViolation
        expr: service_dependency_violations > 0
        for: 1m
        annotations:
          summary: "Service {{ $labels.from }} calling {{ $labels.to }}"
```

---

## Phase 1: 媒体服务合并 (Day 1-2)

### 1.1 执行前验证

```bash
# 检查服务状态
for service in media-service video-service streaming-service cdn-service; do
    kubectl get pods -l app=$service
    kubectl logs -l app=$service --tail=100 | grep ERROR
done

# 检查依赖
grep -r "media-service\|video-service\|streaming-service\|cdn-service" backend/*/Cargo.toml
```

### 1.2 执行合并

```bash
# 运行合并脚本
cd backend/scripts
./merge-media-services.sh --mode=dry-run  # 先演练
./merge-media-services.sh --mode=execute   # 执行

# 验证合并
ls -la backend/media-service/
ls -la backend/delivery-service/
cargo test --workspace
```

### 1.3 部署新服务

```yaml
# k8s/media-service-v2.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: media-service-v2
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
      - name: media-service
        image: nova/media-service:v2
        env:
        - name: SERVICE_VERSION
          value: "v2"
        livenessProbe:
          httpGet:
            path: /health
            port: 50057
        readinessProbe:
          httpGet:
            path: /ready
            port: 50057
```

```bash
# 蓝绿部署
kubectl apply -f k8s/media-service-v2.yaml
kubectl wait --for=condition=ready pod -l app=media-service-v2

# 切换流量
kubectl patch service media-service -p '{"spec":{"selector":{"version":"v2"}}}'

# 验证
curl http://media-service:50057/health
```

### 1.4 回滚计划

```bash
# 如果出现问题，立即回滚
kubectl patch service media-service -p '{"spec":{"selector":{"version":"v1"}}}'
kubectl delete deployment media-service-v2

# 恢复旧服务
kubectl scale deployment video-service streaming-service cdn-service --replicas=3
```

---

## Phase 2: 认证服务分离 (Day 3-4)

### 2.1 创建 Identity Service

```bash
# 1. 创建新服务
cd backend
cargo new identity-service
cd identity-service

# 2. 复制认证相关代码
cp -r ../auth-service/src/token.rs ./src/
cp -r ../auth-service/src/session.rs ./src/
cp -r ../auth-service/src/jwt.rs ./src/

# 3. 更新依赖
cat >> Cargo.toml << 'EOF'
[dependencies]
tonic = "0.11"
tokio = { version = "1", features = ["full"] }
jsonwebtoken = "9"
uuid = { version = "1", features = ["serde", "v4"] }
sqlx = { version = "0.7", features = ["postgres", "runtime-tokio-native-tls"] }
redis = { version = "0.24", features = ["tokio-comp"] }
EOF

# 4. 构建和测试
cargo build
cargo test
```

### 2.2 更新 User Service

```rust
// user-service/src/main.rs
// 移除认证相关代码，只保留用户管理

use tonic::{transport::Server, Request, Response, Status};
use identity_service_client::IdentityServiceClient;

pub struct UserService {
    pool: PgPool,
    identity_client: IdentityServiceClient<Channel>,  // 使用 identity service
}

impl UserService {
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = PgPool::connect(database_url).await?;
        let identity_client = IdentityServiceClient::connect("http://identity-service:50051").await?;

        Ok(Self { pool, identity_client })
    }

    // 用户管理方法
    pub async fn create_user(&self, req: CreateUserRequest) -> Result<User> {
        // 只负责用户数据，不处理认证
        let user = sqlx::query_as!(User,
            "INSERT INTO users (email, name, created_at) VALUES ($1, $2, NOW()) RETURNING *",
            req.email, req.name
        )
        .fetch_one(&self.pool)
        .await?;

        // 发布事件
        self.publish_event(Event::UserCreated { user_id: user.id }).await?;

        Ok(user)
    }
}
```

### 2.3 迁移数据

```sql
-- 1. 迁移 sessions 表所有权
UPDATE sessions SET service_owner = 'identity-service' WHERE service_owner = 'auth-service';

-- 2. 迁移 tokens 表所有权
UPDATE refresh_tokens SET service_owner = 'identity-service' WHERE service_owner = 'auth-service';
UPDATE revoked_tokens SET service_owner = 'identity-service' WHERE service_owner = 'auth-service';

-- 3. 更新约束
ALTER TABLE sessions DROP CONSTRAINT owned_by_auth_sessions;
ALTER TABLE sessions ADD CONSTRAINT owned_by_identity_sessions
    CHECK (service_owner = 'identity-service');

-- 4. 验证
SELECT table_name, service_owner, COUNT(*)
FROM (
    SELECT 'sessions' as table_name, service_owner FROM sessions
    UNION ALL
    SELECT 'refresh_tokens', service_owner FROM refresh_tokens
    UNION ALL
    SELECT 'revoked_tokens', service_owner FROM revoked_tokens
) t
GROUP BY table_name, service_owner;
```

### 2.4 切换流量

```bash
# 1. 部署 identity-service
kubectl apply -f k8s/identity-service.yaml

# 2. 更新服务发现
kubectl patch configmap service-registry --patch '{
  "data": {
    "auth.endpoint": "identity-service:50051"
  }
}'

# 3. 重启依赖服务
kubectl rollout restart deployment user-service
kubectl rollout restart deployment content-service

# 4. 验证
curl -H "Authorization: Bearer $TOKEN" http://api-gateway/api/users/me
```

---

## Phase 3: 消除循环依赖 (Day 5-6)

### 3.1 Content ↔ Feed 解耦

```rust
// 之前: content-service 调用 feed-service
impl ContentService {
    async fn create_post(&self, req: CreatePostRequest) -> Result<Post> {
        let post = self.create_post_internal(req).await?;

        // ❌ 直接调用 feed-service
        self.feed_client.update_feeds(post.id).await?;

        Ok(post)
    }
}

// 之后: 使用事件
impl ContentService {
    async fn create_post(&self, req: CreatePostRequest) -> Result<Post> {
        let post = self.create_post_internal(req).await?;

        // ✅ 发布事件
        self.publish_event(Event::PostCreated {
            post_id: post.id,
            author_id: post.author_id,
            created_at: post.created_at,
        }).await?;

        Ok(post)
    }
}

// feed-service 监听事件
#[event_handler("content.post.created")]
async fn handle_post_created(&self, event: PostCreatedEvent) {
    // 更新相关用户的 feeds
    let followers = self.get_followers(event.author_id).await?;
    for follower in followers {
        self.add_to_feed(follower.id, event.post_id).await?;
    }
}
```

### 3.2 Messaging ↔ Notification 解耦

```rust
// messaging-service: 只处理实时消息
impl MessagingService {
    async fn send_message(&self, req: SendMessageRequest) -> Result<Message> {
        // 保存消息
        let message = self.save_message(req).await?;

        // WebSocket 实时推送
        if let Some(ws) = self.websockets.get(&req.recipient_id) {
            ws.send(message.clone()).await?;
        }

        // 发布事件（不直接调用 notification）
        self.publish_event(Event::MessageSent {
            message_id: message.id,
            recipient_id: req.recipient_id,
        }).await?;

        Ok(message)
    }
}

// notification-service: 监听事件，处理异步通知
#[event_handler("messaging.message.sent")]
async fn handle_message_sent(&self, event: MessageSentEvent) {
    let user = self.get_user_preferences(event.recipient_id).await?;

    if user.push_enabled && !user.is_online {
        self.send_push_notification(event).await?;
    }

    if user.email_notifications {
        self.queue_email_notification(event).await?;
    }
}
```

### 3.3 验证解耦

```bash
# 1. 检查 Cargo.toml 依赖
for service in content-service feed-service messaging-service notification-service; do
    echo "=== $service dependencies ==="
    grep -E "content-service|feed-service|messaging-service|notification-service" \
        backend/$service/Cargo.toml || echo "No circular deps"
done

# 2. 运行依赖验证脚本
./backend/scripts/validate-dependencies.sh

# 3. 测试事件流
# 发送测试事件
kafka-console-producer --broker-list kafka:9092 --topic content.events << EOF
{"event_type": "post.created", "post_id": "test-123", "author_id": "user-456"}
EOF

# 验证消费
kafka-console-consumer --bootstrap-server kafka:9092 \
    --topic content.events --from-beginning --max-messages 1
```

---

## Phase 4: 数据库约束实施 (Day 7)

### 4.1 应用所有权约束

```bash
# 1. 在维护窗口执行
psql -h localhost -U postgres -d nova << 'EOF'
BEGIN;

-- 应用迁移
\i backend/migrations/apply-data-ownership.sql

-- 验证
SELECT * FROM validate_service_boundaries();

COMMIT;
EOF

# 2. 监控违规
watch -n 5 "psql -c 'SELECT * FROM service_boundary_violations ORDER BY violation_time DESC LIMIT 10'"
```

### 4.2 修复跨服务查询

```bash
# 1. 识别所有违规
./backend/scripts/fix-cross-service-db.sh > violations.txt

# 2. 为每个违规生成修复
while IFS= read -r violation; do
    file=$(echo $violation | cut -d: -f1)
    line=$(echo $violation | cut -d: -f2)

    echo "Fixing: $file:$line"
    # 应用自动修复（如果可用）
    ./scripts/apply-fix.sh "$file" "$line"
done < violations.txt

# 3. 手动审查和测试
cargo test --workspace
```

### 4.3 性能优化

```rust
// 添加缓存层减少 gRPC 调用
use moka::future::Cache;

pub struct CachedUserClient {
    inner: UserServiceClient<Channel>,
    cache: Cache<Uuid, User>,
}

impl CachedUserClient {
    pub async fn get_user(&self, id: Uuid) -> Result<User> {
        // 先查缓存
        if let Some(user) = self.cache.get(&id).await {
            return Ok(user);
        }

        // 缓存未命中，调用服务
        let user = self.inner.get_user(GetUserRequest {
            id: id.to_string()
        }).await?.into_inner();

        // 写入缓存（TTL 5分钟）
        self.cache.insert(id, user.clone()).await;

        Ok(user)
    }
}
```

---

## Phase 5: 验证和监控 (Day 8)

### 5.1 运行完整验证

```bash
# 1. 边界验证
./backend/scripts/run-boundary-validation.sh

# 2. 集成测试
cargo test --workspace --test integration

# 3. 性能测试
artillery run load-tests/service-boundaries.yml

# 4. 端到端测试
npm run test:e2e
```

### 5.2 监控仪表板

```yaml
# grafana/dashboards/migration.json
{
  "dashboard": {
    "title": "Service Boundary Migration",
    "panels": [
      {
        "title": "Circular Dependencies",
        "targets": [{
          "expr": "sum(service_circular_dependencies)"
        }]
      },
      {
        "title": "Cross-Service DB Queries",
        "targets": [{
          "expr": "rate(cross_service_db_queries_total[5m])"
        }]
      },
      {
        "title": "Event Processing Lag",
        "targets": [{
          "expr": "kafka_consumer_lag"
        }]
      },
      {
        "title": "Service Call Latency",
        "targets": [{
          "expr": "histogram_quantile(0.95, grpc_server_handling_seconds_bucket)"
        }]
      }
    ]
  }
}
```

### 5.3 健康检查

```bash
# 服务健康状态
for port in 50051 50052 50053 50054 50055 50056 50057 50058; do
    echo -n "Port $port: "
    curl -s http://localhost:$port/health | jq -r .status
done

# 数据库连接
psql -c "SELECT service_name, COUNT(*) as connections
         FROM pg_stat_activity
         GROUP BY service_name"

# Kafka 状态
kafka-consumer-groups --bootstrap-server kafka:9092 --describe --all-groups
```

---

## 回滚计划 (Rollback Plan)

### 触发条件
- [ ] 错误率 > 5%
- [ ] 延迟增加 > 100%
- [ ] 数据不一致报告
- [ ] 关键服务宕机 > 5分钟

### 回滚步骤

```bash
# 1. 切换到备份版本
kubectl set image deployment/media-service media-service=nova/media-service:v1
kubectl set image deployment/identity-service identity-service=nova/auth-service:v1

# 2. 恢复数据库
psql -h localhost -U postgres -d nova < nova_backup_20251111.sql

# 3. 禁用事件处理
kubectl scale deployment event-processor --replicas=0

# 4. 恢复原始服务
kubectl apply -f k8s/backup/original-services.yaml

# 5. 验证
./scripts/verify-rollback.sh
```

---

## 成功标准 (Success Metrics)

### 技术指标
- ✅ 循环依赖数 = 0
- ✅ 跨服务DB查询 = 0
- ✅ 所有服务健康检查通过
- ✅ 错误率 < 0.1%
- ✅ P95 延迟 < 50ms

### 业务指标
- ✅ 用户登录成功率 > 99.9%
- ✅ 内容发布成功率 > 99.9%
- ✅ 消息投递率 > 99.9%
- ✅ 无数据丢失报告

---

## 沟通计划 (Communication Plan)

### 内部沟通
```
Day 0: 团队 Kick-off 会议
Day 1-7: 每日站会 (09:00)
Day 1-7: 进度更新 (18:00)
Day 8: 复盘会议
```

### 外部沟通
```
D-7: 用户通知（计划维护）
D-1: 最终确认邮件
D+0: 维护开始通知
D+8: 维护完成通知
```

---

## 风险登记 (Risk Register)

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| 数据丢失 | Low | Critical | 多重备份，事务保证 |
| 服务中断 | Medium | High | 蓝绿部署，快速回滚 |
| 性能下降 | Medium | Medium | 缓存优化，负载测试 |
| 团队不熟悉 | High | Low | 提前培训，文档完善 |

---

## 签核 (Sign-off)

- [ ] 架构师批准
- [ ] 运维团队确认
- [ ] 产品经理知悉
- [ ] CTO 最终批准

---

*"Regression testing"? What's that? If it compiles, it is good; if it boots up, it is perfect.* - Linus Torvalds

虽然 Linus 这么说，但我们还是要做完整的测试。准备就绪，开始执行！
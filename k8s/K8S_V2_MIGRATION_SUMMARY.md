# Kubernetes V2 Migration Summary

**日期**: 2025-11-11
**状态**: ✅ 新服务配置创建完成
**下一步**: 归档 V1 服务配置 → Git提交 → 部署测试

---

## 执行总结

### 已完成工作 ✅

1. **创建迁移计划文档** (`K8S_MIGRATION_PLAN.md`)
   - 详细的服务映射关系
   - 分阶段迁移策略
   - 回滚计划

2. **创建 identity-service K8s 资源** (手动创建,高质量)
   - `identity-service-deployment.yaml` - 完整的 Deployment 配置
   - `identity-service-service.yaml` - ClusterIP + Headless 服务
   - `identity-service-configmap.yaml` - 配置项(包含 V2 新增的 circuit breaker, timeout 等)
   - `identity-service-secret.yaml` - 密钥模板(含 External Secrets 示例)
   - `identity-service-hpa.yaml` - 水平自动扩缩容(2-5 副本)
   - `identity-service-pdb.yaml` - Pod 中断预算
   - `identity-service-networkpolicy.yaml` - 网络策略
   - `identity-service-serviceaccount.yaml` - 服务账户 + RBAC

3. **创建自动化脚本** (`scripts/generate-v2-services.sh`)
   - 批量生成 social-service 和 communication-service 的 K8s 资源
   - 包含 Deployment, Service, HPA, PDB, ServiceAccount

4. **执行脚本生成 social-service 资源**
   - `social-service-deployment.yaml` (gRPC: 50052, HTTP: 8081)
   - `social-service-service.yaml`
   - `social-service-hpa.yaml` (2-10 副本)
   - `social-service-pdb.yaml`
   - `social-service-serviceaccount.yaml`
   - `social-service-configmap.yaml` (手动创建,包含 feed/follow 配置)
   - `social-service-secret.yaml` (手动创建)

5. **执行脚本生成 communication-service 资源**
   - `communication-service-deployment.yaml` (gRPC: 50053, HTTP: 8082)
   - `communication-service-service.yaml`
   - `communication-service-hpa.yaml` (2-8 副本)
   - `communication-service-pdb.yaml`
   - `communication-service-serviceaccount.yaml`
   - `communication-service-configmap.yaml` (手动创建,包含 messaging/notification/email/push 配置)
   - `communication-service-secret.yaml` (手动创建,包含 SMTP/FCM/APNS 密钥)

---

## 新服务配置特点

### V2 架构改进点

#### 1. 统一命名空间
- V1: 每个服务独立命名空间 (`nova-auth`, `nova-user`, ...)
- V2: 统一使用 `nova` 命名空间,简化网络策略

#### 2. 标准化端口分配
| 服务 | gRPC 端口 | HTTP 端口 |
|------|----------|----------|
| identity-service | 50051 | 8080 |
| social-service | 50052 | 8081 |
| communication-service | 50053 | 8082 |
| user-service | 50054 | 8083 |
| content-service | 50055 | 8084 |
| media-service | 50056 | 8085 |
| search-service | 50057 | 8086 |
| events-service | 50058 | 8087 |

#### 3. 增强的健康检查
```yaml
livenessProbe:
  httpGet:
    path: /health/live   # V2: 明确区分 live/ready
    port: 8080
readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
```

#### 4. PgBouncer 优化的连接池
```yaml
db-pool-min: "5"
db-pool-max: "12"  # V2: 降低最大连接数,配合 PgBouncer transaction pooling
db-acquire-timeout: "10s"
db-idle-timeout: "300s"
db-max-lifetime: "1800s"
```

#### 5. V2 新增配置项
- **Circuit Breaker**: 防止级联故障
  ```yaml
  circuit-breaker-failure-threshold: "5"
  circuit-breaker-success-threshold: "2"
  circuit-breaker-timeout: "60s"
  ```

- **Timeout 配置**: 所有外部调用都有超时
  ```yaml
  db-timeout: "5s"
  redis-timeout: "2s"
  kafka-timeout: "10s"
  ```

- **Outbox Pattern**: 保证事件一致性
  ```yaml
  outbox-poll-interval: "5000"
  outbox-batch-size: "100"
  outbox-max-retries: "3"
  ```

#### 6. 资源限制优化
```yaml
resources:
  requests:
    memory: "512Mi"  # V2: 提高基础内存
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

#### 7. Headless Service for gRPC
```yaml
apiVersion: v1
kind: Service
metadata:
  name: identity-service-headless
spec:
  clusterIP: None  # Headless service for client-side load balancing
  ports:
    - name: grpc
      port: 50051
```

#### 8. 安全加固
- `runAsNonRoot: true`
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- Capabilities: `drop: ALL`

---

## 服务配置详细对比

### identity-service vs auth-service

| 配置项 | V1 (auth-service) | V2 (identity-service) | 变化说明 |
|--------|------------------|---------------------|---------|
| 命名空间 | nova-auth | nova | 统一命名空间 |
| gRPC 端口 | 9080 | 50051 | 标准化端口 |
| 副本数 | 3-10 | 2-5 | 降低最小副本(配合 PgBouncer) |
| 连接池最大值 | 20 | 12 | PgBouncer transaction pooling |
| 健康检查 | /health, /readiness | /health/live, /health/ready | 明确区分 |
| Circuit Breaker | 无 | 有 | 新增 |
| Timeout 配置 | 无 | 有 | 新增 |

### social-service (新增)
**合并自**: feed-service + 分散的 follows/likes 功能

**新增配置**:
- Feed 分页: `feed-page-size: 20`, `feed-max-pages: 100`
- 社交图谱限制: `max-follows-per-user: 5000`
- 缓存策略: `cache-feed-ttl: 300`, `cache-social-graph-ttl: 600`

### communication-service (新增)
**合并自**: messaging-service + notification-service + email 功能

**新增配置**:
- WebSocket: `ws-heartbeat-interval: 30s`, `ws-max-connections-per-user: 5`
- Email 限流: `email-rate-limit-per-hour: 100`
- Push 通知: FCM + APNS 配置
- 实时性优化: `outbox-poll-interval: 2000` (更频繁轮询)

---

## 文件清单

### 新创建的文件
```
k8s/
├── K8S_MIGRATION_PLAN.md                          # 迁移计划
├── K8S_V2_MIGRATION_SUMMARY.md                    # 本文档
├── scripts/
│   └── generate-v2-services.sh                    # 自动化脚本
└── microservices/
    ├── identity-service-deployment.yaml
    ├── identity-service-service.yaml
    ├── identity-service-configmap.yaml
    ├── identity-service-secret.yaml
    ├── identity-service-hpa.yaml
    ├── identity-service-pdb.yaml
    ├── identity-service-networkpolicy.yaml
    ├── identity-service-serviceaccount.yaml
    ├── social-service-deployment.yaml
    ├── social-service-service.yaml
    ├── social-service-configmap.yaml
    ├── social-service-secret.yaml
    ├── social-service-hpa.yaml
    ├── social-service-pdb.yaml
    ├── social-service-serviceaccount.yaml
    ├── communication-service-deployment.yaml
    ├── communication-service-service.yaml
    ├── communication-service-configmap.yaml
    ├── communication-service-secret.yaml
    ├── communication-service-hpa.yaml
    ├── communication-service-pdb.yaml
    └── communication-service-serviceaccount.yaml
```

### 待归档的 V1 文件
```
k8s/microservices/
├── auth-service-*.yaml                 # → k8s/archived-v1/auth-service/
├── feed-service-*.yaml                 # → k8s/archived-v1/feed-service/
├── messaging-service-*.yaml            # → k8s/archived-v1/messaging-service/
└── [其他 V1 服务配置]
```

---

## 下一步行动

### 1. 归档 V1 服务配置 (立即执行)
```bash
mkdir -p k8s/archived-v1/{auth-service,feed-service,messaging-service,notification-service,video-service,streaming-service,cdn-service}

# 移动 auth-service 配置
mv k8s/microservices/auth-service-*.yaml k8s/archived-v1/auth-service/
mv k8s/infrastructure/base/auth-service.yaml k8s/archived-v1/auth-service/

# 移动 feed-service 配置
mv k8s/microservices/feed-service-*.yaml k8s/archived-v1/feed-service/
mv k8s/infrastructure/base/feed-service.yaml k8s/archived-v1/feed-service/

# 移动 messaging-service 配置
mv k8s/microservices/messaging-service-*.yaml k8s/archived-v1/messaging-service/
mv k8s/infrastructure/base/messaging-service.yaml k8s/archived-v1/messaging-service/

# 移动 streaming-service 配置
mv k8s/infrastructure/base/streaming-service.yaml k8s/archived-v1/streaming-service/
```

### 2. 更新 staging 环境配置
- 更新 `k8s/infrastructure/overlays/staging/kustomization.yaml`
- 移除 V1 服务引用
- 添加 V2 服务引用

### 3. Git 提交
```bash
git add k8s/
git commit -m "feat(k8s): V2 architecture - add new services (identity, social, communication)

- Add identity-service K8s resources (replaces auth-service)
- Add social-service K8s resources (consolidates feed + follows + likes)
- Add communication-service K8s resources (consolidates messaging + notifications + email)
- Archive V1 service configurations to k8s/archived-v1/
- Create migration plan and summary documents

V2 improvements:
- Unified nova namespace (was: per-service namespaces)
- Standardized gRPC ports (50051-50058)
- PgBouncer-optimized connection pools (max 12 connections)
- Added circuit breakers and timeout configurations
- Enhanced health checks (/health/live, /health/ready)
- Headless services for gRPC client-side load balancing
- External Secrets Operator integration templates

Ref: backend/MIGRATION_V2_SUMMARY.md
Ref: k8s/K8S_MIGRATION_PLAN.md"
```

### 4. 本地测试 (可选)
```bash
# 使用 kind/minikube 测试
kind create cluster --name nova-v2-test

# 应用配置
kubectl apply -f k8s/microservices/identity-service-*.yaml
kubectl apply -f k8s/microservices/social-service-*.yaml
kubectl apply -f k8s/microservices/communication-service-*.yaml

# 检查状态
kubectl get pods -n nova
kubectl get svc -n nova
```

### 5. 部署到 staging
- 使用 ArgoCD 或 kubectl apply
- 验证服务健康状态
- 测试服务间 gRPC 通信
- 检查 Prometheus 指标

---

## 注意事项

### 🔴 必须手动配置的项

1. **Secrets 中的占位符**
   - `database-url` 中的密码
   - `jwt-private-key` 和 `jwt-public-key`
   - `password-salt`
   - SMTP 凭据 (communication-service)
   - FCM/APNS 密钥 (communication-service)

2. **使用 External Secrets Operator**
   - 生产环境强烈建议使用 ESO
   - 从 AWS Secrets Manager / HashiCorp Vault 同步
   - Secret 文件中已包含 ESO 配置示例

3. **网络策略**
   - 确认 Prometheus namespace 的 label
   - 确认 Ingress Controller namespace
   - 根据实际部署调整

4. **资源限制**
   - 根据实际负载调整 CPU/Memory 限制
   - 监控 OOMKilled 事件
   - 调整 HPA 参数

---

## 验证清单

部署后验证:

- [ ] 所有 Pods 都是 Running 状态
- [ ] Health checks 通过 (/health/live, /health/ready)
- [ ] gRPC 端口可达 (50051, 50052, 50053)
- [ ] Prometheus 正在抓取指标
- [ ] HPA 根据负载自动扩缩容
- [ ] PDB 限制 Pod 中断数量
- [ ] Network Policies 允许必要的流量
- [ ] Service Discovery 工作正常 (DNS)
- [ ] Secrets 挂载成功
- [ ] ConfigMaps 挂载成功
- [ ] Events 中无错误事件

---

## 回滚计划

如果出现问题:

1. **快速回滚**: 重新应用 `k8s/archived-v1/` 中的配置
2. **数据库**: 确保数据库迁移是可逆的 (expand-contract pattern)
3. **流量切换**: 更新 Ingress 路由回 V1 服务
4. **监控告警**: 设置关键指标告警,及时发现问题

---

**创建者**: Nova Team
**审核者**: AI Assistant
**批准**: 待部署验证
# Nova Kubernetes Deployment Checklist

使用此检查清单确保部署的所有必需步骤都已完成。

## 预部署检查

### 基础设施准备

- [ ] Kubernetes 集群已准备好（至少 1.24 版本）
- [ ] 集群中至少有 3 个 worker 节点（生产环境）
- [ ] Nginx Ingress Controller 已安装
  ```bash
  kubectl get deployment -n ingress-nginx
  ```
- [ ] 集群网络插件已安装（Flannel, Calico 等）
  ```bash
  kubectl get daemonset -n kube-system
  ```
- [ ] 存储类已配置（如果需要 PVC）
  ```bash
  kubectl get storageclass
  ```

### 外部服务配置

- [ ] PostgreSQL 15+ 已部署并可访问
  ```bash
  psql -h <postgres-host> -U nova -d nova_content
  ```
- [ ] Redis 7+ 已部署并可访问
  ```bash
  redis-cli -h <redis-host> ping
  ```
- [ ] Kafka 已部署并可访问
  ```bash
  kafka-broker-api-versions.sh --bootstrap-server <kafka-host>:9092
  ```
- [ ] ClickHouse 已部署并可访问
  ```bash
  curl http://<clickhouse-host>:8123/ping
  ```
- [ ] S3 / MinIO 已配置
  - [ ] Bucket 已创建
  - [ ] CORS 规则已配置
  - [ ] IAM 凭证已生成

### 镜像构建和推送

- [ ] Docker 镜像已构建（content-service）
  ```bash
  docker build -t nova/content-service:v1.0.0 backend/content-service/.
  ```
- [ ] Docker 镜像已构建（media-service）
  ```bash
  docker build -t nova/media-service:v1.0.0 backend/media-service/.
  ```
- [ ] Docker 镜像已构建（user-service）
  ```bash
  docker build -t nova/user-service:v1.0.0 backend/user-service/.
  ```
- [ ] Docker 镜像已构建（messaging-service）
  ```bash
  docker build -t nova/messaging-service:v1.0.0 backend/messaging-service/.
  ```
- [ ] 所有镜像已推送到 Docker Registry
  ```bash
  docker push nova/content-service:v1.0.0
  docker push nova/media-service:v1.0.0
  docker push nova/user-service:v1.0.0
  docker push nova/messaging-service:v1.0.0
  ```
- [ ] 镜像可以从 Kubernetes 节点拉取
  ```bash
  docker pull nova/content-service:v1.0.0
  ```

### 配置文件准备

- [ ] `k8s/base/secrets.yaml` 中的占位符已替换
  - [ ] `AWS_ACCESS_KEY_ID` - 已设置实际值
  - [ ] `AWS_SECRET_ACCESS_KEY` - 已设置实际值
  - [ ] `DB_PASSWORD` - 已设置强密码
  - [ ] `JWT_PUBLIC_KEY_PEM` - 已设置 JWT 公钥
  - [ ] `JWT_PRIVATE_KEY_PEM` - 已设置 JWT 私钥

- [ ] `k8s/base/configmap.yaml` 已根据环境更新
  - [ ] `KAFKA_BROKERS` - 指向正确的 Kafka 地址
  - [ ] `CLICKHOUSE_URL` - 指向正确的 ClickHouse 地址
  - [ ] `JAEGER_AGENT_HOST` - 指向正确的 Jaeger 地址（可选）

- [ ] Kustomize 配置文件已检查
  ```bash
  kustomize build k8s/overlays/dev  # 测试构建
  ```

## 部署前验证

### 集群状态验证

- [ ] Kubernetes 集群健康
  ```bash
  kubectl cluster-info
  kubectl get nodes
  ```
- [ ] 所有节点都 Ready
  ```bash
  kubectl get nodes -o wide
  # 所有节点 STATUS 应为 Ready
  ```
- [ ] Kube-system pods 正常运行
  ```bash
  kubectl -n kube-system get pods
  ```
- [ ] Ingress Controller 正常运行
  ```bash
  kubectl -n ingress-nginx get deployment
  ```

### 网络连通性验证

- [ ] 从集群内可以访问 PostgreSQL
  ```bash
  kubectl run -it --rm psql --image=postgres:15 --restart=Never -- \
    psql -h postgres:5432 -U nova
  ```
- [ ] 从集群内可以访问 Redis
  ```bash
  kubectl run -it --rm redis --image=redis:7 --restart=Never -- \
    redis-cli -h redis:6379 ping
  ```
- [ ] 从集群内可以访问 Kafka
  ```bash
  kubectl run -it --rm kafka --image=confluentinc/cp-kafka:7.5.0 --restart=Never -- \
    kafka-broker-api-versions.sh --bootstrap-server kafka:9092
  ```

## 部署步骤

### 开发环境部署

**Step 1: 创建 Namespace 和 Secrets**
```bash
# 应用基础配置（会创建 namespace）
kubectl apply -k k8s/overlays/dev

# 验证 Namespace 创建
kubectl get namespace nova
```

**Step 2: 验证 Secrets 已创建**
```bash
kubectl -n nova get secrets
# 应该看到：nova-s3-credentials, nova-db-credentials, nova-redis-credentials, nova-jwt-keys
```

**Step 3: 检查 Deployments**
```bash
kubectl -n nova get deployments
# 应该看到 4 个 deployment 处于 READY 状态
```

**Step 4: 等待 Pods 启动**
```bash
kubectl -n nova get pods -w
# 所有 Pod 应该进入 Running 状态
```

**Step 5: 检查 Services**
```bash
kubectl -n nova get svc
# 应该看到 4 个 service
```

**Step 6: 检查 Ingress**
```bash
kubectl -n nova get ingress
```

### 生产环境部署

**Step 1: 确认环境**
```bash
# 检查当前 context
kubectl config current-context

# 如果不是生产集群，切换到生产
kubectl config use-context production-cluster
```

**Step 2: 应用生产配置**
```bash
# 先 dry-run 看会发生什么
kubectl apply -k k8s/overlays/prod --dry-run=client

# 应用实际配置
kubectl apply -k k8s/overlays/prod
```

**Step 3: 监控部署进度**
```bash
kubectl -n nova rollout status deployment/content-service
kubectl -n nova rollout status deployment/media-service
kubectl -n nova rollout status deployment/user-service
kubectl -n nova rollout status deployment/messaging-service
```

**Step 4: 验证所有 Pods 运行**
```bash
kubectl -n nova get pods -o wide
# 应该看到 12 个 Pod（每个服务 3 个副本）
# 它们应该分布在不同节点上
```

## 部署后验证

### 功能验证

- [ ] 所有 Services 已创建
  ```bash
  kubectl -n nova get svc -o wide
  ```

- [ ] 所有 Pods 状态为 Running
  ```bash
  kubectl -n nova get pods
  # 应该看到所有 Pod 的 STATUS 都是 Running
  ```

- [ ] Liveness/Readiness 探针成功
  ```bash
  kubectl -n nova describe pod <pod-name> | grep -A5 "Liveness\|Readiness"
  ```

- [ ] Services 有有效的 Endpoints
  ```bash
  kubectl -n nova get endpoints
  # 每个 service 都应该有多个 endpoints
  ```

- [ ] Ingress 已配置正确
  ```bash
  kubectl -n nova describe ingress nova-api-gateway
  ```

### API 端点验证

- [ ] Content Service API 可访问
  ```bash
  kubectl -n nova port-forward svc/content-service 8081:8081
  # 在另一个终端
  curl http://localhost:8081/api/v1/health
  ```

- [ ] Media Service API 可访问
  ```bash
  kubectl -n nova port-forward svc/media-service 8082:8082
  curl http://localhost:8082/api/v1/health
  ```

- [ ] User Service API 可访问
  ```bash
  kubectl -n nova port-forward svc/user-service 8083:8083
  curl http://localhost:8083/api/v1/health
  ```

- [ ] Messaging Service API 可访问
  ```bash
  kubectl -n nova port-forward svc/messaging-service 8084:8084
  curl http://localhost:8084/api/v1/health
  ```

### 性能和资源验证

- [ ] Pod 资源使用正常
  ```bash
  kubectl -n nova top pods
  # 检查 CPU 和 Memory 使用是否在合理范围内
  ```

- [ ] HPA (自动伸缩) 工作正常
  ```bash
  kubectl -n nova get hpa
  kubectl -n nova describe hpa content-service-hpa
  ```

- [ ] 没有 Pod 错误
  ```bash
  kubectl -n nova get pods -o json | jq '.items[].status.containerStatuses[] | select(.state | has("waiting") or has("terminated"))'
  ```

## 生产部署特殊检查

### 高可用性验证

- [ ] 每个服务有多个副本运行
  ```bash
  kubectl -n nova get deployment -o wide
  # 每个 deployment DESIRED 和 CURRENT 应该都是 3
  ```

- [ ] Pods 分布在不同节点
  ```bash
  kubectl -n nova get pods -o wide | awk '{print $7}' | sort | uniq -c
  # 同一服务的 Pod 应该在不同节点
  ```

- [ ] Pod Disruption Budgets 已配置（可选）
  ```bash
  kubectl -n nova get poddisruptionbudgets
  ```

### 监控和日志

- [ ] 可以正常查看 Pod 日志
  ```bash
  kubectl -n nova logs deployment/content-service
  kubectl -n nova logs deployment/content-service --previous  # 查看重启前日志
  ```

- [ ] Prometheus metrics 可访问（如已配置）
  ```bash
  kubectl -n nova port-forward svc/content-service 8081:8081
  curl http://localhost:8081/metrics
  ```

- [ ] 日志聚合工作正常（如已配置）

### 安全验证

- [ ] Secrets 已加密存储
  ```bash
  # 检查 etcd encryption 配置（取决于集群设置）
  ```

- [ ] RBAC 权限已配置
  ```bash
  kubectl -n nova get rolebindings
  kubectl -n nova get serviceaccounts
  ```

- [ ] Network Policies 已应用
  ```bash
  kubectl -n nova get networkpolicies
  ```

- [ ] Pod Security Policies/Standards 已应用（K8s 1.25+）

## 常见问题和回滚

### 如果部署失败

1. **检查错误信息**
   ```bash
   kubectl -n nova describe pod <failing-pod>
   kubectl -n nova logs <failing-pod>
   ```

2. **检查资源约束**
   ```bash
   kubectl describe nodes
   kubectl -n nova top pods
   ```

3. **回滚到上一个版本**
   ```bash
   kubectl rollout undo deployment/content-service
   kubectl -n nova rollout status deployment/content-service
   ```

### 如果 Pod 无法启动

- [ ] 检查 Docker 镜像是否存在和可访问
- [ ] 检查环境变量是否正确设置
- [ ] 检查 Secrets 是否已创建
- [ ] 检查网络连通性（特别是到数据库的连接）
- [ ] 检查资源请求是否超过节点可用资源

## 完成后步骤

- [ ] 文档已更新
- [ ] 监控告警已配置
- [ ] 备份策略已实施
- [ ] 灾难恢复计划已制定
- [ ] 团队培训已完成
- [ ] 维护计划已制定

## 签名和日期

部署人员: ____________________

部署日期: ____________________

验证人员: ____________________

验证日期: ____________________

---

**注意**: 保留此检查清单的副本以供记录和将来的参考。

# Nova Kubernetes Deployment Guide

This guide covers deploying the Nova microservices architecture to Kubernetes. The deployment is organized using Kustomize for environment-specific configurations (dev, staging, prod).

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌─────────────────────────────────┐      │
│  │   Ingress    │  │  Nova Namespace (nova)           │      │
│  │  Controller  │  │  ┌────────────────────────────┐ │      │
│  └──────────────┘  │  │                            │ │      │
│        │           │  │  ┌──────────────┐          │ │      │
│        └─────────► │  │  │ content-svc  │ (8081)   │ │      │
│                    │  │  │ 2 replicas   │          │ │      │
│                    │  │  └──────────────┘          │ │      │
│                    │  │                            │ │      │
│                    │  │  ┌──────────────┐          │ │      │
│                    │  │  │ media-svc    │ (8082)   │ │      │
│                    │  │  │ 2 replicas   │          │ │      │
│                    │  │  └──────────────┘          │ │      │
│                    │  │                            │ │      │
│                    │  │  ┌──────────────┐          │ │      │
│                    │  │  │ user-svc     │ (8083)   │ │      │
│                    │  │  │ 2 replicas   │          │ │      │
│                    │  │  └──────────────┘          │ │      │
│                    │  │                            │ │      │
│                    │  │  ┌──────────────┐          │ │      │
│                    │  │  │ messaging-svc│ (8084)   │ │      │
│                    │  │  │ 2 replicas   │          │ │      │
│                    │  │  └──────────────┘          │ │      │
│                    │  │                            │ │      │
│                    │  └────────────────────────────┘ │      │
│                    │                                  │      │
│                    │  ┌────────────────────────────┐ │      │
│                    │  │ Shared Storage             │ │      │
│                    │  │ - ConfigMap (nova-config)  │ │      │
│                    │  │ - Secrets (credentials)    │ │      │
│                    │  └────────────────────────────┘ │      │
│                    └─────────────────────────────────┘      │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Supporting Services (可选，或使用托管服务)            │  │
│  │  - PostgreSQL (DB)                                    │  │
│  │  - Redis (Cache/Pub-Sub)                              │  │
│  │  - Kafka (Message Queue)                              │  │
│  │  - ClickHouse (Analytics)                             │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
k8s/
├── base/                          # Base Kustomization (所有环境共同的资源)
│   ├── namespace.yaml             # Nova namespace
│   ├── configmap.yaml             # 全局配置
│   ├── secrets.yaml               # 敏感信息（需要由 CI/CD 替换）
│   ├── content-service.yaml       # 贴文服务部署
│   ├── media-service.yaml         # 媒体服务部署
│   ├── user-service.yaml          # 用户服务部署
│   ├── messaging-service.yaml     # 消息服务部署
│   ├── ingress.yaml               # API Gateway (Nginx Ingress)
│   └── kustomization.yaml         # Base 配置
│
├── overlays/
│   ├── dev/                       # 开发环境配置
│   │   ├── kustomization.yaml
│   │   ├── deployment-patch.yaml
│   │   └── replicas-patch.yaml
│   │
│   ├── prod/                      # 生产环境配置
│   │   ├── kustomization.yaml
│   │   ├── deployment-patch.yaml
│   │   └── hpa-patch.yaml
│   │
│   └── staging/                   # 测试环境配置 (可选)
│       ├── kustomization.yaml
│       └── deployment-patch.yaml
│
├── README.md                      # 本文件
└── DEPLOYMENT_CHECKLIST.md        # 部署检查清单
```

## Prerequisites

### 必需工具
- kubectl >= 1.24
- kustomize >= 4.5 (或 kubectl with -k flag)
- Docker CLI (用于构建镜像)
- Git

### Kubernetes 集群要求
- 至少 3 个 worker 节点（生产环境）
- 每个节点最少 2 CPU，4GB 内存
- 已安装 Nginx Ingress Controller
- 已安装 cert-manager（可选，用于 TLS）

### 外部依赖
- PostgreSQL 15+ (或 AWS RDS)
- Redis 7+ (或 AWS ElastiCache)
- Kafka (或 AWS MSK)
- ClickHouse (或自管理)
- S3 或 S3-compatible 存储 (AWS S3 / MinIO / etc.)

## Quick Start

### 1. 准备 Secrets

```bash
# 创建 secrets 文件 (使用实际值替换)
cd k8s/base

# 编辑 secrets.yaml 替换占位符
vi secrets.yaml

# 设置环境变量用于模板替换
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export DB_PASSWORD="your-db-password"
export JWT_PUBLIC_KEY="$(cat path/to/public.pem | base64)"
export JWT_PRIVATE_KEY="$(cat path/to/private.pem | base64)"
```

### 2. 构建 Docker 镜像

```bash
# 构建所有服务镜像
cd backend

# Content Service
cd content-service
docker build -t nova/content-service:v1.0.0 .
docker push nova/content-service:v1.0.0

# Media Service
cd ../media-service
docker build -t nova/media-service:v1.0.0 .
docker push nova/media-service:v1.0.0

# User Service
cd ../user-service
docker build -t nova/user-service:v1.0.0 .
docker push nova/user-service:v1.0.0

# Messaging Service
cd ../messaging-service
docker build -t nova/messaging-service:v1.0.0 .
docker push nova/messaging-service:v1.0.0
```

### 3. 部署到开发环境

```bash
# 查看即将部署的资源
kustomize build k8s/overlays/dev

# 应用部署
kubectl apply -k k8s/overlays/dev

# 验证部署
kubectl -n nova get deployments
kubectl -n nova get pods
kubectl -n nova get services
kubectl -n nova get ingress
```

### 4. 验证部署

```bash
# 检查 Pod 状态
kubectl -n nova get pods -w

# 查看 Pod 日志
kubectl -n nova logs -f deployment/content-service

# 检查服务就绪情况
kubectl -n nova get endpoints

# 验证 API 可访问性
kubectl -n nova port-forward svc/content-service 8081:8081
curl http://localhost:8081/api/v1/health
```

## 部署指南

### 开发环境部署

**特点：**
- 1 个副本 (节省资源)
- Debug 日志级别
- ImagePullPolicy: Always (总是拉取最新镜像)
- 较低的资源限制

```bash
kubectl apply -k k8s/overlays/dev
```

**验证:**
```bash
kubectl -n nova get pods
# 应该看到 4 个 Pod（每个服务 1 个）
```

### 生产环境部署

**特点：**
- 3 个副本 (高可用)
- Info 日志级别
- ImagePullPolicy: IfNotPresent
- 更高的资源限制
- Topology Spread Constraints (跨节点分布)

```bash
# 1. 确保使用正确的镜像版本
export VERSION="v1.0.0"

# 2. 应用生产配置
kubectl apply -k k8s/overlays/prod

# 3. 验证部署
kubectl -n nova get pods -o wide
kubectl -n nova get hpa

# 4. 验证 Ingress
kubectl -n nova get ingress
```

**验证:**
```bash
# 检查所有 Pod 都在不同节点上运行
kubectl -n nova get pods -o wide | grep -E 'content-service|media-service|user-service|messaging-service'

# 每个服务应该在不同节点 (NODE 列不同)
```

## Configuration Management

### ConfigMap 配置

全局配置在 `k8s/base/configmap.yaml` 中定义：

```yaml
APP_ENV: production
KAFKA_BROKERS: kafka:9092
CLICKHOUSE_URL: http://clickhouse:8123
JAEGER_AGENT_HOST: jaeger-agent
```

**更新配置：**
```bash
# 编辑 configmap
kubectl -n nova edit configmap nova-config

# 或者编辑文件后应用
kubectl apply -f k8s/base/configmap.yaml
```

注意：修改 ConfigMap 后，Pod 不会自动重启。需要手动重启：
```bash
kubectl -n nova rollout restart deployment/content-service
kubectl -n nova rollout restart deployment/media-service
kubectl -n nova rollout restart deployment/user-service
kubectl -n nova rollout restart deployment/messaging-service
```

### Secrets 管理

敏感信息存储在 Secrets 中：

```bash
# 查看 Secrets (base64 编码，不显示明文)
kubectl -n nova get secrets

# 编辑 Secret
kubectl -n nova edit secret nova-db-credentials

# 更新特定 Secret 字段
kubectl -n nova patch secret nova-s3-credentials \
  -p '{"data":{"AWS_ACCESS_KEY_ID":"'$(echo -n 'new-key' | base64 -w0)'"}}'
```

**安全最佳实践：**
- 不要将 Secrets 提交到 Git（使用 Sealed Secrets 或 External Secrets Operator）
- 使用 Kubernetes RBAC 限制 Secret 访问
- 启用 Secret 加密（etcd encryption）

## Scaling

### 水平扩展（增加副本数）

```bash
# 使用 Kustomize patch
# 编辑 overlays/prod/replicas-patch.yaml

# 或者直接使用 kubectl
kubectl -n nova scale deployment/content-service --replicas=5

# 使用 HPA 自动扩展
kubectl -n nova get hpa
kubectl -n nova describe hpa content-service-hpa
```

### 垂直扩展（增加资源限制）

编辑相应的部署 YAML 文件中的 `resources.limits` 和 `resources.requests`。

```bash
# 应用更新
kubectl apply -k k8s/overlays/prod
```

## Monitoring and Logging

### 视图 Pod 日志

```bash
# 查看特定 Pod 日志
kubectl -n nova logs <pod-name>

# 跟随日志输出
kubectl -n nova logs -f <pod-name>

# 查看多个 Pod 的日志
kubectl -n nova logs -f deployment/content-service

# 查看上一个已终止 Pod 的日志
kubectl -n nova logs <pod-name> --previous
```

### 监控 Pod 性能

```bash
# 查看 Pod 资源使用情况
kubectl -n nova top pods

# 查看节点资源使用情况
kubectl top nodes

# 持续监控
kubectl -n nova top pods --watch
```

### 事件日志

```bash
# 查看 Namespace 事件
kubectl -n nova get events

# 查看特定对象的事件
kubectl -n nova describe pod <pod-name>
```

## Troubleshooting

### Pod 无法启动

```bash
# 检查 Pod 状态
kubectl -n nova describe pod <pod-name>

# 查看错误日志
kubectl -n nova logs <pod-name>

# 常见问题：
# 1. ImagePullBackOff - 镜像不存在或拉取失败
#    检查: docker pull nova/content-service:v1.0.0
#
# 2. CrashLoopBackOff - 应用启动失败
#    检查: kubectl logs <pod-name>, 应用配置
#
# 3. Pending - Pod 等待资源
#    检查: kubectl describe node, 资源是否足够
```

### Service 无法访问

```bash
# 检查 Service 是否存在
kubectl -n nova get svc

# 检查 Endpoints
kubectl -n nova get endpoints

# 检查 Ingress
kubectl -n nova describe ingress nova-api-gateway

# 测试 Service 连通性
kubectl -n nova run -it --rm debug --image=busybox --restart=Never -- sh
# 在 Pod 内测试
/ # wget -O- http://content-service:8081/api/v1/health
```

### Ingress 无法路由

```bash
# 检查 Ingress 配置
kubectl -n nova describe ingress nova-api-gateway

# 检查 Nginx Ingress Controller 日志
kubectl -n ingress-nginx logs -f deployment/nginx-ingress-controller

# 测试 DNS 解析
nslookup api.nova.local
```

## Rolling Updates

### 更新镜像

```bash
# 方法 1: 编辑 Deployment
kubectl -n nova set image deployment/content-service \
  content-service=nova/content-service:v1.1.0

# 方法 2: 编辑 YAML 并应用
# 编辑 k8s/base/content-service.yaml
# 修改 image: nova/content-service:${VERSION:-latest}
kubectl apply -k k8s/overlays/prod

# 监视更新过程
kubectl -n nova rollout status deployment/content-service

# 查看更新历史
kubectl -n nova rollout history deployment/content-service
```

### 回滚

```bash
# 回滚到上一个版本
kubectl -n nova rollout undo deployment/content-service

# 回滚到特定版本
kubectl -n nova rollout undo deployment/content-service --to-revision=2

# 验证回滚
kubectl -n nova rollout status deployment/content-service
```

## Backup & Disaster Recovery

### 备份 Kubernetes 资源

```bash
# 导出整个 namespace
kubectl -n nova get all -o yaml > nova-backup.yaml

# 导出特定资源类型
kubectl -n nova get deployments -o yaml > deployments-backup.yaml
kubectl -n nova get services -o yaml > services-backup.yaml
kubectl -n nova get configmap -o yaml > configmap-backup.yaml
kubectl -n nova get secrets -o yaml > secrets-backup.yaml
```

### 恢复

```bash
# 恢复资源
kubectl apply -f nova-backup.yaml
```

**注意：** 对于生产环境，使用 Velero 或其他专业备份解决方案。

## Security

### RBAC (Role-Based Access Control)

每个服务都有自己的 ServiceAccount，限制权限。

```bash
# 检查 ServiceAccount
kubectl -n nova get serviceaccount

# 检查 Role/RoleBinding
kubectl -n nova get role,rolebinding
```

### Network Policies

NetworkPolicy 限制 Pod 之间的流量。

```bash
# 检查 NetworkPolicy
kubectl -n nova get networkpolicies

# 测试网络隔离
kubectl -n nova run -it --rm test --image=busybox --restart=Never -- sh
```

## Cleanup

### 删除部署

```bash
# 删除 Overlay
kubectl delete -k k8s/overlays/prod

# 删除整个 namespace
kubectl delete namespace nova
```

## CI/CD Integration

### 使用 ArgoCD

```bash
# 创建 ArgoCD Application
cat << 'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/nova
    targetRevision: main
    path: k8s/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: nova
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### 使用 GitHub Actions

```yaml
# .github/workflows/deploy.yml
name: Deploy to Kubernetes

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: azure/setup-kubectl@v3
      - run: |
          kubectl config use-context production
          kubectl apply -k k8s/overlays/prod
```

## 常见问题

**Q: 如何访问 Services？**
A: 使用 port-forward 用于本地开发，使用 Ingress 用于生产。

**Q: 如何更新 ConfigMap 而不重启 Pod？**
A: Pod 不会自动检测 ConfigMap 更改。需要手动重启：
```bash
kubectl rollout restart deployment/content-service
```

**Q: Pod 内如何访问外部数据库？**
A: 使用环境变量中的连接字符串（DATABASE_URL）。确保 Pod 的网络策略允许出站流量。

**Q: 如何处理持久化存储？**
A: 使用 PersistentVolumeClaim (PVC) 或托管存储服务（AWS RDS, ElastiCache）。

## 相关文档

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Kustomize 文档](https://kustomize.io/)
- [Nginx Ingress 文档](https://kubernetes.github.io/ingress-nginx/)
- [ArgoCD 文档](https://argo-cd.readthedocs.io/)

## 支持

遇到问题？检查以下资源：
1. Pod 日志: `kubectl -n nova logs <pod-name>`
2. 事件: `kubectl -n nova get events`
3. 描述资源: `kubectl -n nova describe <resource-type> <name>`

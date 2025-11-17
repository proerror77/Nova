# Nova Kubernetes Deployment - Unified Configuration

统一的 Kubernetes 部署配置仓库，包含基础设施和微服务部署。

## 目录结构

```
k8s/
├── infrastructure/              # 基础设施 (数据库、缓存、网络)
│   ├── base/                   # Kustomize base 配置
│   │   ├── kustomization.yaml
│   │   ├── configmap.yaml
│   │   ├── secrets.yaml
│   │   ├── namespace.yaml
│   │   ├── postgres.yaml
│   │   ├── identity-service.yaml
│   │   ├── content-service.yaml
│   │   ├── media-service.yaml
│   │   ├── social-service.yaml
│   │   └── ingress.yaml
│   ├── overlays/               # 环境覆盖 (dev, prod, staging)
│   │   ├── dev/
│   │   │   ├── kustomization.yaml
│   │   │   └── deployment-patch.yaml
│   │   └── prod/
│   │       ├── kustomization.yaml
│   │       └── deployment-patch.yaml
│   ├── local/                  # 本地开发配置
│   │   ├── elasticsearch.yaml
│   │   ├── redpanda.yaml
│   │   └── search-service.yaml
│   ├── postgres.yaml           # PostgreSQL 配置
│   ├── redis.yaml              # Redis 配置
│   ├── rbac.yaml               # RBAC 权限配置
│   ├── secret.yaml             # 全局密钥
│   ├── deployment.yaml         # 通用部署配置
│   ├── configmap.yaml          # 全局配置
│   ├── hpa.yaml                # 水平自动扩展
│   ├── ingress.yaml            # 入口配置
│   ├── namespace.yaml          # 命名空间
│   └── kustomization.yaml      # Kustomize 主配置
│
├── microservices/              # 微服务部署配置
│   ├── api-gateway/            # API Gateway 配置
│   │   ├── configmap-nginx.yaml
│   │   ├── deployment.yaml
│   │   ├── namespace.yaml
│   │   └── service.yaml
│   ├── realtime-chat-service-deployment.yaml
│   ├── realtime-chat-service-configmap.yaml
│   ├── realtime-chat-service-secret.yaml
│   ├── realtime-chat-service-service.yaml
│   ├── realtime-chat-service-serviceaccount.yaml
│   ├── realtime-chat-service-hpa.yaml
│   ├── realtime-chat-service-pdb.yaml
│   ├── ingress.yaml            # 微服务路由配置
│   ├── ingress-tls-setup.yaml  # TLS 安全配置
│   ├── gitops-argocd-setup.yaml # GitOps / ArgoCD 配置
│   ├── prometheus-monitoring-setup.yaml # 监控配置
│   ├── turn-server-deployment.yaml # TURN 服务器 (WebRTC)
│   ├── s3-configmap.yaml       # S3 存储配置
│   └── s3-secret.yaml          # S3 密钥
│
├── docs/                       # 部署文档和指南
│   ├── README.md              # 原始架构指南
│   ├── DEPLOYMENT_GUIDE.md    # 详细部署步骤
│   ├── QUICK_START.md         # 快速开始指南
│   ├── QUICK_REFERENCE.md     # 快速参考
│   ├── CHEAT_SHEET.md         # Kubectl 快速查询
│   ├── DEPLOYMENT_CHECKLIST.md # 部署检查清单
│   ├── MICROSERVICES_README.md # 微服务特定说明
│   ├── COMPLETION_SUMMARY.md  # 完成总结
│   ├── INDEX.md               # 文档索引
│   ├── LOCAL_FILES_SUMMARY.md # 本地文件总结
│   ├── LOCAL_VERIFICATION.md  # 本地验证指南
│   ├── OPTIONAL_ENHANCEMENTS.md # 可选增强功能
│   └── OPTIONAL_ENHANCEMENTS_DEPLOYMENT_CHECKLIST.md
│
└── scripts/                    # 部署脚本
    ├── quick-start-local.sh   # 本地快速启动
    ├── verify-local.sh        # 本地验证
    └── DEPLOYMENT_QUICK_COMMANDS.sh # 快速部署命令

```

## 快速开始

### 1. 本地开发 (Docker Compose)

```bash
cd scripts/
bash quick-start-local.sh
bash verify-local.sh
```

### 2. Kubernetes 部署 (Dev 环境)

```bash
# 使用 Kustomize 部署到 dev 环境
kubectl apply -k infrastructure/overlays/dev/

# 部署微服务
kubectl apply -f microservices/
```

### 3. 生产环境部署

```bash
# 使用 Kustomize 部署到 prod 环境
kubectl apply -k infrastructure/overlays/prod/

# 使用 ArgoCD 实现 GitOps (可选)
kubectl apply -f microservices/gitops-argocd-setup.yaml
```

## 主要组件

### 基础设施 (infrastructure/)

- **数据库**: PostgreSQL、ClickHouse
- **缓存**: Redis
- **网络**: Ingress Controller、Service
- **监控**: Prometheus、Grafana (可选)
- **认证**: RBAC、Secrets

### 微服务 (microservices/)

- **API Gateway**: Nginx 反向代理 + 路由
- **Messaging Service**: 实时消息、WebSocket
- **其他服务**: Content、Media、User 等 (在 infrastructure/base 中定义)

### 部署模式

- **Kustomize**: 管理环境特定配置 (dev/prod/staging)
- **GitOps (ArgoCD)**: 持续部署和配置管理 (可选)

## 文档指南

| 文档 | 用途 |
|-----|------|
| `QUICK_START.md` | 初次部署者必读 |
| `DEPLOYMENT_GUIDE.md` | 详细的分步部署说明 |
| `CHEAT_SHEET.md` | Kubectl 常用命令 |
| `DEPLOYMENT_CHECKLIST.md` | 部署前检查清单 |

## 常见任务

### 查看部署状态

```bash
kubectl get deployments -n nova
kubectl get pods -n nova
kubectl logs <pod-name> -n nova
```

### 更新配置

```bash
# 编辑 ConfigMap
kubectl edit configmap nova-config -n nova

# 重启 Pod 使配置生效
kubectl rollout restart deployment/<service-name> -n nova
```

### 扩展服务

```bash
# 手动扩展
kubectl scale deployment <service-name> --replicas=3 -n nova

# 自动扩展 (基于 HPA)
kubectl get hpa -n nova
```

### 查看日志

```bash
# 实时日志
kubectl logs -f <pod-name> -n nova

# 前一个 Pod 的日志 (崩溃后)
kubectl logs <pod-name> --previous -n nova
```

## 环境特定配置

### 开发环境 (Dev)

```bash
kubectl apply -k infrastructure/overlays/dev/
```

- CPU/内存请求较低
- 副本数较少 (1-2)
- 日志级别: DEBUG

### 生产环境 (Prod)

```bash
kubectl apply -k infrastructure/overlays/prod/
```

- 完整的资源请求和限制
- 副本数较多 (3+)
- 日志级别: INFO
- TLS/HTTPS 强制
- Pod 中断预算 (PDB)

## 故障排除

### Pod 无法启动

```bash
# 查看 Pod 事件
kubectl describe pod <pod-name> -n nova

# 查看 Pod 日志
kubectl logs <pod-name> -n nova
```

### 服务无法连接

```bash
# 验证 Service 存在
kubectl get svc -n nova

# 测试连接
kubectl run -it --rm debug --image=busybox -- sh
# 在容器内: wget http://service-name:port
```

### 数据库连接问题

```bash
# 验证 Secret
kubectl get secret -n nova
kubectl describe secret <secret-name> -n nova

# 验证数据库 Pod
kubectl get pod -l app=postgres -n nova
kubectl logs <postgres-pod> -n nova
```

## 监控和可观测性

### Prometheus

```bash
# 转发 Prometheus 端口
kubectl port-forward svc/prometheus 9090:9090 -n nova
# 访问: http://localhost:9090
```

### 日志收集

- 应用日志: 写入 stdout/stderr → Kubernetes 日志
- 集中式日志: 配置 ELK Stack / Loki (可选)

## 安全考虑

- 所有 Secrets 应使用 encrypted etcd
- 生产环境强制 HTTPS/TLS
- 定期更新镜像和依赖
- 实施网络策略隔离 Pod
- 使用 RBAC 限制权限

## 故障恢复 (Disaster Recovery)

- **备份数据库**: 定期备份 PostgreSQL
- **持久化存储**: 使用 PersistentVolume 和 PersistentVolumeClaim
- **灾难恢复计划**: 定期测试恢复流程

## 相关资源

- [Kustomize 文档](https://kustomize.io/)
- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [ArgoCD 文档](https://argo-cd.readthedocs.io/)
- [kubectl 备忘单](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

---

**最后更新**: 2025-10-30
**维护者**: Nova DevOps Team

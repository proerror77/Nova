# Nova Staging 架构设计

## 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                        │
│                                                                  │
│  git push origin main                                           │
│         │                                                        │
└─────────┼────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub Actions CI/CD Pipeline                 │
│                                                                  │
│  .github/workflows/staging-deploy.yml                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Job 1: build-and-push (8 services, max-parallel: 2)      │   │
│  │                                                           │   │
│  │  ┌──────────────┐  ┌──────────────┐                      │   │
│  │  │ auth-service │  │ user-service │ (parallel)           │   │
│  │  └──────┬───────┘  └──────┬───────┘                      │   │
│  │         │          │      │                              │   │
│  │  ┌──────▼────────────────▼──┐                            │   │
│  │  │ Docker Buildx (linux/amd64)                          │   │
│  │  └──────┬───────────────────┘                            │   │
│  │         │                                                │   │
│  │  ┌──────▼────────────────────────────────────────┐      │   │
│  │  │ AWS ECR Registry                              │      │   │
│  │  │ 025434362120.dkr.ecr.ap-northeast-1.amazonaws │      │   │
│  │  │ .com/nova/{service}:{commit-sha}              │      │   │
│  │  └──────────────────────────────────────────────┘      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Job 2: update-deployment                                │   │
│  │                                                           │   │
│  │  kustomize edit set image \                             │   │
│  │    nova/auth-service=...:abc123def456 \                │   │
│  │    nova/user-service=...:abc123def456 \                │   │
│  │    ...                                                  │   │
│  │                                                           │   │
│  │  git add k8s/infrastructure/overlays/staging/...        │   │
│  │  git commit -m "chore(staging): update image tags..."   │   │
│  │  git push origin main                                   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Job 3: deploy-to-staging                                │   │
│  │                                                           │   │
│  │  (Notifies ArgoCD to check for changes)                 │   │
│  │                                                           │   │
│  │  Reference: nova-staging Application                    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Job 4: smoke-test                                        │   │
│  │                                                           │   │
│  │  bash scripts/smoke-staging.sh                          │   │
│  │  - Check /health endpoints                              │   │
│  │  - Check /metrics endpoints                             │   │
│  │  - Verify Redis Sentinel                                │   │
│  │  - Verify Kafka availability                            │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Git Repository (main branch)                 │
│                                                                  │
│  k8s/infrastructure/overlays/staging/kustomization.yaml        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ images:                                                   │   │
│  │ - name: nova/auth-service                               │   │
│  │   newTag: abc123def456...                               │   │
│  │ - name: nova/user-service                               │   │
│  │   newTag: abc123def456...                               │   │
│  │ ...                                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ArgoCD (GitOps Controller)                   │
│                                                                  │
│  Application: nova-staging                                     │
│  - Watch: main branch                                          │
│  - Path: k8s/infrastructure/overlays/staging                   │
│  - Sync: automated (prune: true, selfHeal: true)              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ When changes detected:                                   │   │
│  │ 1. Pull latest kustomization.yaml                        │   │
│  │ 2. Run: kustomize build                                  │   │
│  │ 3. Render final K8s manifests                            │   │
│  │ 4. kubectl apply -f manifests.yaml                       │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│              Kubernetes Staging Cluster (EKS)                   │
│                                                                  │
│  Namespace: nova                                                │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Deployments (2 replicas each, staging resources):        │   │
│  │                                                           │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │   auth-      │  │    user-     │  │   content-   │   │   │
│  │  │  service     │  │   service    │  │   service    │   │   │
│  │  │              │  │              │  │              │   │   │
│  │  │ 100m CPU     │  │ 100m CPU     │  │ 100m CPU     │   │   │
│  │  │ 256Mi mem    │  │ 256Mi mem    │  │ 256Mi mem    │   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │   │
│  │                                                           │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │   feed-      │  │   media-     │  │ messaging-   │   │   │
│  │  │  service     │  │   service    │  │   service    │   │   │
│  │  │              │  │              │  │              │   │   │
│  │  │ 100m CPU     │  │ 100m CPU     │  │ 100m CPU     │   │   │
│  │  │ 512Mi mem    │  │ 512Mi mem    │  │ 512Mi mem    │   │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │   │
│  │                                                           │   │
│  │  ┌──────────────┐  ┌──────────────┐                     │   │
│  │  │   search-    │  │ streaming-   │                     │   │
│  │  │  service     │  │   service    │                     │   │
│  │  │              │  │              │                     │   │
│  │  │ 200m CPU     │  │ 100m CPU     │                     │   │
│  │  │ 512Mi mem    │  │ 512Mi mem    │                     │   │
│  │  └──────────────┘  └──────────────┘                     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Services (ClusterIP + Ingress):                          │   │
│  │  - auth-service:8084                                    │   │
│  │  - user-service:8080                                    │   │
│  │  - content-service:8081                                 │   │
│  │  - ... (and 5 more)                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 核心组件详解

### 1. GitHub Actions Workflow (staging-deploy.yml)

**责任**: 自动化 CI/CD 流程

**Jobs**:
1. **build-and-push**
   - 为 8 个微服务构建 Docker 镜像
   - 使用 Docker Buildx 支持 linux/amd64
   - 推送到 AWS ECR
   - 使用 registry cache 加速后续构建

2. **update-deployment**
   - 下载 kustomize CLI
   - 修改 `k8s/infrastructure/overlays/staging/kustomization.yaml`
   - 更新镜像标签为当前 commit SHA
   - 提交并推送到 main 分支

3. **deploy-to-staging**
   - 验证 staging kustomization 存在
   - 输出 ArgoCD Application 参考模板
   - ArgoCD 监听 main 分支的变更自动部署

4. **smoke-test**
   - 等待 ArgoCD 同步完成
   - 运行 `scripts/smoke-staging.sh`
   - 验证所有服务健康

5. **notify-completion**
   - 输出部署总结
   - 提供调试命令

### 2. Kustomize Overlay (staging)

**文件结构**:
```
k8s/infrastructure/
├── base/                          # 所有环境共享的基础配置
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── ...
└── overlays/
    ├── dev/                       # 开发环境特定配置
    │   ├── kustomization.yaml
    │   └── deployment-patch.yaml
    ├── prod/                      # 生产环境特定配置
    │   ├── kustomization.yaml
    │   └── deployment-patch.yaml
    └── staging/                   # 📦 Staging 环境特定配置
        ├── kustomization.yaml     # 8 个服务的镜像标签 + 副本数 + 资源
        └── deployment-patch.yaml  # Staging 特定的资源限制
```

**Staging 特性**:
- **镜像标签**: 通过 GitHub Actions 动态更新为 commit SHA
- **副本数**: 2 个 (高可用)
- **资源限制**: 中等 (100-200m CPU, 256Mi-512Mi 内存)
- **环境变量**: `APP_ENV=staging`, `LOG_LEVEL=info`

### 3. ArgoCD Application

**配置** (manual - 需要手动创建):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/proerror77/Nova.git
    targetRevision: main              # 监听 main 分支
    path: k8s/infrastructure/overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: nova
  syncPolicy:
    automated:
      prune: true      # 删除未在 Git 中的资源
      selfHeal: true   # 如果集群偏离 Git 自动同步
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### 4. Smoke Testing

**脚本**: `scripts/smoke-staging.sh`

**验证**:
- ✅ 所有 Pod 就绪
- ✅ `/health` 端点可用 (8 个服务)
- ✅ `/metrics` 端点可用 (Prometheus)
- ✅ Redis Sentinel 拓扑 (可选)
- ✅ Kafka 主题列表 (可选)

---

## 数据流示例

### 场景: 推送新代码到 main

```
时间    事件                           说明
────────────────────────────────────────────────────────────
T+0s   git push origin main           开发者推送代码

T+5s   GitHub Actions 触发            检测到 backend/ 目录变更

T+10s  build-and-push 开始            8 个服务并行构建
       - auth-service
       - user-service
       - content-service
       ... (6 more, max-parallel: 2)

T+8m   所有镜像推送到 ECR             完成时间约 8 分钟

T+8m   update-deployment 开始         kustomize 修改镜像标签
       before: newTag: latest
       after:  newTag: abc123def456

T+8m   git push 完成                  变更推送到 main 分支

T+8m   ArgoCD 检测变更               webhook 或定时轮询

T+11m  ArgoCD 开始同步               kustomize build + kubectl apply

T+13m  Pods 启动                     8 个 Deployment 各 2 个副本

T+14m  smoke-test 开始               验证所有服务健康

T+15m  部署完成                      新代码在 staging 运行
       所有检查通过 ✅
```

---

## 资源分配

### Staging 环境资源

| 服务 | Replicas | CPU Request | Memory Request | CPU Limit | Memory Limit |
|------|----------|-------------|----------------|-----------|--------------|
| auth-service | 2 | 100m | 256Mi | 500m | 512Mi |
| user-service | 2 | 100m | 256Mi | 500m | 512Mi |
| content-service | 2 | 100m | 256Mi | 500m | 512Mi |
| feed-service | 2 | 100m | 512Mi | 500m | 1Gi |
| media-service | 2 | 100m | 512Mi | 500m | 1Gi |
| messaging-service | 2 | 100m | 512Mi | 500m | 1Gi |
| search-service | 2 | 200m | 512Mi | 1000m | 2Gi |
| streaming-service | 2 | 100m | 512Mi | 500m | 1Gi |

**总计**: 16 Pods，总资源需求约 9 核 CPU，6.5 GB 内存

---

## 与其他环境的对比

### Dev 环境
```
Trigger: Manual / PR
Image:   dev-latest
Replicas: 1
Resources: Minimal (50m CPU, 128Mi mem)
Path: k8s/infrastructure/overlays/dev
```

### Staging 环境
```
Trigger: main branch push
Image:   commit SHA + latest
Replicas: 2
Resources: Medium (100-200m CPU, 256Mi-512Mi mem)
Path: k8s/infrastructure/overlays/staging
```

### Production 环境
```
Trigger: Release tag
Image:   release tag
Replicas: 3+
Resources: High (depends on service)
Path: k8s/infrastructure/overlays/prod
```

---

## 故障转移和高可用性

### Staging 级别
- **副本数**: 2 个 Pod（至少 1 个存活）
- **健康检查**: liveness + readiness probes
- **自我修复**: ArgoCD selfHeal 自动恢复偏离的资源

### ArgoCD 级别
- **重试机制**: 失败重试 5 次，指数退避
- **自动同步**: 自动同步启用，异常自动修复
- **资源剪枝**: 已删除的资源自动清理

---

## 安全性考虑

1. **镜像安全**
   - 所有镜像从私有 ECR registry 拉取
   - 镜像扫描 (ECR 内置漏洞扫描)
   - imagePullPolicy: Always

2. **访问控制**
   - ArgoCD RBAC 配置
   - Kubernetes RBAC (nova namespace)
   - GitHub Actions secrets (AWS_ROLE_ARN)
   - GitHub Actions OIDC 认证 (no long-lived keys)

3. **网络隔离**
   - Staging K8s 集群独立
   - 与生产环境网络隔离
   - 可选: NetworkPolicy 限制流量

---

## 监控和可观测性

### Prometheus 指标
- `/metrics` 端点在每个服务
- Prometheus scrape 配置监听 8080/8081/8082/8083/8084/3000/8000

### 日志
- stdout/stderr 日志
- 通过 kubectl logs 查看
- 可选: Fluentd/Filebeat 收集到 ELK/CloudWatch

### 事件
- Kubernetes events
- ArgoCD application logs
- GitHub Actions workflow logs

---

## 性能优化

### Docker 构建优化
- **Layer caching**: 使用 registry cache
- **Buildx parallelization**: max-parallel: 2
- **Multi-platform**: linux/amd64 specific

### ArgoCD 优化
- **比较结果缓存**: argocd.argoproj.io/compare-result: "false"
- **异步处理**: 不阻塞 webhook 返回
- **资源定额**: ResourceQuota 防止单个应用占用过多

---

## 总结

Staging 环境的完整流程：

```
推送代码
   ↓
GitHub Actions 自动化
   - 构建 + 推送镜像
   - 更新部署清单
   ↓
Git 变更
   ↓
ArgoCD 检测并同步
   - kustomize build
   - kubectl apply
   ↓
Kubernetes 部署
   - 新 Pods 启动
   - 旧 Pods 关闭 (rolling update)
   ↓
烟雾测试验证
   - 健康检查
   - 功能验证
   ↓
✅ Staging 环境就绪
```

这个架构实现了：
- ✅ **完全自动化**: 无需手动介入
- ✅ **Git 中心化**: 所有变更都在 Git 中可审计
- ✅ **声明式**: 使用 Kustomize 和 ArgoCD 声明式部署
- ✅ **可观测**: 完整的日志、指标、事件跟踪
- ✅ **快速反馈**: 15 分钟内获得部署结果

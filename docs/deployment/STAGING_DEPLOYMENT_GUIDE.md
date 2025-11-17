# Staging 部署指南 - Nova CI/CD Pipeline

## 概览

本指南详细说明 Nova 项目的 Staging 环境 CI/CD 部署流程,包括 Docker 构建、ECR 推送、Kustomize 配置管理和 ArgoCD GitOps 自动同步。

## 架构图

```
┌─────────────┐     ┌──────────────┐     ┌───────────────┐     ┌─────────────┐
│   GitHub    │────▶│ GitHub       │────▶│  AWS ECR      │────▶│  ArgoCD     │
│   Push      │     │ Actions      │     │  Registry     │     │  Sync       │
└─────────────┘     └──────────────┘     └───────────────┘     └─────────────┘
                           │                                            │
                           ▼                                            ▼
                    ┌──────────────┐                            ┌─────────────┐
                    │  Kustomize   │                            │ Kubernetes  │
                    │  Update      │                            │  Cluster    │
                    └──────────────┘                            └─────────────┘
```

## 前置条件

### 1. AWS 配置

#### IAM Role (已配置)
```yaml
Role ARN: arn:aws:iam::025434362120:role/github-actions-role
Account ID: 025434362120
Region: ap-northeast-1
```

#### ECR Repositories
所有 8 个服务的 ECR repositories 必须存在:
```bash
aws ecr describe-repositories --region ap-northeast-1 --query 'repositories[].repositoryName'

# Expected output:
# - nova/auth-service
# - nova/user-service
# - nova/content-service
# - nova/feed-service
# - nova/media-service
# - nova/messaging-service
# - nova/search-service
# - nova/streaming-service
```

### 2. Kubernetes 集群

#### 集群信息
- **EKS Cluster**: `nova-staging`
- **Namespace**: `nova`
- **Node Count**: 3+ (推荐)
- **Node Type**: t3.medium 或更高

#### 验证集群访问
```bash
aws eks update-kubeconfig --name nova-staging --region ap-northeast-1
kubectl cluster-info
kubectl get nodes
```

### 3. ArgoCD 安装

#### 安装 ArgoCD
```bash
# 1. 创建 namespace
kubectl create namespace argocd

# 2. 安装 ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. 等待 pods 就绪
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# 4. 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### 访问 ArgoCD UI
```bash
# Port-forward (开发环境)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 浏览器访问: https://localhost:8080
# Username: admin
# Password: (从上一步获取)
```

#### 创建 Nova Staging Application
```bash
kubectl apply -f k8s/argocd/nova-staging-application.yaml
```

### 4. GitHub Secrets 配置

在 GitHub Repository Settings → Secrets and variables → Actions 中配置:

| Secret Name | Value | 用途 |
|------------|-------|------|
| `AWS_ROLE_ARN` | `arn:aws:iam::025434362120:role/github-actions-role` | AWS OIDC 认证 |

**注意**: 不需要 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY` - 使用 OIDC 认证更安全。

## CI/CD 流程详解

### 阶段 1: 触发构建

#### 自动触发
```yaml
# Push 到 main 分支且修改 backend/ 或 k8s/ 路径
on:
  push:
    branches:
      - main
    paths:
      - 'backend/**'
      - 'k8s/**'
```

#### 手动触发
```bash
# 通过 GitHub CLI
gh workflow run staging-deploy-optimized.yml

# 或在 GitHub UI 中点击 "Run workflow"
```

### 阶段 2: 构建 Docker 镜像

#### Matrix Strategy
```yaml
strategy:
  matrix:
    service: [auth-service, user-service, ...]
  max-parallel: 4  # 并行构建 4 个服务
  fail-fast: false # 一个失败不影响其他服务
```

#### 缓存策略 (多层)
```yaml
cache-from:
  - type=gha                    # GitHub Actions cache
  - type=registry,ref=...       # ECR registry cache

cache-to:
  - type=gha,mode=max           # 缓存所有层
  - type=registry,mode=max      # 推送到 ECR
  - type=inline                 # 内联缓存到镜像
```

#### 镜像标签
```bash
# 只推 SHA tag (不推 latest,避免冲突)
$REGISTRY/nova/$SERVICE:$GITHUB_SHA

# 例如:
# 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/auth-service:a6fdf32
```

### 阶段 3: 更新 Kustomization

#### Kustomize 编辑
```bash
cd k8s/infrastructure/overlays/staging

kustomize edit set image \
  nova/auth-service=$REGISTRY/nova/auth-service:$GITHUB_SHA \
  nova/user-service=$REGISTRY/nova/user-service:$GITHUB_SHA \
  # ... (所有 8 个服务)
```

#### Git Commit
```bash
git add k8s/infrastructure/overlays/staging/kustomization.yaml
git commit -m "chore(staging): update images to $GITHUB_SHA"
git push origin main
```

### 阶段 4: ArgoCD 自动同步

#### Sync Policy
```yaml
syncPolicy:
  automated:
    prune: true      # 删除 Git 中不存在的资源
    selfHeal: true   # 集群状态漂移时自动同步
```

#### 同步流程
1. ArgoCD 检测到 Git 仓库变化 (每 3 分钟轮询)
2. 对比 Git 状态 vs Cluster 状态
3. 自动执行 `kubectl apply -k k8s/infrastructure/overlays/staging`
4. 等待所有 Pods 达到 Healthy 状态
5. 标记为 Synced + Healthy

#### 监控同步状态
```bash
# 查看 Application 状态
kubectl get application nova-staging -n argocd

# 查看详细信息
kubectl describe application nova-staging -n argocd

# 实时日志
kubectl logs -f -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### 阶段 5: 验证部署

#### 自动验证
```bash
# Workflow 会自动等待 2 分钟后检查:
# 1. ArgoCD sync status
# 2. Pod readiness
# 3. Health endpoints
```

#### 手动验证
```bash
# 1. 检查所有 Pods
kubectl get pods -n nova

# 期望输出:
# auth-service-xxx    2/2  Running
# user-service-xxx    2/2  Running
# ... (所有服务)

# 2. 检查 Deployments
kubectl rollout status deployment/auth-service -n nova

# 3. 测试健康检查
kubectl port-forward svc/auth-service 8080:8080 -n nova
curl http://localhost:8080/health

# 4. 查看日志
kubectl logs -f deployment/auth-service -n nova --tail=50
```

## 故障排查

### 问题 1: Docker 构建失败

#### 症状
```
ERROR: failed to solve: failed to compute cache key
```

#### 原因
- Dockerfile 语法错误
- 缺少依赖文件
- Workspace 结构不匹配

#### 解决方法
```bash
# 本地测试构建
docker build -f backend/auth-service/Dockerfile -t test:local .

# 检查 Dockerfile 路径
ls -la backend/auth-service/Dockerfile

# 验证 context
docker build --dry-run -f backend/auth-service/Dockerfile .
```

### 问题 2: ECR Push 失败

#### 症状
```
Error: failed to push: unexpected status: 403 Forbidden
```

#### 原因
- AWS 权限不足
- OIDC 认证失败
- ECR repository 不存在

#### 解决方法
```bash
# 1. 验证 IAM Role 权限
aws sts get-caller-identity

# 2. 手动登录 ECR
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com

# 3. 检查 repository 存在
aws ecr describe-repositories --repository-names nova/auth-service --region ap-northeast-1

# 4. 创建 repository (如果不存在)
aws ecr create-repository --repository-name nova/auth-service --region ap-northeast-1
```

### 问题 3: ArgoCD 不同步

#### 症状
- Git 更新了但 K8s 没变化
- Application 状态显示 OutOfSync

#### 原因
- ArgoCD Application 未创建
- Sync Policy 未启用 automated
- Kustomization 语法错误

#### 解决方法
```bash
# 1. 检查 Application 存在
kubectl get application nova-staging -n argocd

# 2. 手动触发同步
kubectl patch application nova-staging -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'

# 3. 查看同步日志
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# 4. 验证 Kustomization 语法
kubectl kustomize k8s/infrastructure/overlays/staging | head -50
```

### 问题 4: Pods 无法启动

#### 症状
```
CrashLoopBackOff
ImagePullBackOff
```

#### 原因
- 镜像不存在或 tag 错误
- 资源不足
- 配置错误

#### 解决方法
```bash
# 1. 查看 Pod 事件
kubectl describe pod auth-service-xxx -n nova

# 2. 查看容器日志
kubectl logs auth-service-xxx -n nova

# 3. 验证镜像存在
aws ecr describe-images --repository-name nova/auth-service \
  --image-ids imageTag=a6fdf32 --region ap-northeast-1

# 4. 检查资源配额
kubectl describe nodes
kubectl top nodes
```

## 性能优化建议

### 1. Docker 构建优化

#### 使用 cargo-chef 缓存依赖
参考 `backend/auth-service/Dockerfile.optimized`:
- 分离依赖构建和代码编译
- 依赖层单独缓存,代码变更不重新编译依赖
- 构建时间减少 60%+

#### BuildKit 配置
```yaml
# GitHub Actions
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
    build-args: |
      BUILDKIT_INLINE_CACHE=1
```

### 2. GitHub Actions 优化

#### 并行度调优
```yaml
# 根据服务复杂度调整
strategy:
  max-parallel: 4  # 推荐 2-4,取决于 runner 性能
```

#### Runner 选择
```yaml
runs-on: ubuntu-22.04  # 比 ubuntu-latest 更稳定
# 考虑使用 self-hosted runner 以获得更好性能
```

### 3. ArgoCD 优化

#### 同步策略
```yaml
syncPolicy:
  syncOptions:
    - ApplyOutOfSyncOnly=true  # 只同步变化的资源
    - PruneLast=true           # 先创建新资源再删除旧资源
```

#### Webhook 配置 (可选)
```bash
# 配置 GitHub Webhook 实现即时同步
# Settings → Webhooks → Add webhook
# URL: https://argocd.your-domain/api/webhook
# Events: Push events
```

## 监控和告警

### 1. GitHub Actions 通知

#### Slack 集成
```yaml
# 在 workflow 添加:
- name: Notify Slack on failure
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
```

### 2. ArgoCD 通知

#### 配置 Slack 通知
```yaml
# argocd-notifications ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  trigger.on-deployed: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-deployed]
```

### 3. Prometheus Metrics

#### 暴露 Metrics
```yaml
# 在 deployment 添加:
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

## 安全最佳实践

### 1. 镜像签名 (推荐)

```bash
# 使用 cosign 签名镜像
cosign sign --key cosign.key $IMAGE:$TAG

# 在 K8s 验证签名
# 使用 Kyverno Policy
```

### 2. Secret 管理

```bash
# 不要在 Git 中存储 secrets
# 使用 External Secrets Operator

kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: nova-db-credentials
  namespace: nova
spec:
  secretStoreRef:
    name: aws-secrets-manager
  target:
    name: nova-db-credentials
  data:
    - secretKey: auth-db-url
      remoteRef:
        key: nova/staging/auth-db-url
EOF
```

### 3. RBAC 配置

```yaml
# 最小权限原则
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-deployer
  namespace: nova
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "update", "patch"]
```

## 常用命令速查

```bash
# === GitHub Actions ===
gh workflow list
gh workflow run staging-deploy-optimized.yml
gh run list --workflow=staging-deploy-optimized.yml --limit 5
gh run view <run-id> --log

# === AWS ECR ===
aws ecr describe-repositories --region ap-northeast-1
aws ecr list-images --repository-name nova/auth-service --region ap-northeast-1
aws ecr describe-images --repository-name nova/auth-service --region ap-northeast-1

# === Kubernetes ===
kubectl get pods -n nova
kubectl get deployments -n nova
kubectl rollout status deployment/auth-service -n nova
kubectl logs -f deployment/auth-service -n nova
kubectl describe pod <pod-name> -n nova

# === ArgoCD ===
kubectl get applications -n argocd
kubectl get application nova-staging -n argocd -o yaml
kubectl describe application nova-staging -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# === Kustomize ===
kubectl kustomize k8s/infrastructure/overlays/staging
kubectl apply -k k8s/infrastructure/overlays/staging --dry-run=client
kubectl diff -k k8s/infrastructure/overlays/staging

# === 测试脚本 ===
./scripts/test-staging-deploy.sh
```

## 下一步行动

1. **部署 ArgoCD**: `kubectl apply -f k8s/argocd/nova-staging-application.yaml`
2. **测试构建**: 手动触发 workflow 或 push 代码到 main
3. **验证同步**: 观察 ArgoCD Application 状态
4. **配置监控**: 集成 Prometheus + Grafana
5. **设置告警**: 配置 Slack/Email 通知

## 参考资料

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)
- [GitHub Actions - AWS OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Docker BuildKit](https://docs.docker.com/build/buildkit/)

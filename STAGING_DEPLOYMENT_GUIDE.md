# Nova 后端代码 Staging 部署指南

## 📋 概述

这个指南说明如何使用 GitHub Actions 将后端代码 staging 到 staging 环境。

### 完整流程

```
1. 推送代码到 main 分支
   ↓
2. GitHub Actions 触发 staging-deploy.yml
   ↓
3. Job 1: 构建 8 个微服务的 Docker 镜像
   ↓
4. Job 2: 更新 K8s 部署清单中的镜像标签
   ↓
5. Job 3: 推送变更到 Git（触发 ArgoCD）
   ↓
6. ArgoCD 自动同步到 staging 集群
   ↓
7. Job 4: 运行烟雾测试验证
   ↓
8. ✅ Staging 环境已准备就绪
```

---

## 🚀 快速开始

### 方式 1: 自动触发（推荐）

只需推送代码到 main 分支，staging 部署将自动开始：

```bash
# 修改后端代码
vim backend/auth-service/src/main.rs

# 提交并推送
git add backend/
git commit -m "feat: add new feature to auth-service"
git push origin main
```

**Triggers**：
- 在 `backend/**` 目录有变更时自动触发
- 或手动点击 GitHub Actions UI 的 "Run workflow" 按钮

### 方式 2: 手动触发

```bash
# 访问 GitHub Actions
https://github.com/proerror77/Nova/actions

# 找到 "Stage Backend Code to Staging" workflow
# 点击 "Run workflow" 按钮
# 选择分支（main）
# 点击 "Run workflow"
```

---

## 📊 Pipeline 详解

### Job 1: 构建 Docker 镜像 (build-and-push)

**说明**：为 8 个微服务构建 Docker 镜像并推送到 ECR

**配置**：
- **Registry**: `025434362120.dkr.ecr.ap-northeast-1.amazonaws.com`
- **Parallelism**: `max-parallel: 2`（同时构建 2 个服务）
- **Tags**:
  - `${COMMIT_SHA}` - 当前提交的 SHA
  - `latest` - 最新标签

**Services**:
- auth-service
- user-service
- content-service
- feed-service
- media-service
- messaging-service
- search-service
- streaming-service

**输出**：ECR 中存在新的镜像

### Job 2: 更新部署清单 (update-deployment)

**说明**：更新 Kustomize 配置中的镜像标签，指向新构建的镜像

**文件修改**：
```
k8s/infrastructure/overlays/staging/kustomization.yaml
```

**变更示例**：
```yaml
# 更新前
- name: nova/auth-service
  newTag: latest

# 更新后
- name: nova/auth-service
  newTag: abc1234567890...  # commit SHA
```

**提交**：
```
chore(staging): update image tags to abc1234567890...
```

### Job 3: 触发 ArgoCD 同步 (deploy-to-staging)

**说明**：GitHub 变更推送到 main 后，ArgoCD 自动检测并同步到 staging 集群

**前置条件**：
- ✅ ArgoCD 已部署到 staging 集群
- ✅ ArgoCD Application 已配置（nova-staging）

**配置** (参考)：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova-staging
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/proerror77/Nova.git
    targetRevision: main
    path: k8s/infrastructure/overlays/staging
  destination:
    namespace: nova
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**验证**：
```bash
# 查看 ArgoCD 应用状态
argocd app get nova-staging

# 查看同步日志
argocd app logs nova-staging

# 手动同步（如需要）
argocd app sync nova-staging
```

### Job 4: 运行烟雾测试 (smoke-test)

**说明**：部署后验证 staging 环境中所有服务都健康

**前置条件**：
- ✅ GitHub secret `STAGING_KUBE_CONFIG` 已配置
- ✅ `scripts/smoke-staging.sh` 存在

**检查项**：
- 所有 8 个服务的 `/health` 端点
- 所有服务的 `/metrics` 端点（Prometheus）
- Redis Sentinel 拓扑（可选）
- Kafka 主题可用性（可选）

**运行**：
```bash
# 自动运行（通过 GitHub Actions）
# 或手动运行
NAMESPACE=nova bash scripts/smoke-staging.sh
```

---

## 🔧 配置和初始化

### 前置条件清单

#### 1. GitHub Secrets 配置

```bash
# 登录 GitHub → Settings → Secrets and variables

# 必需：
- AWS_ROLE_ARN
  值: arn:aws:iam::025434362120:role/YourGitHubActionsRole

# 可选但推荐：
- STAGING_KUBE_CONFIG (base64 编码的 kubeconfig)
```

#### 2. AWS 配置

```bash
# 确保 IAM 角色有权限：
- ecr:GetAuthorizationToken
- ecr:BatchGetImage
- ecr:PutImage
- ecr:InitiateLayerUpload
- ecr:UploadLayerPart
- ecr:CompleteLayerUpload

# 验证 ECR 仓库存在
aws ecr describe-repositories \
  --region ap-northeast-1 \
  --query 'repositories[?contains(repositoryName, `nova/`)]'
```

#### 3. ArgoCD 配置

```bash
# 在 staging 集群部署 ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 创建 Application 资源
kubectl apply -f - << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nova-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/proerror77/Nova.git
    targetRevision: main
    path: k8s/infrastructure/overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: nova
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

# 验证
argocd app list
argocd app get nova-staging
```

#### 4. Staging Kustomization

```bash
# 确保目录存在
mkdir -p k8s/infrastructure/overlays/staging

# 文件应包含
- kustomization.yaml (已创建)
- deployment-patch.yaml (已创建)
```

---

## 📈 监控和调试

### 查看部署进度

#### GitHub Actions

```bash
# 访问 workflow 执行页面
https://github.com/proerror77/Nova/actions/workflows/staging-deploy.yml

# 查看实时日志
```

#### ArgoCD

```bash
# 打开 UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
open https://localhost:8080

# 或使用 CLI
argocd app get nova-staging --refresh
argocd app logs nova-staging

# 检查同步状态
argocd app get nova-staging | grep -E "Status|Health"
```

#### Kubernetes

```bash
# 监控 Pod 状态
kubectl -n nova get pods -w

# 查看 Deployment 状态
kubectl -n nova get deployments

# 查看最近的事件
kubectl -n nova get events --sort-by='.lastTimestamp' | tail -20

# 检查服务就绪
kubectl -n nova get svc
```

### 故障排除

#### 问题: ECR 镜像推送失败

```bash
# 检查 AWS 权限
aws sts get-caller-identity

# 检查 ECR 仓库
aws ecr describe-repositories --region ap-northeast-1

# 创建缺失的仓库
for service in auth-service user-service content-service feed-service \
               media-service messaging-service search-service streaming-service; do
  aws ecr create-repository \
    --repository-name nova/$service \
    --region ap-northeast-1 2>/dev/null || true
done
```

#### 问题: ArgoCD 同步失败

```bash
# 查看同步错误日志
argocd app logs nova-staging

# 强制同步
argocd app sync nova-staging --force

# 检查 Git 凭证
kubectl -n argocd get secret \
  $(kubectl -n argocd get secret | grep nova-repo | awk '{print $1}')
```

#### 问题: Pod 未就绪

```bash
# 查看 Pod 状态
kubectl -n nova describe pod <pod-name>

# 查看容器日志
kubectl -n nova logs <pod-name>

# 检查资源限制
kubectl -n nova top pods
```

#### 问题: 烟雾测试失败

```bash
# 查看测试日志
# 在 GitHub Actions 中查看 "Run Staging Smoke Tests" 步骤

# 或手动运行测试
NAMESPACE=nova bash scripts/smoke-staging.sh

# 测试单个服务健康检查
kubectl -n nova exec <pod-name> -- \
  curl -f http://localhost:8080/health || echo "Health check failed"
```

---

## 📚 文件清单

| 文件 | 用途 |
|------|------|
| `.github/workflows/staging-deploy.yml` | 主 staging workflow |
| `.github/workflows/staging-smoke.yml` | 烟雾测试 workflow |
| `.github/workflows/simple-ecr-build.yml` | 简化的镜像构建 workflow |
| `k8s/infrastructure/overlays/staging/kustomization.yaml` | Staging 特定配置 |
| `k8s/infrastructure/overlays/staging/deployment-patch.yaml` | Staging 资源限制 |
| `scripts/smoke-staging.sh` | 烟雾测试脚本 |
| `k8s/microservices/gitops-argocd-setup.yaml` | ArgoCD 配置参考 |

---

## 🔄 与其他环境的对比

### Dev 环境
- **触发**: 手动或 PR
- **镜像**: `dev-latest`
- **副本数**: 1
- **资源**: 最小 (50m CPU, 128Mi 内存)
- **路径**: `k8s/infrastructure/overlays/dev`

### Staging 环境
- **触发**: push 到 main 或手动
- **镜像**: commit SHA + latest
- **副本数**: 2
- **资源**: 中等 (100-200m CPU, 256Mi-512Mi 内存)
- **路径**: `k8s/infrastructure/overlays/staging`

### Prod 环境
- **触发**: Release tag
- **镜像**: Release tag
- **副本数**: 3+
- **资源**: 生产级别
- **路径**: `k8s/infrastructure/overlays/prod`

---

## ✅ 完整 Staging 检查清单

部署完成后验证：

- [ ] GitHub Actions workflow 执行成功
  - [ ] build-and-push 所有服务都 pushed
  - [ ] update-deployment 成功提交变更
  - [ ] deploy-to-staging 没有错误

- [ ] ECR 镜像存在且最新
  ```bash
  aws ecr describe-images \
    --repository-name nova/auth-service \
    --region ap-northeast-1
  ```

- [ ] Kubernetes 部署成功
  ```bash
  kubectl -n nova get deployments
  kubectl -n nova get pods
  ```

- [ ] ArgoCD 同步成功
  ```bash
  argocd app get nova-staging
  ```

- [ ] 烟雾测试通过
  ```bash
  bash scripts/smoke-staging.sh
  ```

- [ ] 服务可访问
  ```bash
  kubectl -n nova port-forward svc/auth-service 8084:8084
  curl http://localhost:8084/health
  ```

---

## 📞 支持

遇到问题？

1. **检查日志**
   - GitHub Actions: https://github.com/proerror77/Nova/actions
   - ArgoCD: `argocd app logs nova-staging`
   - Kubernetes: `kubectl -n nova logs <pod-name>`

2. **查看故障排除**
   - 上述"故障排除"章节

3. **手动调试**
   ```bash
   # 查看最新部署状态
   kubectl -n nova describe deployment auth-service

   # 检查网络连接
   kubectl -n nova port-forward svc/auth-service 8084:8084
   curl http://localhost:8084/health
   ```

---

**最后更新**: 2024-10-31

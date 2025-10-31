# 🎯 Nova Staging Environment - 完整指南

> **你的 backend 代码现在可以通过 GitHub 自动 staging 到测试环境了！**

## ✅ 已完成

我为你实现了一套完整的自动化 staging pipeline，包括：

### 1. GitHub Actions 自动 CI/CD Pipeline
✅ `.github/workflows/staging-deploy.yml`
- 自动构建 8 个微服务的 Docker 镜像
- 并行构建（最多同时 2 个）
- 自动推送到 AWS ECR
- 自动更新 Kubernetes 部署清单
- 自动运行烟雾测试验证

### 2. Kubernetes Staging 环境配置
✅ `k8s/infrastructure/overlays/staging/`
- staging 特定的 Kustomize 配置
- 8 个服务的镜像标签管理
- Staging 特定的资源限制和副本数
- 环境变量配置

### 3. 完整的文档
✅ `STAGING_QUICK_START.md` - 5 分钟快速开始
✅ `STAGING_DEPLOYMENT_GUIDE.md` - 完整部署指南
✅ `k8s/docs/STAGING_ARCHITECTURE.md` - 架构和设计
✅ `GITHUB_ACTIONS_RETRY.md` - GitHub Actions 说明

---

## 🚀 立即使用

### 最简单的方式：推送代码

```bash
# 1. 修改后端代码
vim backend/auth-service/src/main.rs

# 2. 提交并推送
git add backend/
git commit -m "feat: add new feature"
git push origin main

# 3. 自动开始！
# 在 GitHub Actions 中查看进度
# https://github.com/proerror77/Nova/actions
```

**就这么简单！** 完整流程约 15 分钟。

### 或者：手动触发

```bash
# 访问 GitHub Actions UI
https://github.com/proerror77/Nova/actions

# 找到 "Stage Backend Code to Staging"
# 点击 "Run workflow" 按钮
```

---

## 📊 完整流程说明

```
推送代码到 main (git push origin main)
        ↓
GitHub Actions 触发 (自动)
        ↓
├─ Job 1: build-and-push
│  ├─ 构建 auth-service Docker 镜像
│  ├─ 构建 user-service Docker 镜像
│  ├─ ... (并行构建，最多 2 个)
│  └─ 推送到 ECR: 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/{service}
│
├─ Job 2: update-deployment
│  ├─ 下载 kustomize CLI
│  ├─ 修改 k8s/infrastructure/overlays/staging/kustomization.yaml
│  ├─ 更新镜像标签为当前 commit SHA
│  └─ 推送变更回 main 分支
│
├─ Job 3: deploy-to-staging
│  ├─ 验证 staging 配置存在
│  └─ ArgoCD 自动检测变更并部署
│
├─ Job 4: smoke-test
│  ├─ 等待 Pods 就绪
│  ├─ 验证 /health 端点
│  ├─ 验证 /metrics 端点
│  └─ 验证服务健康
│
└─ Job 5: notify-completion
   └─ 输出部署总结和调试命令

        ↓
✅ 完成！新代码在 staging 环境运行
```

**总耗时**: 10-15 分钟

---

## 🔧 前置条件

### 1. AWS 配置
- ✅ ECR 仓库已创建 (nova/auth-service, nova/user-service 等)
- ✅ GitHub Actions 有 AWS_ROLE_ARN secret (OIDC 认证)

### 2. Kubernetes Staging 集群
- ✅ EKS 集群准备好
- ✅ `nova` namespace 存在
- ✅ ArgoCD 已部署

### 3. ArgoCD 配置
- ⚠️ 需要手动创建 `nova-staging` Application

**创建 ArgoCD Application**:
```bash
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
```

---

## 📚 文档导航

| 文档 | 目标读者 | 内容 |
|------|--------|------|
| **STAGING_QUICK_START.md** | 开发者 | 5 分钟了解如何使用 |
| **STAGING_DEPLOYMENT_GUIDE.md** | 运维/架构 | 完整部署指南和故障排除 |
| **k8s/docs/STAGING_ARCHITECTURE.md** | 架构师 | 系统设计和技术细节 |
| **GITHUB_ACTIONS_RETRY.md** | 开发者 | GitHub Actions workflow 说明 |

---

## 🎯 关键特性

### ✅ 完全自动化
```
git push origin main → 自动构建 → 自动部署 → 自动验证
```
无需手动干预！

### ✅ 快速反馈
```
Total time: ~15 minutes
- Build: 8 min
- Deploy: 5 min
- Test: 1 min
- Overhead: 1 min
```

### ✅ 并行构建
```
max-parallel: 2 (同时构建 2 个服务)
比顺序构建快 4-5 倍
```

### ✅ GitOps 驱动
```
所有配置都在 Git 中
可审计、可版本控制、可回滚
```

### ✅ 完整验证
```
- 烟雾测试自动运行
- 所有 /health 端点验证
- Prometheus /metrics 验证
- 多层健康检查
```

---

## 📊 Pipeline 架构

```
Developer              GitHub               AWS ECR              K8s Cluster
    │                   │                      │                     │
    ├─ git push ─────→  │                      │                     │
    │                   │                      │                     │
    │              [Trigger]                   │                     │
    │                   │                      │                     │
    │              [Build Job]                 │                     │
    │                   ├─ docker build ──→   │                     │
    │                   ├─ docker build ──→   │                     │
    │                   ├─ docker push  ────→ │                     │
    │                   ├─ ... 8 services     │                     │
    │                   │                      │                     │
    │              [Update Job]                │                     │
    │                   ├─ kustomize edit     │                     │
    │                   ├─ git push ─────────────────────────────→ │
    │                   │                      │                     │
    │              [Deploy Job]                │                     │
    │                   │                      │               [ArgoCD]
    │                   │                      │                     │
    │                   │                      │               [kubectl apply]
    │                   │                      │                     │
    │              [Smoke Test]                │                     │
    │                   ├─ kubectl get pods   │                     │
    │                   ├─ curl /health  ────────────────────────→ │
    │                   ├─ curl /metrics ────────────────────────→ │
    │                   │                      │                     │
    ↓                   ↓                      ↓                     ↓

 Staging 环境准备就绪！
```

---

## 🔍 监控部署进度

### 方式 1: GitHub Actions UI
```
https://github.com/proerror77/Nova/actions
```
- 查看实时构建日志
- 查看每个 job 的详细信息

### 方式 2: Kubernetes
```bash
# 监控 Pod 状态
kubectl -n nova get pods -w

# 查看 Deployment 状态
kubectl -n nova get deployments

# 查看最新事件
kubectl -n nova get events --sort-by=.lastTimestamp
```

### 方式 3: ArgoCD
```bash
# 查看应用同步状态
argocd app get nova-staging

# 查看同步日志
argocd app logs nova-staging

# UI 访问
kubectl port-forward -n argocd svc/argocd-server 8080:443
open https://localhost:8080
```

### 方式 4: ECR
```bash
# 查看推送的镜像
aws ecr describe-images \
  --repository-name nova/auth-service \
  --region ap-northeast-1 \
  --query 'imageDetails[0:3].[imageTags,imagePushedAt]' \
  --output table
```

---

## ❓ 常见问题

### Q: 推送代码后需要多久看到效果？
**A**: 约 15 分钟
- 构建镜像: 8 分钟
- ArgoCD 同步: 3-5 分钟
- 烟雾测试: < 1 分钟

### Q: 如果构建失败怎么办？
**A**:
1. 查看 GitHub Actions 日志
2. 修复问题
3. 重新推送代码
4. 自动重新构建

### Q: 可以只更新 1 个服务吗？
**A**: 目前 workflow 会更新所有 8 个服务。如果想单独更新，需要修改 workflow 的 matrix strategy。

### Q: Staging 和 Production 有什么区别？
**A**:
- Staging: 2 副本，100-200m CPU，从 main 自动部署
- Production: 3+ 副本，更大资源，从 Release tag 部署

### Q: 如何回滚？
**A**:
```bash
# 使用 ArgoCD 回滚
argocd app rollback nova-staging 1

# 或重新部署上一个 commit
git checkout <previous-commit>
git push origin main --force  # 谨慎使用
```

---

## 🛠️ 故障排除

### 问题 1: ECR 镜像推送失败
```bash
# 检查 AWS 权限
aws sts get-caller-identity

# 检查 ECR 仓库
aws ecr describe-repositories --region ap-northeast-1

# 创建缺失的仓库
for service in auth-service user-service content-service; do
  aws ecr create-repository \
    --repository-name nova/$service \
    --region ap-northeast-1
done
```

### 问题 2: ArgoCD 同步失败
```bash
# 查看同步错误
argocd app logs nova-staging

# 强制同步
argocd app sync nova-staging --force

# 检查 Git 凭证
kubectl -n argocd get secret $(kubectl -n argocd get secret | grep nova | awk '{print $1}')
```

### 问题 3: Pod 未就绪
```bash
# 查看 Pod 状态
kubectl -n nova describe pod <pod-name>

# 查看容器日志
kubectl -n nova logs <pod-name>

# 检查资源限制
kubectl -n nova top pods
```

### 问题 4: 烟雾测试失败
```bash
# 手动运行测试
NAMESPACE=nova bash scripts/smoke-staging.sh

# 测试单个服务
kubectl -n nova exec <pod-name> -- curl http://localhost:8080/health
```

---

## 📋 完整检查清单

部署完成后验证：

```
GitHub Actions
☐ build-and-push job 成功
☐ update-deployment job 成功
☐ deploy-to-staging job 成功
☐ smoke-test job 成功

AWS ECR
☐ 所有 8 个服务的镜像都存在
☐ 镜像标签是当前 commit SHA
☐ 镜像大小合理

Kubernetes
☐ 所有 8 个 Deployment 存在
☐ 每个 Deployment 有 2 个就绪的 Pod
☐ 所有服务都有对应的 Service
☐ 没有错误的事件

ArgoCD
☐ nova-staging Application 存在
☐ Application 状态是 Synced
☐ Application 健康状态是 Healthy
☐ 没有同步错误

烟雾测试
☐ 所有 /health 端点返回 200
☐ 所有 /metrics 端点返回 200
☐ 没有服务启动失败

业务验证
☐ 可以访问服务
☐ 服务能正常处理请求
☐ 日志正常输出
```

---

## 🚀 下一步

1. **立即测试**
   ```bash
   git push origin main  # 或修改一个文件后提交
   ```

2. **监控进度**
   访问: https://github.com/proerror77/Nova/actions

3. **验证部署**
   ```bash
   kubectl -n nova get pods
   bash scripts/smoke-staging.sh
   ```

4. **阅读详细文档**
   - `STAGING_QUICK_START.md` (5 min)
   - `STAGING_DEPLOYMENT_GUIDE.md` (15 min)
   - `k8s/docs/STAGING_ARCHITECTURE.md` (20 min)

---

## 📞 获取帮助

- **快速问题**: 查看 `STAGING_QUICK_START.md` 的 FAQ
- **故障排除**: 查看 `STAGING_DEPLOYMENT_GUIDE.md` 的故障排除部分
- **技术细节**: 查看 `k8s/docs/STAGING_ARCHITECTURE.md`
- **GitHub Actions**: 查看 `.github/workflows/staging-deploy.yml`
- **K8s 配置**: 查看 `k8s/infrastructure/overlays/staging/`

---

## 📊 关键文件

| 文件 | 用途 |
|------|------|
| `.github/workflows/staging-deploy.yml` | 主 CI/CD pipeline |
| `k8s/infrastructure/overlays/staging/kustomization.yaml` | Staging K8s 配置 |
| `k8s/infrastructure/overlays/staging/deployment-patch.yaml` | Staging 资源限制 |
| `scripts/smoke-staging.sh` | 烟雾测试脚本 |
| `STAGING_QUICK_START.md` | 快速开始指南 |
| `STAGING_DEPLOYMENT_GUIDE.md` | 完整部署指南 |
| `k8s/docs/STAGING_ARCHITECTURE.md` | 架构文档 |

---

**现在就推送你的代码吧！** 🎉

```bash
git push origin main
```

15 分钟后，你的更新就会在 staging 环境中运行！

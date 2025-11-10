# GitHub Actions 部署指南

## 概述

已配置自动化 CI/CD 流程来构建和部署 GraphQL Gateway 到 AWS EKS。

## 工作流文件

### 1. 构建所有服务（包括 GraphQL Gateway）
**文件**: `.github/workflows/ecr-build-push.yml`

**触发方式**:
- 自动: Push 到 `main` 或 `develop` 分支，修改 `backend/**` 文件
- 手动: GitHub Actions 页面点击 "Run workflow"

**功能**:
- 并行构建所有微服务（包括新增的 graphql-gateway）
- 推送到 ECR: `025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/graphql-gateway:latest`
- 使用 Docker layer 缓存加速构建

### 2. 部署 GraphQL Gateway
**文件**: `.github/workflows/deploy-graphql-gateway.yml`

**触发方式**:
- 自动: Push 到 `main` 分支，修改以下路径:
  - `backend/graphql-gateway/**`
  - `k8s/graphql-gateway/**`
  - `.github/workflows/deploy-graphql-gateway.yml`
- 手动: GitHub Actions 页面点击 "Run workflow"

**流程**:
1. **Build & Push**: 构建 Docker 镜像并推送到 ECR
2. **Deploy to K8s**: 部署到 Kubernetes 集群
3. **Health Checks**: 运行健康检查测试

## 手动触发部署（推荐）

### 方法 1: GitHub Web UI

1. 访问仓库 GitHub Actions 页面
2. 选择 "Deploy GraphQL Gateway" workflow
3. 点击 "Run workflow" 按钮
4. 选择参数:
   - **environment**: staging (默认) 或 production
   - **image_tag**: 留空使用 latest，或指定特定标签
5. 点击 "Run workflow"

### 方法 2: GitHub CLI

```bash
# 部署到 staging (使用最新代码)
gh workflow run deploy-graphql-gateway.yml

# 部署到 production
gh workflow run deploy-graphql-gateway.yml \
  -f environment=production

# 部署指定镜像版本
gh workflow run deploy-graphql-gateway.yml \
  -f image_tag=main-abc123def456
```

### 方法 3: Git Push (自动触发)

```bash
# 提交 GraphQL Gateway 代码
git add backend/graphql-gateway/
git commit -m "feat: update graphql gateway"
git push origin main

# 自动触发构建和部署
```

## 查看构建进度

### GitHub Web UI
1. 访问 Actions 标签页
2. 点击对应的 workflow run
3. 查看每个 job 的日志

### GitHub CLI
```bash
# 查看最近的 runs
gh run list --workflow=deploy-graphql-gateway.yml

# 查看特定 run 的状态
gh run view <run-id>

# 实时查看日志
gh run watch <run-id>
```

## 部署后验证

### 1. 检查 Kubernetes 部署状态

```bash
# 连接到 EKS 集群
aws eks update-kubeconfig --region ap-northeast-1 --name nova-staging

# 检查 GraphQL Gateway pods
kubectl get pods -n nova-gateway -l app=graphql-gateway

# 查看 deployment 状态
kubectl get deployment graphql-gateway -n nova-gateway

# 查看服务
kubectl get svc graphql-gateway -n nova-gateway
```

### 2. 本地测试

```bash
# Port forward 到本地
kubectl port-forward -n nova-gateway svc/graphql-gateway 8080:8080

# 测试健康检查
curl http://localhost:8080/health

# 访问 GraphQL Playground
open http://localhost:8080/playground
```

### 3. 查看日志

```bash
# 查看所有 pods 日志
kubectl logs -n nova-gateway -l app=graphql-gateway --tail=100

# 查看特定 pod 日志
kubectl logs -n nova-gateway <pod-name> -f
```

## 故障排查

### 构建失败

**问题**: Docker build 失败
```bash
# 检查 Dockerfile 语法
docker build -f backend/graphql-gateway/Dockerfile .

# 检查依赖是否正确
grep -r "graphql-gateway" Cargo.toml
```

**问题**: 推送到 ECR 失败
```bash
# 验证 IAM 权限
aws sts get-caller-identity

# 检查 ECR 仓库是否存在
aws ecr describe-repositories --region ap-northeast-1 | grep graphql-gateway
```

### 部署失败

**问题**: Kubernetes 部署失败
```bash
# 检查 pod 事件
kubectl describe pod -n nova-gateway -l app=graphql-gateway

# 查看部署事件
kubectl describe deployment graphql-gateway -n nova-gateway

# 检查配置
kubectl get configmap graphql-gateway-config -n nova-gateway -o yaml
```

**问题**: 镜像拉取失败
```bash
# 验证镜像存在
aws ecr describe-images \
  --repository-name nova/graphql-gateway \
  --region ap-northeast-1

# 检查节点是否有 ECR 访问权限
kubectl get nodes -o wide
```

## 回滚部署

```bash
# 查看 deployment 历史
kubectl rollout history deployment/graphql-gateway -n nova-gateway

# 回滚到上一个版本
kubectl rollout undo deployment/graphql-gateway -n nova-gateway

# 回滚到特定版本
kubectl rollout undo deployment/graphql-gateway -n nova-gateway --to-revision=2
```

## 环境变量配置

GraphQL Gateway 的配置存储在 Kubernetes ConfigMap 和 Secret:

```bash
# 查看 ConfigMap
kubectl get configmap graphql-gateway-config -n nova-gateway -o yaml

# 编辑 ConfigMap (需要重启 pods 生效)
kubectl edit configmap graphql-gateway-config -n nova-gateway

# 查看 Secret
kubectl get secret graphql-gateway-secret -n nova-gateway -o yaml

# 重启 pods 应用新配置
kubectl rollout restart deployment/graphql-gateway -n nova-gateway
```

## 性能监控

### 检查资源使用

```bash
# CPU 和内存使用
kubectl top pods -n nova-gateway

# HPA 状态
kubectl get hpa graphql-gateway-hpa -n nova-gateway

# 查看 pod 详细资源
kubectl describe pod -n nova-gateway <pod-name> | grep -A 5 "Limits\|Requests"
```

### 扩缩容

```bash
# 手动扩容
kubectl scale deployment graphql-gateway -n nova-gateway --replicas=5

# 查看自动扩缩容状态
kubectl get hpa graphql-gateway-hpa -n nova-gateway -w
```

## 安全最佳实践

### 定期更新镜像

```bash
# 触发新构建
git commit --allow-empty -m "chore: rebuild graphql-gateway"
git push origin main
```

### 审计日志

```bash
# 查看 GitHub Actions 审计日志
gh api /repos/OWNER/REPO/actions/runs

# 查看 Kubernetes 审计日志
kubectl get events -n nova-gateway --sort-by='.lastTimestamp'
```

## 生产部署检查清单

- [ ] 代码已经过代码审查
- [ ] 所有测试通过
- [ ] 已在 staging 环境验证
- [ ] 配置已更新（ConfigMap/Secret）
- [ ] 数据库 migration 已运行
- [ ] 监控和告警已配置
- [ ] 回滚计划已准备
- [ ] 团队已通知部署窗口

## 持续改进

### 添加新服务到 CI/CD

编辑 `.github/workflows/ecr-build-push.yml`:

```yaml
strategy:
  matrix:
    service:
      - existing-service
      - your-new-service  # 添加新服务
```

### 自定义部署策略

修改 `k8s/graphql-gateway/deployment.yaml`:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # 零停机部署
```

## 联系支持

遇到问题？

1. 检查 GitHub Actions 日志
2. 查看 Kubernetes 事件: `kubectl get events -n nova-gateway`
3. 查看应用日志: `kubectl logs -n nova-gateway -l app=graphql-gateway`
4. 查阅 DEPLOYMENT_STATUS.md

---

**最后更新**: 2025-11-10
**维护者**: Nova Platform Team

# ArgoCD GitOps 部署指南

完整的 GitOps 工作流，使用 ArgoCD 管理 Nova 微服务在 Kubernetes 上的部署。

## 概述

ArgoCD 是一个声明式的 GitOps 连续部署工具，它：

- **自动同步** Git 仓库与集群状态
- **支持多环境** 部署（staging、production）
- **提供 Web UI** 用于管理和监控
- **实现 GitOps 最佳实践** 所有配置都在 Git 中

## 架构

```
┌─────────────────────┐
│   GitHub Repository │
│   (Nova)            │
└──────────┬──────────┘
           │
           │ ArgoCD monitors
           ↓
┌─────────────────────┐     ┌──────────────────────┐
│  ArgoCD Controller  │────→│  EKS Cluster         │
│  (argocd namespace) │     │  ├─ nova-staging     │
└─────────────────────┘     │  └─ nova-production  │
           ↑                 └──────────────────────┘
           │
           │ sync updates
           │
    ┌──────┴──────────────┐
    │  Git Repositories   │
    │  ├─ main (prod)     │
    │  └─ develop (stage) │
    └─────────────────────┘
```

## 前置条件

1. **EKS 集群已部署** - 使用 Terraform 配置
2. **ArgoCD 已安装** - 通过 Terraform module/addons
3. **GitHub 仓库访问** - 具有 SSH 密钥或 HTTPS 令牌

## 部署步骤

### 1. 验证 ArgoCD 安装

```bash
# 检查 ArgoCD 是否运行
kubectl get pods -n argocd

# 输出应该显示：
# NAME                               READY   STATUS    RESTARTS   AGE
# argocd-application-controller-0    1/1     Running   0          2m
# argocd-dex-server-xxx              1/1     Running   0          2m
# argocd-repo-server-xxx             1/1     Running   0          2m
# argocd-server-xxx                  1/1     Running   0          2m
```

### 2. 获取 ArgoCD 访问凭证

```bash
# 获取初始管理员密码
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 端口转发以访问 Web UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 在浏览器中访问
# https://localhost:8080
# 用户名: admin
# 密码: <上面获得的密码>
```

### 3. 添加 GitHub 仓库凭证

```bash
# 生成 GitHub Personal Access Token (如果需要)
# https://github.com/settings/tokens
# 权限: repo, read:org

# 使用 ArgoCD CLI 添加仓库
argocd repo add https://github.com/proerror77/Nova.git \
  --username <github-username> \
  --password <github-token>

# 或者，如果使用 SSH 密钥
argocd repo add git@github.com:proerror77/Nova.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

### 4. 创建命名空间

```bash
# 创建 staging 命名空间
kubectl create namespace nova-staging

# 创建 production 命名空间
kubectl create namespace nova-production

# 添加 ArgoCD 标签（让 ArgoCD 管理资源）
kubectl label namespace nova-staging argocd.argoproj.io/managed-by=argocd
kubectl label namespace nova-production argocd.argoproj.io/managed-by=argocd
```

### 5. 部署 ArgoCD Applications

```bash
# 部署 Staging 应用
kubectl apply -f nova-staging-app.yaml

# 部署 Production 应用
kubectl apply -f nova-production-app.yaml

# 验证应用已创建
kubectl get applications -n argocd
```

### 6. 监控部署

```bash
# 查看应用同步状态
kubectl get applications -n argocd -w

# 获取详细应用信息
kubectl describe application nova-staging -n argocd

# 查看同步历史
argocd app history nova-staging
```

## Kustomize 覆盖层说明

### 目录结构

```
k8s/
├── base/                          # 基础配置（所有环境共用）
│   ├── kustomization.yaml
│   └── ...
└── overlays/
    ├── staging/                   # Staging 覆盖
    │   ├── kustomization.yaml
    │   └── ...
    └── production/                # Production 覆盖
        ├── kustomization.yaml
        └── ...
```

### Staging 配置

- 使用 `develop` 分支的镜像
- 1 个副本（最小配置）
- 较低的资源限制（256Mi 内存）
- 自动同步启用（开发友好）

### Production 配置

- 使用 `main` 分支的镜像
- 2-3 个副本（高可用）
- 更高的资源限制（512Mi 内存）
- 手动同步（谨慎保守）
- Pod Disruption Budget 启用

## 工作流

### Staging 部署流程

```
1. 开发者在 develop 分支上创建 Pull Request
   ↓
2. GitHub Actions 构建 Docker 镜像
   ↓
3. 镜像推送到 ECR（develop 标签）
   ↓
4. ArgoCD 监测到 develop 分支变更
   ↓
5. 自动拉取新镜像部署到 nova-staging 命名空间
   ↓
6. Staging 环境自动更新
```

### Production 部署流程

```
1. 开发者在 main 分支上创建 Pull Request
   ↓
2. Code review 和 merge
   ↓
3. GitHub Actions 构建 Docker 镜像
   ↓
4. 镜像推送到 ECR（main 标签）
   ↓
5. ArgoCD 检测到 main 分支变更
   ↓
6. 需要手动触发同步（在 ArgoCD UI 中）
   ↓
7. Production 环境更新
   ↓
8. 运维团队进行验证和监控
```

## 常见操作

### 查看应用状态

```bash
# 所有应用
argocd app list

# 单个应用详情
argocd app get nova-staging

# 同步状态
argocd app wait nova-staging
```

### 手动触发同步

```bash
# Staging（如果禁用自动同步）
argocd app sync nova-staging

# Production（总是需要手动同步）
argocd app sync nova-production

# 等待同步完成
argocd app wait nova-production
```

### 回滚到上一个版本

```bash
# 查看历史
argocd app history nova-staging

# 回滚
argocd app rollback nova-staging 1  # 回滚到上一个版本

# 也可以回滚到特定的 Git commit
argocd app set nova-staging --revision <commit-hash>
```

### 更新镜像标签

```bash
# 更新 Kustomize 镜像标签
cd k8s/overlays/staging
kustomize edit set image nova/auth-service:new-tag

# 提交并推送到 Git
git add .
git commit -m "chore: update image tags for staging"
git push origin develop

# ArgoCD 会自动检测并同步
```

## 故障排除

### 应用同步失败

```bash
# 查看错误信息
argocd app get nova-staging --refresh

# 查看 pod 日志
kubectl logs -n argocd -l app=argocd-application-controller

# 检查 Git 仓库连接
argocd repo list
```

### 镜像拉取失败

```bash
# 检查 ECR 凭证
kubectl get secret -n nova-staging regcred

# 如果凭证过期，更新
kubectl create secret docker-registry regcred \
  --docker-server=025434362120.dkr.ecr.ap-northeast-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password) \
  -n nova-staging --dry-run=client -o yaml | kubectl apply -f -
```

### 命名空间权限问题

```bash
# 确保 ArgoCD service account 有足够权限
kubectl get clusterrolebinding argocd-application-controller

# 如果需要，授予权限
kubectl create clusterrolebinding argocd-application-controller \
  --clusterrole=cluster-admin \
  --serviceaccount=argocd:argocd-application-controller
```

## 监控和告警

### 启用 ArgoCD 指标

```bash
# 暴露 Prometheus 指标
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"ClusterIP"}}'

# Prometheus scrape config
# - job_name: 'argocd'
#   static_configs:
#   - targets: ['argocd-server.argocd.svc.cluster.local:8083']
```

### Slack 通知

```bash
# 配置 Slack webhook
kubectl patch secret argocd-secret -n argocd \
  -p '{"data":{"slack.token":"<token>"}}'

# 在 Application 中启用通知
# 参见 nova-staging-app.yaml notifications 部分
```

## 最佳实践

1. **始终在 Git 中定义配置** - 不要直接修改集群
2. **使用覆盖层** - 为不同环境维护不同的配置
3. **谨慎处理 Production** - 启用手动同步和审批
4. **定期备份** - 定期备份 Git 仓库
5. **监控同步** - 定期检查应用同步状态
6. **版本控制** - 对所有配置使用语义版本

## 参考资源

- [ArgoCD 官方文档](https://argo-cd.readthedocs.io/)
- [Kustomize 文档](https://kustomize.io/)
- [GitOps 最佳实践](https://codefresh.io/learn/gitops/)
- [Kubernetes 部署策略](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

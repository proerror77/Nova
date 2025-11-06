# Nova EKS 快速启动指南 (5 分钟版)

## 🚀 快速部署（4 条命令）

```bash
# 1. 初始化并部署基础设施（15 分钟）
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
./deploy.sh apply

# 2. 获取 kubeconfig
aws eks update-kubeconfig --region ap-northeast-1 --name nova-eks

# 3. 添加 GitHub 仓库到 ArgoCD
argocd repo add https://github.com/proerror77/Nova.git \
  --username <你的GitHub用户名> \
  --password <你的GitHub Token>

# 4. 部署应用
kubectl apply -f infrastructure/argocd/nova-staging-app.yaml
```

## ✅ 验证部署

```bash
# 检查集群
kubectl get nodes      # 应该显示 3 个节点
kubectl get pods -A    # 应该显示 argocd pods 和其他系统 pods

# 检查应用
argocd app list        # 应该显示 nova-staging
kubectl get pods -n nova-staging   # 应该显示你的应用 pods
```

## 🔧 常见任务

### 查看日志
```bash
kubectl logs -f <pod-name> -n nova-staging
```

### 进入 ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# 访问: https://localhost:8080
# 用户名: admin
# 密码: (通过 `argocd admin initial-password -n argocd` 获取)
```

### 更新应用
```bash
# 修改 k8s/overlays/staging/ 中的配置
# 提交并推送到 GitHub
git push origin develop
# ArgoCD 会自动同步（通常在 3-5 秒内）
```

### 查看集群成本
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```

## 📊 架构一图

```
GitHub (代码)
  ↓
GitHub Actions (构建)
  ↓
ECR (镜像)
  ↓
ArgoCD (GitOps)
  ↓
EKS Cluster (Nova 服务运行)
```

## 🛑 删除所有资源（谨慎！）

```bash
cd infrastructure/terraform
terraform destroy -auto-approve
```

## 📖 详细指南

参见 [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)

## ❓ 遇到问题？

| 问题 | 解决方案 |
|------|---------|
| Pods 无法启动 | `kubectl describe pod <name> -n <ns>` |
| 镜像拉取失败 | 检查 ECR 凭证：`kubectl get secret -n <ns>` |
| ArgoCD 无法同步 | 检查 Git 连接：`argocd repo list` |
| 集群无响应 | 重新配置 kubeconfig：`aws eks update-kubeconfig ...` |

---

**部署时间**: ~15 分钟（首次）
**月度成本**: ~$300（默认配置）
**支持的环境**: staging、production
**高可用**: 3 个节点跨 2 个可用区

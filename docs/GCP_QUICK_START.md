# GCP Staging 快速参考指南

---

## 🚀 快速决策

### 现在就部署?

#### 选项 A: AWS (推荐)
```bash
# 时间: 2 天
# 成本: $772/月
# 复杂度: 中等

cd terraform
terraform init
terraform plan -var="environment=staging"
terraform apply
```

**优点**:
- ✅ 配置已完成
- ✅ 快速启动
- ✅ 可以立即验证架构

**缺点**:
- ❌ 维护成本高 (ALB + NAT Gateway)
- ❌ 复杂的安全组配置

#### 选项 B: GCP (长期优化)
```bash
# 时间: 7-12 天
# 成本: $760/月
# 复杂度: 低

cd infrastructure/terraform/gcp/main
terraform init
terraform plan -var="environment=staging"
terraform apply
```

**优点**:
- ✅ 维护简单 (managed K8s)
- ✅ 更好的开发体验
- ✅ OIDC 集成更原生

**缺点**:
- ❌ 需要重写 Terraform
- ❌ 需要修改所有 CI/CD workflows
- ❌ 需要等待 7-12 天

---

## 📊 对比总结

| | AWS | GCP |
|---|-----|-----|
| 配置完成度 | 100% ✅ | 0% ❌ |
| 启动时间 | 2 天 | 7-12 天 |
| 月度成本 | $772 | $760 |
| 维护难度 | 中等 | 低 |
| OIDC 设置 | 复杂 | 简单 |

---

## 🔧 AWS 部署 (快速路)

### 1. 前置条件
```bash
# 检查 AWS CLI
aws --version

# 检查 Terraform
terraform --version

# 配置 AWS 凭证
aws configure
```

### 2. 部署
```bash
# 初始化 Terraform
cd terraform
terraform init

# 检查计划
terraform plan \
  -var="environment=staging" \
  -var="aws_region=ap-northeast-1" \
  -var="vpc_cidr=10.0.0.0/16"

# 应用配置
terraform apply \
  -var="environment=staging" \
  -var="aws_region=ap-northeast-1"
```

### 3. 验证
```bash
# 检查 EKS 集群
aws eks describe-cluster --name nova-staging --region ap-northeast-1

# 获取 kubeconfig
aws eks update-kubeconfig --name nova-staging --region ap-northeast-1

# 验证 kubectl 连接
kubectl cluster-info
kubectl get nodes
```

### 4. 部署微服务
```bash
# 应用 K8s manifests
kubectl apply -k k8s/

# 检查部署状态
kubectl get deployments -n nova-staging
kubectl get pods -n nova-staging

# 查看 services
kubectl get svc -n nova-staging
```

---

## 🏗️ GCP 部署 (长期方案)

### 第 1 天: 基础设施

```bash
cd infrastructure/terraform/gcp/main

# 初始化
terraform init \
  -backend-config="bucket=nova-terraform-state" \
  -backend-config="prefix=gcp/staging"

# 部署 VPC + GKE
terraform apply \
  -var="environment=staging" \
  -var="gcp_project_id=banded-pad-479802-k9"

# 获取 kubeconfig
gcloud container clusters get-credentials \
  nova-staging-gke \
  --region=asia-northeast1
```

### 第 2 天: 数据和缓存

```bash
# Cloud SQL 和 Redis 应该已自动部署
# 验证
gcloud sql instances list
gcloud redis instances list --region=asia-northeast1

# 获取连接信息
CLOUD_SQL_IP=$(gcloud sql instances describe nova-staging \
  --format='value(ipAddresses[0].ipAddress)')
echo "Cloud SQL Private IP: $CLOUD_SQL_IP"

REDIS_IP=$(gcloud redis instances describe nova-staging-redis \
  --region=asia-northeast1 \
  --format='value(host)')
echo "Redis IP: $REDIS_IP"
```

### 第 3 天: CI/CD

修改 GitHub Actions workflows (参考 `docs/GCP_CICD_INTEGRATION.md`):

```bash
# 1. 在 GCP 创建 OIDC 配置
gcloud iam workload-identity-pools create github \
  --location=global \
  --display-name="GitHub Actions"

# 2. 创建 Provider
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global \
  --workload-identity-pool=github \
  --display-name="GitHub Provider" \
  --attribute-mapping='google.subject=assertion.sub,attribute.repository=assertion.repository' \
  --issuer-uri=https://token.actions.githubusercontent.com

# 3. 绑定 Service Account
gcloud iam service-accounts add-iam-policy-binding \
  github-actions@banded-pad-479802-k9.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member='principalSet://iam.googleapis.com/projects/690655954246/locations/global/workloadIdentityPools/github/attribute.repository/proerror/nova'

# 4. 修改 GitHub Actions workflows (见 GCP_CICD_INTEGRATION.md)
```

### 第 4 天: 验证 & 优化

```bash
# 部署微服务到 GKE
kubectl apply -k k8s/overlays/staging

# 检查状态
kubectl get deployments -n nova-staging
kubectl get pods -n nova-staging

# 查看日志
kubectl logs -n nova-staging -l app=identity-service --tail=50

# 执行 smoke test
kubectl run test-curl --image=curlimages/curl --rm -it \
  -- curl http://identity-service.nova-staging.svc.cluster.local:8080/health
```

---

## 🐛 常见问题

### AWS

**问**: EKS 集群无法连接?
```bash
# 更新 kubeconfig
aws eks update-kubeconfig --name nova-staging --region ap-northeast-1

# 检查 IAM 权限
aws iam get-user
```

**问**: ECR 推送失败?
```bash
# 获取 ECR 登录令牌
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin \
  025434362120.dkr.ecr.ap-northeast-1.amazonaws.com
```

### GCP

**问**: GKE 节点无法启动?
```bash
# 检查 node pool
gcloud container node-pools list --cluster=nova-staging-gke --region=asia-northeast1

# 检查节点状态
kubectl get nodes -o wide
```

**问**: Cloud SQL 连接失败?
```bash
# 检查私有服务连接
gcloud compute networks peering list

# 测试连接 (从 GKE pod 内)
kubectl run -it --rm debug --image=gcr.io/cloudsql-docker/cloud-sql-proxy \
  -- cloud-sql-proxy nova-staging
```

---

## 📈 部署后检查清单

- [ ] 集群健康检查
  ```bash
  kubectl get nodes
  kubectl get pods --all-namespaces
  ```

- [ ] 数据库连接
  ```bash
  kubectl run -it --rm psql --image=postgres:latest \
    -- psql -h <DB_HOST> -U nova_admin -d nova
  ```

- [ ] Redis 连接
  ```bash
  kubectl run -it --rm redis --image=redis:latest \
    -- redis-cli -h <REDIS_HOST> ping
  ```

- [ ] 镜像仓库
  ```bash
  # AWS
  aws ecr describe-repositories --region ap-northeast-1

  # GCP
  gcloud artifacts repositories list --location=asia-northeast1
  ```

- [ ] 网络连通性
  ```bash
  kubectl run -it --rm curl --image=curlimages/curl \
    -- curl -v http://identity-service.nova-staging.svc.cluster.local:8080/health
  ```

---

## 💰 成本监控

### AWS

```bash
# 查看 EC2 成本
aws ce get-cost-and-usage \
  --time-period Start=2025-11-01,End=2025-11-30 \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# 查看 RDS 成本
aws ce get-cost-and-usage \
  --time-period Start=2025-11-01,End=2025-11-30 \
  --metrics UnblendedCost \
  --filter file://rds-filter.json
```

### GCP

```bash
# 查看成本
gcloud billing accounts list
gcloud compute project-info describe --project=banded-pad-479802-k9 \
  --format='value(commonInstanceMetadata.items[ssh-keys])'

# 使用 Cloud Console
# https://console.cloud.google.com/billing
```

---

## 🎯 建议行动计划

### 立即 (今天)

1. **选择部署方案**
   - [ ] AWS (现有配置)
   - [ ] GCP (长期规划)

2. **如果选 AWS**
   - [ ] 运行 `terraform apply`
   - [ ] 验证 EKS 集群
   - [ ] 部署微服务
   - [ ] **完成时间: 1-2 小时**

3. **如果选 GCP**
   - [ ] 分配 2 周的实施时间
   - [ ] 开始阅读 `GCP_ARCHITECTURE_PLAN.md`
   - [ ] 逐步执行 Terraform 部署

### 本周

- [ ] Staging 环境验证
- [ ] 压力测试
- [ ] 数据库备份策略
- [ ] 监控和告警配置

### 本月

- [ ] 文档完善
- [ ] 团队培训
- [ ] 成本优化
- [ ] 生产环境规划

---

## 📚 文档索引

| 文档 | 目的 |
|------|------|
| `GCP_ARCHITECTURE_PLAN.md` | 详细架构设计 |
| `GCP_CICD_INTEGRATION.md` | CI/CD 集成指南 |
| `GCP_QUICK_START.md` | 本文 (快速参考) |

---

## 🆘 获取帮助

1. **查看 Terraform 错误**
   ```bash
   terraform plan -out=tfplan
   terraform show tfplan | grep -A 5 "Error"
   ```

2. **查看 Kubernetes 错误**
   ```bash
   kubectl describe pod <POD_NAME> -n nova-staging
   kubectl logs <POD_NAME> -n nova-staging -f
   ```

3. **查看云平台日志**
   ```bash
   # AWS
   aws logs tail /aws/eks/nova-staging

   # GCP
   gcloud logging read "resource.type=k8s_cluster"
   ```

---

**版本**: 1.0
**最后更新**: 2025-11-30
**维护人**: Infrastructure Team

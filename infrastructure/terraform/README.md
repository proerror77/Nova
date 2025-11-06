# Nova EKS Infrastructure with Terraform

完整的基础设施即代码（IaC）解决方案，用于在 AWS 上部署和管理 Nova 微服务架构。

## 概述

此 Terraform 配置创建和管理以下 AWS 资源：

### 核心基础设施
- **VPC & Networking**: 跨多个可用区的 VPC，包括公有和私有子网
- **NAT Gateways**: 为私有子网提供出站互联网访问
- **Security Groups**: 针对 EKS 集群控制平面和节点的安全规则

### 容器编排
- **EKS Cluster**: 托管的 Kubernetes 集群（1.28）
- **EKS Node Groups**: 可自动扩展的 EC2 实例
- **OIDC Provider**: 用于 IRSA（IAM Roles for Service Accounts）

### 镜像仓库
- **ECR Repositories**: 为 8 个微服务创建私有 Docker 镜像仓库
- **Lifecycle Policies**: 自动清理旧镜像

### Kubernetes Add-ons
- **AWS Load Balancer Controller**: 管理 ALB/NLB 入站流量
- **Cert-Manager**: 自动 TLS 证书管理
- **Metrics Server**: HPA 自动扩展所需
- **ArgoCD**: GitOps CD 部署
- **CoreDNS, VPC CNI, EBS CSI**: AWS 托管的 EKS add-ons
- **Prometheus**: 可选的监控和指标收集

### IAM & 安全
- **EKS Cluster & Node IAM Roles**: 集群和节点的权限管理
- **IRSA Roles**: 为 add-ons 提供最小权限的 IAM 角色
- **GitHub Actions OIDC**: CI/CD 流程的安全认证

## 前置条件

### 软件要求
```bash
# 安装必要工具
brew install terraform aws-cli kubectl

# 验证版本
terraform version  # >= 1.5
aws --version      # >= 2.13
kubectl version    # >= 1.27
```

### AWS 账户配置
```bash
# 配置 AWS 凭证
aws configure

# 验证认证
aws sts get-caller-identity
```

### AWS S3 Terraform State Backend（可选但推荐）
```bash
# 创建 S3 bucket 和 DynamoDB 表来存储 terraform state
aws s3api create-bucket \
  --bucket nova-terraform-state \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1

aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-1
```

## 快速开始

### 1. 初始化 Terraform
```bash
cd /Users/proerror/Documents/nova/infrastructure/terraform

# 初始化 Terraform（下载提供者和模块）
terraform init
```

### 2. 配置变量
```bash
# 复制示例配置
cp terraform.tfvars.example terraform.tfvars

# 编辑配置以匹配你的需求
vim terraform.tfvars
```

关键配置项：
- `aws_region`: AWS 区域（默认：ap-northeast-1）
- `environment`: 环境名称（staging/production）
- `cluster_name`: EKS 集群名称
- `node_group_desired_size`: 期望的节点数量

### 3. 验证计划
```bash
# 查看将要创建的资源
terraform plan -out=tfplan

# 保存计划以备后用
terraform show tfplan
```

### 4. 应用配置
```bash
# 创建基础设施（需要 10-15 分钟）
terraform apply tfplan

# 或者直接应用（会再次提示确认）
terraform apply
```

### 5. 配置 kubeconfig
```bash
# 获取集群凭证
aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name nova-eks

# 验证连接
kubectl get nodes
kubectl get pods -A
```

## 部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                              │
│                     (10.0.0.0/16)                             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐    ┌──────────────┐   ┌──────────────┐   │
│  │ Internet GW  │    │  NAT GW 1    │   │   NAT GW 2   │   │
│  └──────────────┘    └──────────────┘   └──────────────┘   │
│         ↑                   ↑                    ↑             │
│  ┌──────────────┐    ┌──────────────┐   ┌──────────────┐   │
│  │ Public SN 1  │    │ Private SN 1 │   │ Private SN 2 │   │
│  │ (10.0.1.0)   │    │ (10.0.10.0)  │   │ (10.0.11.0)  │   │
│  └──────────────┘    └──────────────┘   └──────────────┘   │
│                             ↓                    ↓             │
│                      ┌──────────────────────────┐              │
│                      │    EKS Cluster Nodes     │              │
│                      │  (t3.medium/t3.large)    │              │
│                      │   Min: 2, Max: 10        │              │
│                      └──────────────────────────┘              │
│                                                               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    EKS Cluster (1.28)                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  kube-system                                                  │
│  ├─ CoreDNS                  (AWS managed addon)              │
│  ├─ kube-proxy              (AWS managed addon)               │
│  ├─ VPC CNI                 (AWS managed addon)               │
│  ├─ EBS CSI Driver          (AWS managed addon)               │
│  ├─ AWS Load Balancer Controller (Helm)                      │
│  └─ Metrics Server          (Helm)                           │
│                                                               │
│  cert-manager                                                 │
│  ├─ cert-manager            (Helm)                           │
│  └─ cert-manager webhook                                     │
│                                                               │
│  argocd                                                       │
│  ├─ argocd-server           (GitOps CD)                      │
│  ├─ argocd-repo-server                                       │
│  └─ argocd-controller-manager                                │
│                                                               │
│  kube-monitoring (optional)                                  │
│  ├─ Prometheus              (Helm)                           │
│  ├─ Grafana                                                  │
│  └─ AlertManager                                             │
│                                                               │
│  nova-staging / nova-prod                                    │
│  ├─ auth-service (pods)                                      │
│  ├─ user-service (pods)                                      │
│  ├─ content-service (pods)                                   │
│  └─ ...（其他 8 个服务）                                     │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## ECR 仓库

创建以下 ECR 仓库：
- `nova/auth-service`
- `nova/user-service`
- `nova/content-service`
- `nova/feed-service`
- `nova/media-service`
- `nova/messaging-service`
- `nova/search-service`
- `nova/streaming-service`

### 推送镜像到 ECR
```bash
# 获取 ECR 登录令牌
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com

# 构建和推送镜像
docker build -t nova/auth-service:latest ./backend/auth-service
docker tag nova/auth-service:latest \
  025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/auth-service:latest
docker push 025434362120.dkr.ecr.ap-northeast-1.amazonaws.com/nova/auth-service:latest
```

## GitHub Actions 集成

### 设置 GitHub OIDC Provider
```bash
# 1. 在 AWS 中创建 GitHub OIDC Provider
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "1234567890"  # 从 GitHub 获取正确的 thumbprint

# 2. 在 terraform.tfvars 中设置 OIDC Provider ARN
# github_oidc_provider_arn = "arn:aws:iam::025434362120:oidc-provider/token.actions.githubusercontent.com"

# 3. 重新应用 Terraform
terraform apply
```

## 管理和监控

### 查看集群状态
```bash
# 获取集群信息
kubectl cluster-info
kubectl get nodes -o wide
kubectl get ns
kubectl top nodes
kubectl top pods -A
```

### 扩展节点数量
```bash
# 编辑 terraform.tfvars
vim terraform.tfvars
# 修改 node_group_desired_size

# 应用更改
terraform apply
```

### 更新 Kubernetes 版本
```bash
# 编辑 terraform.tfvars
vim terraform.tfvars
# 修改 kubernetes_version

# 应用更改（会导致节点滚动更新）
terraform apply
```

## 成本估算

基于默认配置（us-east-1）的月度成本：

| 资源 | 配置 | 月度成本 |
|------|------|---------|
| EKS 控制平面 | 1 个集群 | $73 |
| EC2 节点 | 3x t3.medium | $150-200 |
| NAT Gateway | 2 个 | $45 |
| 数据传输 | ~100GB | $20 |
| ECR 存储 | ~50GB | $5 |
| **总计** | | **~$300** |

*注意：成本因地区和使用情况而异*

## 清理资源

### 删除 EKS 集群和关联资源
```bash
# 首先删除所有 Load Balancer（否则会卡住）
kubectl delete svc --all -A

# 删除 Terraform 创建的所有资源
terraform destroy

# 验证所有资源都已删除
aws ec2 describe-instances --region ap-northeast-1
aws ecr describe-repositories --region ap-northeast-1
```

## 故障排除

### 问题：Terraform 初始化失败
```bash
# 解决方案：重新初始化
rm -rf .terraform terraform.lock.hcl
terraform init
```

### 问题：EKS 节点无法启动
```bash
# 检查 IAM 角色权限
aws iam get-role --role-name nova-eks-node-role

# 查看 EC2 启动日志
aws ec2 describe-instances --region ap-northeast-1 | grep -A 5 "StatusMessage"
```

### 问题：Kubectl 连接失败
```bash
# 更新 kubeconfig
aws eks update-kubeconfig --region ap-northeast-1 --name nova-eks

# 测试连接
kubectl auth can-i get pods --as system:serviceaccount:default:default
```

## 下一步

1. ✅ 部署 EKS 基础设施
2. → 配置 ArgoCD GitOps 工作流
3. → 修复 GitHub Actions CI/CD 流程
4. → 配置服务部署 Kustomize 清单
5. → 部署应用程序和服务

## 文档和资源

- [AWS EKS 文档](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Kubernetes 文档](https://kubernetes.io/docs/)
- [ArgoCD 文档](https://argo-cd.readthedocs.io/)

## 支持

有问题？查看：
1. Terraform 日志：`terraform plan` 和 `terraform apply`
2. AWS CloudFormation 堆栈事件：检查 AWS 控制台
3. EKS 集群日志：`kubectl logs -f <pod> -n <namespace>`

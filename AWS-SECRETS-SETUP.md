# AWS Secrets Manager Setup - Quick Start Guide

完整的 AWS Secrets Manager 与 Kubernetes External Secrets Operator 集成。

## 📋 Overview

本指南将帮助你配置以下集成:

1. **AWS Secrets Manager**: 存储敏感密钥
2. **IAM Role (IRSA)**: 授予 Kubernetes Pod 访问 AWS 的权限
3. **External Secrets Operator**: 自动同步 AWS 密钥到 Kubernetes
4. **Kubernetes Secrets**: 供应用 Pod 使用

## 🚀 Quick Start (15 分钟)

### Prerequisites

- AWS Account with EKS cluster
- kubectl configured
- helm 3.x installed
- AWS CLI configured
- Terraform (optional)

### Step 1: 创建 AWS Secrets (3 分钟)

```bash
cd /Users/proerror/Documents/nova

# Staging 环境
./scripts/aws/setup-aws-secrets.sh staging

# Production 环境 (可选)
./scripts/aws/setup-aws-secrets.sh production
```

这将在 AWS Secrets Manager 中创建以下密钥:

```
Secret Name: nova-backend-staging
Secret Keys:
  - DATABASE_URL
  - REDIS_URL
  - JWT_PRIVATE_KEY_PEM
  - JWT_PUBLIC_KEY_PEM
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - SMTP_PASSWORD
  - GOOGLE_CLIENT_SECRET
  - FACEBOOK_APP_SECRET
  - APNS_PRIVATE_KEY
  - FCM_SERVICE_ACCOUNT_JSON
  - ... (更多)
```

**重要**: 脚本创建的是占位符值,需要更新为真实值。

### Step 2: 更新密钥值 (5 分钟)

#### 方法 1: AWS Console

1. 登录 AWS Console → Secrets Manager
2. 找到 `nova-backend-staging`
3. 点击 "Retrieve secret value" → "Edit"
4. 更新所有密钥值
5. 保存

#### 方法 2: AWS CLI

```bash
# 准备密钥 JSON 文件
cat > secrets.json <<'EOF'
{
  "DATABASE_URL": "postgresql://nova:REAL_PASSWORD@postgres.nova-staging.svc.cluster.local:5432/nova",
  "REDIS_URL": "redis://:REAL_PASSWORD@redis.nova-staging.svc.cluster.local:6379",
  "JWT_PRIVATE_KEY_PEM": "-----BEGIN PRIVATE KEY-----\nREAL_KEY\n-----END PRIVATE KEY-----",
  "JWT_PUBLIC_KEY_PEM": "-----BEGIN PUBLIC KEY-----\nREAL_KEY\n-----END PUBLIC KEY-----"
}
EOF

# 更新密钥
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string file://secrets.json \
  --region us-west-2

# 删除本地文件 (安全)
rm secrets.json
```

### Step 3: 创建 IAM Role (5 分钟)

#### 使用 Terraform (推荐)

```bash
cd terraform

# 复制并编辑配置
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# 设置你的值:
# aws_account_id = "123456789012"
# eks_cluster_id = "EXAMPLED539D4633E53DE1B71EXAMPLE"
# aws_region = "us-west-2"

# 应用
terraform init
terraform plan
terraform apply

# 记录输出的 Role ARN
# Output: nova_secrets_role_arn = arn:aws:iam::123456789012:role/nova-backend-secrets-role
```

#### 获取 EKS OIDC Provider ID

```bash
# 获取你的 EKS Cluster OIDC Provider ID
aws eks describe-cluster \
  --name YOUR_CLUSTER_NAME \
  --query "cluster.identity.oidc.issuer" \
  --output text | cut -d '/' -f 5
```

#### 手动创建 (AWS CLI)

```bash
# 1. 创建 IAM Policy
aws iam create-policy \
  --policy-name nova-backend-secrets-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-west-2:ACCOUNT_ID:secret:nova-backend-*"
    }]
  }'

# 2. 创建 IAM Role (使用 terraform/iam-secrets-role.tf 中的 Trust Policy)
# 3. 附加 Policy 到 Role
```

### Step 4: 更新 ServiceAccount (2 分钟)

编辑 `k8s/base/external-secrets/serviceaccount.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nova-backend-sa
  namespace: nova-staging
  annotations:
    # 替换为你的 IAM Role ARN
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/nova-backend-secrets-role
```

### Step 5: 安装 External Secrets Operator (2 分钟)

```bash
./scripts/aws/setup-external-secrets-operator.sh
```

或手动安装:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

### Step 6: 部署 Kubernetes 资源 (2 分钟)

```bash
# 应用 ServiceAccount 和 SecretStore
kubectl apply -f k8s/base/external-secrets/

# 应用 ExternalSecret (Staging)
kubectl apply -f k8s/overlays/staging/external-secret.yaml

# 应用 ExternalSecret (Production,可选)
kubectl apply -f k8s/overlays/production/external-secret.yaml
```

### Step 7: 验证集成 (3 分钟)

```bash
# 运行自动化验证脚本
./scripts/aws/verify-secrets-integration.sh staging

# 或手动检查
kubectl get externalsecrets -n nova-staging
kubectl get secrets -n nova-staging
kubectl describe externalsecret nova-backend-secrets -n nova-staging
```

预期输出:

```
NAME                    STORE                 REFRESH INTERVAL   STATUS   READY
nova-backend-secrets    aws-secretsmanager    1h                 Synced   True

NAME                    TYPE     DATA   AGE
nova-backend-secrets    Opaque   15     30s
```

### Step 8: 更新应用 Deployment (3 分钟)

参考示例配置更新你的 Deployment:

```bash
# 使用新的 deployment 配置
kubectl apply -f k8s/base/auth-service-deployment-externalsecrets.yaml

# 或编辑现有 deployment
kubectl edit deployment auth-service -n nova-auth
```

关键变更:

```yaml
spec:
  template:
    spec:
      serviceAccountName: nova-backend-sa  # 添加此行
      containers:
      - name: auth-service
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: nova-backend-secrets  # 更新为新 Secret 名称
              key: DATABASE_URL            # 更新键名
```

## 📁 文件结构

```
/Users/proerror/Documents/nova/
├── scripts/aws/
│   ├── setup-aws-secrets.sh                      # 创建 AWS Secrets
│   ├── setup-external-secrets-operator.sh        # 安装 ESO
│   └── verify-secrets-integration.sh             # 验证集成
│
├── terraform/
│   ├── iam-secrets-role.tf                       # IAM Role for IRSA
│   └── terraform.tfvars.example                  # 配置示例
│
├── k8s/
│   ├── base/
│   │   ├── external-secrets/
│   │   │   ├── README.md                         # 详细说明
│   │   │   ├── namespace.yaml                    # ESO namespace
│   │   │   ├── serviceaccount.yaml               # IRSA ServiceAccount
│   │   │   ├── secretstore.yaml                  # SecretStore 配置
│   │   │   └── kustomization.yaml
│   │   │
│   │   └── auth-service-deployment-externalsecrets.yaml  # 示例 Deployment
│   │
│   └── overlays/
│       ├── staging/
│       │   └── external-secret.yaml              # Staging ExternalSecret
│       └── production/
│           └── external-secret.yaml              # Production ExternalSecret
│
└── docs/
    ├── aws-secrets-manager-integration.md        # 完整集成指南
    └── secrets-rotation-guide.md                 # 密钥轮换指南
```

## 🔍 验证清单

使用此清单确保所有配置正确:

- [ ] AWS Secrets Manager 中的密钥已创建
- [ ] 所有密钥值已更新为真实值 (非占位符)
- [ ] IAM Role 已创建并附加正确的 Policy
- [ ] ServiceAccount 包含正确的 IAM Role ARN
- [ ] External Secrets Operator 已安装并运行
- [ ] SecretStore 状态为 Ready
- [ ] ExternalSecret 状态为 Synced
- [ ] Kubernetes Secret 已创建并包含正确的键
- [ ] 应用 Deployment 使用了新的 Secret
- [ ] Pod 可以访问 AWS Secrets Manager (测试脚本通过)

## 🛠️ 常用操作

### 查看 Secret 内容

```bash
# 查看 Kubernetes Secret
kubectl get secret nova-backend-secrets -n nova-staging -o yaml

# 解码特定键 (仅用于调试)
kubectl get secret nova-backend-secrets -n nova-staging -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

### 更新密钥

```bash
# 1. 更新 AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string '{"DATABASE_URL": "new-value"}'

# 2. 等待自动刷新 (1 小时) 或手动触发
kubectl annotate externalsecret nova-backend-secrets \
  force-sync="$(date +%s)" \
  -n nova-staging \
  --overwrite

# 3. 重启 Pod 使其使用新 Secret
kubectl rollout restart deployment auth-service -n nova-auth
```

### 查看日志

```bash
# External Secrets Operator 日志
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets -f

# 查看特定 ExternalSecret 事件
kubectl describe externalsecret nova-backend-secrets -n nova-staging
```

## 🚨 故障排查

### 问题: ExternalSecret 显示 "SecretSyncedError"

**原因**: IAM 权限不足或 AWS Secret 不存在

**解决**:

```bash
# 1. 检查 ExternalSecret 状态
kubectl describe externalsecret nova-backend-secrets -n nova-staging

# 2. 检查 ESO 日志
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# 3. 验证 AWS 连接
kubectl run -it --rm aws-test \
  --image=amazon/aws-cli \
  --serviceaccount=nova-backend-sa \
  -n nova-staging \
  -- secretsmanager get-secret-value --secret-id nova-backend-staging --region us-west-2
```

### 问题: SecretStore 显示 "Not Ready"

**原因**: ServiceAccount 没有正确的 IRSA 配置

**解决**:

```bash
# 检查 ServiceAccount 注解
kubectl get sa nova-backend-sa -n nova-staging -o yaml

# 验证 Pod 使用了正确的 ServiceAccount
kubectl get pod -l app=auth-service -n nova-auth -o jsonpath='{.items[0].spec.serviceAccountName}'
```

### 问题: Secret 未创建

**原因**: SecretStore 未就绪或 ExternalSecret 配置错误

**解决**:

```bash
# 检查 SecretStore
kubectl get secretstore -n nova-staging

# 检查 ExternalSecret
kubectl get externalsecret -n nova-staging

# 查看详细错误
kubectl describe externalsecret nova-backend-secrets -n nova-staging
```

## 📚 相关文档

| 文档 | 描述 |
|------|------|
| [aws-secrets-manager-integration.md](docs/aws-secrets-manager-integration.md) | 完整集成指南 (包含安全最佳实践) |
| [secrets-rotation-guide.md](docs/secrets-rotation-guide.md) | 密钥轮换策略和自动化 |
| [k8s/base/external-secrets/README.md](k8s/base/external-secrets/README.md) | Kubernetes 配置详解 |
| [External Secrets Operator](https://external-secrets.io/) | 官方文档 |
| [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/) | AWS 官方文档 |
| [IRSA Guide](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) | IAM Roles for Service Accounts |

## 🔒 安全建议

1. **最小权限**: IAM Policy 仅授予必要权限 (GetSecretValue, DescribeSecret)
2. **密钥轮换**: 至少每 90 天轮换一次敏感密钥
3. **环境隔离**: Staging 和 Production 使用不同的 AWS Secrets 和 IAM Roles
4. **审计日志**: 启用 AWS CloudTrail 记录所有 Secrets Manager 访问
5. **加密**: 使用 AWS KMS 自定义密钥加密密钥
6. **访问控制**: 限制谁可以访问 AWS Secrets Manager
7. **网络隔离**: 使用 VPC Endpoints 访问 Secrets Manager (避免公网流量)

## 💰 成本估算

- **AWS Secrets Manager**: $0.40/secret/month + $0.05 per 10,000 API calls
- **External Secrets Operator**: 免费 (开源)
- **数据传输**: VPC Endpoint 流量费用 (可选)

**示例** (5 个 Secrets, 每小时刷新):

- Secrets: 5 × $0.40 = $2.00/月
- API Calls: 5 × 24 × 30 × $0.05/10000 = $0.18/月
- **总计**: ~$2.20/月

## 🎯 下一步

配置完成后,建议:

1. ✅ 设置密钥轮换计划 (见 `secrets-rotation-guide.md`)
2. ✅ 配置 CloudWatch Alarms 监控异常访问
3. ✅ 为所有微服务更新 Deployment 配置
4. ✅ 测试应急密钥轮换流程
5. ✅ 文档化你的自定义密钥和轮换策略

## ❓ 支持

遇到问题?

1. 运行验证脚本: `./scripts/aws/verify-secrets-integration.sh staging`
2. 查看 [故障排查](#-故障排查) 部分
3. 阅读 [完整集成指南](docs/aws-secrets-manager-integration.md)
4. 查看 External Secrets Operator 日志

---

**最后更新**: 2025-11-09
**维护者**: Nova Backend Team

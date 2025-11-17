# AWS Secrets Manager Integration

完整的 AWS Secrets Manager 与 Kubernetes External Secrets Operator 集成指南。

## 架构概览

```
AWS Secrets Manager
       ↓
    IRSA (IAM Role)
       ↓
External Secrets Operator (ESO)
       ↓
Kubernetes Secrets
       ↓
Microservices Pods
```

## 前置要求

- AWS Account with EKS cluster
- kubectl configured
- helm 3.x
- AWS CLI configured
- Terraform (optional, for IAM setup)

## 安装步骤

### 1. 创建 AWS Secrets Manager 密钥

```bash
# Staging 环境
./scripts/aws/setup-aws-secrets.sh staging

# Production 环境
./scripts/aws/setup-aws-secrets.sh production
```

这将创建包含以下密钥结构的 Secret:

```json
{
  "DATABASE_URL": "postgresql://...",
  "REDIS_URL": "redis://...",
  "JWT_PRIVATE_KEY_PEM": "-----BEGIN PRIVATE KEY-----...",
  "JWT_PUBLIC_KEY_PEM": "-----BEGIN PUBLIC KEY-----...",
  "AWS_ACCESS_KEY_ID": "...",
  "AWS_SECRET_ACCESS_KEY": "...",
  "SMTP_PASSWORD": "...",
  "GOOGLE_CLIENT_SECRET": "...",
  "FACEBOOK_APP_SECRET": "...",
  "APNS_PRIVATE_KEY": "...",
  "FCM_SERVICE_ACCOUNT_JSON": "{...}"
}
```

### 2. 创建 IAM Role (IRSA)

#### 使用 Terraform

```bash
cd terraform

# 复制示例配置
cp terraform.tfvars.example terraform.tfvars

# 编辑 terraform.tfvars
# 设置:
#   aws_account_id = "YOUR_ACCOUNT_ID"
#   eks_cluster_id = "YOUR_EKS_CLUSTER_OIDC_ID"
#   aws_region = "us-west-2"

# 应用 Terraform
terraform init
terraform plan
terraform apply
```

#### 手动创建 (AWS CLI)

```bash
# 1. 创建 IAM Policy
aws iam create-policy \
  --policy-name nova-backend-secrets-policy \
  --policy-document file://terraform/iam-secrets-policy.json

# 2. 创建 IAM Role with trust relationship
aws iam create-role \
  --role-name nova-backend-secrets-role \
  --assume-role-policy-document file://terraform/iam-trust-policy.json

# 3. 附加 Policy 到 Role
aws iam attach-role-policy \
  --role-name nova-backend-secrets-role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/nova-backend-secrets-policy
```

**重要**: 获取 Role ARN 并更新 `k8s/base/external-secrets/serviceaccount.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nova-backend-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/nova-backend-secrets-role
```

### 3. 安装 External Secrets Operator

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

### 4. 部署 Kubernetes 资源

#### Staging 环境

```bash
# 应用 ServiceAccount 和 SecretStore
kubectl apply -f k8s/base/external-secrets/

# 应用 ExternalSecret
kubectl apply -f k8s/overlays/staging/external-secret.yaml
```

#### Production 环境

```bash
kubectl apply -f k8s/base/external-secrets/
kubectl apply -f k8s/overlays/production/external-secret.yaml
```

### 5. 验证安装

```bash
# 检查 External Secrets Operator
kubectl get pods -n external-secrets-system

# 检查 ExternalSecret 状态
kubectl get externalsecrets -n nova-staging

# 检查生成的 Kubernetes Secret
kubectl get secrets -n nova-staging nova-backend-secrets

# 查看 Secret 内容 (base64 编码)
kubectl get secret nova-backend-secrets -n nova-staging -o yaml

# 解码查看 (仅用于调试,不要在生产环境执行)
kubectl get secret nova-backend-secrets -n nova-staging -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```

### 6. 更新应用 Deployment

更新你的微服务 Deployment 以使用新的 Secret:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
spec:
  template:
    spec:
      # 使用 IRSA ServiceAccount
      serviceAccountName: nova-backend-sa
      containers:
      - name: auth-service
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: auth-service-secrets  # 由 External Secrets 创建
              key: database-url
        # ... 其他环境变量
```

应用更新:

```bash
kubectl apply -f k8s/base/auth-service-deployment-externalsecrets.yaml
```

## 密钥更新流程

### 更新 AWS Secrets Manager 中的密钥

```bash
# 准备新的密钥 JSON
cat > new-secrets.json <<EOF
{
  "DATABASE_URL": "postgresql://new-password@...",
  "REDIS_URL": "redis://:new-password@..."
}
EOF

# 更新密钥
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string file://new-secrets.json \
  --region us-west-2

# 删除本地文件 (安全)
rm new-secrets.json
```

### 触发 Kubernetes Secret 刷新

External Secrets Operator 会自动刷新 (默认 1 小时),也可以手动触发:

```bash
# 方法 1: 删除 Secret,让 ESO 重新创建
kubectl delete secret nova-backend-secrets -n nova-staging

# 方法 2: 重启 External Secrets Operator (强制刷新所有 Secret)
kubectl rollout restart deployment external-secrets -n external-secrets-system

# 方法 3: 重启应用 Pod (使其获取新 Secret)
kubectl rollout restart deployment auth-service -n nova-auth
```

## 故障排查

### ExternalSecret 显示 "SecretSyncedError"

```bash
# 检查 ExternalSecret 状态
kubectl describe externalsecret nova-backend-secrets -n nova-staging

# 检查 ESO 日志
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# 常见问题:
# 1. IAM Role ARN 错误
# 2. AWS Secrets Manager 密钥名称错误
# 3. IAM 权限不足
```

### ServiceAccount 没有 IRSA 权限

```bash
# 验证 ServiceAccount 注解
kubectl get sa nova-backend-sa -n nova-staging -o yaml

# 确认 Pod 使用了正确的 ServiceAccount
kubectl get pod <pod-name> -n nova-staging -o jsonpath='{.spec.serviceAccountName}'

# 检查 Pod 的 AWS 凭证环境变量
kubectl exec <pod-name> -n nova-staging -- env | grep AWS
```

### Secret 未创建

```bash
# 检查 SecretStore 状态
kubectl get secretstore -n nova-staging

# 检查 SecretStore 详情
kubectl describe secretstore aws-secretsmanager -n nova-staging

# 验证 AWS Secrets Manager 连接
kubectl run -it --rm debug \
  --image=amazon/aws-cli \
  --serviceaccount=nova-backend-sa \
  -n nova-staging \
  -- secretsmanager get-secret-value \
     --secret-id nova-backend-staging \
     --region us-west-2
```

## 安全最佳实践

### 1. 最小权限原则

IAM Policy 仅授予必要权限:

```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue",
    "secretsmanager:DescribeSecret"
  ],
  "Resource": "arn:aws:secretsmanager:us-west-2:ACCOUNT_ID:secret:nova-backend-*"
}
```

### 2. 密钥轮换

```bash
# 启用自动轮换 (AWS Secrets Manager)
aws secretsmanager rotate-secret \
  --secret-id nova-backend-staging \
  --rotation-lambda-arn arn:aws:lambda:... \
  --rotation-rules AutomaticallyAfterDays=30
```

### 3. 审计日志

```bash
# 启用 AWS CloudTrail 记录 Secrets Manager 访问
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=nova-backend-staging
```

### 4. 环境隔离

- Staging 和 Production 使用不同的 AWS Secrets
- 不同的 IAM Role
- 不同的 Kubernetes Namespace

### 5. 密钥加密

AWS Secrets Manager 默认使用 AWS KMS 加密,可以使用自定义 KMS Key:

```bash
aws secretsmanager create-secret \
  --name nova-backend-production \
  --kms-key-id arn:aws:kms:us-west-2:ACCOUNT_ID:key/YOUR_KEY_ID \
  --secret-string '{...}'
```

## 成本估算

- **AWS Secrets Manager**: $0.40/secret/month + $0.05 per 10,000 API calls
- **External Secrets Operator**: 免费 (仅 Kubernetes 资源成本)

示例成本 (5 个 Secrets, 每小时刷新):

- Secrets: 5 × $0.40 = $2.00/月
- API Calls: 5 × 24 × 30 × $0.05/10000 = $0.18/月
- **总计**: ~$2.20/月

## 迁移现有 Secret

如果你已经有 Kubernetes Secret,迁移到 AWS Secrets Manager:

```bash
# 1. 导出现有 Secret
kubectl get secret auth-service-secret -n nova-auth -o json > old-secret.json

# 2. 转换为 AWS Secrets Manager 格式
cat old-secret.json | jq -r '.data | map_values(@base64d) | to_entries | map("\(.key)=\(.value)") | .[]'

# 3. 创建 AWS Secret (使用上面的脚本)
./scripts/aws/setup-aws-secrets.sh staging

# 4. 更新密钥值
aws secretsmanager update-secret --secret-id nova-backend-staging --secret-string '{...}'

# 5. 部署 ExternalSecret
kubectl apply -f k8s/overlays/staging/external-secret.yaml

# 6. 验证新 Secret 创建
kubectl get secret nova-backend-secrets -n nova-staging

# 7. 更新 Deployment 引用
kubectl apply -f k8s/base/auth-service-deployment-externalsecrets.yaml

# 8. 删除旧 Secret (谨慎!)
kubectl delete secret auth-service-secret -n nova-auth
```

## 参考资料

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [IRSA (IAM Roles for Service Accounts)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/#best-practices)

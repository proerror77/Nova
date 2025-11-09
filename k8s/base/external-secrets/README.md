# External Secrets Integration

AWS Secrets Manager 与 Kubernetes 集成,使用 External Secrets Operator 自动同步密钥。

## 快速开始

### 1. 前置要求

- EKS Cluster with OIDC Provider
- AWS CLI configured
- kubectl configured
- helm 3.x

### 2. 安装步骤

```bash
# Step 1: 创建 AWS Secrets
cd /Users/proerror/Documents/nova
./scripts/aws/setup-aws-secrets.sh staging

# Step 2: 创建 IAM Role (Terraform)
cd terraform
terraform init
terraform apply

# Step 3: 安装 External Secrets Operator
./scripts/aws/setup-external-secrets-operator.sh

# Step 4: 部署 Kubernetes 资源
kubectl apply -f k8s/base/external-secrets/
kubectl apply -f k8s/overlays/staging/external-secret.yaml

# Step 5: 验证
kubectl get externalsecrets -n nova-staging
kubectl get secrets -n nova-staging
```

## 文件结构

```
k8s/base/external-secrets/
├── README.md                 # 本文件
├── namespace.yaml           # External Secrets Operator namespace
├── serviceaccount.yaml      # IRSA ServiceAccount
├── secretstore.yaml         # SecretStore 配置
└── kustomization.yaml       # Kustomize 配置

k8s/overlays/staging/
└── external-secret.yaml     # Staging ExternalSecret

k8s/overlays/production/
└── external-secret.yaml     # Production ExternalSecret

scripts/aws/
├── setup-aws-secrets.sh             # 创建 AWS Secrets
└── setup-external-secrets-operator.sh  # 安装 ESO

terraform/
├── iam-secrets-role.tf      # IAM Role for IRSA
└── terraform.tfvars.example # 配置示例
```

## 架构

```
┌─────────────────────────────────────────────────────┐
│          AWS Secrets Manager                        │
│  ┌─────────────────────────────────────────────┐   │
│  │  nova-backend-staging                       │   │
│  │  {                                          │   │
│  │    "DATABASE_URL": "postgresql://...",     │   │
│  │    "REDIS_URL": "redis://...",             │   │
│  │    "JWT_PRIVATE_KEY_PEM": "...",           │   │
│  │    ...                                      │   │
│  │  }                                          │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ IRSA (IAM Role)
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│   External Secrets Operator                         │
│   ┌──────────────────────────────────────────────┐ │
│   │  SecretStore: aws-secretsmanager            │ │
│   │  - Provider: AWS Secrets Manager            │ │
│   │  - Auth: IRSA (ServiceAccount)              │ │
│   └──────────────────────────────────────────────┘ │
│   ┌──────────────────────────────────────────────┐ │
│   │  ExternalSecret: nova-backend-secrets       │ │
│   │  - Target: Kubernetes Secret                │ │
│   │  - Refresh: Every 1 hour                    │ │
│   └──────────────────────────────────────────────┘ │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ Sync
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│   Kubernetes Secret: nova-backend-secrets           │
│   data:                                             │
│     DATABASE_URL: <base64>                          │
│     REDIS_URL: <base64>                             │
│     JWT_PRIVATE_KEY_PEM: <base64>                   │
│     ...                                             │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ mounted as env vars
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│   Microservices Pods                                │
│   - auth-service                                    │
│   - user-service                                    │
│   - messaging-service                               │
│   ...                                               │
└─────────────────────────────────────────────────────┘
```

## 配置说明

### ServiceAccount (IRSA)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nova-backend-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/nova-backend-secrets-role
```

**重要**: 替换 `ACCOUNT_ID` 为你的 AWS Account ID。

### SecretStore

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: nova-backend-sa
```

连接 AWS Secrets Manager,使用 IRSA 认证。

### ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: nova-backend-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
  target:
    name: nova-backend-secrets
  dataFrom:
  - extract:
      key: nova-backend-staging
```

从 AWS Secrets Manager 提取所有键值,创建 Kubernetes Secret。

## 使用方法

### 在 Deployment 中引用 Secret

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
spec:
  template:
    spec:
      serviceAccountName: nova-backend-sa  # 使用 IRSA
      containers:
      - name: auth-service
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: nova-backend-secrets
              key: DATABASE_URL
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: nova-backend-secrets
              key: REDIS_URL
```

### 更新密钥

```bash
# 更新 AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string '{"DATABASE_URL": "new-value"}'

# External Secrets Operator 会在 refreshInterval (1h) 后自动同步
# 或手动触发:
kubectl annotate externalsecret nova-backend-secrets \
  force-sync="$(date +%s)" \
  -n nova-staging \
  --overwrite

# 重启 Pod 以使用新 Secret
kubectl rollout restart deployment auth-service -n nova-auth
```

## 故障排查

### ExternalSecret 未同步

```bash
# 检查状态
kubectl describe externalsecret nova-backend-secrets -n nova-staging

# 查看 ESO 日志
kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets

# 验证 AWS 连接
kubectl run -it --rm aws-cli \
  --image=amazon/aws-cli \
  --serviceaccount=nova-backend-sa \
  -n nova-staging \
  -- secretsmanager get-secret-value --secret-id nova-backend-staging --region us-west-2
```

### IRSA 权限问题

```bash
# 检查 ServiceAccount
kubectl get sa nova-backend-sa -n nova-staging -o yaml

# 验证 Pod 使用正确的 ServiceAccount
kubectl get pod -l app=auth-service -n nova-auth -o jsonpath='{.items[0].spec.serviceAccountName}'

# 检查 AWS 环境变量
kubectl exec -it <pod-name> -n nova-auth -- env | grep AWS
```

## 安全最佳实践

1. **最小权限**: IAM Role 仅授予必要的 Secrets Manager 权限
2. **密钥轮换**: 定期轮换敏感密钥 (见 `docs/secrets-rotation-guide.md`)
3. **环境隔离**: Staging 和 Production 使用不同的 AWS Secrets
4. **审计日志**: 启用 CloudTrail 记录 Secrets 访问
5. **加密传输**: TLS 加密 AWS API 通信

## 相关文档

- [完整集成指南](../../../docs/aws-secrets-manager-integration.md)
- [密钥轮换指南](../../../docs/secrets-rotation-guide.md)
- [External Secrets Operator 官方文档](https://external-secrets.io/)
- [AWS Secrets Manager 文档](https://docs.aws.amazon.com/secretsmanager/)

## 常见问题

**Q: External Secrets 多久刷新一次?**
A: 默认每小时 (`refreshInterval: 1h`),可以手动触发强制刷新。

**Q: 如何在不同环境使用不同的密钥?**
A: 在 `k8s/overlays/{staging,production}/external-secret.yaml` 中配置不同的 AWS Secret 名称。

**Q: 密钥更新后需要重启 Pod 吗?**
A: 是的,环境变量在 Pod 启动时注入,需要重启才能生效。

**Q: 如何回滚到之前的密钥版本?**
A: AWS Secrets Manager 保留旧版本,可以通过 `VersionStage` 切换回 `AWSPREVIOUS`。

**Q: IRSA 如何工作?**
A: Pod 通过 ServiceAccount 获取临时 AWS 凭证,使用 OIDC 与 AWS STS 交互,无需在集群中存储长期凭证。

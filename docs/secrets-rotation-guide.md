# Secrets Rotation Guide

密钥轮换的完整指南,包括自动化和应急响应流程。

## 密钥轮换策略

### 轮换周期

| 密钥类型 | 轮换周期 | 自动化 | 影响范围 |
|---------|---------|--------|---------|
| Database Password | 90 天 | ✅ | 所有微服务 |
| Redis Password | 90 天 | ✅ | 缓存层 |
| JWT Keys | 180 天 | ⚠️ 手动 | 所有认证服务 |
| API Keys (外部) | 90 天 | ❌ | 相关服务 |
| SMTP Password | 90 天 | ⚠️ 半自动 | Messaging Service |
| OAuth Secrets | 180 天 | ❌ | Auth Service |

## 自动化密钥轮换

### 1. 数据库密码轮换

使用 AWS Secrets Manager 的内置轮换功能。

#### 设置自动轮换

```bash
# 创建 Lambda 轮换函数
aws lambda create-function \
  --function-name nova-db-password-rotation \
  --runtime python3.9 \
  --role arn:aws:iam::ACCOUNT_ID:role/SecretsManagerRotationRole \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://rotation-function.zip

# 启用自动轮换
aws secretsmanager rotate-secret \
  --secret-id nova-backend-staging \
  --rotation-lambda-arn arn:aws:lambda:us-west-2:ACCOUNT_ID:function:nova-db-password-rotation \
  --rotation-rules '{"AutomaticallyAfterDays": 90}'
```

#### 轮换流程

```python
# Lambda 轮换函数伪代码
def rotate_database_password(event):
    # Step 1: Create new password
    new_password = generate_secure_password()

    # Step 2: Set AWSPENDING version in Secrets Manager
    secrets_manager.put_secret_value(
        SecretId=secret_arn,
        SecretString=json.dumps({"password": new_password}),
        VersionStages=['AWSPENDING']
    )

    # Step 3: Test new password
    test_database_connection(new_password)

    # Step 4: Promote AWSPENDING to AWSCURRENT
    secrets_manager.update_secret_version_stage(
        SecretId=secret_arn,
        VersionStage='AWSCURRENT',
        MoveToVersionId=pending_version_id
    )

    # Step 5: Deprecate old version
    # Old version automatically becomes AWSPREVIOUS
```

### 2. JWT Keys 轮换

JWT 轮换需要支持密钥版本共存 (grace period)。

#### 轮换步骤

```bash
# 1. 生成新密钥对
openssl genrsa -out jwt_private_new.pem 4096
openssl rsa -in jwt_private_new.pem -pubout -out jwt_public_new.pem

# 2. 更新 AWS Secrets Manager (保留旧密钥)
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string '{
    "JWT_PRIVATE_KEY_PEM": "NEW_PRIVATE_KEY",
    "JWT_PUBLIC_KEY_PEM": "NEW_PUBLIC_KEY",
    "JWT_PRIVATE_KEY_PEM_OLD": "OLD_PRIVATE_KEY",
    "JWT_PUBLIC_KEY_PEM_OLD": "OLD_PUBLIC_KEY"
  }'

# 3. 更新应用代码支持双密钥验证
# Auth Service 现在可以用新密钥签名,同时验证新旧两个公钥

# 4. 等待 Grace Period (7 天)
sleep $((7 * 24 * 3600))

# 5. 移除旧密钥
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string '{
    "JWT_PRIVATE_KEY_PEM": "NEW_PRIVATE_KEY",
    "JWT_PUBLIC_KEY_PEM": "NEW_PUBLIC_KEY"
  }'
```

#### 应用代码支持

```rust
// backend/auth-service/src/jwt.rs
pub struct JwtValidator {
    current_public_key: DecodingKey,
    old_public_key: Option<DecodingKey>,
}

impl JwtValidator {
    pub fn validate_token(&self, token: &str) -> Result<Claims> {
        // 先尝试用当前密钥验证
        match jsonwebtoken::decode(token, &self.current_public_key, &validation) {
            Ok(data) => Ok(data.claims),
            Err(_) => {
                // 如果失败,尝试用旧密钥验证
                if let Some(old_key) = &self.old_public_key {
                    jsonwebtoken::decode(token, old_key, &validation)
                        .map(|data| data.claims)
                        .context("Token validation failed with both keys")
                } else {
                    Err(anyhow!("Token validation failed"))
                }
            }
        }
    }
}
```

### 3. Redis Password 轮换

Redis 支持双密码 (ACL),可以无缝轮换。

```bash
# 1. 添加新密码 (AUTH2)
redis-cli ACL SETUSER default >new_password

# 2. 更新 Secrets Manager
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string '{"REDIS_URL": "redis://:new_password@redis:6379"}'

# 3. 等待所有 Pod 重启 (External Secrets 刷新)
kubectl rollout restart deployment -n nova-staging

# 4. 移除旧密码
redis-cli ACL SETUSER default <old_password
```

## 手动密钥轮换

### OAuth Provider Secrets

```bash
# 1. 登录 OAuth Provider (Google/Facebook)
# 2. 生成新的 Client Secret
# 3. 更新 AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string '{
    "GOOGLE_CLIENT_SECRET": "NEW_SECRET",
    "FACEBOOK_APP_SECRET": "NEW_SECRET"
  }'

# 4. 验证 External Secrets 刷新
kubectl get externalsecret nova-backend-secrets -n nova-staging -o yaml

# 5. 重启受影响的服务
kubectl rollout restart deployment auth-service -n nova-auth
```

### APNS Certificate

```bash
# 1. 在 Apple Developer Portal 生成新证书
# 2. 下载 .p8 文件
# 3. 更新密钥
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string '{
    "APNS_KEY_ID": "NEW_KEY_ID",
    "APNS_PRIVATE_KEY": "NEW_PRIVATE_KEY"
  }'

# 4. 重启 Messaging Service
kubectl rollout restart deployment messaging-service -n nova-messaging
```

## 应急密钥轮换

### 场景: 密钥泄露

假设 Database Password 泄露,需要紧急轮换。

#### 1. 立即响应 (5 分钟内)

```bash
# 生成新密码
NEW_PASSWORD=$(openssl rand -base64 32)

# 更新数据库
psql -h $DB_HOST -U postgres <<EOF
ALTER USER nova WITH PASSWORD '$NEW_PASSWORD';
EOF

# 更新 Secrets Manager
aws secretsmanager update-secret \
  --secret-id nova-backend-staging \
  --secret-string "{\"DATABASE_URL\": \"postgresql://nova:$NEW_PASSWORD@postgres:5432/nova\"}"

# 强制 External Secrets 刷新
kubectl annotate externalsecret nova-backend-secrets \
  force-sync="$(date +%s)" \
  -n nova-staging \
  --overwrite

# 重启所有依赖数据库的服务
kubectl rollout restart deployment -n nova-staging
```

#### 2. 验证 (10 分钟内)

```bash
# 检查所有 Pod 状态
kubectl get pods -n nova-staging

# 检查日志中的数据库连接错误
kubectl logs -l app=auth-service -n nova-auth --tail=50 | grep -i "database"

# 运行健康检查
curl https://api-staging.nova.example.com/health
```

#### 3. 后续行动 (24 小时内)

```bash
# 审计访问日志
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=nova-backend-staging \
  --start-time $(date -d '7 days ago' +%s) \
  --end-time $(date +%s)

# 启用 AWS Config 规则监控
aws configservice put-config-rule \
  --config-rule file://secrets-access-monitoring-rule.json

# 更新所有其他可能受影响的密钥
```

### 场景: 批量密钥轮换

季度例行轮换。

```bash
#!/bin/bash
# scripts/aws/rotate-all-secrets.sh

set -euo pipefail

ENVIRONMENT=$1
SECRET_NAME="nova-backend-${ENVIRONMENT}"

echo "🔄 Starting batch secrets rotation for $ENVIRONMENT"

# 1. 生成所有新密钥
DB_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
JWT_PRIVATE_KEY=$(openssl genrsa 4096 2>/dev/null)
JWT_PUBLIC_KEY=$(echo "$JWT_PRIVATE_KEY" | openssl rsa -pubout 2>/dev/null)

# 2. 更新数据库密码
echo "Rotating database password..."
psql -h $DB_HOST -U postgres -c "ALTER USER nova WITH PASSWORD '$DB_PASSWORD';"

# 3. 更新 Redis 密码
echo "Rotating Redis password..."
redis-cli -h $REDIS_HOST ACL SETUSER default >$REDIS_PASSWORD

# 4. 构建新的 Secret JSON
NEW_SECRETS=$(jq -n \
  --arg db_pass "$DB_PASSWORD" \
  --arg redis_pass "$REDIS_PASSWORD" \
  --arg jwt_priv "$JWT_PRIVATE_KEY" \
  --arg jwt_pub "$JWT_PUBLIC_KEY" \
  '{
    DATABASE_URL: "postgresql://nova:\($db_pass)@postgres:5432/nova",
    REDIS_URL: "redis://:\($redis_pass)@redis:6379",
    JWT_PRIVATE_KEY_PEM: $jwt_priv,
    JWT_PUBLIC_KEY_PEM: $jwt_pub
  }')

# 5. 更新 AWS Secrets Manager
echo "Updating AWS Secrets Manager..."
aws secretsmanager update-secret \
  --secret-id "$SECRET_NAME" \
  --secret-string "$NEW_SECRETS" \
  --region us-west-2

# 6. 触发 Kubernetes Secret 刷新
echo "Refreshing Kubernetes secrets..."
kubectl annotate externalsecret nova-backend-secrets \
  force-sync="$(date +%s)" \
  -n nova-${ENVIRONMENT} \
  --overwrite

# 7. 滚动重启所有服务
echo "Rolling restart all services..."
kubectl rollout restart deployment -n nova-${ENVIRONMENT}

# 8. 等待所有 Pod 就绪
kubectl wait --for=condition=ready pod \
  --all \
  -n nova-${ENVIRONMENT} \
  --timeout=300s

echo "✅ Batch rotation completed successfully!"
```

## 监控和告警

### CloudWatch Alarms

```bash
# 创建 Secrets Manager 访问告警
aws cloudwatch put-metric-alarm \
  --alarm-name secrets-access-spike \
  --alarm-description "Unusual access to secrets" \
  --metric-name SecretAccessCount \
  --namespace AWS/SecretsManager \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-west-2:ACCOUNT_ID:ops-alerts
```

### External Secrets Operator Metrics

```yaml
# k8s/monitoring/externalsecrets-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: external-secrets
  namespace: external-secrets-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: external-secrets
  endpoints:
  - port: metrics
    interval: 30s
```

### Grafana Dashboard

导入预定义的 Dashboard ID: `14837` (External Secrets Operator)

## 密钥轮换检查清单

### 计划轮换 (每季度)

- [ ] 审查所有密钥的最后更新时间
- [ ] 生成新密钥/密码
- [ ] 在非高峰时段执行轮换
- [ ] 更新 AWS Secrets Manager
- [ ] 验证 External Secrets 同步
- [ ] 滚动重启受影响服务
- [ ] 监控应用健康状态 24 小时
- [ ] 更新密钥轮换日志
- [ ] 归档旧密钥 (加密存储,保留 90 天)

### 应急轮换 (密钥泄露)

- [ ] 立即撤销泄露的密钥
- [ ] 生成新密钥
- [ ] 紧急更新所有系统
- [ ] 审计访问日志
- [ ] 通知安全团队
- [ ] 撰写事故报告
- [ ] 实施额外安全措施

## 参考资料

- [AWS Secrets Manager Rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
- [External Secrets Operator Best Practices](https://external-secrets.io/latest/guides/best-practices/)
- [NIST Password Guidelines](https://pages.nist.gov/800-63-3/)

#!/bin/bash
# scripts/aws/setup-aws-secrets.sh
# 初始化 AWS Secrets Manager 密钥
# Usage: ./scripts/aws/setup-aws-secrets.sh staging|production

set -euo pipefail

ENVIRONMENT=$1
if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 staging|production"
    exit 1
fi

# 配置
AWS_REGION="${AWS_REGION:-us-west-2}"
SECRET_NAME="nova-backend-${ENVIRONMENT}"

echo "🔐 Creating AWS Secrets Manager secret: $SECRET_NAME"
echo "   Region: $AWS_REGION"
echo ""

# 创建密钥的 JSON 结构
# 这些是占位符值,需要在创建后通过 AWS Console 或 CLI 更新为真实值
SECRET_JSON=$(cat <<'EOF'
{
  "DATABASE_URL": "postgresql://nova:CHANGE_ME@postgres.nova-staging.svc.cluster.local:5432/nova",
  "REDIS_URL": "redis://:CHANGE_ME@redis.nova-staging.svc.cluster.local:6379",
  "JWT_PRIVATE_KEY_PEM": "-----BEGIN PRIVATE KEY-----\nCHANGE_ME\n-----END PRIVATE KEY-----",
  "JWT_PUBLIC_KEY_PEM": "-----BEGIN PUBLIC KEY-----\nCHANGE_ME\n-----END PUBLIC KEY-----",
  "AWS_ACCESS_KEY_ID": "CHANGE_ME",
  "AWS_SECRET_ACCESS_KEY": "CHANGE_ME",
  "AWS_REGION": "us-west-2",
  "S3_BUCKET_NAME": "nova-media-staging",
  "SMTP_HOST": "email-smtp.us-west-2.amazonaws.com",
  "SMTP_PORT": "587",
  "SMTP_USERNAME": "CHANGE_ME",
  "SMTP_PASSWORD": "CHANGE_ME",
  "SMTP_FROM_EMAIL": "noreply@nova.example.com",
  "GOOGLE_CLIENT_ID": "CHANGE_ME",
  "GOOGLE_CLIENT_SECRET": "CHANGE_ME",
  "FACEBOOK_APP_ID": "CHANGE_ME",
  "FACEBOOK_APP_SECRET": "CHANGE_ME",
  "APNS_KEY_ID": "CHANGE_ME",
  "APNS_TEAM_ID": "CHANGE_ME",
  "APNS_PRIVATE_KEY": "CHANGE_ME",
  "APNS_BUNDLE_ID": "com.nova.app",
  "FCM_SERVICE_ACCOUNT_JSON": "{}",
  "KAFKA_BROKERS": "kafka.nova-staging.svc.cluster.local:9092",
  "MILVUS_HOST": "milvus.nova-staging.svc.cluster.local",
  "MILVUS_PORT": "19530",
  "NEO4J_URI": "bolt://neo4j.nova-staging.svc.cluster.local:7687",
  "NEO4J_USERNAME": "neo4j",
  "NEO4J_PASSWORD": "CHANGE_ME"
}
EOF
)

# 检查密钥是否已存在
if aws secretsmanager describe-secret \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    &> /dev/null; then

    echo "⚠️  Secret $SECRET_NAME already exists."
    read -p "Do you want to update it? (yes/no): " -r
    echo

    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --description "Nova Backend secrets for ${ENVIRONMENT}" \
            --secret-string "$SECRET_JSON" \
            --region "$AWS_REGION"

        echo "✅ Secret updated: $SECRET_NAME"
    else
        echo "❌ Aborted. No changes made."
        exit 0
    fi
else
    # 创建新密钥
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Nova Backend secrets for ${ENVIRONMENT}" \
        --secret-string "$SECRET_JSON" \
        --region "$AWS_REGION" \
        --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=Nova

    echo "✅ Secret created: $SECRET_NAME"
fi

echo ""
echo "📝 Next steps:"
echo "1. Update secret values using AWS Console or CLI:"
echo "   aws secretsmanager update-secret --secret-id $SECRET_NAME --secret-string file://secrets.json --region $AWS_REGION"
echo ""
echo "2. Create IAM role for IRSA (see terraform/iam-secrets-role.tf)"
echo ""
echo "3. Install External Secrets Operator:"
echo "   helm repo add external-secrets https://charts.external-secrets.io"
echo "   helm install external-secrets external-secrets/external-secrets -n external-secrets-system --create-namespace"
echo ""
echo "4. Apply SecretStore and ExternalSecret manifests:"
echo "   kubectl apply -f k8s/base/external-secrets/"
echo ""

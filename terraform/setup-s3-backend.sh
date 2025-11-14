#!/bin/bash
# Setup Terraform S3 Backend for Nova
#
# 这个脚本会创建必要的 S3 bucket 和 DynamoDB table 来存储 Terraform state
# Usage: ./setup-s3-backend.sh

set -e

REGION="ap-northeast-1"
BUCKET_NAME="nova-terraform-state"
TABLE_NAME="nova-terraform-locks"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "🚀 Setting up Terraform S3 Backend..."
echo "   Region: $REGION"
echo "   Account: $AWS_ACCOUNT_ID"
echo "   Bucket: $BUCKET_NAME"
echo "   Lock Table: $TABLE_NAME"
echo ""

# 检查 S3 bucket 是否存在
echo "✓ Checking S3 bucket..."
if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
    echo "  ✓ Bucket already exists: $BUCKET_NAME"
else
    echo "  → Creating S3 bucket: $BUCKET_NAME"
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"

    # 启用版本控制
    echo "  → Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled

    # 启用服务器端加密
    echo "  → Enabling encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'

    echo "  ✓ S3 bucket created and configured"
fi

# 检查 DynamoDB table 是否存在
echo ""
echo "✓ Checking DynamoDB lock table..."
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null; then
    echo "  ✓ Table already exists: $TABLE_NAME"
else
    echo "  → Creating DynamoDB table: $TABLE_NAME"
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION"

    echo "  ✓ DynamoDB table created"
fi

echo ""
echo "✅ Backend setup complete!"
echo ""
echo "下一步:"
echo "  1. cd terraform"
echo "  2. terraform init -backend-config=backend.hcl"
echo "  3. terraform plan -var-file=staging.tfvars"

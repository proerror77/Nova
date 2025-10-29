# S3 配置指南

本文档说明如何为 Nova 的文件上传功能配置 AWS S3 或 S3 兼容的存储服务。

## 快速开始

### 1. AWS S3 配置

#### 方案 A：使用 IAM 用户凭证

```bash
# 设置环境变量
export AWS_REGION=us-east-1
export S3_BUCKET=nova-uploads
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key

# 启动 media-service
cargo run --release
```

#### 方案 B：使用 IAM 角色（推荐用于 EC2/EKS）

```bash
# 设置环境变量
export AWS_REGION=us-east-1
export S3_BUCKET=nova-uploads

# 启动 media-service（自动使用 EC2 IAM 角色）
cargo run --release
```

### 2. MinIO（本地开发）

MinIO 是一个兼容 AWS S3 API 的开源存储服务。

```bash
# 使用 Docker 启动 MinIO
docker run -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio server /data --console-address ":9001"

# 设置环境变量
export AWS_REGION=us-east-1
export S3_BUCKET=nova-uploads
export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export S3_ENDPOINT=http://localhost:9000

# 启动 media-service
cargo run --release
```

### 3. LocalStack（本地 AWS 开发）

```bash
# 使用 Docker Compose
cat > docker-compose-localstack.yml <<'EOF'
version: '3'
services:
  localstack:
    image: localstack/localstack
    ports:
      - "4566:4566"
    environment:
      - SERVICES=s3
      - DEBUG=1
      - DATA_DIR=/tmp/localstack/data
    volumes:
      - ${TMPDIR}:/tmp/localstack
EOF

docker-compose -f docker-compose-localstack.yml up

# 创建 S3 bucket
aws --endpoint-url=http://localhost:4566 s3 mb s3://nova-uploads

# 设置环境变量
export AWS_REGION=us-east-1
export S3_BUCKET=nova-uploads
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export S3_ENDPOINT=http://localhost:4566

# 启动 media-service
cargo run --release
```

## 详细配置说明

### 环境变量

| 环境变量 | 必需 | 说明 | 示例 |
|---------|------|------|------|
| `AWS_REGION` | ✅ | AWS 区域 | `us-east-1` |
| `S3_BUCKET` | ✅ | S3 bucket 名称 | `nova-uploads` |
| `AWS_ACCESS_KEY_ID` | ⚠️ | AWS 访问密钥 ID | 从 IAM 控制台获取 |
| `AWS_SECRET_ACCESS_KEY` | ⚠️ | AWS 密钥 | 从 IAM 控制台获取 |
| `S3_ENDPOINT` | ❌ | 自定义 S3 端点 | `http://localhost:9000` |

**注：** ⚠️ = 仅在不使用 IAM 角色时需要

### .env 文件示例

创建 `.env` 文件在项目根目录：

```bash
# AWS Configuration
AWS_REGION=us-east-1
S3_BUCKET=nova-uploads

# 开发环境（使用 MinIO）
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
S3_ENDPOINT=http://localhost:9000

# 生产环境（使用 AWS S3，需要 IAM 角色）
# AWS_ACCESS_KEY_ID=...
# AWS_SECRET_ACCESS_KEY=...
# S3_ENDPOINT=（不设置，使用 AWS 默认）
```

## AWS S3 设置步骤

### 步骤 1：创建 S3 Bucket

```bash
# 使用 AWS CLI
aws s3 mb s3://nova-uploads --region us-east-1

# 或在 AWS 控制台
# 1. 进入 S3 服务
# 2. 点击 "Create Bucket"
# 3. 填入 bucket 名称：nova-uploads
# 4. 选择区域：us-east-1
# 5. 点击 "Create"
```

### 步骤 2：配置 Bucket 策略

```bash
# 创建允许 presigned URL 上传的策略
cat > bucket-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPresignedUpload",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::nova-uploads/uploads/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "private"
        }
      }
    },
    {
      "Sid": "AllowPublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::nova-uploads/public/*"
    }
  ]
}
EOF

# 应用策略
aws s3api put-bucket-policy \
  --bucket nova-uploads \
  --policy file://bucket-policy.json
```

### 步骤 3：配置 CORS

```bash
cat > cors-config.json <<'EOF'
{
  "CORSRules": [
    {
      "AllowedOrigins": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }
  ]
}
EOF

# 应用 CORS 配置
aws s3api put-bucket-cors \
  --bucket nova-uploads \
  --cors-configuration file://cors-config.json
```

### 步骤 4：创建 IAM 用户（可选）

如果不使用 IAM 角色，创建 IAM 用户获取访问密钥：

```bash
# 创建用户
aws iam create-user --user-name nova-s3-user

# 创建访问密钥
aws iam create-access-key --user-name nova-s3-user

# 创建策略
cat > s3-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::nova-uploads",
        "arn:aws:s3:::nova-uploads/*"
      ]
    }
  ]
}
EOF

# 应用策略
aws iam put-user-policy \
  --user-name nova-s3-user \
  --policy-name nova-s3-policy \
  --policy-document file://s3-policy.json
```

### 步骤 5：配置 EC2 IAM 角色（推荐）

```bash
# 创建信任关系文档
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建角色
aws iam create-role \
  --role-name nova-ec2-s3-role \
  --assume-role-policy-document file://trust-policy.json

# 创建权限策略
cat > ec2-s3-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::nova-uploads",
        "arn:aws:s3:::nova-uploads/*"
      ]
    }
  ]
}
EOF

# 应用权限策略
aws iam put-role-policy \
  --role-name nova-ec2-s3-role \
  --policy-name nova-ec2-s3-policy \
  --policy-document file://ec2-s3-policy.json

# 创建实例配置文件
aws iam create-instance-profile \
  --instance-profile-name nova-ec2-s3-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name nova-ec2-s3-profile \
  --role-name nova-ec2-s3-role

# 启动 EC2 实例时使用该配置文件
# 或将其附加到现有实例
aws ec2 associate-iam-instance-profile \
  --iam-instance-profile Name=nova-ec2-s3-profile \
  --instance-id i-1234567890abcdef0
```

## Kubernetes 部署配置

### 使用 Secrets 存储凭证

```bash
# 创建 Kubernetes Secret
kubectl create secret generic nova-s3-credentials \
  --from-literal=aws-region=us-east-1 \
  --from-literal=s3-bucket=nova-uploads \
  --from-literal=aws-access-key-id=your-access-key \
  --from-literal=aws-secret-access-key=your-secret-key \
  -n nova

# 或使用 YAML
cat > s3-secret.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: nova-s3-credentials
  namespace: nova
type: Opaque
stringData:
  aws-region: us-east-1
  s3-bucket: nova-uploads
  aws-access-key-id: your-access-key
  aws-secret-access-key: your-secret-key
EOF

kubectl apply -f s3-secret.yaml
```

### 在 Pod 中使用 Secrets

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: media-service
  namespace: nova
spec:
  template:
    spec:
      containers:
      - name: media-service
        image: nova/media-service:latest
        env:
        - name: AWS_REGION
          valueFrom:
            secretKeyRef:
              name: nova-s3-credentials
              key: aws-region
        - name: S3_BUCKET
          valueFrom:
            secretKeyRef:
              name: nova-s3-credentials
              key: s3-bucket
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: nova-s3-credentials
              key: aws-access-key-id
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: nova-s3-credentials
              key: aws-secret-access-key
```

### 使用 IRSA（IAM Roles for Service Accounts）

```bash
# 为 media-service 创建 Kubernetes Service Account
kubectl create serviceaccount media-service -n nova

# 关联 IAM 角色（需要提前配置 IRSA）
# 详见：https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html

# Pod 定义
cat > media-service-deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: media-service
  namespace: nova
spec:
  template:
    spec:
      serviceAccountName: media-service
      containers:
      - name: media-service
        image: nova/media-service:latest
        env:
        - name: AWS_REGION
          value: us-east-1
        - name: S3_BUCKET
          value: nova-uploads
EOF
```

## 测试 S3 连接

### 使用 AWS CLI

```bash
# 列出 bucket 中的对象
aws s3 ls s3://nova-uploads --recursive

# 上传文件测试
echo "test content" > test.txt
aws s3 cp test.txt s3://nova-uploads/test/test.txt

# 下载文件测试
aws s3 cp s3://nova-uploads/test/test.txt downloaded.txt

# 删除测试文件
aws s3 rm s3://nova-uploads/test/test.txt
```

### 使用 Nova API

```bash
# 1. 启动上传会话
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8082/api/v1/uploads \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "file_name": "test.jpg",
    "file_size": 1024
  }')

UPLOAD_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

# 2. 获取 Presign URL
curl -X POST http://localhost:8082/api/v1/uploads/$UPLOAD_ID/presigned-url \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "file_name": "test.jpg",
    "content_type": "image/jpeg"
  }' | jq .

# 3. 使用 Presign URL 上传文件（仅限 AWS S3）
# PRESIGN_URL=$(...)
# curl -X PUT "$PRESIGN_URL" --data-binary @test.jpg

# 4. 完成上传
curl -X POST http://localhost:8082/api/v1/uploads/$UPLOAD_ID/complete \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## 故障排除

### 错误：InvalidAccessKeyId

**症状：**
```
Error: The Access Key Id you provided does not exist in our records.
```

**解决方案：**
- 检查 `AWS_ACCESS_KEY_ID` 是否正确
- 确保访问密钥未被删除或禁用
- 重新生成访问密钥

### 错误：SignatureDoesNotMatch

**症状：**
```
Error: The request signature we calculated does not match the signature you provided.
```

**解决方案：**
- 检查 `AWS_SECRET_ACCESS_KEY` 是否正确
- 检查 `AWS_REGION` 是否与 bucket 所在区域一致
- 确保系统时间正确同步

### 错误：NoSuchBucket

**症状：**
```
Error: The specified bucket does not exist
```

**解决方案：**
- 检查 `S3_BUCKET` 名称是否正确
- 确保 bucket 存在
- 检查凭证是否有权访问该 bucket

### 无法生成 Presign URL

**症状：** API 返回 400 或 500 错误

**解决方案：**
```bash
# 检查 media-service 日志
docker logs <media-service-container>

# 验证 S3 连接
aws s3 ls --region us-east-1

# 检查 bucket 权限
aws s3api head-bucket --bucket nova-uploads
```

## 性能优化

### 1. 多部分上传

对于大文件，使用多部分上传提高可靠性：

```bash
# 配置 presign URL 用于多部分上传
# 这需要在 media-service 中实现
```

### 2. S3 传输加速

启用 S3 传输加速（需要 AWS 配置）：

```bash
aws s3api put-bucket-accelerate-configuration \
  --bucket nova-uploads \
  --accelerate-configuration Status=Enabled

# 使用加速端点
# https://nova-uploads.s3-accelerate.amazonaws.com/...
```

### 3. CloudFront CDN

使用 CloudFront 加速文件分发：

```bash
# 创建 CloudFront 分布（在 AWS 控制台）
# - Origin: nova-uploads.s3.us-east-1.amazonaws.com
# - Cache behaviors: 缓存 GET/HEAD 请求
# - TTL: 86400 秒（1 天）
```

## 安全最佳实践

- ✅ **使用 IAM 角色** 而不是硬编码凭证
- ✅ **启用 S3 块公开访问** 防止意外暴露
- ✅ **使用 presign URL** 而不是授予全局访问权限
- ✅ **启用 S3 加密** (SSE-S3 或 SSE-KMS)
- ✅ **启用版本控制** 防止意外删除
- ✅ **配置 bucket 日志** 审计访问
- ✅ **使用 VPC 端点** 避免互联网流量

## 参考资源

- [AWS S3 文档](https://docs.aws.amazon.com/s3/)
- [AWS SDK for Rust](https://github.com/awslabs/aws-sdk-rust)
- [MinIO 文档](https://min.io/docs/minio/linux/index.html)
- [LocalStack 文档](https://docs.localstack.cloud/)

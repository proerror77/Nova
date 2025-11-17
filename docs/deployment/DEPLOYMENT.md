# Nova AWS Deployment Guide

## 概述

這是 Nova 項目的完整 CI/CD 部署指南，涵蓋從本地開發到生產環境的所有步驟。

## 架構圖

```
GitHub Actions → Docker Build → AWS ECR → ECS Fargate → RDS + ElastiCache
```

## 前置需求

1. **AWS 賬號**
   - AWS 賬號 ID
   - IAM 用戶（具有 AdministratorAccess 權限）

2. **本地工具**
   - Terraform >= 1.5.0
   - AWS CLI >= 2.0
   - Docker >= 24.0

3. **域名（可選）**
   - ACM SSL 證書（用於 HTTPS）

## 第一步：創建 S3 Bucket 用於 Terraform State

```bash
# 創建 S3 bucket
aws s3api create-bucket \
  --bucket nova-terraform-state \
  --region us-east-1

# 啟用版本控制
aws s3api put-bucket-versioning \
  --bucket nova-terraform-state \
  --versioning-configuration Status=Enabled

# 啟用加密
aws s3api put-bucket-encryption \
  --bucket nova-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# 創建 DynamoDB 表用於 Terraform 鎖
aws dynamodb create-table \
  --table-name nova-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## 第二步：配置 GitHub Secrets

在 GitHub 倉庫設置中添加以下 secrets：

```
Settings → Secrets and variables → Actions → New repository secret
```

**必需的 Secrets：**

| Secret Name | Description | Example |
|------------|-------------|---------|
| `AWS_ACCOUNT_ID` | AWS 賬號 ID | `123456789012` |
| `AWS_ACCESS_KEY_ID` | IAM 用戶 Access Key | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | IAM 用戶 Secret Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | AWS 區域 | `us-east-1` |
| `SLACK_WEBHOOK_URL` (可選) | Slack Webhook URL | `https://hooks.slack.com/services/...` |

## 第三步：部署 Staging 環境

### 3.1 初始化 Terraform

```bash
cd terraform

# 初始化 Terraform
terraform init

# 驗證配置
terraform validate

# 查看執行計劃
terraform plan -var-file="staging.tfvars"
```

### 3.2 部署基礎設施

```bash
# 部署 Staging 環境
terraform apply -var-file="staging.tfvars"

# 確認輸出
terraform output
```

**預期輸出：**
```
ecr_repository_urls = {
  "auth-service" = "123456789012.dkr.ecr.us-east-1.amazonaws.com/nova-auth-service"
  ...
}
alb_dns_name = "nova-staging-alb-123456789.us-east-1.elb.amazonaws.com"
rds_endpoint = "nova-staging.xxxxxx.us-east-1.rds.amazonaws.com:5432"
```

### 3.3 手動推送第一個 Docker 鏡像

在 GitHub Actions 自動部署之前，需要手動推送初始鏡像：

```bash
# 登錄到 ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

# 構建並推送所有現役服務
for service in identity-service content-service feed-service \
               media-service messaging-service search-service realtime-chat-service \
               notification-service analytics-service graph-service feature-store \
               trust-safety-service; do
  docker build \
    --build-arg SERVICE_NAME=$service \
    -f backend/Dockerfile.template \
    -t ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/nova-$service:latest \
    .

  docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/nova-$service:latest
done
```

### 3.4 觸發初始部署

```bash
# 更新 ECS 服務（強制新部署）
for service in identity-service content-service feed-service \
               media-service messaging-service search-service realtime-chat-service \
               notification-service analytics-service graph-service feature-store \
               trust-safety-service; do
  aws ecs update-service \
    --cluster nova-staging \
    --service nova-$service \
    --force-new-deployment \
    --region us-east-1
done
```

## 第四步：驗證部署

### 4.1 檢查 ECS 服務狀態

```bash
# 查看所有服務狀態
aws ecs list-services --cluster nova-staging --region us-east-1

# 查看特定服務詳情
aws ecs describe-services \
  --cluster nova-staging \
  --services nova-auth-service \
  --region us-east-1
```

### 4.2 測試 HTTP 端點

```bash
# 獲取 ALB DNS 名稱
ALB_DNS=$(terraform output -raw alb_dns_name)

# 測試健康檢查端點
curl http://$ALB_DNS/auth-service/health
curl http://$ALB_DNS/user-service/health
```

### 4.3 查看應用日誌

```bash
# 查看 CloudWatch 日誌
aws logs tail /ecs/nova-staging/auth-service --follow --region us-east-1
```

## 第五步：CI/CD 自動部署

一旦手動部署成功，後續部署將通過 GitHub Actions 自動執行。

### 自動部署觸發條件

**Staging 環境（自動部署）：**
```bash
# 推送到 feature/phase1-grpc-migration 分支
git push origin feature/phase1-grpc-migration
```

**Production 環境（需要手動批准）：**
```bash
# 推送到 main 分支
git push origin main

# GitHub Actions 會暫停，等待手動批准
# 訪問 GitHub → Actions → 選擇工作流 → Review deployments → Approve
```

### 部署流程監控

訪問 GitHub Actions 查看部署進度：
```
https://github.com/<your-org>/nova/actions
```

## 第六步：部署 Production 環境

### 6.1 創建 ACM 證書（用於 HTTPS）

```bash
# 請求證書
aws acm request-certificate \
  --domain-name "api.nova.com" \
  --validation-method DNS \
  --region us-east-1

# 獲取證書 ARN
aws acm list-certificates --region us-east-1
```

### 6.2 更新 Terraform 配置

編輯 `terraform/networking.tf`，取消註釋 HTTPS listener 的證書配置：

```hcl
resource "aws_lb_listener" "https" {
  ...
  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxx"
}
```

### 6.3 部署 Production 環境

```bash
# 部署 Production 環境
terraform apply -var-file="production.tfvars"

# 手動推送初始鏡像（同 Staging 步驟）
# ...
```

## 故障排查

### 問題 1: ECS 任務無法啟動

**症狀：** ECS 服務顯示 `RUNNING` 但沒有健康的任務

**解決方案：**
```bash
# 查看任務失敗原因
aws ecs describe-tasks \
  --cluster nova-staging \
  --tasks $(aws ecs list-tasks --cluster nova-staging --service nova-auth-service --query 'taskArns[0]' --output text) \
  --region us-east-1
```

常見原因：
- ECR 鏡像不存在或拉取失敗
- 環境變量配置錯誤
- 內存/CPU 限制不足

### 問題 2: 健康檢查失敗

**症狀：** ALB 報告目標不健康

**解決方案：**
```bash
# 查看 ALB 目標健康狀態
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -json | jq -r '.alb_target_groups.value["auth-service"]') \
  --region us-east-1
```

檢查項目：
- 應用是否在 8080 端口監聽
- `/health` 端點是否返回 200
- 安全組是否允許流量

### 問題 3: 數據庫連接失敗

**症狀：** 應用日誌顯示數據庫連接錯誤

**解決方案：**
```bash
# 檢查 RDS 端點
terraform output rds_endpoint

# 從 ECS 任務內測試連接
aws ecs execute-command \
  --cluster nova-staging \
  --task <task-id> \
  --container nova-auth-service \
  --command "psql -h <rds-endpoint> -U nova_admin -d nova_staging" \
  --interactive
```

## 成本估算

**Staging 環境（每月）：**
- ECS Fargate: ~$150 (11 服務 × 2 任務)
- RDS t4g.medium: ~$60
- ElastiCache t4g.micro: ~$15
- ALB: ~$25
- NAT Gateway: ~$45
- **總計: ~$295/月**

**Production 環境（每月）：**
- ECS Fargate: ~$450 (11 服務 × 3 任務)
- RDS r6g.xlarge Multi-AZ: ~$600
- ElastiCache r6g.large × 3: ~$300
- ALB: ~$25
- NAT Gateway × 2: ~$90
- **總計: ~$1,465/月**

## 清理資源

**警告：這將刪除所有資源和數據！**

```bash
# 刪除 Staging 環境
terraform destroy -var-file="staging.tfvars"

# 刪除 Production 環境
terraform destroy -var-file="production.tfvars"

# 刪除 S3 bucket 和 DynamoDB 表
aws s3 rb s3://nova-terraform-state --force
aws dynamodb delete-table --table-name nova-terraform-lock --region us-east-1
```

## 下一步

1. **配置自定義域名：** 將 ALB DNS 映射到自定義域名
2. **設置 CloudWatch Dashboard：** 監控所有服務的健康狀況
3. **配置告警：** 為關鍵指標設置 SNS 告警
4. **實施備份策略：** 定期備份 RDS 和 S3 數據
5. **優化成本：** 使用 Fargate Spot 和 Savings Plans

## 參考資料

- [AWS ECS Fargate 文檔](https://docs.aws.amazon.com/ecs/latest/developerguide/AWS_Fargate.html)
- [Terraform AWS Provider 文檔](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions 文檔](https://docs.github.com/en/actions)

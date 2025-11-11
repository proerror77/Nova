# Nova Deployment Quickstart

## 5 分鐘快速部署指南

這是最小化步驟的部署指南，適合快速啟動 Staging 環境。

## 前置條件

- AWS 賬號
- AWS CLI 已配置
- Terraform 已安裝

## 第一步：初始化 AWS 資源

```bash
# 創建 Terraform state bucket
aws s3api create-bucket \
  --bucket nova-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket nova-terraform-state \
  --versioning-configuration Status=Enabled

# 創建 DynamoDB lock table
aws dynamodb create-table \
  --table-name nova-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## 第二步：配置 GitHub Secrets

在 GitHub 倉庫設置中添加：

```
AWS_ACCOUNT_ID
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION=us-east-1
```

## 第三步：部署基礎設施

```bash
cd terraform

# 初始化並部署
terraform init
terraform apply -var-file="staging.tfvars" -auto-approve
```

**預計時間：15-20 分鐘**

## 第四步：推送初始鏡像

```bash
# 獲取 AWS 賬號 ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 登錄 ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com

# 構建並推送所有服務（使用並行處理）
cd ..
cat > /tmp/build-services.sh <<'EOF'
#!/bin/bash
SERVICE=$1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Building $SERVICE..."
docker build \
  --build-arg SERVICE_NAME=$SERVICE \
  -f backend/Dockerfile.template \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/nova-$SERVICE:latest \
  .

echo "Pushing $SERVICE..."
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/nova-$SERVICE:latest

echo "✅ $SERVICE done"
EOF

chmod +x /tmp/build-services.sh

# 並行構建所有服務（使用 GNU Parallel）
echo "auth-service user-service content-service feed-service \
      media-service messaging-service search-service streaming-service \
      notification-service cdn-service events-service" | \
  xargs -n1 -P4 /tmp/build-services.sh
```

**預計時間：30-40 分鐘（並行構建）**

## 第五步：觸發部署

```bash
# 更新所有 ECS 服務
for service in auth-service user-service content-service feed-service \
               media-service messaging-service search-service streaming-service \
               notification-service cdn-service events-service; do
  echo "Deploying $service..."
  aws ecs update-service \
    --cluster nova-staging \
    --service nova-$service \
    --force-new-deployment \
    --region us-east-1 &
done

wait
echo "✅ All services deployed"
```

**預計時間：5-10 分鐘**

## 驗證部署

```bash
# 獲取 ALB DNS 名稱
ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name)

# 測試健康檢查
for service in auth-service user-service content-service; do
  echo "Testing $service..."
  curl -s http://$ALB_DNS/$service/health | jq
done
```

**預期輸出：**
```json
{"status":"healthy","service":"auth-service"}
{"status":"healthy","service":"user-service"}
{"status":"healthy","service":"content-service"}
```

## 啟用 CI/CD 自動部署

一旦手動部署成功，後續只需：

```bash
# 推送代碼到 feature/phase1-grpc-migration 分支
git push origin feature/phase1-grpc-migration
```

GitHub Actions 會自動執行：
1. 運行測試（3 分鐘）
2. 構建 Docker 鏡像（15 分鐘）
3. 推送到 ECR（5 分鐘）
4. 更新 ECS 服務（5 分鐘）

**總部署時間：~30 分鐘**

## 監控部署

查看 GitHub Actions 進度：
```
https://github.com/<your-org>/nova/actions
```

查看 ECS 服務狀態：
```bash
aws ecs list-services --cluster nova-staging --region us-east-1
```

查看應用日誌：
```bash
aws logs tail /ecs/nova-staging/auth-service --follow --region us-east-1
```

## 故障排查一行命令

```bash
# 檢查所有服務健康狀況
for service in auth-service user-service content-service feed-service \
               media-service messaging-service search-service streaming-service \
               notification-service cdn-service events-service; do
  echo -n "$service: "
  aws ecs describe-services \
    --cluster nova-staging \
    --services nova-$service \
    --query 'services[0].runningCount' \
    --region us-east-1
done
```

**預期輸出：每個服務應顯示 `2`（2 個運行中的任務）**

## 成本估算

**Staging 環境：~$10/天**

## 清理資源

```bash
cd terraform
terraform destroy -var-file="staging.tfvars" -auto-approve
```

## 下一步

閱讀完整文檔：[DEPLOYMENT.md](./DEPLOYMENT.md)

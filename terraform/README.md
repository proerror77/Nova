# Nova Terraform Infrastructure

## 概述

這個 Terraform 配置為 Nova 項目部署完整的 AWS 基礎設施，包括：

- **11 個 ECR 倉庫**（每個微服務一個）
- **ECS Fargate 集群**（高可用、自動擴展）
- **VPC + ALB**（跨 2 個可用區）
- **RDS PostgreSQL**（Multi-AZ 可選）
- **ElastiCache Redis**（集群模式）
- **IAM 角色 + Security Groups**

## 文件結構

```
terraform/
├── main.tf              # Provider 配置
├── variables.tf         # 變量定義
├── outputs.tf           # 輸出值
├── ecr.tf              # ECR 倉庫
├── ecs.tf              # ECS 集群和服務
├── networking.tf       # VPC + ALB
├── database.tf         # RDS + ElastiCache
├── security.tf         # IAM + Security Groups
├── staging.tfvars      # Staging 環境變量
└── production.tfvars   # Production 環境變量
```

## 快速開始

### 1. 設定遠端 Backend

```bash
./setup-s3-backend.sh   # 僅首次執行
terraform init -backend-config=backend.hcl
```

### 2. 驗證配置

```bash
terraform validate
terraform plan -var-file="staging.tfvars"
```

#### 如果之前使用 local backend

```bash
terraform init -migrate-state -backend-config=backend.hcl
```

會將 `terraform.tfstate` 從本機搬移到 S3 並在 DynamoDB 加上鎖。

### 3. 部署 Staging 環境

```bash
terraform apply -var-file="staging.tfvars"
```

### 4. 部署 Production 環境

```bash
terraform apply -var-file="production.tfvars"
```

> 💡 注意：Terraform 狀態檔 (`terraform.tfstate*`) 與計畫檔 (`*.tfplan`) 已透過 `.gitignore` 排除，請勿再加入版本控制。若需本機測試，可使用 `terraform workspace` 或替換 `backend.hcl` 的 `key` 值，但仍應存放於 S3/DynamoDB。

## 環境配置

### Staging 環境

- **ECS Task:** 512 CPU / 1024 MB 內存
- **RDS:** db.t4g.medium（單實例）
- **ElastiCache:** cache.t4g.micro × 1
- **成本:** ~$295/月

### Production 環境

- **ECS Task:** 1024 CPU / 2048 MB 內存
- **RDS:** db.r6g.xlarge（Multi-AZ）
- **ElastiCache:** cache.r6g.large × 3
- **成本:** ~$1,465/月

## 關鍵資源

### ECR 倉庫

每個微服務都有獨立的 ECR 倉庫：

```hcl
aws_ecr_repository.services["auth-service"]
aws_ecr_repository.services["user-service"]
...
```

**生命週期策略：** 保留最近 10 個鏡像（Staging）/ 20 個鏡像（Production）

### ECS 服務

每個微服務都部署為獨立的 ECS 服務：

```hcl
aws_ecs_service.services["auth-service"]
  - Desired Count: 2（Staging）/ 3（Production）
  - Launch Type: Fargate
  - Network: Private Subnets
  - Load Balancer: ALB
```

**健康檢查：**
- Path: `/health`
- Interval: 30 秒
- Timeout: 5 秒
- Healthy Threshold: 2

**部署策略：**
- Rolling Update
- Circuit Breaker（自動回滾）

### ALB 路由規則

基於路徑的路由：

```
/auth-service/*    → auth-service target group
/user-service/*    → user-service target group
/content-service/* → content-service target group
...
```

### 服務發現

使用 AWS Cloud Map 進行 gRPC 服務間通信：

```
auth-service.nova-staging.local:50051
user-service.nova-staging.local:50052
...
```

## 變量說明

### 核心變量

| 變量名 | 描述 | 默認值 |
|-------|------|--------|
| `aws_region` | AWS 區域 | `us-east-1` |
| `environment` | 環境名稱 | `staging` |
| `services` | 服務列表 | 11 個微服務 |

### ECS 變量

| 變量名 | 描述 | Staging | Production |
|-------|------|---------|------------|
| `ecs_task_cpu` | CPU 單位 | 512 | 1024 |
| `ecs_task_memory` | 內存 MB | 1024 | 2048 |
| `ecs_task_count` | 任務數量 | 2 | 3 |

### 數據庫變量

| 變量名 | 描述 | Staging | Production |
|-------|------|---------|------------|
| `db_instance_class` | RDS 實例類型 | `db.t4g.medium` | `db.r6g.xlarge` |
| `enable_multi_az` | 多可用區 | `false` | `true` |

### Redis 變量

| 變量名 | 描述 | Staging | Production |
|-------|------|---------|------------|
| `redis_node_type` | Redis 節點類型 | `cache.t4g.micro` | `cache.r6g.large` |
| `redis_num_cache_nodes` | 節點數量 | 1 | 3 |

## 輸出值

部署完成後，Terraform 會輸出以下值：

```bash
# ECR 倉庫 URL
terraform output ecr_repository_urls

# ALB DNS 名稱
terraform output alb_dns_name

# ECS 集群名稱
terraform output ecs_cluster_name

# RDS 端點
terraform output rds_endpoint

# Redis 端點
terraform output redis_endpoint
```

## 常用命令

### 查看當前狀態

```bash
terraform show
```

### 查看特定資源

```bash
terraform state show aws_ecs_service.services[\"auth-service\"]
```

### 更新特定資源

```bash
terraform apply -target=aws_ecs_service.services[\"auth-service\"]
```

### 導入現有資源

```bash
terraform import aws_ecs_service.services[\"auth-service\"] nova-staging/nova-auth-service
```

### 格式化代碼

```bash
terraform fmt -recursive
```

## 升級策略

### 更新 ECS 任務定義

```bash
# 修改 ecs.tf 中的 container_definitions
terraform apply -var-file="staging.tfvars"
```

### 擴展 ECS 服務

```bash
# 修改 staging.tfvars 中的 ecs_task_count
terraform apply -var-file="staging.tfvars"
```

### 升級數據庫實例

```bash
# 修改 staging.tfvars 中的 db_instance_class
terraform apply -var-file="staging.tfvars"
```

## 安全注意事項

### Secrets 管理

- **RDS 密碼：** 自動生成並存儲在 AWS Secrets Manager
- **ECR 訪問：** 通過 IAM 角色控制
- **環境變量：** 通過 ECS 任務定義注入

### 網絡安全

- **ECS 任務：** 運行在私有子網
- **ALB：** 運行在公有子網
- **RDS：** 僅允許來自 ECS 安全組的流量
- **ElastiCache：** 僅允許來自 ECS 安全組的流量

### IAM 最小權限原則

- **ECS Task Execution Role：** 僅允許 ECR 拉取和 CloudWatch 日誌寫入
- **ECS Task Role：** 僅允許應用所需的 S3、SQS、SNS 訪問
- **GitHub Actions Role：** 僅允許 ECR 推送和 ECS 服務更新

## 故障排查

### 問題 1: Terraform 初始化失敗

**錯誤：** `Error: Failed to get existing workspaces`

**解決方案：**
```bash
# 確保 S3 bucket 和 DynamoDB 表已創建
aws s3 ls nova-terraform-state
aws dynamodb describe-table --table-name nova-terraform-lock
```

### 問題 2: ECR 倉庫創建失敗

**錯誤：** `RepositoryAlreadyExistsException`

**解決方案：**
```bash
# 導入現有倉庫
terraform import aws_ecr_repository.services[\"auth-service\"] nova-auth-service
```

### 問題 3: ECS 服務無法啟動

**錯誤：** `service nova-auth-service was unable to place a task`

**解決方案：**
```bash
# 檢查 ECS 集群容量
aws ecs describe-clusters --clusters nova-staging

# 檢查子網可用 IP
aws ec2 describe-subnets --subnet-ids subnet-xxxxx
```

### 問題 4: RDS 實例創建超時

**原因：** Multi-AZ 部署需要更長時間（15-30 分鐘）

**解決方案：** 等待或臨時禁用 Multi-AZ

### 問題 5: Terraform 狀態鎖定

**錯誤：** `Error acquiring the state lock`

**解決方案：**
```bash
# 手動解鎖（謹慎使用）
terraform force-unlock <lock-id>
```

## 清理資源

**警告：這將刪除所有資源和數據！**

```bash
# 刪除 Staging 環境
terraform destroy -var-file="staging.tfvars"

# 刪除 Production 環境
terraform destroy -var-file="production.tfvars"
```

## 成本優化建議

1. **使用 Fargate Spot：** 可節省 70% 成本（適用於非關鍵任務）
2. **RDS Reserved Instance：** 可節省 30-60% 成本（1-3 年承諾）
3. **ElastiCache Reserved Nodes：** 可節省 30-50% 成本
4. **NAT Gateway 優化：** 使用單個 NAT Gateway（非生產環境）
5. **CloudWatch Logs 保留期：** 減少到 7 天（Staging）

## 下一步

1. **配置自定義域名：** 在 Route53 中創建 A 記錄指向 ALB
2. **啟用 HTTPS：** 在 ACM 中創建 SSL 證書
3. **設置監控告警：** 配置 CloudWatch Alarms 和 SNS
4. **實施備份策略：** 配置 RDS 自動備份和快照
5. **優化成本：** 使用 AWS Cost Explorer 分析支出

## 參考資料

- [Terraform AWS Provider 文檔](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS ECS Fargate 最佳實踐](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [AWS VPC 設計指南](https://docs.aws.amazon.com/vpc/latest/userguide/)

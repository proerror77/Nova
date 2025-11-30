# Nova GCP Infrastructure as Code

完整的 Terraform 配置，用於在 Google Cloud Platform 上部署和管理 Nova 應用。支持 Staging 和 Production 兩個環境。

## 📁 目錄結構

```
gcp/
├── main/                          # 主模組編排器
│   ├── main.tf                    # 所有子模組的編排和整合
│   ├── variables.tf               # 所有輸入變數定義
│   ├── outputs.tf                 # 所有輸出值（已包含在 main.tf）
│   ├── terraform.tfvars.staging   # Staging 環境配置
│   ├── terraform.tfvars.production # Production 環境配置
│   ├── deploy.sh                  # 部署自動化腳本
│   └── validate-deployment.sh     # 部署驗證腳本
│
├── network/                       # 網絡模組（VPC、子網、防火牆、Cloud NAT）
│   ├── main.tf
│   └── variables.tf
│
├── compute/                       # 計算模組（GKE 集群和節點池）
│   ├── main.tf
│   └── variables.tf
│
├── database/                      # 數據庫模組（Cloud SQL + Memorystore Redis）
│   ├── main.tf
│   └── variables.tf
│
├── storage/                       # 儲存模組（Artifact Registry + Cloud Storage）
│   ├── main.tf
│   └── variables.tf
│
├── iam/                           # IAM 模組（服務帳戶、Workload Identity Federation）
│   ├── main.tf
│   └── variables.tf
│
└── README.md                      # 本文件
```

## 🚀 快速開始

### 前置條件

```bash
# 檢查必需工具
terraform --version    # >= 1.5.0
gcloud --version
kubectl version --client
```

### Staging 環境部署

```bash
# 進入主模組目錄
cd infrastructure/terraform/gcp/main

# 檢查執行計畫
./deploy.sh staging plan

# 應用配置
./deploy.sh staging apply

# 驗證部署
./validate-deployment.sh staging
```

### Production 環境部署

```bash
# 進入主模組目錄
cd infrastructure/terraform/gcp/main

# 檢查執行計畫（會要求確認）
./deploy.sh production plan

# 應用配置（會要求多次確認）
./deploy.sh production apply

# 驗證部署
./validate-deployment.sh production
```

## ❓ 我們需要 Cloud SQL 嗎？

**決策**: **不需要 Cloud SQL，使用 Kubernetes 中的 PostgreSQL**

詳見: `docs/GCP_ARCHITECTURE_REVISED.md` - 完整的架構分析

**為什麼不需要 Cloud SQL**:
- ✅ PostgreSQL 實際寫入頻率：**350-630 次/秒**（完全可處理）
- ✅ Transactional Outbox Pattern 已實現一致性
- ✅ 高頻操作在 Redis/內存（不寫 PostgreSQL）
- ✅ Kubernetes PostgreSQL 性能足夠
- ✅ 成本節省：$150-200/月（Staging）/ $500-600/月（Production）

**需要自己承擔**:
- 每日備份到 Cloud Storage（自動化）
- 監控和告警（自建）
- 故障轉移（手動，通常 <5 分鐘）
- 升級和補丁（季度一次）

**年度運維成本估算**: ~$5K-10K（工程師兼職）

**建議**: 立即開始 Staging 部署，使用 K8s PostgreSQL！

---

## 📊 模組說明

### 1. Network 模組

**目的**: 創建隔離的 VPC 環境

**資源**:
- VPC 網絡（REGIONAL 模式）
- 主子網（支持私有 Google 訪問）
- Pod 和 Service 的次級 IP 範圍
- Cloud Router 和 Cloud NAT（用於出站連接）
- 防火牆規則（內部通信、SSH、健康檢查）

**變數**:
```hcl
vpc_name    = "nova-vpc"
vpc_cidr    = "10.0.0.0/16"
subnet_cidr = "10.0.0.0/20"
```

### 2. Compute 模組

**目的**: 創建 GKE 集群和節點池

**資源**:
- GKE 集群（VPC 原生、Workload Identity 啟用）
- 隨需節點池（穩定工作負載）
- Spot 節點池（成本優化工作負載）

**配置差異**:
| | Staging | Production |
|---|---------|-----------|
| 隨需節點 | 2-5 x n2-standard-4 | 3-10 x n2-standard-8 |
| Spot 節點 | 禁用 | 1-5 x n2-standard-4 |

### 3. Database 模組

**目的**: 創建受管數據庫服務

**資源**:
- **Cloud SQL**: PostgreSQL 15（私有網絡）
  - Staging: db-custom-4-16384 (4vCPU, 16GB)
  - Production: db-custom-8-32768 (8vCPU, 32GB) HA

- **Memorystore Redis**: 版本 7.0（私有網絡）
  - Staging: 1GB
  - Production: 5GB HA

- **Secret Manager**: 儲存敏感信息
  - 數據庫密碼
  - 連接字符串
  - Redis 連接信息

### 4. Storage 模組

**目的**: 創建容器和文件儲存

**資源**:
- **Artifact Registry**: Docker 映像儲存庫
  - 自動清理策略（保留最近 10/20 個映像）
  - 30 天後刪除舊映像

- **Cloud Storage 桶**:
  - Terraform 狀態存儲
  - 備份存儲（COLDLINE 層，90 天後）
  - 應用日誌（90 天後刪除）

### 5. IAM 模組

**目的**: 設置認證和授權

**資源**:
- **Workload Identity Pool**: GitHub Actions OIDC 集成
- **GitHub Actions Service Account**: 用於 CI/CD
  - 權限: Artifact Registry 推送、GKE 部署、Secret Manager 訪問

- **K8s Workloads Service Account**: Kubernetes 內服務
  - 權限: Cloud SQL、Redis、Secret Manager、Cloud Storage 訪問

## 🔧 常用命令

### 部署命令

```bash
cd infrastructure/terraform/gcp/main

# 查看計畫（不應用更改）
./deploy.sh staging plan

# 應用更改到 Staging
./deploy.sh staging apply

# 查看 Production 計畫
./deploy.sh production plan

# 銷毀 Staging 環境
./deploy.sh staging destroy
```

### Terraform 直接命令

```bash
# 初始化
terraform init -backend-config="bucket=nova-terraform-state" \
               -backend-config="prefix=gcp/staging"

# 驗證配置
terraform validate
terraform fmt -check

# 查看計畫
terraform plan -var-file="terraform.tfvars.staging"

# 應用更改
terraform apply -var-file="terraform.tfvars.staging"

# 查看狀態
terraform show
terraform state list
terraform state show 'module.compute.google_container_cluster.primary'

# 銷毀資源
terraform destroy -var-file="terraform.tfvars.staging"
```

### 驗證命令

```bash
cd infrastructure/terraform/gcp/main

# 執行完整驗證
./validate-deployment.sh staging

# 手動驗證集群
kubectl get nodes
kubectl get pods -A

# 驗證數據庫連接
kubectl run psql-test --image=postgres:15 --rm -it -- \
  psql -h <CLOUD_SQL_IP> -U nova_admin -d nova -c "SELECT 1;"

# 驗證 Redis 連接
kubectl run redis-test --image=redis:7 --rm -it -- \
  redis-cli -h <REDIS_HOST> ping
```

## 📋 環境配置

### Staging 配置（terraform.tfvars.staging）

```hcl
environment = "staging"

# 成本優化但功能完整
on_demand_max_node_count = 5
spot_initial_node_count  = 0          # 禁用，以提高穩定性

database_machine_type = "db-custom-4-16384"
redis_size_gb         = 1

enable_branch_specific_oidc = false
```

### Production 配置（terraform.tfvars.production）

```hcl
environment = "production"

# 高可用性和性能
on_demand_max_node_count = 10
spot_initial_node_count  = 2           # 成本優化

database_machine_type = "db-custom-8-32768"
redis_size_gb         = 5

enable_branch_specific_oidc = true     # 更嚴格的控制
```

## 📈 預期輸出

部署完成後，您將獲得：

### GKE
```
gke_cluster_name: nova-staging-gke
gke_cluster_endpoint: 10.x.x.x (private)
```

### Cloud SQL
```
cloud_sql_instance_name: nova-staging
cloud_sql_private_ip: 10.x.x.x
db_password_secret: nova-staging-password
```

### Redis
```
redis_host: 10.x.x.x
redis_port: 6379
redis_connection_secret: nova-staging-redis-connection
```

### Artifact Registry
```
artifact_registry_url: asia-northeast1-docker.pkg.dev/project/nova
artifact_registry_service_account: artifact-registry-staging@...
```

### IAM
```
github_actions_service_account: github-actions@...
k8s_workloads_service_account: k8s-workloads-staging@...
workload_identity_pool_id: projects/.../locations/global/workloadIdentityPools/github
```

## 🔐 安全性考慮

### 網絡隔離
- ✅ 所有數據庫都在私有網絡中
- ✅ 沒有公共 IP 分配給敏感資源
- ✅ 防火牆規則限制流量

### 認證
- ✅ 使用 Workload Identity，無長期密鑰
- ✅ Secret Manager 存儲敏感信息
- ✅ 數據庫密碼自動生成

### 加密
- ✅ 傳輸中加密（TLS）
- ✅ 靜態數據加密（可選 KMS）
- ✅ Cloud SQL 備份加密

## 📚 相關文檔

- **[GCP 架構計畫](../../docs/GCP_ARCHITECTURE_PLAN.md)**: 完整的架構和設計文檔
- **[GCP CI/CD 集成](../../docs/GCP_CICD_INTEGRATION.md)**: GitHub Actions OIDC 設置
- **[部署指南](../../docs/GCP_DEPLOYMENT_GUIDE.md)**: 詳細的部署步驟
- **[快速參考](../../docs/GCP_QUICK_START.md)**: 快速決策和故障排查

## 🔄 狀態管理

Terraform 狀態存儲在 GCS bucket：

```bash
# 列出所有狀態
gsutil ls gs://nova-terraform-state/

# 查看特定環境狀態
gsutil cat gs://nova-terraform-state/gcp/staging/default.tfstate

# 啟用版本控制（已啟用）
gsutil versioning get gs://nova-terraform-state/
```

## 🛠️ 故障排查

### 常見錯誤

| 錯誤 | 原因 | 解決方案 |
|------|------|--------|
| `backend initialization required` | 首次部署 | 運行 `terraform init` |
| `permission denied on resource` | IAM 權限不足 | 檢查 GCP IAM 角色 |
| `Timeout waiting for network` | 網絡配置慢 | 等待 5-10 分鐘後重試 |
| `node pool creation failed` | 資源配額不足 | 檢查 GCP 配額 |

### 調試

```bash
# 啟用詳細日誌
export TF_LOG=DEBUG
terraform plan -var-file="terraform.tfvars.staging"

# 驗證 GCP 認證
gcloud auth list
gcloud auth application-default login

# 檢查 GCP 配額
gcloud compute project-info describe --project=banded-pad-479802-k9

# 查看 GCP 活動
gcloud logging read "resource.type=k8s_cluster" --limit=10
```

## 📞 支持

- 檢查本 README 和相關文檔
- 查看 Terraform 錯誤消息和日誌
- 查看 GCP Cloud Logging
- 查看 Kubernetes 事件：`kubectl get events -A`

## 📝 版本信息

- **Terraform**: >= 1.5.0
- **Google Provider**: ~> 5.0
- **Kubernetes**: 1.27+
- **PostgreSQL**: 15
- **Redis**: 7.0

---

**最後更新**: 2025-11-30
**維護人**: Infrastructure Team

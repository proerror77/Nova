# GCP 部署完全指南 - 雙環境配置

**版本**: 1.0
**日期**: 2025-11-30
**適用環境**: Staging & Production

---

## 目錄

1. [前置條件](#前置條件)
2. [快速開始](#快速開始)
3. [詳細部署步驟](#詳細部署步驟)
4. [環境間差異](#環境間差異)
5. [驗證部署](#驗證部署)
6. [故障排查](#故障排查)
7. [清理資源](#清理資源)

---

## 前置條件

### 必需工具

```bash
# 1. Google Cloud SDK (gcloud)
gcloud --version

# 2. Terraform (>=1.5.0)
terraform --version

# 3. kubectl
kubectl version --client

# 4. Git
git --version
```

### GCP 設定

```bash
# 1. 設定預設 GCP 專案
gcloud config set project banded-pad-479802-k9

# 2. 驗證認證
gcloud auth list --filter=status:ACTIVE --format="value(account)"

# 3. 啟用必需的 API
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable sql-component.googleapis.com
gcloud services enable redis.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable secretmanager.googleapis.com
```

### Terraform 狀態儲存桶

```bash
# 檢查或創建 Terraform 狀態儲存桶
gsutil ls gs://nova-terraform-state

# 如果不存在，創建它
gsutil mb gs://nova-terraform-state
gsutil versioning set on gs://nova-terraform-state
```

---

## 快速開始

### Staging 環境（2-3 小時）

```bash
# 1. 進入 Terraform 目錄
cd infrastructure/terraform/gcp/main

# 2. 執行部署腳本
./deploy.sh staging plan

# 3. 檢查計畫
# 在輸出中檢查要創建的資源

# 4. 應用部署
./deploy.sh staging apply

# 5. 驗證部署
./validate-deployment.sh staging
```

### Production 環境（2-3 小時）

```bash
# 1. 進入 Terraform 目錄
cd infrastructure/terraform/gcp/main

# 2. 執行部署腳本（會要求確認）
./deploy.sh production plan

# 3. 檢查計畫（仔細檢查 production 設定）
# - 更大的資料庫（db-custom-8-32768）
# - 更大的 Redis（5GB）
# - Spot 節點已啟用
# - 更多副本和自動擴展

# 4. 應用部署
./deploy.sh production apply

# 5. 驗證部署
./validate-deployment.sh production
```

---

## 詳細部署步驟

### 第 1 步：準備工作

```bash
# 1. 克隆倉庫
git clone https://github.com/proerror/nova.git
cd nova

# 2. 檢查分支
git branch -a
git checkout main

# 3. 檢查 Terraform 文件
ls -la infrastructure/terraform/gcp/main/

# 4. 驗證 terraform.tfvars 文件存在
ls infrastructure/terraform/gcp/main/terraform.tfvars.staging
ls infrastructure/terraform/gcp/main/terraform.tfvars.production
```

### 第 2 步：初始化 Terraform

```bash
cd infrastructure/terraform/gcp/main

# 使用部署腳本（自動化）
./deploy.sh staging plan

# 或手動初始化
terraform init \
  -backend-config="bucket=nova-terraform-state" \
  -backend-config="prefix=gcp/staging"
```

### 第 3 步：計畫部署

```bash
# 生成執行計畫
terraform plan \
  -var-file="terraform.tfvars.staging" \
  -out="tfplan.staging"

# 輸出應包括：
# - GKE 集群（1 個）
# - 節點池（2 個：on-demand + spot）
# - Cloud SQL（1 個 PostgreSQL 15）
# - Memorystore Redis（1 個）
# - VPC 和子網
# - Artifact Registry 和儲存桶
# - IAM 角色和服務帳戶
```

### 第 4 步：應用部署

```bash
# 應用 Terraform 計畫
terraform apply tfplan.staging

# 這將需要 2-3 小時，因為：
# - GKE 集群創建：~10 分鐘
# - Cloud SQL 實例初始化：~15-20 分鐘
# - 其他資源：~5 分鐘
# - 節點啟動和就緒：~15-30 分鐘

# 監控進度
watch 'gcloud container clusters list --region=asia-northeast1'
```

### 第 5 步：取得 kubeconfig

```bash
# 自動（部署腳本已包含）
gcloud container clusters get-credentials nova-staging-gke \
  --region=asia-northeast1 \
  --project=banded-pad-479802-k9

# 驗證連接
kubectl cluster-info
kubectl get nodes
```

### 第 6 步：設置 Kubernetes 命名空間

```bash
# 創建命名空間
kubectl create namespace nova-staging

# 創建服務帳戶（用於 Workload Identity）
kubectl create serviceaccount k8s-workloads -n nova-staging

# 標籤命名空間
kubectl label namespace nova-staging \
  environment=staging \
  managed-by=terraform
```

### 第 7 步：同步秘鑰

```bash
# 從 Secret Manager 同步秘鑰到 K8s
kubectl create secret generic nova-db-credentials \
  -n nova-staging \
  --from-literal=connection-string="$(gcloud secrets versions access latest --secret=nova-staging-db-connection-string)"

kubectl create secret generic nova-redis-connection \
  -n nova-staging \
  --from-literal=connection-string="$(gcloud secrets versions access latest --secret=nova-staging-redis-connection)"

# 應用秘鑰同步 CronJob（可選）
kubectl apply -f k8s/infrastructure/overlays/staging/secrets-sync.yaml
```

### 第 8 步：部署微服務

```bash
# 應用 Kustomize 覆蓋
kubectl apply -k k8s/overlays/staging

# 或手動部署特定服務
kubectl apply -f k8s/services/identity-service/deployment.yaml
kubectl apply -f k8s/services/realtime-chat-service/deployment.yaml
# ... 等等

# 驗證部署狀態
kubectl get deployments -n nova-staging
kubectl get pods -n nova-staging
```

---

## 環境間差異

### Staging

| 組件 | 配置 | 用途 |
|------|------|------|
| **GKE 節點** | 2-5 個 n2-standard-4 | 開發/測試 |
| **Cloud SQL** | db-custom-4-16384 (4vCPU, 16GB) | 測試 |
| **Redis** | 1GB STANDARD | 測試 |
| **Spot 節點** | 禁用 | 穩定性優先 |
| **備份** | 7 天保留 | 快速恢復 |

### Production

| 組件 | 配置 | 用途 |
|------|------|------|
| **GKE 節點** | 3-10 個 n2-standard-8 | 生產工作負載 |
| **Cloud SQL** | db-custom-8-32768 (8vCPU, 32GB) HA | 高可用性 |
| **Redis** | 5GB STANDARD HA | 高可用性 |
| **Spot 節點** | 1-5 個 n2-standard-4 | 成本優化 |
| **備份** | 30 天保留 + PITR | 災難恢復 |
| **OIDC** | 分支特定 | 安全控制 |

---

## 驗證部署

### 自動驗證

```bash
# 執行完整驗證
cd infrastructure/terraform/gcp/main
./validate-deployment.sh staging

# 輸出應包括：
# ✓ Cluster has X nodes
# ✓ All nodes are Ready
# ✓ Database credentials secret found
# ✓ Redis connection secret found
# ... 等等
```

### 手動驗證

#### 1. 檢查集群健康

```bash
# 查看節點
kubectl get nodes -o wide

# 查看節點詳細信息
kubectl describe nodes

# 檢查系統 Pod
kubectl get pods -n kube-system

# 查看集群事件
kubectl get events -A --sort-by='.lastTimestamp'
```

#### 2. 檢查 Cloud SQL 連接

```bash
# 運行 Cloud SQL 代理 Pod
kubectl run cloudsql-proxy-test \
  --image=gcr.io/cloudsql-docker/cloud-sql-proxy:latest \
  --rm -it \
  -n nova-staging \
  -- cloud-sql-proxy --help

# 或在 Pod 內測試連接
kubectl exec -it <pod-name> -n nova-staging -- psql \
  -h <CLOUD_SQL_PRIVATE_IP> \
  -U nova_admin \
  -d nova \
  -c "SELECT version();"
```

#### 3. 檢查 Redis 連接

```bash
# 運行 Redis CLI 測試
kubectl run redis-test \
  --image=redis:latest \
  --rm -it \
  -n nova-staging \
  -- redis-cli -h <REDIS_HOST> ping
```

#### 4. 檢查 Artifact Registry

```bash
# 配置 Docker 認證
gcloud auth configure-docker asia-northeast1-docker.pkg.dev

# 列出儲存庫
gcloud artifacts repositories list --location=asia-northeast1

# 測試推送（可選）
docker tag nginx:latest \
  asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/nginx:test

docker push \
  asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/nginx:test
```

#### 5. 檢查 IAM 和 Workload Identity

```bash
# 查看 Workload Identity Pool
gcloud iam workload-identity-pools list --location=global

# 查看 Provider
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool=github \
  --location=global

# 測試 GitHub Actions OIDC（在 GitHub Actions 工作流中）
# 參考 .github/workflows/gcp-deploy.yml
```

---

## 故障排查

### 常見問題

| 問題 | 原因 | 解決方案 |
|------|------|--------|
| Terraform init 失敗 | 無效的 GCS bucket | 檢查 bucket 名稱和權限 |
| GKE 節點無法啟動 | 資源配額不足 | 檢查 `gcloud compute resource-quotas list` |
| Cloud SQL 連接超時 | 防火牆規則缺失 | VPC 對等連接應自動創建 |
| Redis 認證失敗 | 子網不同 | 確認 Redis 在 VPC 中 |
| Workload Identity 失敗 | 服務帳戶綁定不對 | 檢查 `kubectl get sa -o yaml` 中的註解 |

### 調試命令

```bash
# 查看 Terraform 狀態
terraform show
terraform state list

# 查看特定資源
terraform state show 'module.database.google_sql_database_instance.primary'

# 強制重新整理
terraform refresh

# 驗證 Terraform 配置
terraform validate
terraform fmt -check

# 查看詳細日誌
terraform apply -var-file="terraform.tfvars.staging" -input=false 2>&1 | tee deploy.log

# GCP 側調試
gcloud container clusters describe nova-staging-gke --region=asia-northeast1
gcloud sql instances describe nova-staging

# K8s 側調試
kubectl get events -A
kubectl logs <pod-name> -n nova-staging
kubectl describe pod <pod-name> -n nova-staging
```

---

## 清理資源

### 銷毀 Staging 環境

```bash
# 僅銷毀 staging（生產環境保留）
cd infrastructure/terraform/gcp/main

./deploy.sh staging destroy

# 或手動銷毀
terraform destroy \
  -var-file="terraform.tfvars.staging" \
  -auto-approve
```

### 銷毀 Production 環境

```bash
# 警告：此操作不可逆
# 確保已備份所有重要數據

./deploy.sh production destroy

# 部署腳本會要求三次確認
```

### 手動清理

```bash
# 如果 Terraform 失敗，手動清理：

# 1. 刪除 GKE 集群
gcloud container clusters delete nova-staging-gke \
  --region=asia-northeast1 \
  --quiet

# 2. 刪除 Cloud SQL
gcloud sql instances delete nova-staging --quiet

# 3. 刪除 Redis
gcloud redis instances delete nova-staging-redis \
  --region=asia-northeast1 \
  --quiet

# 4. 刪除 VPC
gcloud compute networks delete nova-vpc-staging --quiet
```

---

## 成本監控

### Staging 預期成本

- GKE 集群: $50-80/月
- Cloud SQL: $150-200/月
- Redis: $30-50/月
- 儲存和網絡: $20-30/月
- **總計**: $250-360/月

### Production 預期成本

- GKE 集群: $200-300/月（更大的節點 + Spot）
- Cloud SQL HA: $400-500/月（更大的機器）
- Redis HA: $150-200/月（更大的實例）
- 儲存和網絡: $50-100/月
- **總計**: $800-1100/月

### 監控成本

```bash
# 查看成本估計
gcloud billing accounts list
gcloud compute project-info describe --project=banded-pad-479802-k9 \
  --format='value(commonInstanceMetadata.items[enable-cost-tracking])'

# 在 Cloud Console 查看詳細成本
# https://console.cloud.google.com/billing/projects
```

---

## 檢查清單

### Pre-Deployment

- [ ] 所有工具已安裝（gcloud、Terraform、kubectl）
- [ ] GCP 認證有效
- [ ] 必需 API 已啟用
- [ ] Terraform 狀態 bucket 已創建
- [ ] 選擇了目標環境（staging 或 production）

### Post-Deployment

- [ ] 所有 GKE 節點已就緒
- [ ] Cloud SQL 實例已創建
- [ ] Redis 實例已創建
- [ ] VPC 對等連接已建立
- [ ] kubeconfig 已更新
- [ ] Kubernetes 命名空間已創建
- [ ] 秘鑰已同步
- [ ] 驗證腳本通過
- [ ] 微服務已部署

### Production-Specific

- [ ] 分支特定 OIDC 已啟用
- [ ] 備份策略已驗證
- [ ] 監控和告警已配置
- [ ] 災難恢復計畫已制定
- [ ] 負載測試已完成

---

## 下一步

1. **部署應用層**
   ```bash
   kubectl apply -k k8s/overlays/staging
   ```

2. **配置 CI/CD**
   - 參考 `docs/GCP_CICD_INTEGRATION.md`
   - 設定 GitHub Actions secrets

3. **設置監控**
   ```bash
   kubectl apply -f k8s/monitoring/prometheus-operator.yaml
   kubectl apply -f k8s/monitoring/grafana-dashboard.yaml
   ```

4. **驗證應用**
   ```bash
   kubectl get deployments -n nova-staging
   kubectl logs -n nova-staging -l app=identity-service
   ```

---

## 支持和資源

- [GCP 架構計畫](GCP_ARCHITECTURE_PLAN.md)
- [CI/CD 集成指南](GCP_CICD_INTEGRATION.md)
- [快速參考](GCP_QUICK_START.md)
- [Terraform 文件](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GKE 文件](https://cloud.google.com/kubernetes-engine/docs)

---

**版本**: 1.0
**最後更新**: 2025-11-30
**維護人**: Infrastructure Team

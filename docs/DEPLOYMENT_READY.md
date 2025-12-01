# 🚀 Nova Staging 部署 - 準備就緒

**狀態**: ✅ 所有準備已完成
**日期**: 2025-11-30
**架構**: Kubernetes PostgreSQL（已驗證）
**預期耗時**: 45-60 分鐘

---

## 📋 您已完成的工作

### ✅ 架構決策（已完成）
- **決策**: Kubernetes PostgreSQL + Redis + ClickHouse
- **理由**: PostgreSQL 實際寫入 350-630 次/秒，完全在 K8s 容量內
- **成本節省**: $150-600/月（相對於 Cloud SQL）
- **文檔**: `docs/GCP_ARCHITECTURE_REVISED.md`

### ✅ Terraform 基礎設施（已準備）
- **GCP 項目**: `banded-pad-479802-k9`
- **區域**: `asia-northeast1`
- **GKE 集群**: 2-5 個 n2-standard-4 節點
- **配置**: `infrastructure/terraform/gcp/main/terraform.tfvars.staging`

### ✅ Kubernetes 配置（已準備）
- **StatefulSets**: PostgreSQL, Redis, ClickHouse, Elasticsearch, Kafka
- **Deployments**: 14 個微服務
- **配置**: `k8s/infrastructure/overlays/staging/`

### ✅ 部署文檔（已準備）
1. `docs/GCP_ARCHITECTURE_REVISED.md` - 完整架構分析
2. `docs/STAGING_DEPLOYMENT_GUIDE.md` - 詳細部署步驟
3. `docs/DEPLOYMENT_CHECKLIST.md` - 執行清單（新增）
4. `docs/QUICK_REFERENCE.md` - 快速參考卡（新增）

---

## 🎯 立即開始的三個選項

### 選項 1：按步驟部署（推薦初學者）

**適合**: 首次部署，想要理解每一步

```bash
# 1. 閱讀部署清單
cat docs/DEPLOYMENT_CHECKLIST.md

# 2. 按照 7 個階段執行
# 階段 1: Terraform 狀態設置（5 分鐘）
cd infrastructure/terraform/gcp/main
terraform init -backend-config="bucket=nova-terraform-state" \
               -backend-config="prefix=gcp/staging"

# 階段 2: GCP 基礎設施（15 分鐘）
terraform plan -var-file="terraform.tfvars.staging" -out=staging.tfplan
terraform apply staging.tfplan

# ... 繼續閱讀 DEPLOYMENT_CHECKLIST.md 的其他階段
```

**所需時間**: 60 分鐘
**優勢**: 理解每個步驟，容易排查問題
**劣勢**: 手動操作較多

---

### 選項 2：使用部署腳本（推薦有經驗者）

**適合**: 熟悉 Kubernetes 和 GCP，想要快速部署

```bash
# 1. 驗證前置條件（2 分鐘）
cd infrastructure/terraform/gcp/main
terraform validate
kubectl cluster-info 2>/dev/null || echo "需要先部署 GCP 基礎設施"

# 2. 執行部署腳本
./deploy.sh staging plan
./deploy.sh staging apply

# 3. 驗證
./validate-deployment.sh staging
```

**所需時間**: 30-40 分鐘
**優勢**: 自動化，快速
**劣勢**: 錯誤時難以排查

---

### 選項 3：快速檢查清單（推薦有準備者）

**適合**: 知道自己在做什麼，想要快速參考

```bash
# 使用快速參考卡
cat docs/QUICK_REFERENCE.md

# 複製命令粘貼執行
# 預期完成時間: 45 分鐘
```

**所需時間**: 45-60 分鐘
**優勢**: 最小化等待
**劣勢**: 需要熟悉 kubectl 和 Terraform

---

## ⚙️ 前置條件檢查（2 分鐘）

在開始前，快速檢查：

```bash
# 1. GCP 認證
gcloud auth list
# 預期: 看到您的帳戶

# 2. GCP 項目
gcloud config get-value project
# 預期: banded-pad-479802-k9

# 3. kubectl
kubectl version --client
# 預期: >= 1.27

# 4. Terraform
terraform version
# 預期: >= 1.5.0

# 5. Docker
docker version
# 預期: 已安裝

# 如果任何一項失敗，請先安裝或配置工具
```

---

## 📊 部署流程圖

```
開始
  ↓
[前置條件檢查] ← 2 分鐘
  ↓
[Terraform 部署] ← 15 分鐘
  ├─ 初始化狀態
  ├─ 創建 GKE 集群
  ├─ 配置 VPC
  └─ 設置 IAM
  ↓
[kubectl 認證] ← 2 分鐘
  ↓
[K8s 存儲服務部署] ← 10 分鐘
  ├─ PostgreSQL
  ├─ Redis
  ├─ ClickHouse
  ├─ Elasticsearch
  └─ Kafka
  ↓
[數據庫初始化驗證] ← 5 分鐘
  ├─ PostgreSQL 連接
  ├─ Redis 連接
  └─ 數據表創建
  ↓
[微服務部署] ← 5 分鐘
  ├─ 14 個服務容器
  └─ gRPC 配置
  ↓
[部署驗證] ← 5 分鐘
  ├─ Pod 健康檢查
  ├─ 日誌檢查
  └─ 連接驗證
  ↓
[備份和監控設置] ← 5 分鐘
  ├─ PostgreSQL 備份 CronJob
  ├─ Prometheus 規則
  └─ 監控儀表板
  ↓
完成 ✅
預期總耗時: 45-60 分鐘
```

---

## 🎬 立即開始（3 步驟）

### 步驟 1：打開部署清單

```bash
# 方式 1: 在編輯器中打開
code docs/DEPLOYMENT_CHECKLIST.md

# 方式 2: 在終端中查看
less docs/DEPLOYMENT_CHECKLIST.md

# 方式 3: 打印出來
cat docs/DEPLOYMENT_CHECKLIST.md | lpr
```

### 步驟 2：進入工作目錄

```bash
cd /Users/proerror/Documents/nova
```

### 步驟 3：執行第一條命令

```bash
# 驗證前置條件（所有工具都已安裝）
gcloud config get-value project
```

**如果輸出**: `banded-pad-479802-k9` → 您已準備好！

---

## 📝 部署期間的注意事項

### ✅ 預期情況
- Terraform apply 需要 10-15 分鐘（正常）
- Pod 啟動需要 30-60 秒（正常）
- 首次部署會拉取大型 Docker 映像（正常）

### ⚠️ 常見警告（無需擔心）
```
Warning: The following arguments...
→ 可以忽略，這只是關於棄用的警告

Error: 409 Conflict
→ 通常是網絡暫時問題，重試即可

Warning: some pods are not ready
→ 首次部署 Pod 啟動較慢，等待即可
```

### 🚨 真正的錯誤（需要停止並排查）
```
FATAL: could not connect to database
→ 檢查 PostgreSQL Pod 狀態

ImagePullBackOff
→ Docker 映像不存在，需要構建

Insufficient memory
→ 節點資源不足，擴展節點
```

---

## 🔄 部署流程回退計劃

如果部署失敗：

### 小問題（Pod 崩潰）
```bash
# 檢查日誌
kubectl logs -n nova-staging <pod-name> --previous

# 刪除 Pod，讓它重新啟動
kubectl delete pod <pod-name> -n nova-staging
```

### 中等問題（存儲故障）
```bash
# 檢查 PVC
kubectl get pvc -n nova-staging

# 如果滿了，擴展大小
kubectl patch pvc postgresql-data -n nova-staging -p \
  '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

### 大問題（集群故障）
```bash
# 銷毀並重新開始
cd infrastructure/terraform/gcp/main
terraform destroy -var-file="terraform.tfvars.staging"

# 等待 10 分鐘
sleep 600

# 重新部署
terraform apply -var-file="terraform.tfvars.staging"
```

---

## 📞 遇到問題時

### 第 1 步：檢查文檔
1. `DEPLOYMENT_CHECKLIST.md` - 常見問題排查部分
2. `QUICK_REFERENCE.md` - 診斷命令
3. `GCP_ARCHITECTURE_REVISED.md` - 架構理解

### 第 2 步：收集信息
```bash
# 集群狀態
kubectl cluster-info dump

# Pod 詳情
kubectl describe pod -n nova-staging <pod-name>

# 事件
kubectl get events -n nova-staging --sort-by='.lastTimestamp'
```

### 第 3 步：嘗試恢復
- 對於 Pod 問題: 刪除 Pod 讓其重新啟動
- 對於 Terraform 問題: 運行 `terraform refresh` 和 `terraform plan`
- 對於網絡問題: 檢查 VPC 和防火牆規則

---

## 🎉 預期成果

部署完成後，您將擁有：

### 基礎設施
```
✅ GKE 集群 (asia-northeast1)
✅ VPC 網絡隔離
✅ Artifact Registry (Docker 映像)
✅ IAM 和 Workload Identity
```

### 數據存儲
```
✅ PostgreSQL StatefulSet（持久存儲）
✅ Redis StatefulSet（緩存和計數器）
✅ ClickHouse StatefulSet（實時分析）
✅ Elasticsearch（全文搜索）
✅ Kafka（事件流）
```

### 應用服務
```
✅ 14 個微服務
✅ gRPC 內部通信
✅ GraphQL 網關（外部 API）
✅ WebSocket 實時服務
```

### 運維工具
```
✅ 自動化備份 (PostgreSQL CronJob)
✅ Prometheus 監控
✅ 日誌聚合 (Cloud Logging)
✅ 告警規則
```

---

## ⏱️ 時間表

| 時間點 | 狀態 | 檢查項 |
|--------|------|--------|
| T+0 | 開始 | 終端打開，前置條件驗證 |
| T+5 | Terraform 初始化 | `terraform validate` 通過 |
| T+20 | GCP 基礎設施 | GKE 集群列表中出現 |
| T+25 | kubectl 認證 | `kubectl get nodes` 看到 2+ 節點 |
| T+35 | K8s 服務 | `kubectl get pods` 看到 5+ Running Pod |
| T+40 | 驗證 | 連接測試通過 |
| T+50 | 微服務 | 所有 14 個服務 Running |
| T+55 | 最終驗證 | 日誌檢查，無錯誤 |
| T+60 | 完成 | ✅ 部署成功 |

---

## 🎯 下一步

### 立即（部署後）
```bash
# 1. 查看儀表板
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# 2. 查看應用日誌
kubectl logs -n nova-staging -l app=identity-service -f

# 3. 測試 API
kubectl port-forward -n nova-staging svc/graphql-gateway 8080:8080
curl http://localhost:8080/graphql
```

### 今天（部署後）
- [ ] 驗證所有 Pod 健康
- [ ] 測試數據庫連接
- [ ] 運行集成測試
- [ ] 檢查監控告警

### 本週
- [ ] 測試備份恢復流程
- [ ] 配置負載均衡
- [ ] 設置 SSL/TLS
- [ ] 準備生產環境清單

---

## 📚 相關文檔

### 部署相關
- **完整架構分析**: `docs/GCP_ARCHITECTURE_REVISED.md`
- **詳細部署步驟**: `docs/STAGING_DEPLOYMENT_GUIDE.md`
- **執行清單**: `docs/DEPLOYMENT_CHECKLIST.md`
- **快速參考**: `docs/QUICK_REFERENCE.md`

### 基礎設施相關
- **Terraform 配置**: `infrastructure/terraform/gcp/main/`
- **K8s 配置**: `k8s/infrastructure/overlays/staging/`
- **原始決策**: `docs/CLOUD_SQL_DECISION_SUMMARY.md`

---

## 🏁 準備就緒檢查清單

在開始部署前，確認：

- [ ] 已閱讀本文件
- [ ] 已檢查所有前置條件（gcloud, kubectl, terraform, docker）
- [ ] GCP 項目 ID 正確（`banded-pad-479802-k9`）
- [ ] 網絡連接良好
- [ ] 已備份重要數據
- [ ] 已清除終端歷史（如有敏感信息）
- [ ] 已打開 `DEPLOYMENT_CHECKLIST.md` 或 `QUICK_REFERENCE.md`

---

## 🚀 開始部署

**現在您已準備就緒。選擇您的路線：**

### 路線 A：按步驟部署（詳細）
```bash
cat docs/DEPLOYMENT_CHECKLIST.md
# 按照 7 個階段逐步進行
```

### 路線 B：快速部署（簡潔）
```bash
cat docs/QUICK_REFERENCE.md
# 複製和粘貼命令
```

### 路線 C：使用腳本（自動化）
```bash
cd infrastructure/terraform/gcp/main
./deploy.sh staging apply
```

---

**祝您部署順利！**

如有任何問題，請參考 `DEPLOYMENT_CHECKLIST.md` 的「常見問題排查」部分。

---

**最後更新**: 2025-11-30
**狀態**: ✅ 準備就緒
**預期完成**: 1 小時


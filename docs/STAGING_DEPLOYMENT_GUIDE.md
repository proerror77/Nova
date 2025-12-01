# Staging 部署完整指南 - Kubernetes 中的所有服務

**版本**: 1.0
**日期**: 2025-11-30
**決策**: 所有服務（包括 PostgreSQL）都在 GKE 中運行
**時間估算**: 30-45 分鐘

---

## 🎯 部署概覽

### 本次部署會創建

```
GKE 集群 (GCP)
│
├─ GKE 節點 (2-5 個 n2-standard-4)
│
└─ 14 個微服務 + 5 個基礎設施服務
   ├─ identity-service
   ├─ realtime-chat-service
   ├─ content-service
   ├─ social-service
   ├─ analytics-service
   ├─ ... (其他 9 個服務)
   │
   ├─ PostgreSQL (StatefulSet) ← K8s 管理
   ├─ Redis (StatefulSet)      ← K8s 管理
   ├─ ClickHouse (StatefulSet) ← K8s 管理
   ├─ Elasticsearch (StatefulSet) ← K8s 管理
   └─ Kafka (StatefulSet)      ← K8s 管理
```

### 不會創建

```
❌ Cloud SQL - 使用 K8s PostgreSQL 代替
❌ Memorystore Redis - 使用 K8s Redis 代替
✅ Cloud Storage - 用於備份
✅ Artifact Registry - 用於 Docker 鏡像
```

---

## 📋 前置條件檢查

```bash
# 1. 驗證 GCP 認證
gcloud config set project banded-pad-479802-k9
gcloud auth list --filter=status:ACTIVE --format="value(account)"

# 預期輸出：您的 Google 帳戶

# 2. 驗證 Terraform 已安裝
terraform version
# 預期：Terraform v1.5+

# 3. 驗證 kubectl 已安裝
kubectl version --client
# 預期：1.27+

# 4. 驗證 gcloud 已安裝
gcloud --version
```

---

## 🚀 第 1 步：部署 GCP 基礎設施（5 分鐘）

### 1.1 初始化 Terraform

```bash
cd infrastructure/terraform/gcp/main

# 驗證配置
terraform validate
terraform fmt -check

# 檢查變數
cat terraform.tfvars.staging
```

**預期的 terraform.tfvars.staging 內容**：

```hcl
gcp_project_id = "banded-pad-479802-k9"
gcp_region     = "asia-northeast1"
environment    = "staging"

gke_cluster_name   = "nova-staging-gke"
kubernetes_version = "1.27"

# 節點配置
on_demand_initial_node_count = 2
on_demand_max_node_count     = 5
on_demand_machine_type       = "n2-standard-4"

# 存儲配置
artifact_repo_name = "nova"
artifact_keep_recent_versions = 10

# GitHub OIDC（可選，用於 CI/CD）
github_org     = "proerror"
github_repo    = "nova"
enable_branch_specific_oidc = false

tags = {
  environment = "staging"
  managed_by  = "terraform"
}
```

### 1.2 初始化 Terraform Backend

```bash
# 建立 GCS 狀態存儲桶
gsutil mb gs://nova-terraform-state 2>/dev/null || echo "Bucket already exists"
gsutil versioning set on gs://nova-terraform-state

# 初始化 Terraform
terraform init \
  -backend-config="bucket=nova-terraform-state" \
  -backend-config="prefix=gcp/staging" \
  -upgrade

# 預期輸出：
# Initializing the backend...
# Successfully configured the backend "gcs"!
```

### 1.3 執行 Terraform Plan

```bash
# 查看將要創建的資源
terraform plan -var-file="terraform.tfvars.staging" -out="tfplan.staging"

# 檢查輸出中是否包括：
# ✅ module.network.google_compute_network.vpc
# ✅ module.compute.google_container_cluster.primary
# ✅ module.storage.google_storage_bucket.*
# ✅ module.iam.google_iam_workload_identity_pool.*
```

### 1.4 應用 Terraform

```bash
# 部署基礎設施（需要 15-20 分鐘）
terraform apply tfplan.staging

# 預期輸出：
# Apply complete! Resources: 25 added, 0 changed, 0 destroyed.
#
# Outputs:
# gke_cluster_name = "nova-staging-gke"
# ...

# 獲取 kubeconfig
gcloud container clusters get-credentials nova-staging-gke \
  --region asia-northeast1 \
  --project banded-pad-479802-k9

# 驗證連接
kubectl cluster-info
kubectl get nodes

# 預期：2-5 個 n2-standard-4 節點處於 Ready 狀態
```

---

## 🚀 第 2 步：部署 Kubernetes 數據存儲服務（10 分鐘）

### 2.1 創建命名空間

```bash
# 創建應用命名空間
kubectl create namespace nova-staging

# 創建 ClickHouse 命名空間（可選）
kubectl create namespace clickhouse
```

### 2.2 部署 PostgreSQL

```bash
# 應用 PostgreSQL 配置
kubectl apply -f k8s/infrastructure/overlays/staging/postgres-init-config.yaml
kubectl apply -f k8s/infrastructure/overlays/staging/postgres-pvc-gp3.yaml
kubectl apply -f k8s/infrastructure/overlays/staging/postgres-statefulset.yaml
kubectl apply -f k8s/infrastructure/overlays/staging/postgres-multi-db-init.yaml

# 等待 Pod 就緒（1-2 分鐘）
kubectl wait --for=condition=ready pod -l app=postgres -n nova-staging --timeout=300s

# 驗證
kubectl get statefulset -n nova-staging postgres
kubectl get pvc -n nova-staging | grep postgres

# 預期：
# NAME       READY   AGE
# postgres   1/1     1m
```

### 2.3 部署 Redis

```bash
# 應用 Redis 配置
kubectl apply -f k8s/infrastructure/overlays/staging/redis-cluster-statefulset.yaml

# 等待就緒
kubectl wait --for=condition=ready pod -l app=redis -n nova-staging --timeout=300s

# 驗證
kubectl get statefulset -n nova-staging redis
```

### 2.4 部署 ClickHouse

```bash
# 應用 ClickHouse 配置
kubectl apply -f k8s/infrastructure/overlays/staging/nova-clickhouse-credentials.yaml
kubectl apply -f k8s/infrastructure/overlays/staging/clickhouse-statefulset.yaml
kubectl apply -f k8s/infrastructure/overlays/staging/clickhouse-service-internal.yaml

# 等待就緒
kubectl wait --for=condition=ready pod -l app=clickhouse -n nova-staging --timeout=600s

# 驗證
kubectl get statefulset -n nova-staging clickhouse
```

### 2.5 部署 Elasticsearch

```bash
# 應用 Elasticsearch 配置
kubectl apply -f k8s/infrastructure/overlays/staging/elasticsearch-replicas-patch.yaml

# 等待就緒
kubectl wait --for=condition=ready pod -l app=elasticsearch -n nova-staging --timeout=300s

# 驗證
kubectl get statefulset -n nova-staging elasticsearch
```

### 2.6 部署 Kafka + Zookeeper

```bash
# 應用 Kafka 配置
kubectl apply -f k8s/infrastructure/overlays/staging/kafka-zookeeper-deployment.yaml
kubectl apply -f k8s/infrastructure/overlays/staging/kafka-topics.yaml

# 等待就緒
kubectl wait --for=condition=ready pod -l app=kafka -n nova-staging --timeout=300s
kubectl wait --for=condition=ready pod -l app=zookeeper -n nova-staging --timeout=300s

# 驗證
kubectl get deployment -n nova-staging kafka
kubectl get deployment -n nova-staging zookeeper
```

### 2.7 驗證所有服務正常運行

```bash
# 檢查所有 Pod
kubectl get pods -n nova-staging

# 預期輸出（所有 Pod 應為 Running）：
# NAME           READY   STATUS    RESTARTS
# postgres-0     1/1     Running   0
# redis-0        1/1     Running   0
# clickhouse-0   1/1     Running   0
# elasticsearch-0 1/1    Running   0
# kafka-0        1/1     Running   0
# zookeeper-0    1/1     Running   0

# 檢查存儲
kubectl get pvc -n nova-staging

# 預期：所有 PVC 應為 Bound
```

---

## 🚀 第 3 步：部署微服務（5 分鐘）

### 3.1 構建和推送 Docker 鏡像

```bash
# 配置 Docker 認證
gcloud auth configure-docker asia-northeast1-docker.pkg.dev

# 從源代碼構建所有服務
cd backend

# 構建 identity-service
cd identity-service
docker build -t asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/identity-service:latest .
docker push asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/identity-service:latest

# 重複構建其他 13 個服務...
# 或使用批量構建腳本

for service in identity-service realtime-chat-service content-service social-service \
               analytics-service feed-service ranking-service notification-service \
               search-service trust-safety-service streaming-service user-service graph-service; do
  echo "Building $service..."
  cd ../$service
  docker build -t asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/$service:latest .
  docker push asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/$service:latest
  cd ..
done

# 構建 GraphQL Gateway
cd ../graphql-gateway
docker build -t asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/graphql-gateway:latest .
docker push asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/graphql-gateway:latest
```

### 3.2 部署應用

```bash
# 應用所有 Kubernetes 配置
kubectl apply -k k8s/overlays/staging

# 驗證部署
kubectl get deployments -n nova-staging

# 等待所有 Pod 就緒
kubectl wait --for=condition=available --timeout=600s \
  deployment -l app in (identity-service,realtime-chat-service,content-service) \
  -n nova-staging

# 預期：所有 14 個服務都應為 Running
```

### 3.3 驗證應用連接

```bash
# 檢查 identity-service 日誌（驗證 PostgreSQL 連接）
kubectl logs -n nova-staging -l app=identity-service --tail=50

# 預期輸出應包含：
# Connected to PostgreSQL
# Database migration completed
# gRPC server started on port 50051

# 檢查其他服務日誌
kubectl logs -n nova-staging -l app=realtime-chat-service --tail=20
kubectl logs -n nova-staging -l app=analytics-service --tail=20
```

---

## ✅ 第 4 步：驗證部署（5 分鐘）

### 4.1 運行驗證腳本

```bash
cd infrastructure/terraform/gcp/main
./validate-deployment.sh staging

# 預期輸出：
# ✓ Cluster has 2-5 nodes
# ✓ All nodes are Ready
# ✓ PostgreSQL pod is running
# ✓ Redis pod is running
# ✓ ClickHouse pod is running
# ✓ All 14 microservices deployed
```

### 4.2 手動驗證核心功能

#### **測試 PostgreSQL 連接**

```bash
# 進入 PostgreSQL Pod
kubectl exec -it postgres-0 -n nova-staging -- psql -U nova_admin -d nova

# SQL 查詢
SELECT version();
SELECT * FROM users LIMIT 1;
\dt  # 列出所有表

# 預期：能夠連接並查詢數據
```

#### **測試 Redis 連接**

```bash
# 進入 Redis Pod
kubectl exec -it redis-0 -n nova-staging -- redis-cli

# Redis 命令
PING
INFO
GET test-key

# 預期：PONG，INFO 輸出正常
```

#### **測試 gRPC 服務**

```bash
# 使用 grpcurl 測試 identity-service
kubectl port-forward svc/identity-service 50051:50051 -n nova-staging &

grpcurl -plaintext localhost:50051 list

# 預期：列出所有 gRPC 服務
```

#### **測試 GraphQL Gateway**

```bash
# 端口轉發到 GraphQL Gateway
kubectl port-forward svc/graphql-gateway 8080:8080 -n nova-staging &

# 查詢 GraphQL
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ viewer { id email }}"}'

# 預期：返回 GraphQL 響應（可能需要認證）
```

### 4.3 監控資源使用

```bash
# 查看節點資源
kubectl top nodes

# 預期：CPU/Memory 使用合理（<60%）

# 查看 Pod 資源
kubectl top pods -n nova-staging

# 預期：每個 Pod 的資源使用在預期範圍內
```

---

## 🔒 第 5 步：備份和安全設置（5 分鐘）

### 5.1 設置 PostgreSQL 自動備份

```bash
# 創建 Cloud Storage 備份 bucket
gsutil mb gs://nova-staging-backups

# 創建 backup cronjob
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: nova-staging
spec:
  schedule: "0 2 * * *"  # 每天 02:00 UTC
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: postgres-backup
          containers:
          - name: backup
            image: google/cloud-sdk:latest
            command:
            - /bin/bash
            - -c
            - |
              POD_NAME=postgres-0
              BACKUP_NAME=pg-backup-\$(date +%Y%m%d-%H%M%S).sql
              kubectl exec \$POD_NAME -- pg_dump -U postgres nova > /tmp/\$BACKUP_NAME
              gsutil cp /tmp/\$BACKUP_NAME gs://nova-staging-backups/
              rm /tmp/\$BACKUP_NAME
          restartPolicy: OnFailure
EOF

# 驗證 backup 已創建
kubectl get cronjobs -n nova-staging
```

### 5.2 配置監控告警

```bash
# 創建 Prometheus Rule for PostgreSQL
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: postgres-alerts
  namespace: nova-staging
spec:
  groups:
  - name: postgres.rules
    interval: 30s
    rules:
    - alert: PostgreSQLDown
      expr: pg_up == 0
      for: 5m
      annotations:
        summary: "PostgreSQL is down"
    - alert: PostgreSQLHighConnections
      expr: sum(pg_stat_activity_count) > 100
      for: 5m
      annotations:
        summary: "High connection count"
    - alert: PostgreSQLDiskSpace
      expr: pg_database_size_bytes > 450000000000  # 450GB
      annotations:
        summary: "Disk space low"
EOF
```

---

## 📊 部署驗收清單

### 基礎設施

- [ ] GKE 集群已創建（2-5 個節點）
- [ ] 所有 PVC 已綁定
- [ ] Cloud Storage bucket 已創建

### 數據存儲服務

- [ ] PostgreSQL Pod 運行中
  - [ ] 可以連接並執行查詢
  - [ ] 自動備份已配置
  - [ ] 監控告警已啟用

- [ ] Redis Pod 運行中
  - [ ] PING 命令成功
  - [ ] 內存使用 < 50%

- [ ] ClickHouse Pod 運行中
  - [ ] 可以查詢表
  - [ ] CDC 同步工作中

- [ ] Elasticsearch Pod 運行中
  - [ ] 集群健康狀態為 green
  - [ ] 索引正常創建

- [ ] Kafka Pod 運行中
  - [ ] Topic 已創建
  - [ ] Producer/Consumer 工作正常

### 微服務

- [ ] 所有 14 個微服務已部署
- [ ] 所有 Pod 狀態為 Running
- [ ] 沒有 CrashLoopBackOff 或 Pending Pod
- [ ] 日誌中沒有致命錯誤

### 應用功能

- [ ] 身份驗證服務可以連接 PostgreSQL
- [ ] GraphQL Gateway 可以路由到後端服務
- [ ] 實時聊天服務 WebSocket 連接正常
- [ ] 分析服務 CDC 同步工作中

---

## 🔧 故障排查

### Pod 無法啟動

```bash
# 查看 Pod 事件
kubectl describe pod <pod-name> -n nova-staging

# 查看日誌
kubectl logs <pod-name> -n nova-staging
kubectl logs <pod-name> -n nova-staging --previous  # 上一次運行的日誌

# 常見原因：
# - 連接字符串錯誤（環境變數）
# - 鏡像拉取失敗（docker registry 權限）
# - 資源不足（節點 CPU/Memory）
```

### PostgreSQL 無法連接

```bash
# 檢查 StatefulSet 狀態
kubectl describe statefulset postgres -n nova-staging

# 檢查 PVC
kubectl describe pvc postgres-data-postgres-0 -n nova-staging

# 檢查服務發現
kubectl get svc -n nova-staging postgres

# 測試連通性（從另一個 Pod）
kubectl run -it --rm debug --image=postgres:15 --restart=Never -n nova-staging -- \
  psql -h postgres.nova-staging.svc.cluster.local -U nova_admin -d nova -c "SELECT 1"
```

### 磁盤空間不足

```bash
# 檢查 PVC 容量
kubectl get pvc -n nova-staging

# 如果 PostgreSQL 容量不足，擴展 PVC
kubectl patch pvc postgres-data-postgres-0 -n nova-staging \
  -p '{"spec":{"resources":{"requests":{"storage":"1Ti"}}}}'

# 驗證
kubectl get pvc -n nova-staging postgres-data-postgres-0
```

---

## 📈 下一步

### 立即（部署完成後）
1. ✅ 運行全套驗收測試
2. ✅ 進行負載測試（模擬預期流量）
3. ✅ 驗證備份和恢復流程

### 本週
1. ✅ 在 Staging 環境進行集成測試
2. ✅ 收集性能指標
3. ✅ 識別優化機會

### 下週
1. ✅ 根據 Staging 經驗優化配置
2. ✅ 準備 Production 部署

---

**預計總時間**: 30-45 分鐘
**需要的權限**: GCP Owner 角色
**聯絡**: 如有問題，查看故障排查部分


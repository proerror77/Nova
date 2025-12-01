# Nova Staging 部署執行清單

**版本**: 1.0
**狀態**: 準備執行
**預期耗時**: 30-45 分鐘
**架構選擇**: Kubernetes PostgreSQL（已驗證）

---

## ✅ 前置條件檢查

### 1. GCP 環境 (2 分鐘)

```bash
# 驗證 GCP 項目
gcloud config list
# 預期：project = banded-pad-479802-k9

# 驗證認證
gcloud auth list
# 預期：active account 應該是您的 Google 帳戶

# 驗證 IAM 權限（您已有 roles/owner）
gcloud projects get-iam-policy banded-pad-479802-k9 \
  --flatten="bindings[].members" \
  --filter="bindings.members:$(gcloud auth list --filter=status:ACTIVE --format='value(account)')"
# 預期：roles/owner
```

**檢查清單**:
- [ ] GCP 項目正確設置
- [ ] 已認證到正確帳戶
- [ ] 擁有 owner 角色
- [ ] 沒有配額警告

---

### 2. 本地工具 (2 分鐘)

```bash
# Terraform
terraform version
# 預期：>= 1.5.0

# Kubernetes
kubectl version --client
# 預期：>= 1.27

# gcloud CLI
gcloud --version
# 預期：最新版本

# Docker（用於構建映像）
docker --version
# 預期：20.x 或更新
```

**檢查清單**:
- [ ] Terraform >= 1.5.0
- [ ] kubectl >= 1.27
- [ ] gcloud CLI 已安裝
- [ ] Docker 已安裝

---

### 3. 代碼和配置 (2 分鐘)

```bash
# 驗證文件結構
ls -la infrastructure/terraform/gcp/main/
# 預期：main.tf, variables.tf, terraform.tfvars.staging 存在

ls -la k8s/infrastructure/overlays/staging/
# 預期：kustomization.yaml 和相關配置存在

ls -la docs/
# 預期：GCP_ARCHITECTURE_REVISED.md, STAGING_DEPLOYMENT_GUIDE.md 存在
```

**檢查清單**:
- [ ] Terraform 配置文件存在
- [ ] K8s 配置文件存在
- [ ] 部署文檔已準備

---

## 🚀 部署執行步驟

### 第 1 階段：Terraform 狀態設置 (5 分鐘)

```bash
# 進入 Terraform 目錄
cd infrastructure/terraform/gcp/main

# 初始化 Terraform（首次部署必須）
terraform init -backend-config="bucket=nova-terraform-state" \
               -backend-config="prefix=gcp/staging"

# 驗證配置語法
terraform validate
terraform fmt -check

# 查看將要創建的資源
terraform plan -var-file="terraform.tfvars.staging" -out=staging.tfplan

# 審查計劃輸出，確認：
# ✓ GKE 集群創建
# ✓ VPC 和網絡配置
# ✓ IAM 角色設置
# ✓ Artifact Registry 創建

echo "檢查計劃輸出後，按 Enter 繼續..."
read
```

**檢查清單**:
- [ ] Terraform 初始化成功
- [ ] 驗證語法通過
- [ ] 計劃顯示預期資源
- [ ] 沒有警告或錯誤

---

### 第 2 階段：GCP 基礎設施部署 (15 分鐘)

```bash
# 應用 Terraform 配置
terraform apply staging.tfplan

# 等待完成（大約 10-15 分鐘）
# 預期輸出：
# - GKE 集群已創建
# - VPC 和子網已配置
# - Artifact Registry 已創建
# - Service Accounts 已設置

# 獲取 GKE 集群認證
gcloud container clusters get-credentials nova-staging-gke \
  --region=asia-northeast1 \
  --project=banded-pad-479802-k9

# 驗證 kubectl 連接
kubectl cluster-info
kubectl get nodes
# 預期：2-5 個 n2-standard-4 節點處於 Ready 狀態
```

**檢查清單**:
- [ ] Terraform apply 完成
- [ ] kubectl 可以訪問集群
- [ ] 至少 2 個節點處於 Ready 狀態
- [ ] 集群網絡配置正確

---

### 第 3 階段：K8s 數據存儲服務部署 (10 分鐘)

```bash
# 返回项目根目录
cd /Users/proerror/Documents/nova

# 部署 StatefulSet（PostgreSQL, Redis, ClickHouse, Elasticsearch, Kafka）
kubectl apply -k k8s/infrastructure/overlays/staging

# 驗證 Pod 啟動
kubectl get pods -n nova-staging -w
# 預期：所有 Pod 最終進入 Running 或 Completed 狀態

# 檢查特定服務（等待 30-60 秒）
kubectl get statefulset -n nova-staging
# 預期：
# - postgresql-0 Running
# - redis-0 Running
# - clickhouse-0 Running
# - elasticsearch-0 Running
# - kafka-0 Running

# 驗證 PVC 已綁定
kubectl get pvc -n nova-staging
# 預期：所有 PVC 狀態為 Bound
```

**檢查清單**:
- [ ] 所有 StatefulSet Pod 達到 Running 狀態
- [ ] 所有 PVC 狀態為 Bound
- [ ] 沒有 Pod Crash/Pending
- [ ] 存儲空間充足

---

### 第 4 階段：數據庫初始化 (5 分鐘)

```bash
# 驗證 PostgreSQL 連接性
kubectl run -it --rm --image=postgres:15 --restart=Never \
  -n nova-staging psql-test -- \
  psql -h postgresql.nova-staging.svc.cluster.local -U nova -d nova \
  -c "SELECT version();"

# 預期輸出：PostgreSQL 15.x 版本信息

# 檢查數據庫初始化日誌
kubectl logs -n nova-staging postgresql-0 | tail -20

# 驗證 Redis 連接性
kubectl run -it --rm --image=redis:7 --restart=Never \
  -n nova-staging redis-test -- \
  redis-cli -h redis.nova-staging.svc.cluster.local ping

# 預期輸出：PONG
```

**檢查清單**:
- [ ] PostgreSQL 連接成功
- [ ] Redis 連接成功
- [ ] 數據庫初始化完成
- [ ] 沒有連接錯誤

---

### 第 5 階段：微服務部署 (5 分鐘)

```bash
# 構建 Docker 映像（可選：如果本地有源碼）
docker build -t nova-identity-service:latest \
  -f backend/identity-service/Dockerfile \
  backend/identity-service

# 推送到 Artifact Registry
docker tag nova-identity-service:latest \
  asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/identity-service:latest

docker push asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/identity-service:latest

# 應用微服務 Deployment（如果已有映像）
kubectl apply -k k8s/overlays/staging

# 監視部署進度
kubectl rollout status deployment -n nova-staging --timeout=10m

# 檢查所有 Pod
kubectl get pods -n nova-staging
# 預期：所有微服務 Pod 處於 Running 狀態
```

**檢查清單**:
- [ ] Docker 映像已構建和推送
- [ ] 所有 Deployment Pod 達到 Running
- [ ] 沒有 ImagePullBackOff 錯誤
- [ ] CPU/內存請求已設置

---

### 第 6 階段：部署驗證 (3 分鐘)

```bash
# 1. 驗證基礎設施
./docs/validate-deployment.sh staging

# 2. 檢查微服務健康狀況
kubectl get pods -n nova-staging --field-selector=status.phase!=Running

# 3. 檢查服務
kubectl get svc -n nova-staging

# 4. 驗證 gRPC 連接性（內部測試）
kubectl run -it --rm --image=grpcurl:latest --restart=Never \
  -n nova-staging grpc-test -- \
  grpcurl -plaintext identity-service:50051 list

# 5. 檢查日誌查找任何錯誤
kubectl logs -n nova-staging -l app=identity-service --tail=50
kubectl logs -n nova-staging -l app=realtime-chat-service --tail=50
```

**檢查清單**:
- [ ] validate-deployment.sh 通過所有檢查
- [ ] 沒有 Pod 處於 Pending/CrashLoopBackOff 狀態
- [ ] gRPC 端點可訪問
- [ ] 日誌中沒有 ERROR 級別消息
- [ ] 服務發現正常

---

### 第 7 階段：備份和監控設置 (5 分鐘)

```bash
# 1. 設置 PostgreSQL 備份 CronJob
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgresql-backup
  namespace: nova-staging
spec:
  schedule: "0 2 * * *"  # 每天 02:00 執行
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: postgresql-backup
          containers:
          - name: backup
            image: postgres:15
            command:
            - /bin/sh
            - -c
            - pg_dump -h postgresql.nova-staging.svc.cluster.local -U nova nova | gzip > /backups/nova-\$(date +%Y%m%d-%H%M%S).sql.gz
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
          volumes:
          - name: backup-storage
            emptyDir: {}
          restartPolicy: OnFailure
EOF

# 2. 驗證 CronJob 創建
kubectl get cronjob -n nova-staging

# 3. 設置基本監控警報（可選）
kubectl apply -f k8s/infrastructure/overlays/staging/prometheus-rules.yaml

# 4. 檢查 metrics-server（用於 HPA）
kubectl get deployment metrics-server -n kube-system
```

**檢查清單**:
- [ ] 備份 CronJob 已創建
- [ ] Prometheus rules 已部署
- [ ] metrics-server 正在運行
- [ ] 可以訪問監控儀表板

---

## 📊 預期最終狀態

### GCP 資源
```
GKE 集群: nova-staging-gke
├─ 節點: 2-5 x n2-standard-4
├─ VPC: nova-vpc
├─ 子網: 10.0.0.0/20
└─ Artifact Registry: nova-docker-repo

可用區: asia-northeast1
```

### Kubernetes 資源
```
nova-staging 命名空間:
├─ StatefulSets:
│  ├─ postgresql
│  ├─ redis
│  ├─ clickhouse
│  ├─ elasticsearch
│  └─ kafka
├─ Deployments:
│  ├─ identity-service
│  ├─ realtime-chat-service
│  ├─ social-service
│  ├─ content-service
│  └─ 9 個其他微服務
└─ Services:
   ├─ postgresql (內部)
   ├─ redis (內部)
   └─ ... 所有 gRPC 服務
```

### 預期 Pod 數量
```
StatefulSets: 5 個 Pod
Deployments: 14 個 Pod（微服務）
CronJobs: 1 個（PostgreSQL 備份）
────────────────────
總計: 20+ 個 Pod（Running 狀態）
```

---

## 🆘 常見問題排查

### 問題 1：Terraform 初始化失敗

```bash
# 錯誤：backend initialization failed

# 解決方案：
# 1. 確保 Cloud Storage bucket 已創建
gsutil mb gs://nova-terraform-state

# 2. 啟用版本控制
gsutil versioning set on gs://nova-terraform-state

# 3. 重試初始化
terraform init -backend-config="bucket=nova-terraform-state" \
               -backend-config="prefix=gcp/staging"
```

### 問題 2：GKE 節點無法啟動

```bash
# 錯誤：nodes not ready

# 檢查：
gcloud container clusters describe nova-staging-gke \
  --region=asia-northeast1 \
  --format='value(status)'

# 可能原因：
# - 配額不足：檢查 compute.googleapis.com 配額
# - 網絡問題：檢查 VPC 和防火牆規則
# - 等待 10-15 分鐘（首次部署較慢）
```

### 問題 3：PostgreSQL Pod Crash

```bash
# 檢查日誌
kubectl logs -n nova-staging postgresql-0 --previous

# 可能原因：
# - 磁盤空間不足：擴展 PVC
# - 初始化錯誤：檢查 initdb 配置
# - 內存不足：增加節點資源

# 解決方案：
kubectl delete pod postgresql-0 -n nova-staging
# Pod 會自動重啟
```

### 問題 4：微服務無法連接 PostgreSQL

```bash
# 檢查 DNS 解析
kubectl run -it --rm --image=busybox --restart=Never \
  -n nova-staging dns-test -- \
  nslookup postgresql.nova-staging.svc.cluster.local

# 檢查網絡策略
kubectl get networkpolicies -n nova-staging

# 檢查 Service
kubectl get svc postgresql -n nova-staging -o wide

# 驗證連接字符串
# postgresql://nova:password@postgresql.nova-staging.svc.cluster.local:5432/nova
```

---

## ⏱️ 時間表估算

| 階段 | 任務 | 預期耗時 |
|------|------|---------|
| 1 | Terraform 狀態設置 | 5 分鐘 |
| 2 | GCP 基礎設施部署 | 15 分鐘 |
| 3 | K8s 數據存儲部署 | 10 分鐘 |
| 4 | 數據庫初始化驗證 | 5 分鐘 |
| 5 | 微服務部署 | 5 分鐘 |
| 6 | 部署驗證 | 3 分鐘 |
| 7 | 備份監控設置 | 5 分鐘 |
| **總計** | | **45-60 分鐘** |

---

## ✨ 下一步

部署完成後：

1. **測試應用**
   ```bash
   # 運行集成測試
   kubectl run -it --rm --image=curling --restart=Never \
     -n nova-staging curl-test -- \
     curl http://graphql-gateway:8080/graphql
   ```

2. **監控應用**
   ```bash
   # 設置日誌聚合（Stackdriver）
   kubectl apply -k k8s/infrastructure/overlays/staging/logging
   ```

3. **準備生產部署**
   ```bash
   # 執行相同步驟，但使用 production 配置
   ./deploy.sh production plan
   ```

---

**狀態**: ✅ 準備執行
**下一步**: 運行第 1 階段 - Terraform 狀態設置
**預期完成**: 1 小時內


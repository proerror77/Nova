# Nova Staging 部署快速參考卡

**打印本頁面或保存為 PDF，在部署時使用**

---

## 🚀 部署命令速查

### 第 1 階段：Terraform (5 分鐘)
```bash
cd infrastructure/terraform/gcp/main

terraform init -backend-config="bucket=nova-terraform-state" \
               -backend-config="prefix=gcp/staging"

terraform plan -var-file="terraform.tfvars.staging" -out=staging.tfplan
terraform apply staging.tfplan

gcloud container clusters get-credentials nova-staging-gke \
  --region=asia-northeast1 \
  --project=banded-pad-479802-k9
```

### 第 2 階段：K8s 存儲服務 (10 分鐘)
```bash
cd /Users/proerror/Documents/nova

kubectl apply -k k8s/infrastructure/overlays/staging

# 監視 Pod 啟動
kubectl get pods -n nova-staging -w
```

### 第 3 階段：驗證 (5 分鐘)
```bash
# 驗證數據庫
kubectl run -it --rm --image=postgres:15 --restart=Never \
  -n nova-staging psql-test -- \
  psql -h postgresql.nova-staging.svc.cluster.local -U nova -d nova \
  -c "SELECT version();"

# 驗證 Redis
kubectl run -it --rm --image=redis:7 --restart=Never \
  -n nova-staging redis-test -- \
  redis-cli -h redis.nova-staging.svc.cluster.local ping

# 驗證部署
kubectl get pods -n nova-staging
```

---

## 🔍 常用診斷命令

### 查看資源狀態
```bash
# 所有 Pod
kubectl get pods -n nova-staging

# 所有 Service
kubectl get svc -n nova-staging

# 所有 StatefulSet
kubectl get statefulset -n nova-staging

# 所有 PVC
kubectl get pvc -n nova-staging
```

### 查看日誌
```bash
# 特定 Pod 的日誌
kubectl logs -n nova-staging postgresql-0

# 查看上一個容器的日誌（Crash）
kubectl logs -n nova-staging postgresql-0 --previous

# 實時跟蹤日誌
kubectl logs -n nova-staging postgresql-0 -f

# 所有微服務的日誌
kubectl logs -n nova-staging -l app=identity-service --all-containers=true
```

### 執行命令進入 Pod
```bash
# 進入 PostgreSQL Pod
kubectl exec -it -n nova-staging postgresql-0 -- psql -U nova -d nova

# 進入 Redis Pod
kubectl exec -it -n nova-staging redis-0 -- redis-cli

# 進入任何 Pod 的 shell
kubectl exec -it -n nova-staging <pod-name> -- /bin/sh
```

### 描述資源問題
```bash
# 詳細信息
kubectl describe pod -n nova-staging postgresql-0

# 查看事件
kubectl get events -n nova-staging --sort-by='.lastTimestamp'

# 查看特定故障
kubectl describe pod -n nova-staging <pod-name> | grep -A 20 "Events:"
```

---

## 🔧 常見故障排查

| 症狀 | 命令 | 預期結果 |
|------|------|---------|
| Pod 未啟動 | `kubectl get pods -n nova-staging` | Status = Running |
| Pod 崩潰 | `kubectl logs -n nova-staging <pod> --previous` | 查看錯誤信息 |
| 連接超時 | `kubectl exec -it <pod> -- ping <service>` | 收到 ping 回應 |
| 磁盤滿 | `kubectl exec -it postgresql-0 -- df -h` | 可用空間 > 10% |
| 內存不足 | `kubectl top nodes` | 可用內存充足 |
| Network 問題 | `kubectl get networkpolicies -n nova-staging` | 檢查策略 |

---

## 📊 健康檢查清單

### 基礎設施層
- [ ] `gcloud compute instances list` - 節點正在運行
- [ ] `kubectl get nodes` - 所有節點 Ready
- [ ] `kubectl get pvc -n nova-staging` - 所有 PVC Bound

### 數據存儲層
- [ ] PostgreSQL 連接成功（psql 測試）
- [ ] Redis 連接成功（redis-cli ping）
- [ ] ClickHouse HTTP 端點可訪問

### 應用層
- [ ] 所有微服務 Pod Running
- [ ] gRPC 端點可訪問
- [ ] 沒有 ImagePullBackOff 錯誤

### 監控和備份
- [ ] Prometheus 收集指標
- [ ] PostgreSQL 備份 CronJob 已創建
- [ ] Logging 已配置

---

## 🚨 P0 緊急情況

### PostgreSQL Pod 無法啟動
```bash
# 檢查存儲
kubectl get pvc -n nova-staging postgresql-data
# 如果 Pending，可能是節點磁盤滿

# 檢查節點資源
kubectl top nodes
kubectl describe node <node-name>

# 最後手段：重新初始化
kubectl delete pvc postgresql-data -n nova-staging
kubectl apply -k k8s/infrastructure/overlays/staging
```

### 所有 Pod 崩潰
```bash
# 檢查集群狀態
kubectl cluster-info
kubectl get nodes

# 檢查配額
gcloud compute project-info describe --project=banded-pad-479802-k9

# 檢查 API 服務
kubectl get cs
```

### 無法連接到集群
```bash
# 重新獲取認證
gcloud container clusters get-credentials nova-staging-gke \
  --region=asia-northeast1

# 驗證上下文
kubectl config current-context
kubectl config use-context gke_banded-pad-479802-k9_asia-northeast1_nova-staging-gke
```

---

## 💾 備份和恢復

### 手動備份
```bash
# PostgreSQL 備份
kubectl exec -n nova-staging postgresql-0 -- \
  pg_dump -U nova nova | gzip > nova-backup-$(date +%Y%m%d).sql.gz

# 上傳到 GCS
gsutil cp nova-backup-*.sql.gz gs://nova-backups/staging/
```

### 恢復
```bash
# 從備份恢復
gunzip < nova-backup-20240101.sql.gz | \
  kubectl exec -i -n nova-staging postgresql-0 -- \
  psql -U nova nova
```

---

## 📈 性能監控

### 檢查資源使用
```bash
# CPU 和內存
kubectl top pods -n nova-staging
kubectl top nodes

# 磁盤使用
kubectl exec -n nova-staging postgresql-0 -- du -sh /var/lib/postgresql/data
```

### 查看 Prometheus 指標
```bash
# Port forward
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# 訪問 http://localhost:9090
# 查詢：
# - postgresql_queries_total
# - redis_connected_clients
# - container_memory_usage_bytes
```

---

## 🔐 安全檢查

### 驗證網絡隔離
```bash
# 檢查 NetworkPolicy
kubectl get networkpolicies -n nova-staging

# 檢查 Service 類型（應該是 ClusterIP，不是 LoadBalancer）
kubectl get svc -n nova-staging

# 驗證 Pod 之間的連接性
kubectl run -it --rm --image=busybox --restart=Never \
  -n nova-staging test -- wget -O- http://postgresql:5432
```

### 檢查 Secret
```bash
# 列出 Secret
kubectl get secrets -n nova-staging

# 驗證 Secret 已掛載
kubectl describe pod -n nova-staging postgresql-0 | grep -A 5 "Mounts:"
```

---

## 📞 支持資源

### 文檔
- 完整架構: `docs/GCP_ARCHITECTURE_REVISED.md`
- 部署指南: `docs/STAGING_DEPLOYMENT_GUIDE.md`
- 部署清單: `docs/DEPLOYMENT_CHECKLIST.md`
- 快速參考: `docs/QUICK_REFERENCE.md`（本文件）

### GCP 相關
- GKE 文檔: https://cloud.google.com/kubernetes-engine/docs
- GCP 控制台: https://console.cloud.google.com/kubernetes
- 項目 ID: `banded-pad-479802-k9`
- 區域: `asia-northeast1`

### Kubernetes
- kubectl 文檔: https://kubernetes.io/docs/
- 故障排查: https://kubernetes.io/docs/tasks/debug-application-cluster/

---

**最後更新**: 2025-11-30
**部署狀態**: 準備執行
**預期完成時間**: 45-60 分鐘


# 本地 Kubernetes 部署指南（Minikube / Kind）

## 概述

本指南介紹如何在本地開發環境部署完整的 Nova 後端系統到 Kubernetes。

基於架構評審，此配置解決了以下關鍵問題：
- ✅ Redis 單點故障 → Redis Sentinel (3 副本自動轉移)
- ✅ PostgreSQL 共享 → 數據庫隔離 + Schema 分割
- ✅ 跨服務通信無超時 → 3s 超時配置 + 熔斷器
- ✅ CDC 無恰好一次語義 → (需在 Kafka 層配置，見下文)

---

## 前置條件

### 系統要求
```bash
# 最低配置
- CPU: 4 核心
- 內存: 8GB
- 磁盤: 30GB 空間

# 推薦配置
- CPU: 8+ 核心
- 內存: 16GB
- 磁盤: 50GB+ SSD
```

### 安裝必要工具

#### 1. Minikube（推薦用於單機開發）
```bash
# macOS
brew install minikube

# Linux
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# 啟動 Minikube 集群（分配 8GB 內存、4 核 CPU）
minikube start --cpus 4 --memory 8192 --disk-size 30gb
```

#### 2. Kind（推薦用於 CI/CD）
```bash
# 安裝
go install sigs.k8s.io/kind@latest

# 創建集群 (使用本目錄的 kind-config.yaml)
kind create cluster --config kind-config.yaml --name nova-dev
```

#### 3. kubectl
```bash
# 安裝
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# 驗證
kubectl version --client
```

---

## 快速開始（5 分鐘）

### 步驟 1：檢查集群連接
```bash
kubectl cluster-info
kubectl get nodes
```

### 步驟 2：運行部署腳本
```bash
cd backend/k8s

# 部署所有組件
./deploy-local-k8s.sh deploy

# 監視部署進度
watch kubectl get pods -n nova-services
```

### 步驟 3：驗證部署
```bash
# 查看所有 Pod
kubectl get pods -A

# 檢查服務
kubectl get svc -n nova-services

# 查看日誌
kubectl logs -f -l app=user-service -n nova-services
```

### 步驟 4：訪問服務
```bash
# 端口轉發到本地
kubectl port-forward svc/user-service 8080:8080 -n nova-services

# 另一個終端測試
curl http://localhost:8080/health
```

---

## 詳細部署步驟

### 第 1 部分：準備環境

#### 1.1 創建 Kind 集群（如果使用 Kind）
```bash
# 創建集群配置
cat > kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
  - role: worker
  - role: worker
EOF

# 創建集群
kind create cluster --config kind-config.yaml --name nova-dev

# 切換上下文
kubectl cluster-info --context kind-nova-dev
```

#### 1.2 為 Minikube 啟用插件（可選）
```bash
# 啟用指標服務器（用於 HPA）
minikube addons enable metrics-server

# 啟用 Ingress
minikube addons enable ingress

# 查看所有插件
minikube addons list
```

#### 1.3 配置存儲類
```bash
# 檢查默認存儲類
kubectl get storageclass

# 如果沒有，為 Minikube 創建
kubectl create -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: k8s.io/minikube-hostpath
EOF
```

### 第 2 部分：部署基礎設施

#### 2.1 部署 Redis Sentinel
```bash
# 應用配置
kubectl apply -f redis-sentinel-statefulset.yaml

# 監控 Pod
kubectl get pods -n nova-redis -w

# 等待 StatefulSet 就緒
kubectl wait --for=condition=ready pod -l app=redis -n nova-redis --timeout=300s

# 測試連接
kubectl port-forward svc/redis-sentinel 6379:6379 -n nova-redis &
redis-cli -h localhost -a redis_password_change_me ping
```

#### 2.2 部署 PostgreSQL HA
```bash
# 應用配置
kubectl apply -f postgres-ha-statefulset.yaml

# 監控
kubectl get pods -n nova-database -w

# 等待 Ready
kubectl wait --for=condition=ready pod -l app=postgres -n nova-database --timeout=600s

# 測試連接
kubectl port-forward svc/postgres-primary 5432:5432 -n nova-database &
psql -h localhost -U postgres -d nova_core -c "SELECT version();"
```

### 第 3 部分：部署微服務

#### 3.1 應用敏感數據（Secrets）
```bash
# 編輯敏感信息（重要！）
vi microservices-secrets.yaml

# 關鍵需要更新：
# - app_password_change_me
# - redis_password_change_me
# - jwt-secret
# - 其他服務密鑰

# 應用
kubectl apply -f microservices-secrets.yaml
```

#### 3.2 部署微服務
```bash
# 應用配置
kubectl apply -f microservices-deployments.yaml

# 監控部署
kubectl get deploy -n nova-services -w

# 等待所有 Pod Ready
kubectl wait --for=condition=ready pod -l component=social -n nova-services --timeout=300s
```

#### 3.3 驗證微服務狀態
```bash
# 查看所有 Pod
kubectl get pods -n nova-services -o wide

# 檢查 Pod 事件（如果有失敗）
kubectl describe pod <pod-name> -n nova-services

# 查看日誌
kubectl logs <pod-name> -n nova-services --tail=100 -f
```

### 第 4 部分：測試和驗證

#### 4.1 本地訪問服務
```bash
# 端口轉發（每個服務一個終端）

# user-service
kubectl port-forward svc/user-service 8080:8080 -n nova-services &

# auth-service
kubectl port-forward svc/auth-service 8084:8084 -n nova-services &

# messaging-service
kubectl port-forward svc/messaging-service 3000:3000 -n nova-services &

# search-service
kubectl port-forward svc/search-service 8086:8086 -n nova-services &
```

#### 4.2 測試 API
```bash
# user-service 健康檢查
curl -i http://localhost:8080/health

# auth-service 健康檢查
curl -i http://localhost:8084/health

# 查看實際響應
curl http://localhost:8080/api/v1/users/me -H "Authorization: Bearer <token>"
```

#### 4.3 檢查 Redis 連接
```bash
# 連接到 Redis Sentinel
kubectl port-forward svc/redis-sentinel 6379:6379 -n nova-redis &
redis-cli -h localhost -a redis_password_change_me

# 查看 Sentinel 狀態
SENTINEL masters

# 查看 Redis 複製狀態
replicaof ? no one  # 查看主從狀態
```

#### 4.4 檢查 PostgreSQL 複製
```bash
# 連接到 PostgreSQL
kubectl port-forward svc/postgres-primary 5432:5432 -n nova-database &

psql -h localhost -U app_user -d nova_core << EOF
-- 檢查複製狀態
SELECT slot_name, restart_lsn FROM pg_replication_slots;

-- 查看連接的副本
SELECT * FROM pg_stat_replication;
EOF
```

---

## 架構驗證清單

完成部署後，驗證以下架構改進：

### Redis 高可用性
- [ ] 3 個 Redis Pod 運行在不同節點
- [ ] Redis Sentinel 正常工作
- [ ] 手動終止 master，檢查是否自動轉移
```bash
# 測試故障轉移
kubectl delete pod redis-master-0 -n nova-redis
# 等待並檢查 Sentinel 轉移
kubectl logs -l app=redis,component=master -n nova-redis -f
```

### PostgreSQL 高可用性
- [ ] 3 個 PostgreSQL Pod 運行在不同節點
- [ ] etcd 集群正常
- [ ] 複製延遲在 100ms 以內
```bash
# 檢查複製延遲
kubectl exec -it postgres-0 -n nova-database -- \
  psql -U postgres -c "SELECT slot_name, confirmed_flush_lsn FROM pg_replication_slots;"
```

### 微服務隔離
- [ ] 每個微服務在單獨的 Pod 中
- [ ] 資源限制獨立（CPU、內存）
- [ ] Pod 在不同節點分布
```bash
# 驗證 Pod 分布
kubectl get pods -n nova-services -o wide | grep -E "node-|worker"
```

### 跨服務通信
- [ ] 所有微服務能相互通信
- [ ] 超時配置生效（3s）
- [ ] 熔斷器正常工作
```bash
# 測試通信
kubectl exec -it <user-service-pod> -n nova-services -- \
  curl -v http://messaging-service.nova-services.svc.cluster.local:3000/health
```

---

## 常見問題和故障排查

### 問題 1：Pod 一直處於 Pending 狀態
```bash
# 原因 1：存儲類不可用
kubectl describe pvc <pvc-name> -n <namespace>

# 解決方案
kubectl create -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: k8s.io/minikube-hostpath
EOF

# 原因 2：節點資源不足
kubectl describe node

# 解決方案：增加 Minikube 資源
minikube delete
minikube start --cpus 8 --memory 16384
```

### 問題 2：Redis / PostgreSQL 無法連接
```bash
# 檢查 Pod 狀態
kubectl describe pod <pod-name> -n nova-redis

# 檢查日誌
kubectl logs <pod-name> -n nova-redis

# 檢查 Secret
kubectl get secret -n nova-redis
kubectl describe secret redis-credentials -n nova-redis
```

### 問題 3：微服務無法訪問 Redis / PostgreSQL
```bash
# 檢查 DNS 解析
kubectl exec -it <pod-name> -n nova-services -- nslookup redis-sentinel.nova-redis.svc.cluster.local

# 測試連接
kubectl exec -it <pod-name> -n nova-services -- \
  curl -v http://redis-sentinel.nova-redis.svc.cluster.local:6379

# 檢查 Network Policy
kubectl get networkpolicies -n nova-services
```

### 問題 4：內存不足
```bash
# 檢查節點內存
kubectl top nodes

# 檢查 Pod 內存使用
kubectl top pods -n nova-services

# 降低資源限制（僅限開發環境）
kubectl set resources deployment user-service \
  -c=user-service \
  --limits=cpu=1000m,memory=1Gi \
  --requests=cpu=250m,memory=256Mi \
  -n nova-services
```

---

## 清理和重置

### 清理所有資源
```bash
# 使用脚本
./deploy-local-k8s.sh cleanup

# 或手動清理
kubectl delete namespace nova-services nova-database nova-redis
```

### 重置集群
```bash
# Minikube
minikube delete

# Kind
kind delete cluster --name nova-dev
```

---

## 性能優化和監控

### 監控資源使用
```bash
# 實時查看
kubectl top pods -A --containers

# 查看 Pod 事件
kubectl get events -n nova-services --sort-by='.lastTimestamp'

# 監控持續運行
watch -n 2 'kubectl top pods -n nova-services; echo "---"; kubectl top nodes'
```

### 啟用 Prometheus 監控（可選）
```bash
# 安裝 Prometheus Operator
kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.68.0/bundle.yaml

# 應用 Prometheus 配置
kubectl apply -f prometheus-monitoring-setup.yaml
```

---

## 生產部署注意事項

本配置用於本地開發。生產部署需要：

1. **Secrets 管理**
   - 使用 HashiCorp Vault 或 AWS Secrets Manager
   - 不在 YAML 中存儲密碼
   - 使用 Sealed Secrets 或 External Secrets

2. **持久化存儲**
   - 使用 EBS、NFS 或其他雲存儲
   - 配置定期備份
   - 測試災難恢復

3. **高可用性**
   - 配置多可用區
   - 設置負載均衡器
   - 配置 Ingress Controller

4. **監控和告警**
   - 部署 Prometheus + Grafana
   - 配置告警規則
   - 設置中央日誌聚合（ELK / Loki）

5. **安全性**
   - 啟用 RBAC
   - 配置 Network Policies
   - 使用 Pod Security Policies
   - 掃描容器漏洞

---

## 相關文件

| 文件 | 用途 |
|------|------|
| `redis-sentinel-statefulset.yaml` | Redis Sentinel 部署 |
| `postgres-ha-statefulset.yaml` | PostgreSQL HA 部署 |
| `microservices-deployments.yaml` | 微服務 Deployment |
| `microservices-secrets.yaml` | 敏感數據管理 |
| `deploy-local-k8s.sh` | 自動化部署腳本 |

---

## 下一步

1. **本地開發工作流**
   - 修改代碼 → `make build` → 更新鏡像 → `kubectl rollout restart`

2. **集成 CI/CD**
   - GitHub Actions / GitLab CI
   - 自動構建和推送鏡像
   - 自動部署到開發集群

3. **設置 ArgoCD**
   - GitOps 管理（見 gitops-argocd-setup.yaml）
   - 自動同步配置

4. **遷移到生產**
   - 遷移到 EKS / AKS / GKE
   - 配置生產級別的 secrets 管理
   - 設置備份和災難恢復

---

## 快速參考命令

```bash
# 部署
./deploy-local-k8s.sh deploy

# 查看狀態
./deploy-local-k8s.sh status
kubectl get pods -A

# 查看日誌
./deploy-local-k8s.sh logs user-service
kubectl logs -f -l app=user-service -n nova-services

# 端口轉發
kubectl port-forward svc/user-service 8080:8080 -n nova-services

# 執行命令
kubectl exec -it <pod> -n nova-services -- /bin/sh

# 清理
./deploy-local-k8s.sh cleanup
```

---

## 支持和反饋

如遇到問題，請：

1. 查看 Pod 日誌
2. 檢查事件
3. 驗證 Secrets 和 ConfigMaps
4. 檢查節點資源

---

**最後更新**: 2024-10-28
**版本**: 1.0

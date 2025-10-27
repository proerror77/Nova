# Kubernetes 快速開始卡片

## 前置條件檢查清單

```bash
# 1. 安裝必要工具
command -v kubectl          # kubectl 應已安裝
command -v minikube         # (可選) Minikube
command -v kind             # (可選) Kind
command -v redis-cli        # (可選) Redis CLI
command -v psql             # (可選) PostgreSQL CLI

# 2. 驗證集群連接
kubectl cluster-info
kubectl get nodes

# 3. 檢查存儲類
kubectl get storageclass
```

---

## 一鍵部署（推薦）

```bash
cd nova/backend/k8s

# 部署所有組件（Redis + PostgreSQL + 微服務）
./deploy-local-k8s.sh deploy

# 監控部署進度
watch kubectl get pods -A

# 驗證完成
./deploy-local-k8s.sh status
```

---

## 手動逐步部署

```bash
# 1. 創建命名空間
kubectl create namespace nova-redis
kubectl create namespace nova-database
kubectl create namespace nova-services

# 2. 部署基礎設施
kubectl apply -f redis-sentinel-statefulset.yaml
kubectl apply -f postgres-ha-statefulset.yaml
kubectl wait --for=condition=ready pod -l app=redis -n nova-redis --timeout=300s
kubectl wait --for=condition=ready pod -l app=postgres -n nova-database --timeout=600s

# 3. 部署微服務
kubectl apply -f microservices-secrets.yaml
kubectl apply -f microservices-deployments.yaml
kubectl wait --for=condition=ready pod -l app=user-service -n nova-services --timeout=300s

# 4. 驗證
kubectl get pods -A
kubectl get svc -n nova-services
```

---

## 本地訪問服務（端口轉發）

```bash
# 開啟多個終端窗口

# 終端 1: user-service
kubectl port-forward svc/user-service 8080:8080 -n nova-services

# 終端 2: auth-service
kubectl port-forward svc/auth-service 8084:8084 -n nova-services

# 終端 3: messaging-service
kubectl port-forward svc/messaging-service 3000:3000 -n nova-services

# 終端 4: search-service
kubectl port-forward svc/search-service 8086:8086 -n nova-services

# 終端 5: streaming-api
kubectl port-forward svc/streaming-api 8081:8081 -n nova-services

# 終端 6: Redis
kubectl port-forward svc/redis-sentinel 6379:6379 -n nova-redis

# 終端 7: PostgreSQL
kubectl port-forward svc/postgres-primary 5432:5432 -n nova-database
```

---

## 測試 API

```bash
# 健康檢查
curl -i http://localhost:8080/health
curl -i http://localhost:8084/health
curl -i http://localhost:3000/health
curl -i http://localhost:8086/health
curl -i http://localhost:8081/health

# 獲取用戶信息
curl -i http://localhost:8080/api/v1/users/me \
  -H "Authorization: Bearer <your-token>"

# 測試搜索
curl -i http://localhost:8086/api/v1/search \
  -d '{"query":"test"}' \
  -H "Content-Type: application/json"
```

---

## 測試數據庫連接

```bash
# Redis
kubectl port-forward svc/redis-sentinel 6379:6379 -n nova-redis &
redis-cli -a redis_password_change_me ping

# PostgreSQL
kubectl port-forward svc/postgres-primary 5432:5432 -n nova-database &
psql -h localhost -U app_user -d nova_core -c "SELECT version();"

# 查看複製狀態
psql -h localhost -U app_user -d nova_core << EOF
SELECT * FROM pg_stat_replication;
EOF

# 查看 Redis 複製狀態
redis-cli -a redis_password_change_me info replication
```

---

## 常用 kubectl 命令

```bash
# 查看資源
kubectl get pods                           # 當前命名空間的 Pod
kubectl get pods -n nova-services          # 指定命名空間
kubectl get pods -A                        # 所有命名空間
kubectl get svc -n nova-services           # 服務
kubectl get pvc -n nova-database           # 持久化卷
kubectl get nodes                          # 節點

# 詳細信息
kubectl describe pod <pod-name> -n <ns>    # Pod 詳情
kubectl describe node <node-name>          # 節點詳情
kubectl describe pvc <pvc-name> -n <ns>    # 卷詳情

# 日誌
kubectl logs <pod-name> -n <ns>            # Pod 日誌
kubectl logs -f <pod-name> -n <ns>         # 實時日誌
kubectl logs -l app=user-service -n nova-services  # 標籤選擇

# 執行命令
kubectl exec -it <pod-name> -n <ns> -- /bin/sh    # 進入 Pod
kubectl exec -it <pod-name> -n <ns> -- curl ...   # 執行命令

# 資源使用
kubectl top nodes                          # 節點資源
kubectl top pods -n nova-services          # Pod 資源

# 修改資源
kubectl scale deployment user-service --replicas=5 -n nova-services
kubectl set image deployment/user-service \
  user-service=nova/user-service:v2 -n nova-services
kubectl rollout status deployment/user-service -n nova-services

# 刪除資源
kubectl delete pod <pod-name> -n <ns>
kubectl delete deployment user-service -n nova-services
kubectl delete namespace nova-services
```

---

## 故障排查快速檢查

```bash
# Pod 未啟動？
kubectl describe pod <pod-name> -n nova-services
kubectl logs <pod-name> -n nova-services

# 無法連接資源？
kubectl get svc -n nova-redis              # Redis 服務存在？
kubectl get svc -n nova-database           # PostgreSQL 服務存在？
kubectl exec -it <pod> -n nova-services -- nslookup redis-sentinel.nova-redis

# 內存不足？
kubectl top nodes
kubectl top pods -n nova-services

# 存儲問題？
kubectl get pvc -A
kubectl describe pvc <pvc-name> -n <ns>

# 網絡問題？
kubectl get networkpolicies -n nova-services
kubectl get svc -n nova-services
```

---

## 監控和日誌

```bash
# 實時監控
watch kubectl get pods -n nova-services
watch kubectl top pods -n nova-services

# 查看事件
kubectl get events -n nova-services --sort-by='.lastTimestamp'
kubectl describe pod <pod-name> -n nova-services

# 查看所有日誌
kubectl logs -f -l app=user-service -n nova-services --all-containers=true

# 查看特定日誌
kubectl logs <pod-name> -n nova-services --previous  # 前一個容器的日誌
kubectl logs <pod-name> -n nova-services -c <container>  # 特定容器
```

---

## 清理和重置

```bash
# 查看要清理的資源
kubectl get all -n nova-services
kubectl get all -n nova-database
kubectl get all -n nova-redis

# 清理微服務
kubectl delete namespace nova-services

# 清理數據庫
kubectl delete namespace nova-database

# 清理 Redis
kubectl delete namespace nova-redis

# 重置 Minikube 集群
minikube delete
minikube start --cpus 4 --memory 8192

# 重置 Kind 集群
kind delete cluster --name nova-dev
kind create cluster --name nova-dev
```

---

## 配置 Minikube

```bash
# 啟動 Minikube（推薦配置）
minikube start \
  --cpus 4 \
  --memory 8192 \
  --disk-size 30gb \
  --driver=docker

# 啟用插件
minikube addons enable metrics-server     # 用於 HPA
minikube addons enable ingress             # Ingress Controller
minikube addons enable dashboard           # Kubernetes 儀表板

# 開啟儀表板
minikube dashboard

# 檢查狀態
minikube status
minikube config view
```

---

## 配置 Kind

```bash
# 創建集群配置（kind-config.yaml）
cat > kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
      - containerPort: 443
        hostPort: 443
  - role: worker
  - role: worker
  - role: worker
EOF

# 創建集群
kind create cluster --config kind-config.yaml --name nova-dev

# 查看集群列表
kind get clusters

# 刪除集群
kind delete cluster --name nova-dev
```

---

## 性能優化命令

```bash
# 查看 Pod 資源使用
kubectl top pods -n nova-services --containers

# 查看節點資源
kubectl top nodes

# 實時監控資源
watch -n 2 'kubectl top pods -n nova-services; echo "---"; kubectl top nodes'

# 調整資源限制（開發環境）
kubectl set resources deployment user-service \
  -c=user-service \
  --requests=cpu=250m,memory=256Mi \
  --limits=cpu=1000m,memory=1Gi \
  -n nova-services

# 查看 HPA 狀態
kubectl get hpa -n nova-services
kubectl describe hpa user-service-hpa -n nova-services
watch kubectl get hpa user-service-hpa -n nova-services
```

---

## 生產級別檢查

```bash
# 1. 驗證高可用性
kubectl get statefulset -n nova-redis
kubectl get statefulset -n nova-database
kubectl get deployment -n nova-services

# 2. 驗證備份
kubectl get pvc -A
kubectl describe pvc postgres-data-postgres-0 -n nova-database

# 3. 驗證安全性
kubectl get rbac -n nova-services
kubectl get networkpolicies -n nova-services
kubectl get secrets -n nova-services

# 4. 驗證監控
kubectl get prometheus
kubectl get alertmanagerconfig
```

---

## 故障轉移測試

```bash
# 測試 Redis 故障轉移
kubectl delete pod redis-master-0 -n nova-redis
# 觀察：Sentinel 應自動提升一個副本為 master
watch kubectl get pods -n nova-redis

# 查看轉移日誌
kubectl logs -f redis-master-0 -n nova-redis

# 測試 PostgreSQL 故障轉移
kubectl delete pod postgres-0 -n nova-database
# PostgreSQL 會重新同步數據
watch kubectl get pods -n nova-database
```

---

## 環境變量快速參考

```bash
# 設置默認命名空間
kubectl config set-context --current --namespace=nova-services

# 查看當前上下文
kubectl config current-context

# 切換上下文
kubectl config use-context minikube
kubectl config use-context docker-desktop
kubectl config use-context kind-nova-dev

# 列出所有上下文
kubectl config get-contexts
```

---

## 常用別名（可選）

```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
alias kns='kubectl config set-context --current --namespace'
alias kgp='kubectl get pods -A'
alias kgs='kubectl get svc -A'
alias kgd='kubectl get deploy -A'

# 使用示例
k get pods -n nova-services
kg svc -n nova-database
kl -f user-service-pod -n nova-services
ke user-service-pod -n nova-services -- /bin/sh
```

---

## 常見報錯和解決方案

```bash
# 錯誤: Pod pending
→ kubectl describe pod 查看事件
→ kubectl get pvc 檢查持久化卷
→ 可能原因：存儲類不可用，資源不足

# 錯誤: CrashLoopBackOff
→ kubectl logs --previous 查看前一個容器日誌
→ 檢查 Secret 和 ConfigMap 是否正確

# 錯誤: ImagePullBackOff
→ 檢查鏡像是否存在：docker images
→ 檢查鏡像名稱是否正確

# 錯誤: Connection timeout
→ kubectl exec 進入 Pod
→ 運行 nslookup 檢查 DNS
→ 檢查 NetworkPolicy 是否阻止

# 錯誤: Disk space low
→ kubectl get pvc 列出所有卷
→ docker system prune -a 清理本地
→ 增加 Minikube 磁盤大小
```

---

## 快速獲幫助

```bash
# 查看 kubectl 幫助
kubectl --help
kubectl deploy --help
kubectl logs --help

# 查看 API 資源
kubectl api-resources

# 查看 API 版本
kubectl api-versions

# 檢查集群狀態
kubectl status

# 訪問 Kubernetes 儀表板
minikube dashboard
```

---

## 完整部署流程（複製粘貼）

```bash
#!/bin/bash
set -e

cd nova/backend/k8s

echo "=== 部署 Nova Kubernetes ==="
./deploy-local-k8s.sh deploy

echo "=== 驗證部署 ==="
sleep 10
./deploy-local-k8s.sh status

echo "=== 部署完成！==="
echo ""
echo "訪問服務："
echo "  kubectl port-forward svc/user-service 8080:8080 -n nova-services &"
echo "  curl http://localhost:8080/health"
echo ""
echo "查看日誌："
echo "  ./deploy-local-k8s.sh logs user-service"
```

---

**最後更新**: 2024-10-28
**版本**: 1.0

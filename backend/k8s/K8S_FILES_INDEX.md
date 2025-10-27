# Kubernetes 配置文件完整索引

## 📑 新增文件清單（2024-10-28）

### 基礎設施部署 (2 個)

#### 1. **redis-sentinel-statefulset.yaml**
- **用途**: Redis Sentinel 高可用集群部署
- **大小**: 500+ 行
- **內容**:
  - ConfigMap: Redis 和 Sentinel 配置
  - Secret: Redis 憑證
  - StatefulSet: 1 個 master + 2 個 replica
  - Services: Headless Service (發現) + ClusterIP (客戶端)
  - PodDisruptionBudget: 最少 2 副本
- **解決問題**: Redis 單點故障
- **關鍵配置**:
  ```yaml
  Redis Sentinel:
    - 3 個 Pod (1 master + 2 replicas)
    - 512MB 存儲限制
    - 自動故障轉移 (quorum: 2/3)
    - 5秒檢測超時
    - RDB + AOF 持久化
  ```

#### 2. **postgres-ha-statefulset.yaml**
- **用途**: PostgreSQL 高可用 + etcd 協調部署
- **大小**: 600+ 行
- **內容**:
  - ConfigMap: etcd 和 PostgreSQL 配置
  - Secret: 數據庫憑證
  - StatefulSet: 3 個 PostgreSQL Pod (主從複製)
  - StatefulSet: 3 個 etcd Pod (分佈式協調)
  - Init scripts: 數據庫和 schema 創建
  - Services: Headless + Primary + ReadReplicas
  - PodDisruptionBudget
- **解決問題**: PostgreSQL 共享 + schema 隔離缺失
- **關鍵配置**:
  ```yaml
  PostgreSQL:
    - 3 副本 (主從複製)
    - 20GB 存儲 per pod
    - 數據庫隔離:
      * nova_core (user, auth, streaming)
      * nova_messaging (messaging)
      * nova_search (search)
    - Schema 分割 (auth, streaming, messaging)

  etcd:
    - 3 個分佈式協調 Pod
    - 1GB 存儲 per pod
  ```

---

### 微服務部署 (2 個)

#### 3. **microservices-deployments.yaml**
- **用途**: 所有應用微服務部署配置
- **大小**: 700+ 行
- **內容**:
  - Namespace: nova-services
  - ConfigMap: 跨服務配置 (超時、連接池、熔斷器)
  - Deployment: user-service (3 副本)
  - Deployment: auth-service (2 副本)
  - Deployment: search-service (2 副本)
  - Deployment: streaming-api (2 副本)
  - Services: ClusterIP (內部訪問)
  - HPA: user-service 自動伸縮
  - PodDisruptionBudget
- **解決問題**: 跨服務通信無超時、微服務初始化序列太長
- **關鍵配置**:
  ```yaml
  HTTP 客戶端:
    - 超時: 3 秒
    - 連接超時: 1 秒
    - 連接池: 50 連接
    - 隊列: 1000 待處理請求

  熔斷器:
    - 失敗閾值: 50%
    - 成功閾值: 5 次成功後恢復
    - 超時: 60 秒

  重試:
    - 最多 3 次重試
    - 延遲: 100ms

  資源隔離:
    - user-service: 512Mi 請求, 2Gi 限制
    - auth/search/streaming: 256Mi 請求, 512Mi 限制
  ```

#### 4. **microservices-secrets.yaml**
- **用途**: 敏感數據管理 (密碼、密鑰、憑證)
- **大小**: 200+ 行
- **內容**:
  - Secret: 數據庫連接字符串
  - Secret: Redis 連接配置
  - Secret: Kafka 代理列表
  - Secret: JWT 密鑰
  - Secret: APNs 推送證書
  - Secret: TURN 服務器憑證
  - Secret: TLS 證書 (可選)
  - Secret: Docker Registry (可選)
- **⚠️ 重要**: 生產環境不應提交到 Git
- **使用**:
  ```bash
  # 編輯敏感信息
  vi microservices-secrets.yaml

  # 應用
  kubectl apply -f microservices-secrets.yaml
  ```

---

### 自動化工具 (1 個)

#### 5. **deploy-local-k8s.sh** (可執行腳本)
- **用途**: 一鍵部署所有 Kubernetes 資源
- **大小**: 8KB
- **功能**:
  - ✅ 前置條件檢查
  - ✅ 命名空間創建
  - ✅ Redis Sentinel 部署
  - ✅ PostgreSQL 部署
  - ✅ 微服務部署
  - ✅ 部署驗證
  - ✅ 服務信息顯示
- **使用**:
  ```bash
  ./deploy-local-k8s.sh deploy      # 部署
  ./deploy-local-k8s.sh status      # 查看狀態
  ./deploy-local-k8s.sh logs        # 查看日誌
  ./deploy-local-k8s.sh cleanup     # 清理
  ```

---

### 文檔指南 (4 個)

#### 6. **K8S_LOCAL_DEPLOYMENT_GUIDE.md**
- **用途**: 完整的本地部署指南
- **大小**: 400+ 行
- **內容**:
  - 前置條件檢查清單
  - 快速開始 (5 分鐘)
  - 詳細部署步驟 (4 個部分)
  - 架構驗證清單
  - 常見問題和故障排查
  - 性能優化和監控
  - 生產部署注意事項
  - 快速參考命令
- **目標讀者**: 想快速部署的開發者

#### 7. **K8S_DEPLOYMENT_SUMMARY.md**
- **用途**: 架構評審與 K8s 部署的對應關係總結
- **大小**: 300+ 行
- **內容**:
  - 5 個架構問題的 K8s 解決方案對應表
  - 完整交付清單
  - 命名空間結構圖
  - 資源配置明細
  - 與 docker-compose 的對比
  - 驗收標準
- **目標讀者**: 項目經理、架構師、QA

#### 8. **K8S_QUICK_START.md**
- **用途**: 快速參考卡片，一頁紙命令參考
- **大小**: 200+ 行
- **內容**:
  - 前置條件檢查
  - 一鍵部署命令
  - 手動逐步部署
  - 本地訪問端口轉發
  - API 測試命令
  - 常用 kubectl 命令
  - 故障排查快速檢查
  - 環境配置 (Minikube / Kind)
  - 常用別名
  - 常見報錯解決方案
- **目標讀者**: 日常使用開發者

#### 9. **K8S_FILES_INDEX.md** (此文件)
- **用途**: 所有新增文件的完整索引和導航
- **內容**: 文件清單、使用指南、快速導航

---

## 🗺️ 使用導航地圖

### 🚀 我要快速部署
```
K8S_QUICK_START.md
  → 前置條件檢查
  → 一鍵部署
  → 本地訪問
  → 常用命令
```

### 📖 我要詳細理解
```
K8S_LOCAL_DEPLOYMENT_GUIDE.md
  → 環境設置
  → 快速開始 (5 分鐘)
  → 詳細部署步驟
  → 驗證清單
  → 故障排查
```

### 📊 我要了解架構
```
K8S_DEPLOYMENT_SUMMARY.md
  → 問題對應表
  → 命名空間結構
  → 資源配置
  → 與 docker-compose 對比
```

### 🔍 我要查找具體命令
```
K8S_QUICK_START.md → 常用 kubectl 命令
或
K8S_LOCAL_DEPLOYMENT_GUIDE.md → 快速參考命令
```

### 🛠️ 我遇到問題了
```
K8S_QUICK_START.md → 故障排查快速檢查
或
K8S_LOCAL_DEPLOYMENT_GUIDE.md → 常見問題和故障排查
```

---

## 📋 文件依賴關係

```
deploy-local-k8s.sh (主入口)
├── redis-sentinel-statefulset.yaml
├── postgres-ha-statefulset.yaml
├── microservices-deployments.yaml
└── microservices-secrets.yaml

文檔依賴關係：
K8S_QUICK_START.md (入門)
  ↓
K8S_LOCAL_DEPLOYMENT_GUIDE.md (詳細)
  ↓
K8S_DEPLOYMENT_SUMMARY.md (總結)
  ↓
K8S_FILES_INDEX.md (導航)
```

---

## 🎯 按場景選擇文件

### 場景 1: 首次部署（5-10 分鐘）
**推薦文件順序**:
1. K8S_QUICK_START.md - 前置條件檢查
2. 運行 `./deploy-local-k8s.sh deploy`
3. K8S_QUICK_START.md - 本地訪問服務

### 場景 2: 理解整個架構
**推薦文件順序**:
1. K8S_DEPLOYMENT_SUMMARY.md - 了解問題和解決方案
2. K8S_LOCAL_DEPLOYMENT_GUIDE.md - 了解詳細配置
3. 查看 YAML 文件本身 - 理解實現細節

### 場景 3: 日常開發工作
**推薦文件順序**:
1. K8S_QUICK_START.md - 常用命令
2. K8S_QUICK_START.md - 故障排查快速檢查

### 場景 4: 遷移到生產
**推薦文件順序**:
1. K8S_DEPLOYMENT_SUMMARY.md - 了解生產級別考慮
2. K8S_LOCAL_DEPLOYMENT_GUIDE.md - 生產部署注意事項
3. 修改 YAML 文件中的生產級別配置

---

## 📦 與舊配置的關係

### 保留的文件
```
✅ messaging-service-namespace.yaml
✅ messaging-service-configmap.yaml
✅ messaging-service-secret.yaml
✅ messaging-service-deployment.yaml
✅ messaging-service-service.yaml
✅ messaging-service-hpa.yaml
✅ messaging-service-pdb.yaml
✅ ... (其他 messaging 相關文件)
```

### 新增文件（架構改進）
```
+ redis-sentinel-statefulset.yaml        (解決 Redis 單點故障)
+ postgres-ha-statefulset.yaml           (解決 PostgreSQL 共享)
+ microservices-deployments.yaml         (解決跨服務通信)
+ microservices-secrets.yaml             (敏感數據管理)
+ deploy-local-k8s.sh                    (自動化部署)
+ K8S_LOCAL_DEPLOYMENT_GUIDE.md          (完整指南)
+ K8S_DEPLOYMENT_SUMMARY.md              (對應總結)
+ K8S_QUICK_START.md                     (快速參考)
+ K8S_FILES_INDEX.md                     (文件導航)
```

---

## 🔄 部署步驟快速流程

```
1. 檢查前置條件
   ↓
2. 運行 ./deploy-local-k8s.sh deploy
   ↓
3. 等待所有 Pod Ready (20-40 分鐘)
   ↓
4. 運行 ./deploy-local-k8s.sh status
   ↓
5. 使用端口轉發訪問服務
   ↓
6. 按 K8S_QUICK_START.md 進行測試
   ↓
7. 參考 K8S_LOCAL_DEPLOYMENT_GUIDE.md 進行驗證
```

---

## 📊 文件統計

| 類別 | 文件數 | 總行數 | 用途 |
|------|--------|--------|------|
| 基礎設施部署 | 2 | 1100+ | Redis + PostgreSQL HA |
| 微服務部署 | 2 | 900+ | 所有應用微服務 |
| 自動化工具 | 1 | 280 | 一鍵部署腳本 |
| 文檔指南 | 4 | 1500+ | 部署和使用指南 |
| **合計** | **9** | **3780+** | **完整 K8s 系統** |

---

## ✅ 完成檢查清單

部署前驗證：
- [ ] 已閱讀 K8S_QUICK_START.md 的前置條件
- [ ] kubectl 已安裝並可連接到集群
- [ ] 有 4+ CPU 核心和 8GB+ 內存
- [ ] 編輯了 microservices-secrets.yaml 中的敏感信息

部署後驗證：
- [ ] 所有 Pod 都處於 Running 狀態
- [ ] 所有 Service 都有 ClusterIP
- [ ] 可以端口轉發訪問服務
- [ ] API 健康檢查通過

---

## 🚀 後續步驟

### 立即可做（完成部署後）
1. 查看 K8S_QUICK_START.md 學習常用命令
2. 測試各個 API 端點
3. 查看 Pod 日誌了解運行狀態

### 本周建議
1. 配置 Prometheus + Grafana 監控
2. 設置 log 聚合 (ELK / Loki)
3. 實施 Kafka offset 管理 (CDC 改進)

### 本月建議
1. 遷移到生產集群 (EKS / AKS / GKE)
2. 配置 Ingress Controller (TLS 支持)
3. 部署 ArgoCD GitOps

---

## 🎓 學習資源

### 官方文檔
- [Kubernetes 官方文檔](https://kubernetes.io/docs/)
- [kubectl 命令參考](https://kubernetes.io/docs/reference/kubectl/)
- [Kubernetes API 文檔](https://kubernetes.io/docs/reference/generated/kubernetes-api/)

### 本項目資源
- `K8S_QUICK_START.md` - 快速命令參考
- `K8S_LOCAL_DEPLOYMENT_GUIDE.md` - 深度部署指南
- YAML 文件註釋 - 配置說明

---

## 🆘 獲取幫助

### 按步驟查找
1. 檢查 K8S_QUICK_START.md 的「常見報錯和解決方案」
2. 查看 K8S_LOCAL_DEPLOYMENT_GUIDE.md 的「故障排查」
3. 運行 `kubectl describe pod <pod-name> -n <ns>` 查看詳細信息
4. 查看 Pod 日誌: `kubectl logs <pod-name> -n <ns>`

### 常用檢查命令
```bash
# 快速狀態檢查
./deploy-local-k8s.sh status

# 查看特定日誌
kubectl logs -f <pod-name> -n nova-services

# 進入 Pod 調試
kubectl exec -it <pod-name> -n nova-services -- /bin/sh
```

---

**最後更新**: 2024-10-28
**版本**: 1.0
**狀態**: ✅ 完成

May the Force be with you.

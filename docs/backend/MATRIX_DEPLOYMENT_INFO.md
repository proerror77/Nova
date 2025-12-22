# Matrix Synapse 部署資訊

**部署時間**: 2025-12-09
**環境**: nova-staging (GKE)
**狀態**: ✅ 部署成功並驗證

---

## 連線資訊（提供給後端服務）

### 必填環境變數

後端 `realtime-chat-service` 需要以下環境變數來連接 Matrix：

```bash
MATRIX_ENABLED=true
MATRIX_HOMESERVER_URL=http://matrix-synapse:8008
MATRIX_SERVICE_USER=@nova-service:staging.nova.internal
MATRIX_DEVICE_NAME=nova-realtime-chat-service
MATRIX_SERVER_NAME=staging.nova.internal
MATRIX_ACCESS_TOKEN=syt_bm92YS1zZXJ2aWNl_fvxysrZSJjIkuqsZtmiL_2lTBn4
```

### ConfigMap 配置

已在 `realtime-chat-service-config` ConfigMap 中設置：

- ✅ `MATRIX_ENABLED`: `false` (預設關閉，需手動啟用)
- ✅ `MATRIX_HOMESERVER_URL`: `http://matrix-synapse:8008`
- ✅ `MATRIX_SERVICE_USER`: `@nova-service:staging.nova.internal`
- ✅ `MATRIX_DEVICE_NAME`: `nova-realtime-chat-service`
- ✅ `MATRIX_SERVER_NAME`: `staging.nova.internal`

### Secret 配置

已建立 `nova-matrix-service-token` Secret：

- ✅ `MATRIX_ACCESS_TOKEN`: `syt_bm92YS1zZXJ2aWNl_fvxysrZSJjIkuqsZtmiL_2lTBn4`

---

## 部署詳情

### 資源狀態

```bash
# Synapse Pod
kubectl get pods -n nova-staging -l app=matrix-synapse
# NAME: matrix-synapse-6d9f45b4c9-pzq4x
# STATUS: Running
# READY: 1/1

# Synapse Service
kubectl get svc -n nova-staging matrix-synapse
# CLUSTER-IP: 34.118.229.87
# PORT: 8008/TCP
```

### 資料庫配置

- **Database**: `synapse` (PostgreSQL 15)
- **User**: `synapse`
- **Password**: `synapse_nova_2024`
- **Host**: `postgres:5432` (內部)

### 認證資訊

- **Service Account**: `@nova-service:staging.nova.internal`
- **Password**: `NovaService2024SecurePassword`
- **Device ID**: `NOVA_SERVICE`
- **Access Token**: `syt_bm92YS1zZXJ2aWNl_fvxysrZSJjIkuqsZtmiL_2lTBn4`

**重要**: Access token 已儲存在 `nova-matrix-service-token` Secret 中。

---

## 啟用 Matrix 步驟

### 1. 啟用 Matrix 功能

```bash
kubectl patch configmap realtime-chat-service-config -n nova-staging \
  --type merge -p '{"data":{"MATRIX_ENABLED":"true"}}'
```

### 2. 重啟 realtime-chat-service

```bash
kubectl rollout restart deployment/realtime-chat-service -n nova-staging
```

### 3. 驗證服務

```bash
# 檢查 pod 日誌確認 Matrix 初始化
kubectl logs -n nova-staging -l app=realtime-chat-service --tail=100 | grep -i matrix

# 驗證環境變數
kubectl exec -n nova-staging deploy/realtime-chat-service -- env | grep MATRIX
```

---

## 驗證測試

### 測試 1: Synapse 健康檢查

```bash
kubectl exec -n nova-staging deploy/matrix-synapse -- \
  curl -s http://localhost:8008/health
# 預期輸出: OK
```

### 測試 2: 驗證 Access Token

```bash
kubectl exec -n nova-staging deploy/matrix-synapse -- sh -c "
  curl -s -X GET 'http://localhost:8008/_matrix/client/v3/account/whoami' \
    -H 'Authorization: Bearer syt_bm92YS1zZXJ2aWNl_fvxysrZSJjIkuqsZtmiL_2lTBn4'
"
# 預期輸出: {"user_id":"@nova-service:staging.nova.internal","is_guest":false,"device_id":"NOVA_SERVICE"}
```

### 測試 3: 從 realtime-chat-service 連接

啟用 Matrix 後，realtime-chat-service 應該能：

1. 初始化 Matrix SDK 客戶端
2. 使用 access token 登入
3. 開始 sync loop
4. 建立/查詢 Matrix rooms

---

## 架構資訊

### Synapse 配置特點

- ✅ **Federation 已關閉**: 純內部使用，不與外部 Matrix 伺服器通訊
- ✅ **Registration 已關閉**: 只能透過 admin API 建立帳號
- ✅ **PostgreSQL**: 使用 nova-staging 的 postgres StatefulSet
- ✅ **Metrics**: 暴露在 `/_synapse/metrics` (可接入 Prometheus)
- ✅ **Media Storage**: 儲存在 PVC `matrix-synapse-data` (10Gi)

### 網路

- **內部 URL**: `http://matrix-synapse:8008`
- **Service**: ClusterIP `34.118.229.87:8008`
- **Namespace**: `nova-staging`

### 安全考量

- ✅ Registration shared secret 僅限於建立新用戶
- ✅ Access token 儲存在 Kubernetes Secret
- ✅ 所有通訊在叢集內部，不對外暴露
- ⚠️  未啟用 TLS (內部使用 HTTP，依賴 K8s 網路隔離)

---

## 後續工作

### 程式碼整合 (待完成)

需要在 `realtime-chat-service` 中整合：

1. **Matrix SDK 初始化**
   - 讀取環境變數 `MATRIX_*`
   - 建立 Matrix 客戶端實例
   - 使用 `MATRIX_ACCESS_TOKEN` 登入

2. **Room 管理**
   - `conversation_id` ↔ `matrix_room_id` 映射
   - 建立 DM/群組 room
   - 邀請用戶加入 room

3. **訊息處理**
   - `send_message()` → Matrix `m.room.message` event
   - `send_audio_message()` → Matrix media upload + `m.room.message` (audio)
   - 訊息編輯 → Matrix event replacement
   - 訊息刪除 → Matrix redaction

4. **WebSocket 推播**
   - Matrix sync loop → 監聽新事件
   - 轉換 Matrix events 為現有 WS 格式
   - 推送給前端 (`message.new`, `message.edited`, `message.deleted`)

5. **附件處理**
   - 上傳到 Matrix media API (`/_matrix/media/v3/upload`)
   - 取得 `mxc://` URI
   - 或繼續使用 S3 但訊息經 Matrix 傳送

### 監控與維護

- [ ] 設定 Prometheus ServiceMonitor (如果使用 prometheus-operator)
- [ ] 建立告警規則 (pod down, DB connection errors)
- [ ] 設定備份策略 (postgres synapse DB + media PVC)
- [ ] 配置日誌收集 (ELK/Loki)

### Production 遷移

當準備好 production 部署時：

1. 複製到 `backend/k8s/overlays/prod/`
2. 更新 `MATRIX_SERVER_NAME` 為正式 domain (如 `chat.nova.com`)
3. 申請 TLS 證書並配置 ingress
4. 增加資源配額和副本數
5. 啟用持久化備份

---

## 故障排除

### Pod CrashLoopBackOff

```bash
# 檢查日誌
kubectl logs -n nova-staging -l app=matrix-synapse --tail=100

# 常見問題：
# 1. DB 連線失敗 → 檢查 postgres 是否運行
# 2. 權限錯誤 → 確認 synapse 用戶有 schema 權限
# 3. ConfigMap 缺失 → 檢查 nova-staging-config 存在
```

### Access Token 失效

```bash
# 重新登入取得新 token
kubectl exec -n nova-staging deploy/matrix-synapse -- sh -c "
  curl -s -X POST http://localhost:8008/_matrix/client/v3/login \
    -H 'Content-Type: application/json' \
    -d '{\"type\":\"m.login.password\",\"user\":\"nova-service\",\"password\":\"NovaService2024SecurePassword\"}'
"

# 更新 Secret
kubectl patch secret nova-matrix-service-token -n nova-staging \
  -p '{"stringData":{"MATRIX_ACCESS_TOKEN":"<new_token>"}}'
```

### 重新建立 Database

```bash
# 刪除並重建
kubectl exec -n nova-staging postgres-0 -- psql -U nova -d nova_auth -c "
  DROP DATABASE IF EXISTS synapse;
  CREATE DATABASE synapse ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' template=template0;
  GRANT ALL ON SCHEMA public TO synapse;
"

# 重啟 Synapse
kubectl delete pod -n nova-staging -l app=matrix-synapse
```

---

## 相關檔案

- **Deployment**: `backend/k8s/base/matrix-synapse.yaml`
- **Secrets Template**: `backend/k8s/base/matrix-synapse-secrets.yaml.template`
- **Staging Overlay**: `backend/k8s/overlays/staging/kustomization.yaml`
- **部署腳本**: `backend/k8s/scripts/deploy-matrix-synapse.sh`

---

**部署完成！** 🎉

下一步：請通知後端開發團隊上述連線資訊，開始整合 Matrix SDK 到 `realtime-chat-service`。

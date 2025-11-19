# Home Feed 服務接入狀態 - 正確版本

**更新時間**: 2025-11-18
**狀態**: ⚠️ **已接入但後端服務有問題**

---

## 📊 真實狀態

### Backend 服務狀態 (Staging)

| 服務 | Pod 狀態 | 端口 | 問題 |
|------|---------|------|------|
| **feed-service** | Running (0/1) | HTTP: 8084, gRPC: 9084 | 依賴服務不可用 |
| **content-service** | CrashLoopBackOff | HTTP: 8080 | ❌ 數據庫連接失敗 |
| **social-service** | Scaled to 0 | - | ⚠️ 未部署 |

### feed-service 日誌分析

```json
✅ "starting service: 0.0.0.0:8084"
✅ "gRPC server listening on 0.0.0.0:9084"
⚠️ "social-service calls will fail until service is deployed"
⚠️ "graph-service calls will fail until service is deployed"
⚠️ "ranking-service calls will fail until service is deployed"
```

**問題：**
- feed-service 正在運行但缺少依賴服務
- 監聽在 **8084** 端口（不是 8080）

### content-service 崩潰日誌

```
ERROR: Failed to create database pool: pool timed out while waiting for an open connection
```

**問題：**
- 無法連接到 PostgreSQL 數據庫
- 導致 CrashLoopBackOff

---

## 🏗️ 架構理解

### 正確的服務關係

```
iOS App
  ↓
POST /api/v2/feed/user
  ↓
feed-service (8084) ← 你在這裡
  ↓ 依賴
  ├── content-service (8080) ← ❌ 崩潰
  ├── social-service        ← ❌ 未部署
  ├── graph-service         ← ❌ 未部署
  └── ranking-service       ← ❌ 未部署
```

### ❌ 錯誤理解（已修正）

~~feed-service 失敗 → fallback 到 content-service~~

**為什麼錯誤：**
1. feed-service **依賴** content-service 來獲取數據
2. content-service 崩潰 → feed-service 也無法工作
3. 它們不是互為替代的關係

---

## 📱 iOS 實現（已修正）

### SocialService.swift

```swift
/// Get user's personalized feed (v2 API)
/// POST /api/v2/feed/user
/// Calls feed-service which aggregates content from multiple sources
func getUserFeed(userId: String, limit: Int = 20, cursor: String? = nil)
    async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {

    let request = FeedRequest(userId: userId, limit: limit, cursor: cursor)
    let response: FeedResponse = try await client.request(
        endpoint: "/api/v2/feed/user",
        method: "POST",
        body: request
    )

    return (response.posts, response.nextCursor, response.hasMore)
}
```

**改進：**
- ✅ 移除了錯誤的 fallback 邏輯
- ✅ 直接調用 feed-service v2 API
- ✅ 錯誤會正確拋出給 UI 層處理

---

## 🔧 當前問題

### 1. content-service 數據庫連接失敗

**問題：**
```
Failed to create database pool: pool timed out
```

**可能原因：**
- PostgreSQL 服務不可用
- 數據庫 URL 配置錯誤
- 網絡連接問題
- 連接池配置過小

**檢查步驟：**
```bash
# 檢查 PostgreSQL pod
kubectl get pods -n nova-staging | grep postgres

# 檢查 content-service 配置
kubectl get configmap content-service-config -n nova-staging -o yaml

# 查看完整日誌
kubectl logs -n nova-staging content-service-7fc947f4dc-j4lxq
```

### 2. feed-service 端口路由問題

**問題：**
- feed-service 監聽 **8084** 端口
- Ingress 可能配置為 **8080**

**檢查 Ingress 配置：**
```bash
kubectl get ingress -n nova-staging -o yaml
```

**需要確認：**
- Ingress 是否將 `/api/v2/feed/*` 路由到 `feed-service:8084`
- 或者 feed-service 需要改為監聽 8080

---

## 🚀 修復步驟

### 優先級 P0: 修復 content-service

1. **檢查數據庫連接**
   ```bash
   # 檢查 PostgreSQL
   kubectl get svc -n nova-staging | grep postgres

   # 測試連接
   kubectl run -it --rm debug --image=postgres:14 --restart=Never -- \
     psql -h postgres-service -U postgres -d nova_content
   ```

2. **檢查配置**
   ```bash
   # 查看 content-service 配置
   kubectl describe deployment content-service -n nova-staging

   # 檢查 Secret
   kubectl get secret content-service-secret -n nova-staging
   ```

3. **增加數據庫連接池配置**
   ```yaml
   # 在 content-service-config ConfigMap 中
   DATABASE_MAX_CONNECTIONS: "50"
   DATABASE_MIN_CONNECTIONS: "10"
   DATABASE_CONNECT_TIMEOUT: "30"
   ```

### 優先級 P1: 修復 feed-service 路由

1. **檢查當前 Ingress**
   ```bash
   kubectl get ingress nova-api-gateway -n nova-staging -o yaml
   ```

2. **確認路由規則**
   ```yaml
   # 應該有類似的配置
   - path: /api/v2/feed
     backend:
       service:
         name: feed-service
         port:
           number: 8084  # 注意：是 8084 不是 8080
   ```

3. **測試端點**
   ```bash
   # 直接測試 feed-service
   kubectl port-forward svc/feed-service 8084:8084 -n nova-staging

   # 在另一個終端
   curl http://localhost:8084/api/v1/health
   ```

### 優先級 P2: 部署依賴服務

```bash
# social-service (點讚、評論需要)
kubectl scale deployment social-service -n nova-staging --replicas=1

# graph-service (關注關係需要)
kubectl scale deployment graph-service -n nova-staging --replicas=1

# ranking-service (排序算法需要)
kubectl scale deployment ranking-service -n nova-staging --replicas=1
```

---

## 📝 iOS 測試狀態

### 當前可測試

- ❌ User Feed - feed-service 運行但依賴不可用
- ❌ Explore Feed - 同上
- ❌ Trending Posts - 同上

### 錯誤預期

```swift
// iOS 會收到以下錯誤
APIError.serverError(statusCode: 500, message: "Service dependencies unavailable")
// 或
APIError.networkError(Error: "Connection failed")
```

### UI 錯誤顯示

```swift
// HomeView 會顯示錯誤狀態
VStack {
    Image(systemName: "exclamationmark.triangle")
    Text("Failed to load feed: ...")
    Button("重試") { ... }
}
```

---

## ✅ 下一步行動

### 1. 立即修復（必須）

- [ ] 修復 content-service 數據庫連接
- [ ] 確認 feed-service Ingress 路由配置正確
- [ ] 測試 `/api/v2/feed/user` 端點

### 2. 短期部署（建議）

- [ ] 部署 social-service (點讚、評論功能)
- [ ] 部署 graph-service (關注關係)
- [ ] 部署 ranking-service (feed 排序)

### 3. 驗證測試

```bash
# 測試 feed API
curl -X POST \
  http://[LOADBALANCER]/api/v2/feed/user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"user_id":"test","limit":20}'

# 預期：200 OK with { posts, next_cursor, has_more }
```

---

## 📊 總結

### iOS 端
- ✅ v2 API 已接入
- ✅ 移除了錯誤的 fallback 邏輯
- ✅ 錯誤處理正確
- ⏳ 等待後端服務修復

### Backend 端
- ⚠️ feed-service 運行但缺少依賴
- ❌ content-service 崩潰（數據庫連接）
- ❌ 依賴服務未部署

### 用戶體驗
- ❌ Feed 功能目前不可用
- ✅ 有正確的錯誤提示
- ✅ 有重試機制

---

**維護者**: Nova iOS Team
**最後更新**: 2025-11-18
**狀態**: Backend 需要修復
